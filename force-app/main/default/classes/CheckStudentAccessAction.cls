/**
 * Invocable wrapper around StudentAccess, so flows can enforce the same advising-relationship
 * check as the Apex actions. Every flow action calls this first and stops unless allowed is true.
 * The check is a USER_MODE query plus an owner match, so it holds whatever context the flow runs in.
 */
public with sharing class CheckStudentAccessAction {

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Salesforce Id of the Student (Contact) record.' required=true)
        public String studentRecordId;
    }

    public class Response {
        @InvocableVariable(label='Allowed' description='True only when the running advisor owns this student.')
        public Boolean allowed;
        @InvocableVariable(label='Student Name' description='The student\'s name, when allowed.')
        public String studentName;
        @InvocableVariable(label='Message' description='Refusal message to return when not allowed.')
        public String message;
    }

    @InvocableMethod(label='Check Student Access' description='Returns whether the running advisor owns the given student. Call before any flow reads or writes student data.')
    public static List<Response> check(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Response res = new Response();
            Contact s = null;
            try {
                s = StudentAccess.ownedStudent(r.studentRecordId);
            } catch (Exception e) {
                s = null; // a malformed Id is treated like any other refusal
            }
            res.allowed = s != null;
            res.studentName = s == null ? null : s.Name;
            res.message = s == null ? 'There is no student record owned by you with that information.' : null;
            out.add(res);
        }
        return out;
    }
}
