/**
 * Last advising contact and open follow-ups for a student, read live from the CRM.
 * Used by Student360DataAction so the agent sees advising activity alongside Data 360.
 */
public with sharing class StudentAdvisingActivity {

    // Advising contact = a completed task, a past event, or a note on the student.
    // Open tasks are follow-ups, not contact. Respects the running user's access (USER_MODE).
    public static String summarize(Id studentId) {
        Datetime lastAt = null;
        String lastWhat = null;

        for (Task t : [SELECT Subject, CompletedDateTime, LastModifiedDate, Owner.Name FROM Task
                       WHERE WhoId = :studentId AND IsClosed = true
                       WITH USER_MODE ORDER BY CompletedDateTime DESC NULLS LAST, LastModifiedDate DESC LIMIT 1]) {
            Datetime doneAt = t.CompletedDateTime != null ? t.CompletedDateTime : t.LastModifiedDate;
            lastAt = doneAt; lastWhat = 'completed task "' + t.Subject + '" (' + t.Owner.Name + ')';
        }
        for (Event e : [SELECT Subject, EndDateTime, Owner.Name FROM Event
                        WHERE WhoId = :studentId AND EndDateTime <= :Datetime.now()
                        WITH USER_MODE ORDER BY EndDateTime DESC LIMIT 1]) {
            if (lastAt == null || e.EndDateTime > lastAt) {
                lastAt = e.EndDateTime; lastWhat = 'meeting "' + e.Subject + '" (' + e.Owner.Name + ')';
            }
        }
        for (Note n : [SELECT Title, CreatedDate, Owner.Name FROM Note
                       WHERE ParentId = :studentId WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1]) {
            if (lastAt == null || n.CreatedDate > lastAt) {
                lastAt = n.CreatedDate; lastWhat = 'note "' + n.Title + '" (' + n.Owner.Name + ')';
            }
        }
        try { // Enhanced Notes (ContentNote) appear as linked SNOTE documents
            for (ContentDocumentLink l : [SELECT ContentDocument.Title, ContentDocument.CreatedDate, ContentDocument.Owner.Name
                                          FROM ContentDocumentLink
                                          WHERE LinkedEntityId = :studentId AND ContentDocument.FileType = 'SNOTE'
                                          WITH USER_MODE ORDER BY ContentDocument.CreatedDate DESC LIMIT 1]) {
                if (lastAt == null || l.ContentDocument.CreatedDate > lastAt) {
                    lastAt = l.ContentDocument.CreatedDate;
                    lastWhat = 'note "' + l.ContentDocument.Title + '" (' + l.ContentDocument.Owner.Name + ')';
                }
            }
        } catch (Exception ignored) {}

        List<String> lines = new List<String>();
        if (lastAt == null) {
            lines.add('- Last advising contact: none recorded in the CRM.');
        } else {
            Integer days = lastAt.date().daysBetween(Date.today());
            lines.add('- Last advising contact: ' + lastAt.date().format() + ' (' + days + ' days ago), ' + lastWhat + '.');
        }

        List<Task> openTasks = [SELECT Subject, ActivityDate FROM Task
                           WHERE WhoId = :studentId AND IsClosed = false
                           WITH USER_MODE ORDER BY ActivityDate ASC NULLS LAST LIMIT 50];
        List<String> overdue = new List<String>();
        Task nextDue = null;
        for (Task t : openTasks) {
            if (t.ActivityDate != null && t.ActivityDate < Date.today()) {
                overdue.add('"' + t.Subject + '" due ' + t.ActivityDate.format());
            } else if (nextDue == null && t.ActivityDate != null) {
                nextDue = t;
            }
        }
        String followUps = '- Open follow-ups: ' + openTasks.size() + ' (today is ' + Date.today().format() + ')';
        if (!overdue.isEmpty()) {
            followUps += '; ' + overdue.size() + ' overdue (' + String.join(overdue.size() > 3
                ? new List<String>{ overdue[0], overdue[1], overdue[2], '...' } : overdue, '; ') + ')';
        } else if (!openTasks.isEmpty()) {
            followUps += '; none overdue';
        }
        if (nextDue != null) followUps += '; next "' + nextDue.Subject + '" due ' + nextDue.ActivityDate.format();
        lines.add(followUps + '.');
        return String.join(lines, '\n');
    }
}
