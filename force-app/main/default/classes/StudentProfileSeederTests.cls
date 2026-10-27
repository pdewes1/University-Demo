@IsTest
private class StudentProfileSeederTests {

    @IsTest
    static void fillsBlankProfileFieldsAndKeepsExistingOnes() {
        insert new List<Contact>{
            new Contact(FirstName = 'Michael', LastName = 'Reyes', Student_ID__c = 'U09001'),
            new Contact(FirstName = 'Dana', LastName = 'Lee', Student_ID__c = 'U09002', Student_Level__c = 'Graduate',
                        Student_Stage__c = 'On Leave', Title = 'Nurse Manager'),
            new Contact(FirstName = 'Not', LastName = 'AStudent')
        };
        StudentProfileSeeder.Request req = new StudentProfileSeeder.Request();
        req.overwrite = false;
        List<StudentProfileSeeder.Result> res = StudentProfileSeeder.run(new List<StudentProfileSeeder.Request>{ req });
        System.assertEquals(2, res[0].updated);

        Contact a = [SELECT Program__c, Program_Modality__c, Enrollment_Intensity__c, Start_Term__c, Expected_Graduation_Term__c,
                            Preferred_Name__c, MobilePhone, Student_Level__c, Student_Stage__c, Description
                     FROM Contact WHERE Student_ID__c = 'U09001'];
        System.assertNotEquals(null, a.Program__c);
        System.assertNotEquals(null, a.Program_Modality__c);
        System.assertNotEquals(null, a.Start_Term__c);
        System.assertNotEquals(null, a.Expected_Graduation_Term__c);
        System.assertEquals('Mike', a.Preferred_Name__c);
        System.assert(a.MobilePhone.startsWith('(555) 555-'));
        System.assertEquals('Enrolled', a.Student_Stage__c, 'blank stage is filled');
        System.assert(a.Description.contains(a.Program__c));

        Contact b = [SELECT Program__c, Enrollment_Intensity__c, Title, Student_Level__c, Student_Stage__c
                     FROM Contact WHERE Student_ID__c = 'U09002'];
        System.assertEquals('Nurse Manager', b.Title, 'existing values are kept');
        System.assertEquals('Graduate', b.Student_Level__c);
        System.assertEquals('On Leave', b.Student_Stage__c);
        System.assertEquals('Part-time', b.Enrollment_Intensity__c, 'students on leave are part-time');
        System.assert(b.Program__c == 'MBA' || b.Program__c.startsWith('MS ') || b.Program__c.startsWith('MA '),
            'graduate students get a graduate program: ' + b.Program__c);

        System.assertEquals(null, [SELECT Program__c FROM Contact WHERE LastName = 'AStudent'].Program__c);
    }

    @IsTest
    static void canvasProfileDrivesProgramModalityIntensityAndTerms() {
        StudentProfileSeeder.canvasProfiles = new Map<String, List<String>>{
            'U09010' => new List<String>{ 'Psychology', 'Senior', 'Full-time', 'Downtown Campus' },
            'U09011' => new List<String>{ 'History', 'Freshman', 'Part-time', 'Online' },
            'U09012' => new List<String>{ 'Business Administration', 'Graduate', 'Full-time', 'Online' }
        };
        insert new List<Contact>{
            new Contact(FirstName = 'Ana', LastName = 'Ruiz', Student_ID__c = 'U09010', Student_Level__c = 'Undergraduate', Student_Stage__c = 'Enrolled'),
            new Contact(FirstName = 'Ben', LastName = 'Lowe', Student_ID__c = 'U09011', Student_Level__c = 'Undergraduate', Student_Stage__c = 'Enrolled'),
            new Contact(FirstName = 'Cal', LastName = 'Moss', Student_ID__c = 'U09012', Student_Level__c = 'Graduate', Student_Stage__c = 'Enrolled')
        };
        StudentProfileSeeder.Request req = new StudentProfileSeeder.Request();
        req.overwrite = true;
        List<StudentProfileSeeder.Result> res = StudentProfileSeeder.run(new List<StudentProfileSeeder.Request>{ req });
        System.assert(res[0].message.contains('3 matched to a Canvas profile'), res[0].message);

        Map<String, Contact> byId = new Map<String, Contact>();
        for (Contact c : [SELECT Student_ID__c, Program__c, Program_Modality__c, Enrollment_Intensity__c, Start_Term__c,
                                 Expected_Graduation_Term__c FROM Contact WHERE Student_ID__c LIKE 'U0901%']) {
            byId.put(c.Student_ID__c, c);
        }
        Contact ana = byId.get('U09010');
        System.assertEquals('BS Psychology', ana.Program__c);
        System.assertEquals('On Campus', ana.Program_Modality__c);
        System.assertEquals('Full-time', ana.Enrollment_Intensity__c);
        System.assertEquals('Spring 2027', ana.Expected_Graduation_Term__c, 'seniors finish next spring');

        Contact ben = byId.get('U09011');
        System.assertEquals('BA History', ben.Program__c);
        System.assertEquals('Online', ben.Program_Modality__c);
        System.assertEquals('Part-time', ben.Enrollment_Intensity__c);
        System.assertEquals('Fall 2026', ben.Start_Term__c);
        System.assertEquals('Fall 2030', ben.Expected_Graduation_Term__c, 'part-time adds a term');

        Contact cal = byId.get('U09012');
        System.assertEquals('MBA', cal.Program__c);
        System.assertEquals('Spring 2027', cal.Expected_Graduation_Term__c);
    }

    @IsTest
    static void rerunsGiveTheSameProfileAndDemoStudentsAreFixed() {
        insert new List<Contact>{
            new Contact(FirstName = 'Priya', LastName = 'Cooper', Student_ID__c = 'U00002', Student_Level__c = 'Undergraduate', Student_Stage__c = 'Enrolled'),
            new Contact(FirstName = 'Sam', LastName = 'Ortiz', Student_ID__c = 'U09003')
        };
        StudentProfileSeeder.Request req = new StudentProfileSeeder.Request();
        req.overwrite = true;
        StudentProfileSeeder.run(new List<StudentProfileSeeder.Request>{ req });
        Contact first = [SELECT Program__c, Start_Term__c, MobilePhone FROM Contact WHERE Student_ID__c = 'U09003'];
        StudentProfileSeeder.run(new List<StudentProfileSeeder.Request>{ req });
        Contact second = [SELECT Program__c, Start_Term__c, MobilePhone FROM Contact WHERE Student_ID__c = 'U09003'];
        System.assertEquals(first.Program__c, second.Program__c);
        System.assertEquals(first.Start_Term__c, second.Start_Term__c);
        System.assertEquals(first.MobilePhone, second.MobilePhone);

        Contact priya = [SELECT Program__c, Program_Modality__c, Employer__c, First_Generation__c, Expected_Graduation_Term__c FROM Contact WHERE Student_ID__c = 'U00002'];
        System.assertEquals('Fall 2030', priya.Expected_Graduation_Term__c);
        System.assertEquals('BA History', priya.Program__c);
        System.assertEquals('On Campus', priya.Program_Modality__c);
        System.assertEquals('Target', priya.Employer__c);
        System.assert(priya.First_Generation__c);
    }
}
