/**
 * Controller for the student360Card Lightning web component on the Student (Contact) record page.
 * Reads the same Student_360_Graph data graph the agent uses and turns it into a handful of
 * numbers and flags an advisor can take in at a glance: the engagement score (calculated insight),
 * attendance, on-time work, course scores, LMS activity, discussion posts and financial aid status.
 * Advising contact and overdue follow-ups are read live from the CRM.
 *
 * Access: the record must be visible to the running user (USER_MODE), the same rule as the
 * Data 360 related lists on the page. Financial aid is status only; no amounts are read.
 */
public with sharing class Student360CardController {

    public class Course {
        @AuraEnabled public String courseId;
        @AuraEnabled public String state;
        @AuraEnabled public Decimal currentScore;
    }

    public class Snapshot {
        @AuraEnabled public Boolean available = false;
        @AuraEnabled public String message;
        @AuraEnabled public String studentName;

        @AuraEnabled public Decimal engagementScore;
        @AuraEnabled public String engagementBand;      // On track | Watch | At risk

        @AuraEnabled public Integer classesRecorded = 0;
        @AuraEnabled public Integer absences = 0;
        @AuraEnabled public Decimal attendanceRate;
        @AuraEnabled public String lastAbsence;

        @AuraEnabled public Integer submissions = 0;
        @AuraEnabled public Integer lateSubmissions = 0;
        @AuraEnabled public Integer missingSubmissions = 0;
        @AuraEnabled public Decimal onTimeRate;
        @AuraEnabled public Decimal averageScore;

        @AuraEnabled public List<Course> courses = new List<Course>();

        @AuraEnabled public Integer pageViews = 0;
        @AuraEnabled public Decimal lmsMinutes = 0;
        @AuraEnabled public String lastLogin;

        @AuraEnabled public Integer discussionPosts = 0;

        @AuraEnabled public String aidYear;
        @AuraEnabled public String fafsaStatus;
        @AuraEnabled public String verificationStatus;
        @AuraEnabled public String sapStatus;

        @AuraEnabled public String lastAdvisingContact;
        @AuraEnabled public Integer daysSinceContact;
        @AuraEnabled public Integer overdueFollowUps = 0;

        @AuraEnabled public List<String> flags = new List<String>();
    }

    @AuraEnabled(cacheable=true)
    public static Snapshot getSnapshot(Id recordId) {
        Snapshot s = new Snapshot();
        List<Contact> found = [
            SELECT Id, Name, Student_ID__c FROM Contact
            WHERE Id = :recordId WITH USER_MODE LIMIT 1
        ];
        if (found.isEmpty()) {
            s.message = 'This student record is not available to you.';
            return s;
        }
        Contact student = found[0];
        s.studentName = student.Name;
        addAdvisingActivity(s, student.Id);

        if (String.isBlank(student.Student_ID__c)) {
            s.message = 'No Student ID on this record, so there is no Data 360 profile to match.';
            finishFlags(s);
            return s;
        }
        try {
            String studentKey = student.Student_ID__c;
            List<SObject> unified = Database.query(
                'SELECT ssot__Id__c FROM UnifiedIndividual__dlm WHERE Student_ID__c = :studentKey LIMIT 1');
            if (unified.isEmpty()) {
                s.message = 'No Data 360 profile found for Student ID ' + studentKey + '.';
                finishFlags(s);
                return s;
            }
            ConnectApi.CdpQueryOutput graph = ConnectApi.CdpQuery.getDataGraphData(
                Student360DataAction.DATA_GRAPH_NAME, (String) unified[0].get('ssot__Id__c'));
            String raw = graphJson(graph);
            if (String.isBlank(raw)) {
                s.message = 'The Student 360 data graph has no data for this student yet.';
                finishFlags(s);
                return s;
            }
            applyGraph(s, raw);
        } catch (Exception e) {
            s.message = 'Data 360 is not reachable right now: ' + e.getMessage();
        }
        finishFlags(s);
        return s;
    }

    // ---- Graph to snapshot --------------------------------------------------

    @TestVisible
    private static void applyGraph(Snapshot s, String raw) {
        Object root = JSON.deserializeUntyped(raw);
        s.available = true;

        Map<String, Object> ci = first(root, 'Student_Engagement_Score__cio');
        if (ci != null && num(ci, 'engagement_score__c') != null) {
            s.engagementScore = num(ci, 'engagement_score__c').setScale(1);
            s.engagementBand = s.engagementScore >= 75 ? 'On track' : (s.engagementScore >= 50 ? 'Watch' : 'At risk');
        }

        List<Map<String, Object>> att = rows(root, 'Snowflake_Canvas_Attendance__dlm');
        Decimal attended = 0; Integer counted = 0; String lastAbsDate = '';
        for (Map<String, Object> a : att) {
            String st = str(a, 'status__c').toLowerCase();
            if (st == 'excused') continue;
            counted++;
            if (st == 'present') attended += 1;
            else if (st == 'tardy') attended += 0.5;
            else if (st == 'absent') {
                s.absences++;
                String d = str(a, 'class_date__c');
                if (d > lastAbsDate) { lastAbsDate = d; s.lastAbsence = str(a, 'course_id__c') + ' on ' + d; }
            }
        }
        s.classesRecorded = att.size();
        if (counted > 0) s.attendanceRate = (attended * 100 / counted).setScale(0);

        List<Map<String, Object>> subs = rows(root, 'Canvas_Submissions__dlm');
        Decimal onTime = 0, earned = 0, possible = 0; Integer scored = 0;
        for (Map<String, Object> sub : subs) {
            String st = str(sub, 'workflow_state__c').toLowerCase();
            if (st == 'excused') continue;
            scored++;
            if (st == 'graded' || st == 'submitted') onTime += 1;
            else if (st == 'late') { onTime += 0.5; s.lateSubmissions++; }
            else if (st == 'missing' || st == 'unsubmitted') s.missingSubmissions++;
            Decimal sc = num(sub, 'score__c'), pp = num(sub, 'points_possible__c');
            if (sc != null && pp != null && pp > 0) { earned += sc; possible += pp; }
        }
        s.submissions = subs.size();
        if (scored > 0) s.onTimeRate = (onTime * 100 / scored).setScale(0);
        if (possible > 0) s.averageScore = (earned * 100 / possible).setScale(0);

        for (Map<String, Object> e : rows(root, 'Snowflake_Canvas_Enrollment__dlm')) {
            Course c = new Course();
            c.courseId = str(e, 'course_id__c');
            c.state = str(e, 'enrollment_state__c');
            Decimal cs = num(e, 'current_score__c');
            c.currentScore = cs == null ? null : cs.setScale(0);
            s.courses.add(c);
        }

        List<Map<String, Object>> pv = rows(root, 'Snowflake_Canvas_Page_Views__dlm');
        Decimal secs = 0;
        for (Map<String, Object> p : pv) { Decimal d = num(p, 'duration_seconds__c'); if (d != null) secs += d; }
        s.pageViews = pv.size();
        s.lmsMinutes = (secs / 60).setScale(0);
        Map<String, Object> user = first(root, 'Snowflake_Canvas_Users__dlm');
        if (user != null && str(user, 'last_login__c') != '') s.lastLogin = str(user, 'last_login__c').left(10);

        s.discussionPosts = rows(root, 'Snowflake_Canvas_Discussion_Entries__dlm').size();

        Map<String, Object> aid = first(root, 'Snowflake_Banner_Financial_Aid_Summa__dlm');
        if (aid != null) {   // status fields only, by design
            s.aidYear = formatAidYear(str(aid, 'aid_year__c'));
            s.fafsaStatus = str(aid, 'fafsa_status__c');
            s.verificationStatus = str(aid, 'verification_status__c');
            s.sapStatus = str(aid, 'satisfactory_academic_progress__c');
        }
    }

    // Banner aid year codes are YYZZ (2627 = the 2026-27 aid year); Data 360 stores them as decimals.
    @TestVisible
    private static String formatAidYear(String raw) {
        if (String.isBlank(raw)) return null;
        Integer code;
        try { code = Decimal.valueOf(raw).intValue(); } catch (Exception e) { return raw; }
        Integer startYy = code / 100, endYy = Math.mod(code, 100);
        if (code >= 1000 && code <= 9999 && Math.mod(startYy + 1, 100) == endYy) {
            return '20' + String.valueOf(startYy).leftPad(2, '0') + '–' + String.valueOf(endYy).leftPad(2, '0');
        }
        return String.valueOf(code);
    }

    // Same signals the agent calls out, as short labels for the card.
    @TestVisible
    private static void finishFlags(Snapshot s) {
        if (s.engagementBand == 'At risk') s.flags.add('Low engagement score');
        if (s.attendanceRate != null && s.attendanceRate < 80) s.flags.add('Attendance below 80%');
        else if (s.absences > 0) s.flags.add(s.absences == 1 ? 'Missed a class' : 'Missed ' + s.absences + ' classes');
        if (s.missingSubmissions > 0) s.flags.add(s.missingSubmissions + ' missing assignment' + (s.missingSubmissions == 1 ? '' : 's'));
        else if (s.lateSubmissions > 0) s.flags.add(s.lateSubmissions + ' late assignment' + (s.lateSubmissions == 1 ? '' : 's'));
        if (s.available && s.discussionPosts == 0) s.flags.add('No discussion posts');
        if (s.available && s.pageViews < 5) s.flags.add('Little LMS activity');
        if (String.isNotBlank(s.fafsaStatus) && s.fafsaStatus.toLowerCase() != 'received') s.flags.add('FAFSA not received');
        if (String.isNotBlank(s.verificationStatus) && s.verificationStatus.toLowerCase().contains('pending'))
            s.flags.add('Aid verification pending');
        if (String.isNotBlank(s.sapStatus) && s.sapStatus.toLowerCase() != 'met')
            s.flags.add('Academic progress: ' + s.sapStatus);
        if (s.daysSinceContact == null) s.flags.add('No advising contact recorded');
        else if (s.daysSinceContact > 30) s.flags.add('No contact in ' + s.daysSinceContact + ' days');
        if (s.overdueFollowUps > 0) s.flags.add(s.overdueFollowUps + ' overdue follow-up' + (s.overdueFollowUps == 1 ? '' : 's'));
    }

    // ---- CRM advising activity ----------------------------------------------

    @TestVisible
    private static void addAdvisingActivity(Snapshot s, Id studentId) {
        Datetime lastAt = null;
        for (Task t : [SELECT CompletedDateTime, LastModifiedDate FROM Task
                       WHERE WhoId = :studentId AND IsClosed = true
                       WITH USER_MODE ORDER BY CompletedDateTime DESC NULLS LAST, LastModifiedDate DESC LIMIT 1]) {
            lastAt = t.CompletedDateTime != null ? t.CompletedDateTime : t.LastModifiedDate;
        }
        for (Event e : [SELECT EndDateTime FROM Event WHERE WhoId = :studentId AND EndDateTime <= :Datetime.now()
                        WITH USER_MODE ORDER BY EndDateTime DESC LIMIT 1]) {
            if (lastAt == null || e.EndDateTime > lastAt) lastAt = e.EndDateTime;
        }
        for (Note n : [SELECT CreatedDate FROM Note WHERE ParentId = :studentId
                       WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1]) {
            if (lastAt == null || n.CreatedDate > lastAt) lastAt = n.CreatedDate;
        }
        try {
            for (ContentDocumentLink l : [SELECT ContentDocument.CreatedDate FROM ContentDocumentLink
                                          WHERE LinkedEntityId = :studentId AND ContentDocument.FileType = 'SNOTE'
                                          WITH USER_MODE ORDER BY ContentDocument.CreatedDate DESC LIMIT 1]) {
                if (lastAt == null || l.ContentDocument.CreatedDate > lastAt) lastAt = l.ContentDocument.CreatedDate;
            }
        } catch (Exception ignored) {}
        if (lastAt != null) {
            s.lastAdvisingContact = lastAt.date().format();
            s.daysSinceContact = lastAt.date().daysBetween(Date.today());
        }
        s.overdueFollowUps = [SELECT COUNT() FROM Task WHERE WhoId = :studentId AND IsClosed = false
                              AND ActivityDate < :Date.today() WITH USER_MODE];
    }

    // ---- JSON helpers -----------------------------------------------------------

    private static String graphJson(ConnectApi.CdpQueryOutput graph) {
        if (graph == null || graph.data == null || graph.data.isEmpty()) return null;
        Map<String, Object> row = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(graph.data[0]));
        for (String key : row.keySet()) {
            Object v = row.get(key);
            if (v instanceof String && ((String) v).trim().startsWith('{')) return (String) v;
        }
        return JSON.serialize(row);
    }

    private static List<Map<String, Object>> rows(Object node, String dmo) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        collect(node, dmo, out);
        return out;
    }

    private static void collect(Object node, String dmo, List<Map<String, Object>> out) {
        if (node instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) node;
            for (String k : m.keySet()) {
                Object v = m.get(k);
                if (k.endsWithIgnoreCase(dmo)) {
                    if (v instanceof List<Object>) {
                        for (Object o : (List<Object>) v) if (o instanceof Map<String, Object>) out.add((Map<String, Object>) o);
                    } else if (v instanceof Map<String, Object>) {
                        out.add((Map<String, Object>) v);
                    }
                }
                collect(v, dmo, out);
            }
        } else if (node instanceof List<Object>) {
            for (Object o : (List<Object>) node) collect(o, dmo, out);
        }
    }

    private static Map<String, Object> first(Object root, String dmo) {
        List<Map<String, Object>> r = rows(root, dmo);
        return r.isEmpty() ? null : r[0];
    }

    private static Object val(Map<String, Object> m, String field) {
        for (String k : m.keySet()) if (k.equalsIgnoreCase(field)) return m.get(k);
        return null;
    }

    private static String str(Map<String, Object> m, String field) {
        Object v = val(m, field);
        return v == null ? '' : String.valueOf(v);
    }

    private static Decimal num(Map<String, Object> m, String field) {
        Object v = val(m, field);
        if (v == null) return null;
        try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return null; }
    }
}
