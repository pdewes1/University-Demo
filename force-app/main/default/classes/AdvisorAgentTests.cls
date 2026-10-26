/**
 * Tests for the Advisor Agent actions. The focus is the trust boundary: every action must refuse
 * a student owned by another advisor before it touches Data 360, Calendly, the LLM or any record,
 * and the search must never return another advisor's students.
 * Calendly is mocked; the LLM call in DraftStudentEmailAction is not exercised (only its refusal
 * path and the prompt helpers are).
 */
@IsTest
private class AdvisorAgentTests {

    private static final String EVENT_TYPE = 'https://api.calendly.com/event_types/test-event-type';

    @TestSetup
    static void setup() {
        // Another advisor = another user set up for Calendly (User rows are visible to tests). In this
        // org Apex can't compile references to some standard User fields, so the custom field is used.
        User other = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId()
                      AND Calendly_Event_Type_URI__c != null LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = UserInfo.getUserId(), Calendly_Event_Type_URI__c = EVENT_TYPE);
        }
        insert new List<Contact>{
            new Contact(FirstName = 'Testmine', LastName = 'Ownedstudent', Email = 'testmine.owned@example.edu',
                Student_ID__c = 'U99001', OwnerId = UserInfo.getUserId()),
            new Contact(FirstName = 'Testtheirs', LastName = 'Otherstudent', Email = 'testtheirs.other@example.edu',
                Student_ID__c = 'U99002', OwnerId = other.Id)
        };
    }

    private static Contact mine() {
        return [SELECT Id, FirstName, LastName, Email, Student_Level__c, Student_Stage__c FROM Contact WHERE Email = 'testmine.owned@example.edu'];
    }
    private static Contact theirs() { return [SELECT Id FROM Contact WHERE Student_ID__c = 'U99002']; }

    // ---- StudentAccess ----------------------------------------------------

    @IsTest
    static void accessReturnsOnlyOwnedStudents() {
        System.assertNotEquals(null, StudentAccess.ownedStudent(mine().Id));
        System.assertEquals(null, StudentAccess.ownedStudent(theirs().Id), 'Another advisor\'s student must not be returned');
        System.assertEquals(null, StudentAccess.ownedStudent(''));
        System.assertEquals(null, StudentAccess.ownedStudent(UserInfo.getUserId()), 'A non-Contact Id must not be returned');
    }

    // ---- FindStudentsAction -----------------------------------------------

    private static FindStudentsAction.Response find(String text, String stage) {
        FindStudentsAction.Request r = new FindStudentsAction.Request();
        r.searchText = text;
        r.studentStage = stage;
        return FindStudentsAction.find(new List<FindStudentsAction.Request>{ r })[0];
    }

    @IsTest
    static void searchFindsOwnStudentByNameIdEmailAndRecordId() {
        System.assertEquals(1, find('Testmine Ownedstudent', null).matchCount);
        System.assertEquals(1, find('the student with ID u99001 please', null).matchCount, 'Student ID inside a sentence');
        System.assertEquals(1, find('testmine.owned@example.edu', null).matchCount);
        System.assertEquals(1, find(String.valueOf(mine().Id), null).matchCount);
        System.assertEquals(1, find('Mark Testmine Ownedstudent\'s follow-up as done', null).matchCount, 'Word-pair fallback');
    }

    @IsTest
    static void searchNeverReturnsAnotherAdvisorsStudent() {
        for (String q : new List<String>{
                'Testtheirs Otherstudent', 'U99002', 'show me U99002 now', 'testtheirs.other@example.edu',
                String.valueOf(theirs().Id), 'Mark Testtheirs Otherstudent\'s task' }) {
            FindStudentsAction.Response res = find(q, null);
            System.assertEquals(0, res.matchCount, 'Leaked another advisor\'s student for: ' + q);
            System.assert(!res.studentsJson.contains('Otherstudent'), q);
        }
    }

    @IsTest
    static void searchExplainsItsLimitsAndNeedsInput() {
        FindStudentsAction.Response none = find('engagement score below 50', null);
        System.assertEquals(0, none.matchCount);
        System.assert(none.message.contains('cannot filter by engagement'), none.message);
        FindStudentsAction.Response empty = find('', null);
        System.assertEquals(0, empty.matchCount);
        System.assert(empty.message.startsWith('Tell me'), empty.message);
    }

    // ---- UpdateStudentRecordAction ----------------------------------------

    private static UpdateStudentRecordAction.Response updateStudent(Id studentId, String json) {
        UpdateStudentRecordAction.Request r = new UpdateStudentRecordAction.Request();
        r.studentRecordId = studentId;
        r.fieldUpdatesJson = json;
        return UpdateStudentRecordAction.updateStudent(new List<UpdateStudentRecordAction.Request>{ r })[0];
    }

    @IsTest
    static void updateChangesAllowedFieldsOnly() {
        UpdateStudentRecordAction.Response res = updateStudent(mine().Id,
            '{"Title":"Peer mentor","OwnerId":"' + UserInfo.getUserId() + '","Student_ID__c":"U00000"}');
        System.assert(res.success, res.message);
        System.assert(res.message.contains('OwnerId') && res.message.contains('Student_ID__c'), 'Protected fields reported as skipped');
        Contact c = [SELECT Title, Student_ID__c FROM Contact WHERE Id = :mine().Id];
        System.assertEquals('Peer mentor', c.Title);
        System.assertEquals('U99001', c.Student_ID__c, 'Student ID must not change');
    }

    @IsTest
    static void updateRefusesOtherStudentsAndBadInput() {
        UpdateStudentRecordAction.Response refused = updateStudent(theirs().Id, '{"Title":"x"}');
        System.assert(!refused.success);
        System.assert(refused.message.startsWith('There is no student record owned by you'), refused.message);
        System.assertEquals(null, [SELECT Title FROM Contact WHERE Id = :theirs().Id].Title);
        System.assert(!updateStudent(mine().Id, 'not json').success);
        System.assert(!updateStudent(mine().Id, '{"OwnerId":"x"}').success, 'Only protected fields: nothing to update');
    }

    // ---- CreateStudentTaskAction / LogStudentNoteAction -------------------

    @IsTest
    static void taskIsCreatedForOwnStudentOnly() {
        CreateStudentTaskAction.Request r = new CreateStudentTaskAction.Request();
        r.studentRecordId = mine().Id;
        r.subject = 'Follow up on HIST 210';
        r.priority = 'high';
        CreateStudentTaskAction.Response ok = CreateStudentTaskAction.create(new List<CreateStudentTaskAction.Request>{ r })[0];
        System.assert(ok.success, ok.message);
        Task t = [SELECT Priority, ActivityDate, WhoId, OwnerId FROM Task WHERE Id = :ok.taskId];
        System.assertEquals('High', t.Priority);
        System.assertEquals(Date.today().addDays(3), t.ActivityDate, 'Default due date');
        System.assertEquals(UserInfo.getUserId(), t.OwnerId);

        r.studentRecordId = theirs().Id;
        System.assert(!CreateStudentTaskAction.create(new List<CreateStudentTaskAction.Request>{ r })[0].success);
        r.studentRecordId = mine().Id;
        r.subject = ' ';
        System.assert(!CreateStudentTaskAction.create(new List<CreateStudentTaskAction.Request>{ r })[0].success);
        System.assertEquals(1, [SELECT COUNT() FROM Task], 'Only the one allowed task exists');
    }

    @IsTest
    static void noteIsLoggedForOwnStudentOnly() {
        LogStudentNoteAction.Request r = new LogStudentNoteAction.Request();
        r.studentRecordId = mine().Id;
        r.title = 'Advising check-in';
        r.body = 'Discussed a job conflict.\nWill check back Friday.';
        LogStudentNoteAction.Response ok = LogStudentNoteAction.logNote(new List<LogStudentNoteAction.Request>{ r })[0];
        System.assert(ok.success, ok.message);
        System.assertNotEquals(null, ok.noteId);

        r.studentRecordId = theirs().Id;
        LogStudentNoteAction.Response refused = LogStudentNoteAction.logNote(new List<LogStudentNoteAction.Request>{ r })[0];
        System.assert(!refused.success);
        r.studentRecordId = mine().Id;
        r.body = '';
        System.assert(!LogStudentNoteAction.logNote(new List<LogStudentNoteAction.Request>{ r })[0].success);
        System.assertEquals('<p>a &lt;b&gt;</p><p>c</p>', LogStudentNoteAction.toHtml('a <b>\nc'));
    }

    // ---- StudentAdvisingActivity ------------------------------------------

    @IsTest
    static void advisingActivitySummarizesContactAndFollowUps() {
        Id sid = mine().Id;
        System.assert(StudentAdvisingActivity.summarize(sid).contains('none recorded'));
        insert new List<Task>{
            new Task(WhoId = sid, Subject = 'Called student', Status = 'Completed', ActivityDate = Date.today().addDays(-5)),
            new Task(WhoId = sid, Subject = 'Overdue check', Status = 'Not Started', ActivityDate = Date.today().addDays(-1)),
            new Task(WhoId = sid, Subject = 'Upcoming check', Status = 'Not Started', ActivityDate = Date.today().addDays(4))
        };
        insert new Note(ParentId = sid, Title = 'Job conflict', Body = 'x');
        String s = StudentAdvisingActivity.summarize(sid);
        System.assert(s.contains('Last advising contact'), s);
        System.assert(s.contains('1 overdue') && s.contains('Overdue check'), s);
        System.assert(s.contains('next "Upcoming check"'), s);
    }

    @IsTest
    static void advisingActivitySaysNoneOverdue() {
        insert new Task(WhoId = mine().Id, Subject = 'Upcoming', Status = 'Not Started', ActivityDate = Date.today().addDays(2));
        System.assert(StudentAdvisingActivity.summarize(mine().Id).contains('none overdue'));
    }

    // ---- Student360DataAction ---------------------------------------------

    private static Student360DataAction.Response s360(Id studentId) {
        Student360DataAction.Request r = new Student360DataAction.Request();
        r.studentRecordId = studentId;
        return Student360DataAction.getStudent360(new List<Student360DataAction.Request>{ r })[0];
    }

    @IsTest
    static void student360RefusesOtherAdvisorsStudent() {
        Student360DataAction.Response res = s360(theirs().Id);
        System.assert(!res.success);
        System.assert(res.message.startsWith('There is no student record owned by you'), res.message);
        System.assertEquals(null, res.studentSummary, 'Nothing about the student is returned');
    }

    @IsTest
    static void student360WithoutStudentIdStillReturnsCrmActivity() {
        update new Contact(Id = mine().Id, Student_ID__c = null);
        Student360DataAction.Response res = s360(mine().Id);
        System.assert(!res.success);
        System.assert(res.message.contains('no Student ID'), res.message);
        System.assert(res.studentSummary.contains('Last advising contact'), res.studentSummary);
    }

    @IsTest
    static void student360OwnStudentReachesDataCloudLookup() {
        // Data 360 isn't available in tests; the action must fail closed with a message, not throw.
        Student360DataAction.Response res = s360(mine().Id);
        System.assertNotEquals(null, res.message);
    }

    private static final String GRAPH_JSON = '{"IndividualIdentityLink__dlm":[{"ssot__Individual__dlm":[{'
        + '"Snowflake_Canvas_Users__dlm":[{"major__c":"History","class_year__c":"Freshman","campus__c":"Main",'
        + '"enrollment_status__c":"Part-time","last_login__c":"2026-09-15",'
        + '"Snowflake_Canvas_Attendance__dlm":[{"status__c":"present"},{"status__c":"absent"},{"status__c":"tardy"}],'
        + '"Canvas_Submissions__dlm":[{"workflow_state__c":"graded","score__c":45,"points_possible__c":50}],'
        + '"Snowflake_Canvas_Enrollment__dlm":[{"course_id__c":"HIST210","enrollment_state__c":"active","current_score__c":83.3,"final_grade__c":"B"}],'
        + '"Snowflake_Canvas_Page_Views__dlm":[{"duration_seconds__c":600,"event_at__c":"2026-10-13"}],'
        + '"Snowflake_Canvas_Discussion_Entries__dlm":[{"word_count__c":120}]}],'
        + '"Snowflake_Banner_Financial_Aid_Summa__dlm":[{"aid_year__c":2627,"fafsa_status__c":"Received",'
        + '"verification_status__c":"Complete","satisfactory_academic_progress__c":"Met",'
        + '"total_offered__c":13500,"unmet_need__c":2100,"pell_eligible__c":true,"cost_of_attendance__c":30000,'
        + '"student_aid_index__c":4000}]}]}],'
        + '"Student_Engagement_Score__cio":[{"engagement_score__c":71.6}]}';

    @IsTest
    static void financialAidIsReducedToStatusOnly() {
        String redacted = Student360DataAction.redactFinancialAid(GRAPH_JSON);
        for (String amountField : new List<String>{ 'total_offered__c', 'unmet_need__c', 'pell_eligible__c',
                'cost_of_attendance__c', 'student_aid_index__c', '13500', '2100' }) {
            System.assert(!redacted.contains(amountField), 'Aid detail leaked: ' + amountField);
        }
        System.assert(redacted.contains('fafsa_status__c') && redacted.contains('satisfactory_academic_progress__c'));
    }

    @IsTest
    static void summaryCoversEveryDataArea() {
        String s = Student360DataAction.summarize('Test Student', Student360DataAction.redactFinancialAid(GRAPH_JSON));
        for (String expected : new List<String>{ 'major History', 'Engagement score (0-100): 71.6', 'absent 1',
                'average score on graded work 90.0%', 'HIST210', 'LMS page views', 'Discussion posts (recent window): 1',
                'FAFSA Received', 'not available to advisors' }) {
            System.assert(s.contains(expected), 'Missing "' + expected + '" in: ' + s);
        }
        System.assert(!s.contains('13500'), 'No aid amounts in the summary');
    }

    // ---- Calendly (mocked) ------------------------------------------------

    private class CalendlyMock implements HttpCalloutMock {
        Integer status;
        CalendlyMock(Integer status) { this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            if (req.getEndpoint().contains('scheduling_links')) {
                System.assertEquals('POST', req.getMethod());
                System.assert(req.getBody().contains('"max_event_count":1'), 'Links must be single-use');
                res.setBody('{"resource":{"booking_url":"https://calendly.com/d/test-link"}}');
            } else {
                res.setBody('{"collection":[{"name":"Advising","duration":30,"scheduling_url":"https://calendly.com/x","uri":"' + EVENT_TYPE + '"}]}');
            }
            return res;
        }
    }

    private static CreateCalendlyBookingLinkAction.Response link(Id studentId) {
        CreateCalendlyBookingLinkAction.Request r = new CreateCalendlyBookingLinkAction.Request();
        r.studentRecordId = studentId;
        return CreateCalendlyBookingLinkAction.create(new List<CreateCalendlyBookingLinkAction.Request>{ r })[0];
    }

    @IsTest
    static void bookingLinkIsSingleUseAndPrefilled() {
        Test.setMock(HttpCalloutMock.class, new CalendlyMock(201));
        Test.startTest();
        CreateCalendlyBookingLinkAction.Response res = link(mine().Id);
        Test.stopTest();
        System.assert(res.success, res.message);
        System.assert(res.bookingUrl.startsWith('https://calendly.com/d/test-link?name=Testmine'), res.bookingUrl);
        System.assert(res.bookingUrl.contains('email=testmine.owned%40example.edu'), res.bookingUrl);
    }

    @IsTest
    static void bookingLinkRefusedForOtherStudentAndReportsCalendlyErrors() {
        Test.setMock(HttpCalloutMock.class, new CalendlyMock(500));
        Test.startTest();
        CreateCalendlyBookingLinkAction.Response refused = link(theirs().Id);
        CreateCalendlyBookingLinkAction.Response failed = link(mine().Id);
        Test.stopTest();
        System.assert(!refused.success);
        System.assert(refused.message.contains('no student record owned by you'), refused.message);
        System.assert(!failed.success);
        System.assert(failed.message.contains('Calendly returned 500'), failed.message);
    }

    @IsTest
    static void prefillHandlesEmptyValues() {
        System.assertEquals(null, CalendlyService.withPrefill(null, 'A', 'b@c.d'));
        System.assertEquals('https://x', CalendlyService.withPrefill('https://x', null, null));
        System.assertEquals('https://x?a=1&name=A+B', CalendlyService.withPrefill('https://x?a=1', 'A B', null));
    }

    @IsTest
    static void listEventTypesReturnsSlimRows() {
        Test.setMock(HttpCalloutMock.class, new CalendlyMock(200));
        ListCalendlyEventTypesAction.Request r = new ListCalendlyEventTypesAction.Request();
        r.calendlyUserUri = 'https://api.calendly.com/users/test';
        Test.startTest();
        ListCalendlyEventTypesAction.Response res = ListCalendlyEventTypesAction.listTypes(new List<ListCalendlyEventTypesAction.Request>{ r })[0];
        Test.stopTest();
        System.assert(res.message.startsWith('1 event type'), res.message);
        System.assert(res.eventTypesJson.contains(EVENT_TYPE));
    }

    // ---- DraftStudentEmailAction ------------------------------------------

    @IsTest
    static void emailRefusedForOtherStudentBeforeAnyCallout() {
        // No mock is set: any Calendly or LLM callout would fail the test.
        DraftStudentEmailAction.Request r = new DraftStudentEmailAction.Request();
        r.studentRecordId = theirs().Id;
        DraftStudentEmailAction.Response res = DraftStudentEmailAction.draft(new List<DraftStudentEmailAction.Request>{ r })[0];
        System.assert(!res.success);
        System.assert(res.message.startsWith('There is no student record owned by you'), res.message);
        System.assertEquals(null, res.bookingUrl);
    }

    @IsTest
    static void emailPromptKeepsNamesAndLinksOutOfTheModel() {
        Contact s = mine();
        String prompt = DraftStudentEmailAction.buildPrompt(s, 'Testmine Ownedstudent missed HIST 210', 'attendance', 'Paul Advisor', true);
        System.assert(!prompt.contains('Testmine') && !prompt.contains('Ownedstudent'), 'Student name must not reach the model');
        System.assert(prompt.contains('{FIRST_NAME}') && prompt.contains('{BOOKING_LINK}'));
        System.assert(!DraftStudentEmailAction.buildPrompt(s, null, null, 'Paul', false).contains('{BOOKING_LINK} on its own line'));

        System.assertEquals('Hi Ana, book: https://l', DraftStudentEmailAction.fillLink(
            DraftStudentEmailAction.fillNames('Hi {FIRST_NAME}, book: {BOOKING_LINK}', 'Ana', 'Paul'), 'https://l'));
        System.assert(DraftStudentEmailAction.fillLink('Hi there', 'https://l').endsWith('https://l'), 'Link appended when the model omits it');
        System.assertEquals('Hi', DraftStudentEmailAction.fillLink('Hi {BOOKING_LINK}', null));
        System.assertEquals(null, DraftStudentEmailAction.fillLink(null, 'https://l'));
    }
}
