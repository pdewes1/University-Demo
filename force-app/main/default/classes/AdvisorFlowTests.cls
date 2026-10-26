/**
 * Tests for the hybrid agent's Flow actions. Each flow is run the way the agent runs it, through
 * Flow.Interview, so the tests cover the flow logic and the Flow access check it calls first.
 */
@IsTest
private class AdvisorFlowTests {

    @TestSetup
    static void setup() {
        // Same "other advisor" choice as AdvisorAgentTests: this org's Apex can't reference some
        // standard User fields, so pick another user through the custom Calendly field.
        User other = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId()
                      AND Calendly_Event_Type_URI__c != null LIMIT 1];
        insert new List<Contact>{
            new Contact(FirstName = 'Flowmine', LastName = 'Ownedstudent', Email = 'flowmine.owned@example.edu',
                Student_ID__c = 'U99101', Student_Stage__c = 'On Leave', Phone = '317-555-0100', OwnerId = UserInfo.getUserId()),
            new Contact(FirstName = 'Flowtheirs', LastName = 'Otherstudent', Email = 'flowtheirs.other@example.edu',
                Student_ID__c = 'U99102', Phone = '317-555-0200', OwnerId = other.Id)
        };
    }

    private static Contact mine() {
        return [SELECT Id, Student_Stage__c, Student_Level__c, Email, Phone, MobilePhone, Title, MailingCity, Description
                FROM Contact WHERE Student_ID__c = 'U99101'];
    }
    private static Contact theirs() {
        return [SELECT Id, Phone FROM Contact WHERE Student_ID__c = 'U99102'];
    }
    private static Flow.Interview run(String flowName, Map<String, Object> inputs) {
        Flow.Interview f = Flow.Interview.createInterview(flowName, inputs);
        f.start();
        return f;
    }

    // ---- Advisor_Check_Student_Access (the subflow every agent flow calls first) ---

    @IsTest
    static void accessFlowAllowsOnlyOwnedStudents() {
        Flow.Interview own = run('Advisor_Check_Student_Access', new Map<String, Object>{ 'studentRecordId' => mine().Id });
        System.assertEquals(true, own.getVariableValue('allowed'));
        System.assertEquals('Flowmine Ownedstudent', own.getVariableValue('studentName'));

        Flow.Interview other = run('Advisor_Check_Student_Access', new Map<String, Object>{ 'studentRecordId' => theirs().Id });
        System.assertEquals(false, other.getVariableValue('allowed'));
        System.assertEquals(null, other.getVariableValue('studentName'), 'Nothing about another advisor\'s student is returned');
        System.assert(((String) other.getVariableValue('message')).contains('no student record owned by you'));
    }

    @IsTest
    static void accessFlowRefusesBlankAndMalformedIds() {
        for (String bad : new List<String>{ '', 'not-an-id', '001000000000000AAA' }) {
            Flow.Interview f = run('Advisor_Check_Student_Access', new Map<String, Object>{ 'studentRecordId' => bad });
            System.assertEquals(false, f.getVariableValue('allowed'), 'Refused: ' + bad);
        }
    }

    // ---- Advisor_Create_Student_Task ---------------------------------------

    @IsTest
    static void taskFlowCreatesTaskForOwnStudentWithDefaults() {
        Flow.Interview f = run('Advisor_Create_Student_Task', new Map<String, Object>{
            'studentRecordId' => mine().Id, 'subject' => 'Call about HIST 210', 'priority' => 'high' });

        System.assertEquals(true, f.getVariableValue('success'));
        Task t = [SELECT WhoId, OwnerId, Subject, Priority, Status, ActivityDate FROM Task
                  WHERE Id = :(String) f.getVariableValue('taskId')];
        System.assertEquals(mine().Id, t.WhoId);
        System.assertEquals(UserInfo.getUserId(), t.OwnerId);
        System.assertEquals('High', t.Priority);
        System.assertEquals('Not Started', t.Status);
        System.assertEquals(Date.today().addDays(3), t.ActivityDate, 'Due date defaults to three days out');
        System.assert(((String) f.getVariableValue('message')).contains('Flowmine Ownedstudent'));
    }

    @IsTest
    static void taskFlowRefusesAnotherAdvisorsStudent() {
        Flow.Interview f = run('Advisor_Create_Student_Task', new Map<String, Object>{
            'studentRecordId' => theirs().Id, 'subject' => 'Should not exist' });

        System.assertEquals(false, f.getVariableValue('success'));
        System.assert(((String) f.getVariableValue('message')).contains('no student record owned by you'));
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE Subject = 'Should not exist']);
    }

    @IsTest
    static void taskFlowNeedsASubjectAndUsesGivenDate() {
        Flow.Interview noSubject = run('Advisor_Create_Student_Task', new Map<String, Object>{
            'studentRecordId' => mine().Id, 'subject' => '' });
        System.assertEquals(false, noSubject.getVariableValue('success'));
        System.assertEquals('A task subject is required.', noSubject.getVariableValue('message'));

        Date due = Date.today().addDays(10);
        Flow.Interview dated = run('Advisor_Create_Student_Task', new Map<String, Object>{
            'studentRecordId' => mine().Id, 'subject' => 'Check in', 'dueDate' => due, 'priority' => 'whenever' });
        Task t = [SELECT ActivityDate, Priority FROM Task WHERE Id = :(String) dated.getVariableValue('taskId')];
        System.assertEquals(due, t.ActivityDate);
        System.assertEquals('Normal', t.Priority, 'Unknown priorities fall back to Normal');
    }

    // ---- Advisor_Update_Student_Record -------------------------------------

    @IsTest
    static void updateFlowChangesOnlyGivenFields() {
        Flow.Interview f = run('Advisor_Update_Student_Record', new Map<String, Object>{
            'studentRecordId' => mine().Id, 'studentStage' => 'Enrolled', 'mobilePhone' => '317-555-0111',
            'title' => 'Peer Mentor', 'mailingCity' => 'Waterbury', 'description' => 'Prefers email.' });

        System.assertEquals(true, f.getVariableValue('success'), (String) f.getVariableValue('message'));
        System.assertEquals('Student Stage, Mobile Phone, Title, Description, Mailing City', f.getVariableValue('updatedFields'));
        Contact c = mine();
        System.assertEquals('Enrolled', c.Student_Stage__c);
        System.assertEquals('317-555-0111', c.MobilePhone);
        System.assertEquals('Peer Mentor', c.Title);
        System.assertEquals('Waterbury', c.MailingCity);
        System.assertEquals('Prefers email.', c.Description);
        System.assertEquals('317-555-0100', c.Phone, 'Blank inputs leave fields as they were');
        System.assertEquals('flowmine.owned@example.edu', c.Email);
    }

    @IsTest
    static void updateFlowRefusesAnotherAdvisorsStudent() {
        Flow.Interview f = run('Advisor_Update_Student_Record', new Map<String, Object>{
            'studentRecordId' => theirs().Id, 'phone' => '317-555-0999' });

        System.assertEquals(false, f.getVariableValue('success'));
        System.assert(((String) f.getVariableValue('message')).contains('no student record owned by you'));
        System.assertEquals('317-555-0200', theirs().Phone, 'Another advisor\'s student is untouched');
    }

    @IsTest
    static void updateFlowExplainsWhenNothingToChange() {
        Flow.Interview f = run('Advisor_Update_Student_Record', new Map<String, Object>{ 'studentRecordId' => mine().Id });
        System.assertEquals(false, f.getVariableValue('success'));
        System.assert(((String) f.getVariableValue('message')).startsWith('No changes were given'));
    }

    @IsTest
    static void updateFlowReportsSaveErrors() {
        Flow.Interview f = run('Advisor_Update_Student_Record', new Map<String, Object>{
            'studentRecordId' => mine().Id, 'email' => 'not an email' });
        System.assertEquals(false, f.getVariableValue('success'));
        System.assert(((String) f.getVariableValue('message')).startsWith('Could not update the student record'));
    }
}
