@IsTest
private class Student360CardControllerTests {

    // A trimmed graph payload shaped like Student_360_Graph output.
    private static final String GRAPH = JSON.serialize(new Map<String, Object>{
        'ssot__Id__c' => 'UI-1',
        'Student_Engagement_Score__cio' => new List<Object>{ new Map<String, Object>{ 'engagement_score__c' => 71.6 } },
        'ssot__Individual__dlm' => new List<Object>{ new Map<String, Object>{
            'Snowflake_Canvas_Users__dlm' => new List<Object>{ new Map<String, Object>{
                'last_login__c' => '2026-09-15T14:02:00.000Z',
                'Snowflake_Canvas_Attendance__dlm' => new List<Object>{
                    new Map<String, Object>{ 'status__c' => 'present', 'class_date__c' => '2026-09-08', 'course_id__c' => 'ENG 101' },
                    new Map<String, Object>{ 'status__c' => 'present', 'class_date__c' => '2026-09-09', 'course_id__c' => 'MATH 120' },
                    new Map<String, Object>{ 'status__c' => 'absent', 'class_date__c' => '2026-09-10', 'course_id__c' => 'HIST 210' },
                    new Map<String, Object>{ 'status__c' => 'excused', 'class_date__c' => '2026-09-11', 'course_id__c' => 'HIST 210' }
                },
                'Canvas_Submissions__dlm' => new List<Object>{
                    new Map<String, Object>{ 'workflow_state__c' => 'graded', 'score__c' => 47, 'points_possible__c' => 50 },
                    new Map<String, Object>{ 'workflow_state__c' => 'late', 'score__c' => 45, 'points_possible__c' => 50 },
                    new Map<String, Object>{ 'workflow_state__c' => 'missing' }
                },
                'Snowflake_Canvas_Enrollment__dlm' => new List<Object>{
                    new Map<String, Object>{ 'course_id__c' => 'HIST 210', 'enrollment_state__c' => 'active', 'current_score__c' => 88.4 }
                },
                'Snowflake_Canvas_Page_Views__dlm' => new List<Object>{
                    new Map<String, Object>{ 'duration_seconds__c' => 120 },
                    new Map<String, Object>{ 'duration_seconds__c' => 180 }
                }
            } },
            'Snowflake_Banner_Financial_Aid_Summa__dlm' => new List<Object>{ new Map<String, Object>{
                'aid_year__c' => 2026, 'fafsa_status__c' => 'Received',
                'verification_status__c' => 'Selected - Pending', 'satisfactory_academic_progress__c' => 'Warning'
            } }
        } }
    });

    @IsTest
    static void graphBecomesSnapshot() {
        Student360CardController.Snapshot s = new Student360CardController.Snapshot();
        Student360CardController.applyGraph(s, GRAPH);

        System.assert(s.available);
        System.assertEquals(71.6, s.engagementScore);
        System.assertEquals('Watch', s.engagementBand);
        System.assertEquals(4, s.classesRecorded);
        System.assertEquals(1, s.absences);
        System.assertEquals(67, s.attendanceRate, 'excused classes do not count');
        System.assertEquals('HIST 210 on 2026-09-10', s.lastAbsence);
        System.assertEquals(3, s.submissions);
        System.assertEquals(1, s.lateSubmissions);
        System.assertEquals(1, s.missingSubmissions);
        System.assertEquals(50, s.onTimeRate);
        System.assertEquals(92, s.averageScore);
        System.assertEquals(1, s.courses.size());
        System.assertEquals(88, s.courses[0].currentScore);
        System.assertEquals(2, s.pageViews);
        System.assertEquals(5, s.lmsMinutes);
        System.assertEquals('2026-09-15', s.lastLogin);
        System.assertEquals(0, s.discussionPosts);
        System.assertEquals('Received', s.fafsaStatus);
        System.assertEquals('Warning', s.sapStatus);
    }

    @IsTest
    static void flagsMatchWhatTheAgentCallsOut() {
        Student360CardController.Snapshot s = new Student360CardController.Snapshot();
        Student360CardController.applyGraph(s, GRAPH);
        s.daysSinceContact = 45;
        s.overdueFollowUps = 2;
        Student360CardController.finishFlags(s);

        System.assert(s.flags.contains('Attendance below 80%'), s.flags);
        System.assert(s.flags.contains('1 missing assignment'), s.flags);
        System.assert(s.flags.contains('No discussion posts'), s.flags);
        System.assert(s.flags.contains('Little LMS activity'), s.flags);
        System.assert(s.flags.contains('Aid verification pending'), s.flags);
        System.assert(s.flags.contains('Academic progress: Warning'), s.flags);
        System.assert(s.flags.contains('No contact in 45 days'), s.flags);
        System.assert(s.flags.contains('2 overdue follow-ups'), s.flags);
        System.assert(!s.flags.contains('FAFSA not received'), s.flags);
    }

    @IsTest
    static void lowScoreIsAtRiskAndHighScoreOnTrack() {
        Student360CardController.Snapshot low = new Student360CardController.Snapshot();
        Student360CardController.applyGraph(low, '{"Student_Engagement_Score__cio":[{"engagement_score__c":42}]}');
        System.assertEquals('At risk', low.engagementBand);
        Student360CardController.finishFlags(low);
        System.assert(low.flags.contains('Low engagement score'));
        System.assert(low.flags.contains('No advising contact recorded'));

        Student360CardController.Snapshot high = new Student360CardController.Snapshot();
        Student360CardController.applyGraph(high, '{"Student_Engagement_Score__cio":[{"engagement_score__c":88}]}');
        System.assertEquals('On track', high.engagementBand);
    }

    @IsTest
    static void advisingActivityComesFromTheCrm() {
        Contact c = new Contact(LastName = 'Cooper', FirstName = 'Priya');
        insert c;
        insert new Task(WhoId = c.Id, Subject = 'Check-in call', Status = 'Completed');
        insert new Task(WhoId = c.Id, Subject = 'Follow up', Status = 'Not Started', ActivityDate = Date.today().addDays(-2));

        Student360CardController.Snapshot s = Student360CardController.getSnapshot(c.Id);
        System.assertEquals('Priya Cooper', s.studentName);
        System.assertEquals(0, s.daysSinceContact);
        System.assertEquals(1, s.overdueFollowUps);
        System.assert(s.message.contains('No Student ID'), s.message);
        System.assert(!s.available);
    }

    @IsTest
    static void studentWithIdReachesTheDataCloudLookup() {
        Contact c = new Contact(LastName = 'Allen', FirstName = 'Aisha', Student_ID__c = 'U00099');
        insert c;
        Student360CardController.Snapshot s = Student360CardController.getSnapshot(c.Id);
        // Data 360 objects can't be queried in Apex tests, so this ends in a handled message.
        System.assertNotEquals(null, s.message);
        System.assertEquals('Aisha Allen', s.studentName);
    }

    @IsTest
    static void unknownRecordIsNotAvailable() {
        Contact c = new Contact(LastName = 'Gone');
        insert c;
        Id gone = c.Id;
        delete c;
        Student360CardController.Snapshot s = Student360CardController.getSnapshot(gone);
        System.assertEquals('This student record is not available to you.', s.message);
    }
}
