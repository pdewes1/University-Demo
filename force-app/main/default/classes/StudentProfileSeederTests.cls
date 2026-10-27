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
        System.assert(new Set<String>{ 'MBA', 'MS Accounting', 'MS Human Services', 'MEd Higher Education Administration' }
            .contains(b.Program__c), 'graduate students get a graduate program');

        System.assertEquals(null, [SELECT Program__c FROM Contact WHERE LastName = 'AStudent'].Program__c);
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

        Contact priya = [SELECT Program__c, Program_Modality__c, Employer__c, First_Generation__c FROM Contact WHERE Student_ID__c = 'U00002'];
        System.assertEquals('BS Business Administration', priya.Program__c);
        System.assertEquals('Online', priya.Program_Modality__c);
        System.assertEquals('Target', priya.Employer__c);
        System.assert(priya.First_Generation__c);
    }
}
