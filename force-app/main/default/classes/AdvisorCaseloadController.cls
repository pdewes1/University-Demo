/**
 * Controller for the advisorCaseload component on the Advisor Home page.
 *
 * Shows the running advisor's own students (Contact owner = the advisor), ranked by who needs
 * attention. Signals come from Data 360 in a few batch SQL queries across the whole caseload
 * (engagement score, attendance, missing work, last Canvas login, financial aid status), and
 * advising activity (overdue follow-ups, last contact) comes live from the CRM.
 *
 * Access: students are read WITH USER_MODE and filtered to OwnerId = the running user, so Data 360
 * is only ever queried for the advisor's own Student IDs. Financial aid is status only.
 */
public with sharing class AdvisorCaseloadController {

    @TestVisible static final Integer MAX_ROWS = 200;
    @TestVisible static final Integer LOGIN_GAP_DAYS = 21;
    @TestVisible static final Integer CONTACT_GAP_DAYS = 30;

    public class StudentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String studentId;
        @AuraEnabled public String program;
        @AuraEnabled public String stage;
        @AuraEnabled public Boolean onLeave = false;
        @AuraEnabled public Decimal engagementScore;
        @AuraEnabled public String engagementBand;     // On track | Watch | At risk | On leave
        @AuraEnabled public Decimal attendanceRate;
        @AuraEnabled public Integer absences = 0;
        @AuraEnabled public Integer missingWork = 0;
        @AuraEnabled public String lastLogin;
        @AuraEnabled public Integer daysSinceLogin;
        @AuraEnabled public String aidStatus;          // short label, status only
        @AuraEnabled public Boolean aidAction = false;
        @AuraEnabled public Integer overdueFollowUps = 0;
        @AuraEnabled public Integer openFollowUps = 0;
        @AuraEnabled public String lastContact;
        @AuraEnabled public Integer daysSinceContact;
        @AuraEnabled public List<String> flags = new List<String>();
        @AuraEnabled public Decimal priority = 0;
        @AuraEnabled public Boolean needsAttention = false;
        @AuraEnabled public String status;             // Needs attention | Watch | On track
    }

    public class Caseload {
        @AuraEnabled public Integer totalStudents = 0;
        @AuraEnabled public Integer needsAttention = 0;
        @AuraEnabled public Integer overdueFollowUps = 0;
        @AuraEnabled public Integer noRecentContact = 0;
        @AuraEnabled public Integer aidActionNeeded = 0;
        @AuraEnabled public Integer onLeave = 0;
        @AuraEnabled public Decimal averageEngagement;
        @AuraEnabled public Boolean dataCloudAvailable = true;
        @AuraEnabled public String message;
        @AuraEnabled public String asOf;
        @AuraEnabled public Boolean truncated = false;
        @AuraEnabled public List<StudentRow> students = new List<StudentRow>();
    }

    // Data 360 signals for one Student ID. Tests set signalsOverride instead of calling Data 360.
    public class Signals {
        public Decimal engagement;
        public Integer classes = 0;
        public Integer absences = 0;
        public Integer missing = 0;
        public String lastLogin;
        public String fafsa;
        public String verification;
        public String sap;
    }
    @TestVisible static Map<String, Signals> signalsOverride;

    @AuraEnabled(cacheable=true)
    public static Caseload getCaseload() {
        Caseload result = new Caseload();
        result.asOf = Date.today().format();

        List<Contact> students = [
            SELECT Id, Name, Preferred_Name__c, FirstName, LastName, Student_ID__c, Program__c, Student_Stage__c
            FROM Contact
            WHERE OwnerId = :UserInfo.getUserId() AND Student_ID__c != null
            WITH USER_MODE
            ORDER BY LastName
            LIMIT 2000
        ];
        result.totalStudents = students.size();
        if (students.isEmpty()) {
            result.message = 'No students are assigned to you yet.';
            return result;
        }

        Map<String, Signals> signals = loadSignals(students, result);
        Map<Id, Datetime> lastContact = lastAdvisingContact(students);
        Map<Id, Integer[]> followUps = followUpCounts(students);

        Decimal engagementTotal = 0;
        Integer engagementCount = 0;
        List<StudentRow> rows = new List<StudentRow>();
        for (Contact c : students) {
            StudentRow r = buildRow(c, signals.get(c.Student_ID__c), lastContact.get(c.Id), followUps.get(c.Id));
            rows.add(r);
            if (r.needsAttention) result.needsAttention++;
            if (r.overdueFollowUps > 0) result.overdueFollowUps += r.overdueFollowUps;
            if (r.daysSinceContact == null || r.daysSinceContact > CONTACT_GAP_DAYS) result.noRecentContact++;
            if (r.aidAction) result.aidActionNeeded++;
            if (r.onLeave) result.onLeave++;
            if (r.engagementScore != null && !r.onLeave) { engagementTotal += r.engagementScore; engagementCount++; }
        }
        if (engagementCount > 0) result.averageEngagement = (engagementTotal / engagementCount).setScale(0);

        rows.sort(new ByPriority());
        if (rows.size() > MAX_ROWS) {
            result.truncated = true;
            for (Integer i = 0; i < MAX_ROWS; i++) result.students.add(rows[i]);
        } else {
            result.students = rows;
        }
        return result;
    }

    // ---- One student --------------------------------------------------------

    @TestVisible
    static StudentRow buildRow(Contact c, Signals s, Datetime contactAt, Integer[] followUps) {
        StudentRow r = new StudentRow();
        r.id = c.Id;
        r.name = String.isNotBlank(c.Preferred_Name__c) ? c.Preferred_Name__c + ' ' + c.LastName : c.Name;
        r.studentId = c.Student_ID__c;
        r.program = c.Program__c;
        r.stage = c.Student_Stage__c;
        r.onLeave = c.Student_Stage__c == 'On Leave';

        if (followUps != null) { r.openFollowUps = followUps[0]; r.overdueFollowUps = followUps[1]; }
        if (contactAt != null) {
            r.lastContact = contactAt.date().format();
            r.daysSinceContact = contactAt.date().daysBetween(Date.today());
        }

        if (s != null) {
            if (s.engagement != null) r.engagementScore = s.engagement.setScale(0);
            r.absences = s.absences;
            if (s.classes > 0) r.attendanceRate = (Decimal.valueOf(s.classes - s.absences) * 100 / s.classes).setScale(0);
            r.missingWork = s.missing;
            if (String.isNotBlank(s.lastLogin)) {
                r.lastLogin = s.lastLogin.left(10);
                try { r.daysSinceLogin = Date.valueOf(r.lastLogin).daysBetween(Date.today()); } catch (Exception ignored) {}
            }
            r.aidStatus = aidLabel(s);
            r.aidAction = aidNeedsAction(s);
        }
        r.engagementBand = r.onLeave ? 'On leave'
            : r.engagementScore == null ? null
            : r.engagementScore >= 75 ? 'On track' : (r.engagementScore >= 50 ? 'Watch' : 'At risk');

        // Flags and a simple priority so the advisor sees who to reach first. Weights: low engagement 3;
        // missing work, academic progress not met, an overdue follow-up or 2+ absences 2; one absence,
        // a long Canvas gap or an aid task 1. Three or more points = needs attention.
        if (!r.onLeave) {
            if (r.engagementScore != null && r.engagementScore < 50) { r.flags.add('Low engagement'); r.priority += 3; }
            if (r.attendanceRate != null && r.attendanceRate < 80) {
                r.flags.add('Attendance ' + r.attendanceRate + '%');
                r.priority += r.absences >= 2 ? 2 : 1;
            }
            if (r.missingWork > 0) { r.flags.add(r.missingWork + ' missing assignment' + (r.missingWork == 1 ? '' : 's')); r.priority += 2; }
            if (r.daysSinceLogin != null && r.daysSinceLogin > LOGIN_GAP_DAYS) { r.flags.add('No Canvas login in ' + r.daysSinceLogin + ' days'); r.priority += 1; }
        }
        if (s != null) {
            if (String.isNotBlank(s.fafsa) && s.fafsa.toLowerCase() != 'received') { r.flags.add('FAFSA not received'); r.priority += 1; }
            if (String.isNotBlank(s.verification) && s.verification.toLowerCase().contains('pending')) { r.flags.add('Aid verification pending'); r.priority += 1; }
            if (String.isNotBlank(s.sap) && s.sap.toLowerCase() != 'met') { r.flags.add('Academic progress: ' + s.sap); r.priority += 2; }
        }
        if (r.overdueFollowUps > 0) { r.flags.add(r.overdueFollowUps + ' overdue follow-up' + (r.overdueFollowUps == 1 ? '' : 's')); r.priority += 2; }
        r.needsAttention = r.priority >= 3;
        r.status = r.needsAttention ? 'Needs attention' : (r.priority >= 1 ? 'Watch' : 'On track');
        return r;
    }

    @TestVisible
    static String aidLabel(Signals s) {
        if (String.isBlank(s.fafsa)) return 'No aid record';
        if (s.fafsa.toLowerCase() != 'received') return 'FAFSA ' + s.fafsa.toLowerCase();
        if (String.isNotBlank(s.verification) && s.verification.toLowerCase().contains('pending')) return 'Verification pending';
        if (String.isNotBlank(s.sap) && s.sap.toLowerCase() != 'met') return 'SAP ' + s.sap;
        return 'On track';
    }

    static Boolean aidNeedsAction(Signals s) {
        return (String.isNotBlank(s.fafsa) && s.fafsa.toLowerCase() != 'received')
            || (String.isNotBlank(s.verification) && s.verification.toLowerCase().contains('pending'))
            || (String.isNotBlank(s.sap) && s.sap.toLowerCase() != 'met');
    }

    public class ByPriority implements Comparator<StudentRow> {
        public Integer compare(StudentRow a, StudentRow b) {
            if (a.priority != b.priority) return a.priority > b.priority ? -1 : 1;
            Decimal ea = a.engagementScore == null ? 101 : a.engagementScore;
            Decimal eb = b.engagementScore == null ? 101 : b.engagementScore;
            if (ea != eb) return ea < eb ? -1 : 1;
            return a.name.compareTo(b.name);
        }
    }

    // ---- Data 360 ------------------------------------------------------------

    static Map<String, Signals> loadSignals(List<Contact> students, Caseload result) {
        if (signalsOverride != null) return signalsOverride;
        Map<String, Signals> out = new Map<String, Signals>();
        List<String> ids = new List<String>();
        for (Contact c : students) ids.add(c.Student_ID__c);
        try {
            // Two queries per chunk: one row per student (Canvas profile + Banner aid + engagement
            // calculated insight via the unified individual), and attendance/submission counts.
            for (List<String> chunk : chunks(ids, 500)) {
                String inList = '(\'' + String.join(escaped(chunk), '\',\'') + '\')';
                for (List<Object> row : sql(
                        'SELECT c.user_id__c, c.last_login__c, a.fafsa_status__c, a.verification_status__c, '
                      + 'a.satisfactory_academic_progress__c, e.engagement_score__c '
                      + 'FROM Snowflake_Canvas_Users__dlm c '
                      + 'LEFT JOIN Snowflake_Banner_Financial_Aid_Summa__dlm a ON a.banner_id__c = c.student_id__c '
                      + 'LEFT JOIN UnifiedIndividual__dlm u ON u.Student_ID__c = c.user_id__c '
                      + 'LEFT JOIN Student_Engagement_Score__cio e ON e.unified_individual_id__c = u.ssot__Id__c '
                      + 'WHERE c.user_id__c IN ' + inList)) {
                    Signals s = get(out, row[0]);
                    s.lastLogin = row[1] == null ? null : String.valueOf(row[1]);
                    s.fafsa = row[2] == null ? null : String.valueOf(row[2]);
                    s.verification = row[3] == null ? null : String.valueOf(row[3]);
                    s.sap = row[4] == null ? null : String.valueOf(row[4]);
                    if (row[5] != null) s.engagement = dec(row[5]);
                }
                for (List<Object> row : sql(
                        'SELECT user_id__c, \'attendance\' AS kind, COUNT(*) AS total, '
                      + 'SUM(CASE WHEN LOWER(status__c) = \'absent\' THEN 1 ELSE 0 END) AS flagged '
                      + 'FROM Snowflake_Canvas_Attendance__dlm WHERE user_id__c IN ' + inList + ' GROUP BY user_id__c '
                      + 'UNION ALL '
                      + 'SELECT user_id__c, \'submissions\' AS kind, COUNT(*) AS total, '
                      + 'SUM(CASE WHEN LOWER(workflow_state__c) IN (\'missing\',\'unsubmitted\') THEN 1 ELSE 0 END) AS flagged '
                      + 'FROM Canvas_Submissions__dlm WHERE user_id__c IN ' + inList + ' GROUP BY user_id__c')) {
                    Signals s = get(out, row[0]);
                    if (String.valueOf(row[1]) == 'attendance') {
                        s.classes = intVal(row[2]);
                        s.absences = intVal(row[3]);
                    } else {
                        s.missing = intVal(row[3]);
                    }
                }
            }
        } catch (Exception e) {
            result.dataCloudAvailable = false;
            result.message = 'Data 360 signals are not available right now, so the list shows CRM activity only.';
            System.debug(LoggingLevel.WARN, 'Caseload Data 360 query failed: ' + e.getMessage());
        }
        return out;
    }

    static List<List<Object>> sql(String statement) {
        List<List<Object>> rows = new List<List<Object>>();
        ConnectApi.CdpQueryInput q = new ConnectApi.CdpQueryInput();
        q.sql = statement;
        ConnectApi.CdpQueryOutputV2 res = ConnectApi.CdpQuery.queryAnsiSqlV2(q);
        while (res != null) {
            if (res.data != null) for (ConnectApi.CdpQueryV2Row r : res.data) rows.add(r.rowData);
            res = String.isBlank(res.nextBatchId) ? null : ConnectApi.CdpQuery.nextBatchAnsiSqlV2(res.nextBatchId);
        }
        return rows;
    }

    static Signals get(Map<String, Signals> m, Object key) {
        String k = String.valueOf(key);
        if (!m.containsKey(k)) m.put(k, new Signals());
        return m.get(k);
    }

    @TestVisible
    static List<List<String>> chunks(List<String> items, Integer size) {
        List<List<String>> out = new List<List<String>>();
        for (Integer i = 0; i < items.size(); i += size) {
            List<String> part = new List<String>();
            for (Integer j = i; j < Math.min(i + size, items.size()); j++) part.add(items[j]);
            out.add(part);
        }
        return out;
    }

    static List<String> escaped(List<String> items) {
        List<String> out = new List<String>();
        for (String s : items) out.add(String.escapeSingleQuotes(s));
        return out;
    }

    static Decimal dec(Object v) {
        if (v == null) return null;
        try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return null; }
    }

    static Integer intVal(Object v) {
        Decimal d = dec(v);
        return d == null ? 0 : d.intValue();
    }

    // ---- CRM advising activity ----------------------------------------------

    // Last advising contact per student: a completed task, a past event or an Enhanced Note.
    @TestVisible
    static Map<Id, Datetime> lastAdvisingContact(List<Contact> students) {
        Set<Id> ids = new Map<Id, Contact>(students).keySet();
        Map<Id, Datetime> out = new Map<Id, Datetime>();
        for (AggregateResult ar : [SELECT WhoId who, MAX(CompletedDateTime) done, MAX(LastModifiedDate) modified
                                   FROM Task WHERE WhoId IN :ids AND IsClosed = true
                                   WITH USER_MODE GROUP BY WhoId]) {
            Datetime d = (Datetime) ar.get('done');
            keepLatest(out, (Id) ar.get('who'), d != null ? d : (Datetime) ar.get('modified'));
        }
        for (AggregateResult ar : [SELECT WhoId who, MAX(EndDateTime) ended FROM Event
                                   WHERE WhoId IN :ids AND EndDateTime <= :Datetime.now()
                                   WITH USER_MODE GROUP BY WhoId]) {
            keepLatest(out, (Id) ar.get('who'), (Datetime) ar.get('ended'));
        }
        try {
            for (ContentDocumentLink l : [SELECT LinkedEntityId, ContentDocument.CreatedDate FROM ContentDocumentLink
                                          WHERE LinkedEntityId IN :ids AND ContentDocument.FileType = 'SNOTE'
                                          WITH USER_MODE LIMIT 2000]) {
                keepLatest(out, l.LinkedEntityId, l.ContentDocument.CreatedDate);
            }
        } catch (Exception ignored) {}
        return out;
    }

    static void keepLatest(Map<Id, Datetime> m, Id key, Datetime value) {
        if (key == null || value == null) return;
        if (!m.containsKey(key) || value > m.get(key)) m.put(key, value);
    }

    // [open follow-ups, overdue follow-ups] per student.
    @TestVisible
    static Map<Id, Integer[]> followUpCounts(List<Contact> students) {
        Set<Id> ids = new Map<Id, Contact>(students).keySet();
        Map<Id, Integer[]> out = new Map<Id, Integer[]>();
        for (Task t : [SELECT WhoId, ActivityDate FROM Task WHERE WhoId IN :ids AND IsClosed = false
                       WITH USER_MODE LIMIT 5000]) {
            if (!out.containsKey(t.WhoId)) out.put(t.WhoId, new Integer[]{ 0, 0 });
            Integer[] c = out.get(t.WhoId);
            c[0]++;
            if (t.ActivityDate != null && t.ActivityDate < Date.today()) c[1]++;
        }
        return out;
    }
}
