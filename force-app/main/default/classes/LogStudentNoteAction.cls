/**
 * Agent action: logs an advising note on a Student (Contact) owned by the running advisor.
 * Uses Enhanced Notes (ContentNote) when enabled in the org, otherwise a classic Note.
 */
public with sharing class LogStudentNoteAction {

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Salesforce Id of the Student (Contact) record.' required=true)
        public String studentRecordId;
        @InvocableVariable(label='Title' description='Short note title, e.g. "Advising check-in 10/24".' required=true)
        public String title;
        @InvocableVariable(label='Body' description='The note text.' required=true)
        public String body;
    }

    public class Response {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Note Id') public String noteId;
        @InvocableVariable(label='Message') public String message;
    }

    @InvocableMethod(label='Log Student Note' description='Logs an advising note on one of the advisor\'s students.')
    public static List<Response> logNote(List<Request> requests) {
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
            if (String.isBlank(req.title) || String.isBlank(req.body)) {
                res.message = 'A note title and body are required.';
                return res;
            }
            Schema.SObjectType enhanced = Schema.getGlobalDescribe().get('ContentNote');
            if (enhanced != null) {
                SObject note = enhanced.newSObject();
                note.put('Title', req.title.left(255));
                note.put('Content', Blob.valueOf(toHtml(req.body)));
                Database.insert(note, AccessLevel.USER_MODE);
                insert new ContentDocumentLink(
                    ContentDocumentId = note.Id, LinkedEntityId = s.Id, ShareType = 'I', Visibility = 'AllUsers');
                res.noteId = note.Id;
            } else {
                Note n = new Note(ParentId = s.Id, Title = req.title.left(80), Body = req.body, OwnerId = UserInfo.getUserId());
                Database.insert(n, AccessLevel.USER_MODE);
                res.noteId = n.Id;
            }
            res.success = true;
            res.message = 'Note "' + req.title + '" logged on ' + s.Name + '.';
        } catch (Exception e) {
            res.message = 'Could not log the note: ' + e.getMessage();
        }
        return res;
    }

    // Enhanced Notes store HTML; escape the text and keep line breaks as paragraphs.
    @TestVisible
    private static String toHtml(String text) {
        List<String> paras = new List<String>();
        for (String line : text.split('\n')) paras.add('<p>' + line.escapeHtml4() + '</p>');
        return String.join(paras, '');
    }
}
