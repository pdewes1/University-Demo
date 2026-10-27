@IsTest
private class AdvisorCaseloadControllerTests {

    static AdvisorCaseloadController.Signals signals(Decimal engagement, Integer classes, Integer absences, Integer missing,
                                                     String lastLogin, String fafsa, String verification, String sap) {
        AdvisorCaseloadController.Signals s = new AdvisorCaseloadController.Signals();
        s.engagement = engagement;
        s.classes = classes;
        s.absences = absences;
        s.missing = missing;
        s.lastLogin = lastLogin;
        s.fafsa = fafsa;
        s.verification = verification;
        s.sap = sap;
        return s;
    }

    @IsTest
    static void ranksOwnStudentsAndCountsKpis() {
        String recent = String.valueOf(Date.today().addDays(-2));
        String stale = String.valueOf(Date.today().addDays(-40));
        List<Contact> students = new List<Contact>{
            new Contact(FirstName = 'Omar', LastName = 'Low', Student_ID__c = 'U09101', Student_Stage__c = 'Enrolled', Program__c = 'BS Mathematics'),
            new Contact(FirstName = 'Kim', LastName = 'Fine', Student_ID__c = 'U09102', Student_Stage__c = 'Enrolled', Preferred_Name__c = 'Kimmy'),
            new Contact(FirstName = 'Lee', LastName = 'Leave', Student_ID__c = 'U09103', Student_Stage__c = 'On Leave'),
            new Contact(FirstName = 'No', LastName = 'Data', Student_ID__c = 'U09104', Student_Stage__c = 'Enrolled'),
            new Contact(FirstName = 'Not', LastName = 'Student')
        };
        insert students;
        // Overdue follow-up on Kim, recent completed contact on Kim.
        insert new List<Task>{
            new Task(WhoId = students[1].Id, Subject = 'Call', ActivityDate = Date.today().addDays(-3), Status = 'Not Started'),
            new Task(WhoId = students[1].Id, Subject = 'Met', Status = 'Completed', ActivityDate = Date.today())
        };

        AdvisorCaseloadController.signalsOverride = new Map<String, AdvisorCaseloadController.Signals>{
            'U09101' => signals(20, 4, 2, 1, stale, 'Not Received', null, 'Met'),
            'U09102' => signals(90, 4, 0, 0, recent, 'Received', 'Not Selected', 'Met'),
            'U09103' => signals(40, 2, 2, 0, stale, 'Received', 'Not Selected', 'Warning')
        };

        Test.startTest();
        AdvisorCaseloadController.Caseload c = AdvisorCaseloadController.getCaseload();
        Test.stopTest();

        System.assertEquals(4, c.totalStudents, 'only Contacts with a Student ID count');
        System.assert(c.dataCloudAvailable);
        System.assertEquals('Omar Low', c.students[0].name, 'the most at-risk student comes first');
        AdvisorCaseloadController.StudentRow omar = c.students[0];
        System.assertEquals('At risk', omar.engagementBand);
        System.assertEquals(50, omar.attendanceRate);
        System.assert(omar.flags.contains('Low engagement'));
        System.assert(omar.flags.contains('Attendance 50%'));
        System.assert(omar.flags.contains('FAFSA not received'));
        System.assert(omar.needsAttention);
        System.assertEquals('Needs attention', omar.status);

        AdvisorCaseloadController.StudentRow kim, lee;
        for (AdvisorCaseloadController.StudentRow r : c.students) {
            if (r.studentId == 'U09102') kim = r;
            if (r.studentId == 'U09103') lee = r;
        }
        System.assertEquals('Kimmy Fine', kim.name, 'preferred name is used');
        System.assertEquals(1, kim.overdueFollowUps);
        System.assertEquals(1, kim.openFollowUps);
        System.assertEquals(0, kim.daysSinceContact);
        System.assertEquals('On track', kim.engagementBand);
        System.assertEquals('Watch', kim.status, 'an overdue follow-up alone is worth watching');

        System.assertEquals('On leave', lee.engagementBand);
        System.assert(!lee.flags.contains('Low engagement'), 'on-leave students are not flagged for engagement');
        System.assert(lee.flags.contains('Academic progress: Warning'));

        System.assertEquals(1, c.overdueFollowUps);
        System.assertEquals(1, c.onLeave);
        System.assertEquals(2, c.aidActionNeeded, 'FAFSA not received and SAP warning');
        System.assertEquals(3, c.noRecentContact, 'everyone except Kim');
        System.assertEquals(55, c.averageEngagement, 'average of enrolled students with a score (20 and 90)');
    }

    @IsTest
    static void othersStudentsAreNotShown() {
        User other = [SELECT Id FROM User WHERE Id != :UserInfo.getUserId()
                      AND Calendly_Event_Type_URI__c != null LIMIT 1];   // an advisor user, as in AdvisorAgentTests
        insert new Contact(FirstName = 'Their', LastName = 'Student', Student_ID__c = 'U09201', OwnerId = other.Id);
        AdvisorCaseloadController.signalsOverride = new Map<String, AdvisorCaseloadController.Signals>();
        AdvisorCaseloadController.Caseload c = AdvisorCaseloadController.getCaseload();
        for (AdvisorCaseloadController.StudentRow r : c.students) {
            System.assertNotEquals('U09201', r.studentId, 'another advisor\'s student never appears');
        }
    }

    @IsTest
    static void emptyCaseloadAndDataCloudFallback() {
        AdvisorCaseloadController.Caseload empty = AdvisorCaseloadController.getCaseload();
        System.assertEquals(0, empty.totalStudents);
        System.assertEquals('No students are assigned to you yet.', empty.message);

        insert new Contact(FirstName = 'Solo', LastName = 'Student', Student_ID__c = 'U09301', Student_Stage__c = 'Enrolled');
        // No override: Data 360 isn't reachable in tests, so the list falls back to CRM activity.
        AdvisorCaseloadController.Caseload c = AdvisorCaseloadController.getCaseload();
        System.assertEquals(1, c.totalStudents);
        System.assert(!c.dataCloudAvailable);
        System.assertNotEquals(null, c.message);
        System.assert(c.students[0].flags.isEmpty(), 'no signals, no flags');
        System.assertEquals('On track', c.students[0].status);
        System.assertEquals(1, c.noRecentContact, 'never contacted still counts in the tile');
    }

    @IsTest
    static void helpers() {
        List<List<String>> parts = AdvisorCaseloadController.chunks(new List<String>{ 'a', 'b', 'c' }, 2);
        System.assertEquals(2, parts.size());
        System.assertEquals(1, parts[1].size());
        System.assertEquals('No aid record', AdvisorCaseloadController.aidLabel(signals(null, 0, 0, 0, null, null, null, null)));
        System.assertEquals('Verification pending', AdvisorCaseloadController.aidLabel(signals(null, 0, 0, 0, null, 'Received', 'Selected - Pending', 'Met')));
        System.assertEquals('SAP Warning', AdvisorCaseloadController.aidLabel(signals(null, 0, 0, 0, null, 'Received', 'Not Selected', 'Warning')));
        System.assertEquals('On track', AdvisorCaseloadController.aidLabel(signals(null, 0, 0, 0, null, 'Received', 'Not Selected', 'Met')));
    }
}
