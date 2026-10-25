/**
 * Agent action: creates a follow-up Task on a Student (Contact) owned by the running advisor.
 * The task is assigned to the advisor and related to the student (WhoId).
 */
public with sharing class CreateStudentTaskAction {

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Salesforce Id of the Student (Contact) record.' required=true)
        public String studentRecordId;
        @InvocableVariable(label='Subject' description='Short task subject, e.g. "Follow up on missed HIST 210 class".' required=true)
        public String subject;
        @InvocableVariable(label='Description' description='Optional details for the task.')
        public String description;
        @InvocableVariable(label='Due Date' description='Optional due date (YYYY-MM-DD). Defaults to 3 days from today.')
        public Date dueDate;
        @InvocableVariable(label='Priority' description='High, Normal or Low. Defaults to Normal.')
        public String priority;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Task Id') public String taskId;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='Create Student Task' description='Creates a follow-up task for the advisor on one of their students.')
    public static List<Response> create(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) results.add(handle(req));
        return results;
    }

    private static Response handle(Request req) {
        Response res = new Response();
        res.success = false;
        try {
            Contact s = StudentAccess.ownedStudent(req.studentRecordId);
            if (s == null) {
                res.message = 'There is no student record owned by you with that information.';
                return res;
            }
            if (String.isBlank(req.subject)) {
                res.message = 'A task subject is required.';
                return res;
            }
            String priority = 'Normal';
            if (String.isNotBlank(req.priority) && new Set<String>{ 'high', 'normal', 'low' }.contains(req.priority.toLowerCase())) {
                priority = req.priority.substring(0, 1).toUpperCase() + req.priority.substring(1).toLowerCase();
            }
            Task t = new Task(
                WhoId = s.Id,
                OwnerId = UserInfo.getUserId(),
                Subject = req.subject.left(255),
                Description = req.description,
                ActivityDate = req.dueDate != null ? req.dueDate : Date.today().addDays(3),
                Priority = priority,
                Status = 'Not Started'
            );
            Database.insert(t, AccessLevel.USER_MODE);
            res.taskId = t.Id;
            res.success = true;
            res.message = 'Task "' + t.Subject + '" created for ' + s.Name + ', due ' + String.valueOf(t.ActivityDate) + '.';
        } catch (Exception e) {
            res.message = 'Could not create the task: ' + e.getMessage();
        }
        return res;
    }
}
