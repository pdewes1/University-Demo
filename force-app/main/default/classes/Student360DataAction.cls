/**
 * Agent action: returns Data 360 context for a Student (Contact) from the
 * Student_360_Graph data graph so an Academic Advisor can act on it.
 * Resolves Contact.Student_ID__c -> UnifiedIndividual__dlm.ssot__Id__c, reads the
 * graph by that key, and returns a readable summary plus the raw graph JSON.
 * Also reads advising activity live from the CRM (last advising contact and overdue
 * follow-ups), since tasks and notes change during the day and the graph refreshes daily.
 * Only students owned by the running user are returned.
 */
public with sharing class Student360DataAction {

    public static final String DATA_GRAPH_NAME = 'Student_360_Graph';
    private static final Integer MAX_RAW_CHARS = 60000;

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Salesforce Id of the Student (Contact) record.' required=true)
        public String studentRecordId;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when Data 360 data was found for the student.')
        public Boolean success;
        @InvocableVariable(label='Message' description='Status or error message for the advisor.')
        public String message;
        @InvocableVariable(label='Student Summary' description='Readable summary of attendance, coursework, grades, engagement, discussion activity and financial aid status.')
        public String studentSummary;
        @InvocableVariable(label='Student 360 JSON' description='Raw data graph JSON for the student, for detailed follow-up questions.')
        public String student360Json;
    }

    @InvocableMethod(label='Get Student 360 Data' description='Retrieves attendance, submissions, enrollment, page views, discussion entries, financial aid status and engagement score for a student from the Student 360 data graph.')
    public static List<Response> getStudent360(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            results.add(handle(req));
        }
        return results;
    }

    private static Response handle(Request req) {
        Response res = new Response();
        res.success = false;
        try {
            List<Contact> students = [
                SELECT Id, Name, Student_ID__c, OwnerId
                FROM Contact WHERE Id = :req.studentRecordId
                WITH USER_MODE LIMIT 1
            ];
            if (students.isEmpty() || students[0].OwnerId != UserInfo.getUserId()) {
                res.message = 'There is no student record owned by you with that information.';
                return res;
            }
            Contact student = students[0];
            String advising = StudentAdvisingActivity.summarize(student.Id);
            res.studentSummary = advising; // returned even if Data 360 has nothing
            if (String.isBlank(student.Student_ID__c)) {
                res.message = student.Name + ' has no Student ID, so Data 360 data cannot be matched.';
                return res;
            }
            String studentKey = student.Student_ID__c;
            List<SObject> unified = Database.query(
                'SELECT ssot__Id__c FROM UnifiedIndividual__dlm WHERE Student_ID__c = :studentKey LIMIT 1');
            if (unified.isEmpty()) {
                res.message = 'No Data 360 profile was found for Student ID ' + studentKey + '.';
                return res;
            }
            String unifiedId = (String) unified[0].get('ssot__Id__c');

            ConnectApi.CdpQueryOutput graph = ConnectApi.CdpQuery.getDataGraphData(DATA_GRAPH_NAME, unifiedId);
            String raw = extractGraphJson(graph);
            if (String.isBlank(raw)) {
                res.message = 'The Student 360 data graph returned no data for ' + student.Name + '. The graph may still be building.';
                return res;
            }
            raw = redactFinancialAid(raw);
            res.student360Json = raw.length() > MAX_RAW_CHARS ? raw.substring(0, MAX_RAW_CHARS) : raw;
            res.studentSummary = summarize(student.Name, raw) + '\n' + advising;
            res.success = true;
            res.message = 'Data 360 data retrieved for ' + student.Name + '.';
        } catch (Exception e) {
            res.message = 'Could not retrieve Data 360 data: ' + e.getMessage();
        }
        return res;
    }

    // The graph row carries the nested record as a JSON string field (name varies by release).
    private static String extractGraphJson(ConnectApi.CdpQueryOutput graph) {
        if (graph == null || graph.data == null || graph.data.isEmpty()) return null;
        Map<String, Object> row = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(graph.data[0]));
        for (String key : row.keySet()) {
            Object v = row.get(key);
            if (v instanceof String && ((String) v).trim().startsWith('{')) return (String) v;
        }
        return JSON.serialize(row);
    }

    // ---- Summary ----------------------------------------------------------

    @TestVisible
    private static String summarize(String studentName, String raw) {
        Object root = JSON.deserializeUntyped(raw);
        List<String> lines = new List<String>{ 'Student 360 summary for ' + studentName + ':' };

        Map<String, Object> users = firstRecord(root, 'Snowflake_Canvas_Users__dlm');
        if (users != null) {
            lines.add('- Profile: major ' + str(users, 'major__c') + ', class year ' + str(users, 'class_year__c')
                + ', campus ' + str(users, 'campus__c') + ', enrollment status ' + str(users, 'enrollment_status__c')
                + ', last LMS login ' + str(users, 'last_login__c') + '.');
        }

        Map<String, Object> ci = firstRecord(root, 'Student_Engagement_Score__cio');
        if (ci != null) lines.add('- Engagement score (0-100): ' + str(ci, 'engagement_score__c') + '.');

        List<Map<String, Object>> att = records(root, 'Snowflake_Canvas_Attendance__dlm');
        if (!att.isEmpty()) {
            Map<String, Integer> c = countBy(att, 'status__c');
            Integer counted = att.size() - nz(c.get('excused'));
            Decimal rate = counted > 0 ? (nz(c.get('present')) + 0.5 * nz(c.get('tardy'))) * 100 / counted : 0;
            lines.add('- Attendance: ' + att.size() + ' class records; present ' + nz(c.get('present'))
                + ', tardy ' + nz(c.get('tardy')) + ', absent ' + nz(c.get('absent')) + ', excused ' + nz(c.get('excused'))
                + ' (attendance rate ' + rate.setScale(1) + '%).');
        }

        List<Map<String, Object>> subs = records(root, 'Canvas_Submissions__dlm');
        if (!subs.isEmpty()) {
            Map<String, Integer> c = countBy(subs, 'workflow_state__c');
            Decimal earned = 0, possible = 0;
            for (Map<String, Object> s : subs) {
                Decimal sc = num(s, 'score__c'), pp = num(s, 'points_possible__c');
                if (sc != null && pp != null && pp > 0) { earned += sc; possible += pp; }
            }
            String pct = possible > 0 ? (earned * 100 / possible).setScale(1) + '%' : 'n/a';
            lines.add('- Submissions (recent window): ' + subs.size() + ' total; states ' + JSON.serialize(c)
                + '; average score on graded work ' + pct + '.');
        }

        List<Map<String, Object>> enr = records(root, 'Snowflake_Canvas_Enrollment__dlm');
        if (!enr.isEmpty()) {
            List<String> courses = new List<String>();
            for (Map<String, Object> e : enr) {
                String grade = str(e, 'final_grade__c');
                courses.add(str(e, 'course_id__c') + ' (' + str(e, 'enrollment_state__c') + ', current score '
                    + str(e, 'current_score__c') + (grade == 'n/a' ? '' : ', final grade ' + grade) + ')');
            }
            lines.add('- Enrollments: ' + String.join(courses, '; ') + '.');
        }

        List<Map<String, Object>> pv = records(root, 'Snowflake_Canvas_Page_Views__dlm');
        if (!pv.isEmpty()) {
            Decimal secs = 0; String latest = '';
            for (Map<String, Object> p : pv) {
                Decimal d = num(p, 'duration_seconds__c'); if (d != null) secs += d;
                String at = str(p, 'event_at__c'); if (at != 'n/a' && at > latest) latest = at;
            }
            lines.add('- LMS page views (recent window): ' + pv.size() + ' views, ' + (secs / 60).setScale(0)
                + ' minutes total, most recent ' + (latest == '' ? 'n/a' : latest) + '.');
        }

        List<Map<String, Object>> disc = records(root, 'Snowflake_Canvas_Discussion_Entries__dlm');
        if (!disc.isEmpty()) {
            Decimal words = 0;
            for (Map<String, Object> d : disc) { Decimal w = num(d, 'word_count__c'); if (w != null) words += w; }
            lines.add('- Discussion posts (recent window): ' + disc.size() + ' entries, average '
                + (words / disc.size()).setScale(0) + ' words.');
        } else {
            lines.add('- Discussion posts (recent window): none.');
        }

        Map<String, Object> aid = firstRecord(root, 'Snowflake_Banner_Financial_Aid_Summa__dlm');
        if (aid != null) {
            lines.add('- Financial aid status (aid year ' + str(aid, 'aid_year__c') + '): FAFSA ' + str(aid, 'fafsa_status__c')
                + ', verification ' + str(aid, 'verification_status__c') + ', satisfactory academic progress '
                + str(aid, 'satisfactory_academic_progress__c')
                + '. Award amounts and need are not available to advisors; refer the student to the financial aid office.');
        }
        return String.join(lines, '\n');
    }

    // ---- Financial aid: advisors see status only --------------------------

    // Allow-list: anything not listed (amounts, need, cost of attendance, SAI, Pell, dependency) is removed.
    @TestVisible
    private static final Set<String> AID_VISIBLE_FIELDS = new Set<String>{
        'aid_year__c', 'fafsa_status__c', 'fafsa_received_date__c',
        'verification_status__c', 'satisfactory_academic_progress__c', 'banner_id__c'
    };

    @TestVisible
    private static String redactFinancialAid(String raw) {
        Object root = JSON.deserializeUntyped(raw);
        redactNode(root);
        return JSON.serialize(root);
    }

    private static void redactNode(Object node) {
        if (node instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) node;
            for (String k : m.keySet()) {
                Object v = m.get(k);
                if (k.endsWithIgnoreCase('Snowflake_Banner_Financial_Aid_Summa__dlm')) {
                    if (v instanceof List<Object>) {
                        for (Object o : (List<Object>) v) if (o instanceof Map<String, Object>) keepOnly((Map<String, Object>) o);
                    } else if (v instanceof Map<String, Object>) {
                        keepOnly((Map<String, Object>) v);
                    }
                } else {
                    redactNode(v);
                }
            }
        } else if (node instanceof List<Object>) {
            for (Object o : (List<Object>) node) redactNode(o);
        }
    }

    private static void keepOnly(Map<String, Object> rec) {
        for (String k : new List<String>(rec.keySet())) {
            if (!AID_VISIBLE_FIELDS.contains(k.toLowerCase())) rec.remove(k);
        }
    }

    // Find every list stored under a key ending with the DMO name, anywhere in the tree.
    private static List<Map<String, Object>> records(Object node, String dmo) {
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

    private static Map<String, Object> firstRecord(Object root, String dmo) {
        List<Map<String, Object>> r = records(root, dmo);
        return r.isEmpty() ? null : r[0];
    }

    private static Map<String, Integer> countBy(List<Map<String, Object>> rows, String field) {
        Map<String, Integer> c = new Map<String, Integer>();
        for (Map<String, Object> r : rows) {
            String v = str(r, field).toLowerCase();
            c.put(v, nz(c.get(v)) + 1);
        }
        return c;
    }

    private static Object val(Map<String, Object> m, String field) {
        for (String k : m.keySet()) if (k.equalsIgnoreCase(field)) return m.get(k);
        return null;
    }

    private static String str(Map<String, Object> m, String field) {
        Object v = val(m, field);
        if (v == null) return 'n/a';
        if (v instanceof Decimal) return ((Decimal) v).stripTrailingZeros().toPlainString();
        if (v instanceof Double) return Decimal.valueOf((Double) v).stripTrailingZeros().toPlainString();
        return String.valueOf(v);
    }

    private static Decimal num(Map<String, Object> m, String field) {
        Object v = val(m, field);
        if (v == null) return null;
        try { return Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { return null; }
    }

    private static Integer nz(Integer i) { return i == null ? 0 : i; }
}
