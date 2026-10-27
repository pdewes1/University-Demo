/**
 * Demo data only. Fills the student profile fields on Contact (program, modality, terms, preferred
 * contact, first-gen / military / transfer flags, employer) plus a mobile number, job title,
 * languages and a short description, so the Student record page looks like a real student.
 *
 * Program, modality, enrollment intensity and terms follow each student's Canvas profile in Data 360
 * (major, campus, enrollment status, class year), so the record agrees with what the agent reads.
 * Everything else is derived from the Student ID, so running it again gives the same result.
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

    // Canvas majors and the program names they map to. Undergraduates get the BS/BA name, graduate
    // students the master's name. Students with no Canvas profile get a random program from the same lists.
    static final Map<String, List<String>> PROGRAMS = new Map<String, List<String>>{
        'Biology' => new List<String>{ 'BS Biology', 'MS Biology' },
        'Business Administration' => new List<String>{ 'BS Business Administration', 'MBA' },
        'Chemistry' => new List<String>{ 'BS Chemistry', 'MS Chemistry' },
        'Computer Science' => new List<String>{ 'BS Computer Science', 'MS Computer Science' },
        'Economics' => new List<String>{ 'BS Economics', 'MS Economics' },
        'English' => new List<String>{ 'BA English', 'MA English' },
        'History' => new List<String>{ 'BA History', 'MA History' },
        'Mathematics' => new List<String>{ 'BS Mathematics', 'MS Mathematics' },
        'Mechanical Engineering' => new List<String>{ 'BS Mechanical Engineering', 'MS Mechanical Engineering' },
        'Nursing' => new List<String>{ 'BS Nursing', 'MS Nursing' },
        'Political Science' => new List<String>{ 'BA Political Science', 'MA Political Science' },
        'Psychology' => new List<String>{ 'BS Psychology', 'MS Psychology' }
    };
    static final List<String> MAJORS = new List<String>{
        'Biology', 'Business Administration', 'Chemistry', 'Computer Science', 'Economics', 'English',
        'History', 'Mathematics', 'Mechanical Engineering', 'Nursing', 'Political Science', 'Psychology'
    };
    static final List<String> CLASS_YEARS = new List<String>{ 'Freshman', 'Sophomore', 'Junior', 'Senior' };
    // Class year to start and expected-graduation terms for a full-time undergraduate (today: Fall 2026).
    static final Map<String, List<String>> CLASS_YEAR_TERMS = new Map<String, List<String>>{
        'Freshman' => new List<String>{ 'Fall 2026', 'Spring 2030' },
        'Sophomore' => new List<String>{ 'Fall 2025', 'Spring 2029' },
        'Junior' => new List<String>{ 'Fall 2024', 'Spring 2028' },
        'Senior' => new List<String>{ 'Fall 2023', 'Spring 2027' }
    };

    // Canvas profile by Student ID: major, class year, enrollment status, campus. Tests set this directly.
    @TestVisible
    static Map<String, List<String>> canvasProfiles;

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

    // The two demo students the scripts and tests talk about get a fixed, story-consistent profile
    // (program, modality and intensity still agree with their Canvas profiles).
    static final Map<String, Map<String, Object>> DEMO = new Map<String, Map<String, Object>>{
        'U00002' => new Map<String, Object>{
            'Program__c' => 'BA History', 'Program_Modality__c' => 'On Campus',
            'Enrollment_Intensity__c' => 'Part-time', 'Start_Term__c' => 'Fall 2026',
            'Expected_Graduation_Term__c' => 'Fall 2030', 'Preferred_Contact_Method__c' => 'Text Message',
            'Employer__c' => 'Target', 'Title' => 'Sales Associate', 'Languages__c' => 'English',
            'First_Generation__c' => true, 'Military_Affiliated__c' => false, 'Transfer_Student__c' => false,
            'Description' => 'Part-time on-campus student in BA History. Works as a Sales Associate at Target. First in their family to attend college.'
        },
        'U00017' => new Map<String, Object>{
            'Program__c' => 'MS Chemistry', 'Program_Modality__c' => 'On Campus',
            'Enrollment_Intensity__c' => 'Part-time', 'Start_Term__c' => 'Spring 2025',
            'Expected_Graduation_Term__c' => 'Fall 2027', 'Preferred_Contact_Method__c' => 'Email',
            'Employer__c' => 'Hartford HealthCare', 'Title' => 'Medical Assistant', 'Languages__c' => 'English',
            'First_Generation__c' => false, 'Military_Affiliated__c' => true, 'Transfer_Student__c' => false,
            'Description' => 'Part-time on-campus student in MS Chemistry, currently on leave. Works as a Medical Assistant at Hartford HealthCare. Military spouse.'
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
        Map<String, List<String>> canvas = loadCanvas();
        Integer matched = 0;
        for (Contact c : students) {
            if (canvas.containsKey(c.Student_ID__c)) {
                matched++;
            }
            apply(c, overwrite);
        }
        update students;
        Result r = new Result();
        r.updated = students.size();
        r.message = 'Seeded ' + students.size() + ' students, ' + matched + ' matched to a Canvas profile' + (overwrite ? ' (overwrite).' : ' (blank fields only).');
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

        List<String> profile = loadCanvas().get(sid);
        String major = profile != null && PROGRAMS.containsKey(profile[0]) ? profile[0] : MAJORS[roll(sid, 'd3', MAJORS.size())];
        String program = PROGRAMS.get(major)[isGrad ? 1 : 0];
        String canvasStatus = profile != null ? profile[2] : null;
        String modality;
        if (profile != null) {
            modality = profile[3] == 'Online' ? 'Online' : 'On Campus';
        } else {
            Integer m = roll(sid, 'd7', 20);
            modality = m < 15 ? 'Online' : (m < 18 ? 'Hybrid' : 'On Campus');
        }
        String intensity;
        if (onLeave || canvasStatus == 'Part-time' || canvasStatus == 'Leave of Absence') {
            intensity = 'Part-time';
        } else if (canvasStatus == 'Full-time') {
            intensity = 'Full-time';
        } else {
            intensity = roll(sid, 'd11', 20) < 11 ? 'Part-time' : 'Full-time';
        }

        // Terms follow the Canvas class year. Graduate students: two years full-time, plus a term part-time.
        String classYear = profile != null ? profile[1] : CLASS_YEARS[roll(sid, 'd13', 4)];
        if (!CLASS_YEAR_TERMS.containsKey(classYear)) {
            classYear = 'Senior';    // Canvas says Graduate but the record says Undergraduate
        }
        Boolean transfer = !isGrad && classYear != 'Freshman' && roll(sid, 'd17', 10) < 3;
        String startTerm;
        String gradTerm;
        if (isGrad) {
            startTerm = 'Fall 2025';
            gradTerm = intensity == 'Part-time' ? 'Fall 2027' : 'Spring 2027';
        } else {
            startTerm = CLASS_YEAR_TERMS.get(classYear)[0];
            gradTerm = CLASS_YEAR_TERMS.get(classYear)[1];
            if (transfer) {
                // Transferred in a year later with credit; same expected finish.
                Integer y = Integer.valueOf(startTerm.right(4)) + 1;
                startTerm = 'Fall ' + Math.min(y, 2026);
            }
            if (intensity == 'Part-time') {
                gradTerm = 'Fall ' + Integer.valueOf(gradTerm.right(4));
            }
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
        fill(c, 'Start_Term__c', startTerm, overwrite);
        fill(c, 'Expected_Graduation_Term__c', gradTerm, overwrite);
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

    // Reads every student's Canvas profile from Data 360 once per run. If Data 360 can't be reached
    // (for example in tests), students fall back to generated values.
    static Map<String, List<String>> loadCanvas() {
        if (canvasProfiles != null) {
            return canvasProfiles;
        }
        canvasProfiles = new Map<String, List<String>>();
        try {
            ConnectApi.CdpQueryInput q = new ConnectApi.CdpQueryInput();
            q.sql = 'SELECT user_id__c, major__c, class_year__c, enrollment_status__c, campus__c '
                  + 'FROM Snowflake_Canvas_Users__dlm WHERE user_id__c LIKE \'U%\'';
            ConnectApi.CdpQueryOutputV2 res = ConnectApi.CdpQuery.queryAnsiSqlV2(q);
            while (res != null) {
                for (ConnectApi.CdpQueryV2Row row : res.data) {
                    List<Object> v = row.rowData;
                    canvasProfiles.put(String.valueOf(v[0]), new List<String>{
                        String.valueOf(v[1]), String.valueOf(v[2]), String.valueOf(v[3]), String.valueOf(v[4]) });
                }
                res = String.isBlank(res.nextBatchId) ? null : ConnectApi.CdpQuery.nextBatchAnsiSqlV2(res.nextBatchId);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Canvas profiles not loaded: ' + e.getMessage());
        }
        return canvasProfiles;
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
