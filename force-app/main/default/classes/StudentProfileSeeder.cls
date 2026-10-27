/**
 * Demo data only. Fills the student profile fields on Contact (program, modality, terms, preferred
 * contact, first-gen / military / transfer flags, employer) plus a mobile number, job title,
 * languages and a short description, so the Student record page looks like a real student.
 *
 * Values are derived from each student's Student ID, so running it again gives the same result.
 * By default it only fills blank fields; pass overwrite = true to regenerate everything it manages.
 * Run it as an invocable action:
 *   POST /services/data/v67.0/actions/custom/apex/StudentProfileSeeder  {"inputs":[{"overwrite":false}]}
 */
public with sharing class StudentProfileSeeder {

    public class Request {
        @InvocableVariable(label='Overwrite existing values')
        public Boolean overwrite;
    }

    public class Result {
        @InvocableVariable(label='Students updated')
        public Integer updated;
        @InvocableVariable(label='Message')
        public String message;
    }

    static final List<String> UNDERGRAD = new List<String>{
        'BS Business Administration', 'BS Business Administration', 'BS Accounting', 'BS Psychology',
        'BS Criminal Justice', 'BS Cybersecurity', 'BS Computer Information Systems',
        'BS Health Care Management', 'RN to BSN', 'AS Early Childhood Education'
    };
    static final List<String> GRAD = new List<String>{
        'MBA', 'MBA', 'MS Accounting', 'MS Human Services', 'MEd Higher Education Administration'
    };
    static final List<String> TERMS = new List<String>{ 'Spring', 'Summer', 'Fall' };
    static final List<List<String>> JOBS = new List<List<String>>{
        new List<String>{ 'Waterbury Hospital', 'Patient Care Technician' },
        new List<String>{ 'Travelers', 'Claims Associate' },
        new List<String>{ 'Amazon', 'Fulfillment Associate' },
        new List<String>{ 'Starbucks', 'Shift Supervisor' },
        new List<String>{ 'Target', 'Sales Associate' },
        new List<String>{ 'U.S. Army National Guard', 'Logistics Specialist' },
        new List<String>{ 'Bank of America', 'Personal Banker' },
        new List<String>{ 'Hartford HealthCare', 'Medical Assistant' },
        new List<String>{ 'Bright Horizons', 'Assistant Teacher' },
        new List<String>{ 'State of Connecticut', 'Administrative Assistant' },
        new List<String>{ 'CVS Health', 'Pharmacy Technician' },
        new List<String>{ 'Comcast', 'Customer Service Representative' },
        new List<String>{ 'Self-employed', 'Small Business Owner' },
        new List<String>{ 'Local police department', 'Dispatcher' },
        new List<String>{ 'Deloitte', 'IT Support Analyst' }
    };
    static final Map<String, String> NICKNAMES = new Map<String, String>{
        'Alexander' => 'Alex', 'Christopher' => 'Chris', 'Elizabeth' => 'Liz', 'Jennifer' => 'Jen',
        'Michael' => 'Mike', 'Robert' => 'Rob', 'William' => 'Will', 'Katherine' => 'Kate',
        'Daniel' => 'Dan', 'Jessica' => 'Jess', 'Joseph' => 'Joe', 'Nicholas' => 'Nick',
        'Samantha' => 'Sam', 'Anthony' => 'Tony', 'Rebecca' => 'Becca', 'Matthew' => 'Matt',
        'Benjamin' => 'Ben', 'Victoria' => 'Tori', 'Jonathan' => 'Jon', 'Gabriel' => 'Gabe'
    };

    // The two demo students the scripts and tests talk about get a fixed, story-consistent profile.
    static final Map<String, Map<String, Object>> DEMO = new Map<String, Map<String, Object>>{
        'U00002' => new Map<String, Object>{
            'Program__c' => 'BS Business Administration', 'Program_Modality__c' => 'Online',
            'Enrollment_Intensity__c' => 'Full-time', 'Start_Term__c' => 'Fall 2025',
            'Expected_Graduation_Term__c' => 'Spring 2029', 'Preferred_Contact_Method__c' => 'Text Message',
            'Employer__c' => 'Target', 'Title' => 'Sales Associate', 'Languages__c' => 'English',
            'First_Generation__c' => true, 'Military_Affiliated__c' => false, 'Transfer_Student__c' => false,
            'Description' => 'Full-time online student in BS Business Administration. Works part-time as a Sales Associate at Target. First in their family to attend college.'
        },
        'U00017' => new Map<String, Object>{
            'Program__c' => 'MS Human Services', 'Program_Modality__c' => 'Online',
            'Enrollment_Intensity__c' => 'Part-time', 'Start_Term__c' => 'Spring 2025',
            'Expected_Graduation_Term__c' => 'Fall 2027', 'Preferred_Contact_Method__c' => 'Email',
            'Employer__c' => 'Hartford HealthCare', 'Title' => 'Medical Assistant', 'Languages__c' => 'English',
            'First_Generation__c' => false, 'Military_Affiliated__c' => true, 'Transfer_Student__c' => false,
            'Description' => 'Part-time online student in MS Human Services, currently on leave. Works as a Medical Assistant at Hartford HealthCare. Military spouse.'
        }
    };

    @InvocableMethod(label='Seed student profile demo data' description='Fills demo profile fields on every student Contact.')
    public static List<Result> run(List<Request> requests) {
        Boolean overwrite = !requests.isEmpty() && requests[0].overwrite == true;
        List<Contact> students = [
            SELECT Id, FirstName, Student_ID__c, Student_Level__c, Student_Stage__c, MobilePhone, Title,
                   Languages__c, Description, Program__c, Program_Modality__c, Enrollment_Intensity__c,
                   Start_Term__c, Expected_Graduation_Term__c, Preferred_Name__c, Preferred_Contact_Method__c,
                   First_Generation__c, Military_Affiliated__c, Transfer_Student__c, Employer__c
            FROM Contact WHERE Student_ID__c != null
        ];
        for (Contact c : students) {
            apply(c, overwrite);
        }
        update students;
        Result r = new Result();
        r.updated = students.size();
        r.message = 'Seeded ' + students.size() + ' students' + (overwrite ? ' (overwrite).' : ' (blank fields only).');
        return new List<Result>{ r };
    }

    @TestVisible
    static void apply(Contact c, Boolean overwrite) {
        String sid = c.Student_ID__c;

        // Level and stage only when missing: these come from Banner and some tests depend on them.
        if (String.isBlank(c.Student_Level__c)) {
            c.Student_Level__c = roll(sid, 'd0', 7) == 0 ? 'Graduate' : 'Undergraduate';
        }
        if (String.isBlank(c.Student_Stage__c)) {
            c.Student_Stage__c = 'Enrolled';
        }
        Boolean isGrad = c.Student_Level__c == 'Graduate';
        Boolean onLeave = c.Student_Stage__c == 'On Leave';

        String program = isGrad ? GRAD[roll(sid, 'd0', GRAD.size())] : UNDERGRAD[roll(sid, 'd3', UNDERGRAD.size())];
        Integer m = roll(sid, 'd7', 20);
        String modality = m < 15 ? 'Online' : (m < 18 ? 'Hybrid' : 'On Campus');
        String intensity = onLeave || roll(sid, 'd11', 20) < 11 ? 'Part-time' : 'Full-time';

        // Start between Spring 2022 and Fall 2026; finish date follows program length and intensity.
        Integer startIndex = roll(sid, 'd13', 15);            // 0..14 terms after Spring 2022
        Integer startYear = 2022 + startIndex / 3;
        String startSeason = TERMS[Math.mod(startIndex, 3)];
        Integer years = program.startsWith('AS ') ? 2 : (isGrad ? 2 : 4);
        if (intensity == 'Part-time') {
            years += isGrad ? 1 : 2;
        }
        if (program == 'RN to BSN') {
            years = intensity == 'Part-time' ? 3 : 2;
        }
        Boolean transfer = !isGrad && roll(sid, 'd17', 10) < 3;
        if (transfer) {
            years = Math.max(2, years - 1);
        }
        String gradSeason = startSeason == 'Fall' ? 'Spring' : 'Fall';
        Integer gradYear = startYear + years - (startSeason == 'Fall' ? 0 : 1);
        // Current students can't have a finish date in the past: the earliest is Spring 2027.
        if (c.Student_Stage__c != 'Withdrawn' && (gradYear < 2027)) {
            gradSeason = 'Spring';
            gradYear = 2027;
        }

        Integer methodPick = roll(sid, 'd19', 20);
        String contactMethod = methodPick < 9 ? 'Email' : (methodPick < 15 ? 'Text Message' : (methodPick < 19 ? 'Mobile Phone' : 'Phone'));
        Boolean working = isGrad || intensity == 'Part-time' || roll(sid, 'd23', 10) < 4;
        List<String> job = JOBS[roll(sid, 'd29', JOBS.size())];
        Integer lang = roll(sid, 'd31', 25);
        String languages = lang < 20 ? 'English' : (lang < 23 ? 'English, Spanish' : (lang < 24 ? 'English, Portuguese' : 'English, Haitian Creole'));

        Boolean military = roll(sid, 'd37', 20) < 3 || job[0].contains('Army');
        if (military && !job[0].contains('Army') && working && roll(sid, 'coin', 2) == 0) {
            job = JOBS[5];
        }
        Boolean firstGen = roll(sid, 'd41', 20) < 7;

        fill(c, 'Program__c', program, overwrite);
        fill(c, 'Program_Modality__c', modality, overwrite);
        fill(c, 'Enrollment_Intensity__c', intensity, overwrite);
        fill(c, 'Start_Term__c', startSeason + ' ' + startYear, overwrite);
        fill(c, 'Expected_Graduation_Term__c', gradSeason + ' ' + gradYear, overwrite);
        fill(c, 'Preferred_Contact_Method__c', contactMethod, overwrite);
        fill(c, 'Languages__c', languages, overwrite);
        fill(c, 'MobilePhone', '(555) 555-' + String.valueOf(1000 + roll(sid, 'd43', 9000)), overwrite);
        if (c.FirstName != null && NICKNAMES.containsKey(c.FirstName)) {
            fill(c, 'Preferred_Name__c', NICKNAMES.get(c.FirstName), overwrite);
        } else if (overwrite) {
            c.Preferred_Name__c = null;
        }
        if (working) {
            fill(c, 'Employer__c', job[0], overwrite);
            fill(c, 'Title', job[1], overwrite);
        } else if (overwrite) {
            c.Employer__c = null;
            c.Title = null;
        }
        if (overwrite || (!c.First_Generation__c && !c.Military_Affiliated__c && !c.Transfer_Student__c)) {
            c.First_Generation__c = firstGen;
            c.Military_Affiliated__c = military;
            c.Transfer_Student__c = transfer;
        }
        fill(c, 'Description', describe(c, program, modality, intensity, working, job, military, firstGen, transfer), overwrite);

        if (DEMO.containsKey(c.Student_ID__c)) {
            for (String field : DEMO.get(c.Student_ID__c).keySet()) {
                c.put(field, DEMO.get(c.Student_ID__c).get(field));
            }
        }
    }

    static String describe(Contact c, String program, String modality, String intensity, Boolean working,
                           List<String> job, Boolean military, Boolean firstGen, Boolean transfer) {
        List<String> parts = new List<String>();
        parts.add(intensity + ' ' + modality.toLowerCase() + ' student in ' + program + '.');
        if (working) {
            parts.add(job[0] == 'Self-employed' ? 'Runs their own small business.' : 'Works as ' + article(job[1]) + ' ' + job[1] + ' at ' + job[0] + '.');
        }
        if (military) {
            parts.add('Military-affiliated.');
        }
        if (firstGen) {
            parts.add('First in their family to attend college.');
        }
        if (transfer) {
            parts.add('Transferred in with prior credit.');
        }
        return String.join(parts, ' ');
    }

    static String article(String word) {
        return 'AEIOU'.contains(word.left(1).toUpperCase()) ? 'an' : 'a';
    }

    static void fill(Contact c, String field, Object value, Boolean overwrite) {
        if (overwrite || c.get(field) == null || String.isBlank(String.valueOf(c.get(field)))) {
            c.put(field, value);
        }
    }

    // Stable pseudo-random number in [0, size) from the Student ID and a per-attribute salt,
    // so reruns give the same profile and neighbouring Student IDs don't get look-alike values.
    @TestVisible
    static Integer roll(String studentId, String salt, Integer size) {
        Long m = 2147483647L;
        Long x = Math.mod(Math.abs((Long) (studentId + '|' + salt).hashCode()), m) + 1;
        for (Integer i = 0; i < 3; i++) {
            x = Math.mod(x * 48271L, m);    // Lehmer steps stay well inside Long range
        }
        return (Integer) Math.mod(x, (Long) size);
    }
}
