/**
 * Shared guard for advisor agent actions: returns the Student (Contact) only when the
 * running user can see it and owns it (owner = assigned advisor). Otherwise null.
 */
public with sharing class StudentAccess {
    public static Contact ownedStudent(String studentRecordId) {
        if (String.isBlank(studentRecordId)) return null;
        List<Contact> found = [
            SELECT Id, Name, OwnerId FROM Contact
            WHERE Id = :studentRecordId WITH USER_MODE LIMIT 1
        ];
        if (found.isEmpty() || found[0].OwnerId != UserInfo.getUserId()) return null;
        return found[0];
    }
}
