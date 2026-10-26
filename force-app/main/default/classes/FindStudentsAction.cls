/**
 * Agent action: searches the running advisor's own students.
 * Replaces the standard Query Records action, whose "only my students" rule was an
 * instruction to an LLM-built query rather than an enforced filter. Here the owner
 * filter is in the SOQL, so other advisors' students never reach the agent.
 */
public with sharing class FindStudentsAction {

    private static final Integer MAX_RESULTS = 25;
    private static final Set<String> STOP_WORDS = new Set<String>{
        'student', 'students', 'id', 'the', 'with', 'named', 'name', 'and', 'my', 'a', 'an', 'of'
    };

    public class Request {
        @InvocableVariable(label='Search Text' description='Student name (full or partial), Student ID such as U00002, email address, or record Id. Leave blank to list students by stage or level.')
        public String searchText;
        @InvocableVariable(label='Student Stage' description='Optional Student Stage filter, for example Enrolled or On Leave.')
        public String studentStage;
        @InvocableVariable(label='Student Level' description='Optional Student Level filter, for example Undergraduate or Graduate.')
        public String studentLevel;
    }

    public class Response {
        @InvocableVariable(label='Students JSON' description='Matching students owned by the advisor: Id, Name, Student ID, Email, Stage and Level.')
        public String studentsJson;
        @InvocableVariable(label='Match Count' description='Number of matching students returned.')
        public Integer matchCount;
        @InvocableVariable(label='Message' description='Status message for the advisor.')
        public String message;
    }

    @InvocableMethod(label='Find Students' description='Searches only the students owned by the running advisor, by name, Student ID, email or record Id, with optional stage and level filters.')
    public static List<Response> find(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) out.add(handle(r));
        return out;
    }

    @TestVisible
    private static Response handle(Request req) {
        Response res = new Response();
        Id me = UserInfo.getUserId();
        String text = req.searchText == null ? '' : req.searchText.trim();
        String stage = String.isBlank(req.studentStage) ? null : req.studentStage.trim();
        String level = String.isBlank(req.studentLevel) ? null : req.studentLevel.trim();

        if (text == '' && stage == null && level == null) {
            res.matchCount = 0;
            res.message = 'Tell me a student name, Student ID or email to search for.';
            return res;
        }

        // Owner filter is always applied first; everything else narrows within it.
        List<String> clauses = new List<String>{ 'OwnerId = :me' };
        Id recordId = null;
        String exact = null;
        List<String> words = new List<String>();
        if (text != '') {
            // Look at each token: a record Id, email or Student ID anywhere in the text wins over
            // name words, so "Aisha Chen U00974" resolves to that one student.
            for (String raw : text.split('\\s+')) {
                String tok = raw.replaceAll('^[^A-Za-z0-9@]+|[^A-Za-z0-9@.]+$', '').removeEnd('.').removeEndIgnoreCase('\'s');
                if (tok == '') continue;
                if ((tok.length() == 15 || tok.length() == 18) && tok.startsWith('003')) {
                    try { recordId = Id.valueOf(tok); continue; } catch (Exception e) { recordId = null; }
                }
                if (tok.contains('@')) { exact = tok; continue; }
                if (Pattern.matches('(?i)U\\d{3,}', tok)) { exact = tok.toUpperCase(); continue; }
                if (!STOP_WORDS.contains(tok.toLowerCase())) words.add('%' + tok + '%');
            }
            if (recordId != null) {
                clauses.add('Id = :recordId');
            } else if (exact != null) {
                clauses.add('(Email = :exact OR Student_ID__c = :exact)');
            } else {
                for (Integer i = 0; i < words.size() && i < 4; i++) clauses.add('Name LIKE :w' + i);
            }
            if (recordId != null || exact != null) words.clear();
        }
        if (stage != null) clauses.add('Student_Stage__c = :stage');
        if (level != null) clauses.add('Student_Level__c = :level');

        Map<String, Object> binds = new Map<String, Object>{ 'me' => me };
        if (recordId != null) binds.put('recordId', recordId);
        if (exact != null) binds.put('exact', exact);
        if (stage != null) binds.put('stage', stage);
        if (level != null) binds.put('level', level);
        for (Integer i = 0; i < words.size() && i < 4; i++) binds.put('w' + i, words[i]);

        String soql = 'SELECT Id, Name, Student_ID__c, Email, Student_Stage__c, Student_Level__c FROM Contact WHERE '
            + String.join(clauses, ' AND ') + ' ORDER BY Name LIMIT ' + MAX_RESULTS;
        List<Contact> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

        // Extra words ("Mark Priya Cooper's follow-up") make the all-words match fail. Fall back to
        // adjacent word pairs, still inside the owner filter, and use the first pair that matches.
        if (rows.isEmpty() && recordId == null && exact == null && words.size() > 2) {
            List<String> base = new List<String>{ 'OwnerId = :me' };
            if (stage != null) base.add('Student_Stage__c = :stage');
            if (level != null) base.add('Student_Level__c = :level');
            for (Integer i = 0; i + 1 < words.size() && rows.isEmpty(); i++) {
                Map<String, Object> pairBinds = new Map<String, Object>{ 'me' => me, 'p0' => words[i], 'p1' => words[i + 1] };
                if (stage != null) pairBinds.put('stage', stage);
                if (level != null) pairBinds.put('level', level);
                String pairSoql = 'SELECT Id, Name, Student_ID__c, Email, Student_Stage__c, Student_Level__c FROM Contact WHERE '
                    + String.join(base, ' AND ') + ' AND Name LIKE :p0 AND Name LIKE :p1 ORDER BY Name LIMIT ' + MAX_RESULTS;
                rows = Database.queryWithBinds(pairSoql, pairBinds, AccessLevel.USER_MODE);
            }
        }

        List<Map<String, Object>> students = new List<Map<String, Object>>();
        for (Contact c : rows) {
            students.add(new Map<String, Object>{
                'Id' => c.Id, 'Name' => c.Name, 'StudentId' => c.Student_ID__c, 'Email' => c.Email,
                'Stage' => c.Student_Stage__c, 'Level' => c.Student_Level__c
            });
        }
        res.matchCount = students.size();
        res.studentsJson = JSON.serialize(students);
        res.message = students.isEmpty()
            ? 'No students owned by you match that search. This search finds your students by name, Student ID, email, '
                + 'record Id, stage or level only; it cannot filter by engagement score, grades, attendance or other Data 360 data.'
            : students.size() + ' of your students match' + (students.size() == MAX_RESULTS ? ' (showing the first ' + MAX_RESULTS + ')' : '') + '.';
        return res;
    }
}
