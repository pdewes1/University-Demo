/**
 * Agent action: updates fields on a Student (Contact) record owned by the running user.
 * Only an allow-list of advisor-editable fields can change; field-level security and
 * sharing are enforced (USER_MODE). Returns which fields changed and which were rejected.
 */
public with sharing class UpdateStudentRecordAction {

    // Fields an Academic Advisor may change through the agent.
    @TestVisible
    private static final Set<String> EDITABLE_FIELDS = new Set<String>{
        'email', 'phone', 'mobilephone', 'title', 'description',
        'student_stage__c', 'student_level__c', 'level__c', 'languages__c',
        'mailingstreet', 'mailingcity', 'mailingstate', 'mailingpostalcode', 'mailingcountry'
    };

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Salesforce Id of the Student (Contact) record to update.' required=true)
        public String studentRecordId;
        @InvocableVariable(label='Field Updates JSON' description='JSON object of field API names to new values, e.g. {"Student_Stage__c":"Enrolled","Phone":"317-555-0100"}. Allowed fields: Email, Phone, MobilePhone, Title, Description, Student_Stage__c, Student_Level__c, Level__c, Languages__c, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry.' required=true)
        public String fieldUpdatesJson;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when the record was updated.')
        public Boolean success;
        @InvocableVariable(label='Message' description='What changed, or why nothing changed.')
        public String message;
        @InvocableVariable(label='Updated Fields' description='Comma-separated list of fields that were updated.')
        public String updatedFields;
    }

    @InvocableMethod(label='Update Student Record' description='Updates allowed fields on a Student record owned by the running user.')
    public static List<Response> updateStudent(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) results.add(handle(req));
        return results;
    }

    private static Response handle(Request req) {
        Response res = new Response();
        res.success = false;
        try {
            List<Contact> found = [SELECT Id, Name, OwnerId FROM Contact WHERE Id = :req.studentRecordId WITH USER_MODE LIMIT 1];
            if (found.isEmpty() || found[0].OwnerId != UserInfo.getUserId()) {
                res.message = 'There is no student record owned by you with that information.';
                return res;
            }

            Map<String, Object> changes = (Map<String, Object>) JSON.deserializeUntyped(req.fieldUpdatesJson);
            Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Contact.fields.getMap();
            Contact rec = new Contact(Id = found[0].Id);
            List<String> applied = new List<String>();
            List<String> rejected = new List<String>();

            for (String apiName : changes.keySet()) {
                String key = apiName.trim().toLowerCase();
                Schema.SObjectField f = fieldMap.get(key);
                if (f == null || !EDITABLE_FIELDS.contains(key) || !f.getDescribe().isUpdateable()) {
                    rejected.add(apiName);
                    continue;
                }
                rec.put(f, coerce(f.getDescribe().getType(), changes.get(apiName)));
                applied.add(f.getDescribe().getLabel() + ' (' + f.getDescribe().getName() + ')');
            }

            if (applied.isEmpty()) {
                res.message = 'No allowed fields to update.' + (rejected.isEmpty() ? '' : ' Not allowed: ' + String.join(rejected, ', ') + '.');
                return res;
            }

            Database.update(rec, AccessLevel.USER_MODE);
            res.success = true;
            res.updatedFields = String.join(applied, ', ');
            res.message = 'Updated ' + found[0].Name + ': ' + res.updatedFields + '.'
                + (rejected.isEmpty() ? '' : ' Skipped (not allowed): ' + String.join(rejected, ', ') + '.');
        } catch (JSONException e) {
            res.message = 'Field updates must be a JSON object of field names to values.';
        } catch (Exception e) {
            res.message = 'Could not update the student record: ' + e.getMessage();
        }
        return res;
    }

    private static Object coerce(Schema.DisplayType t, Object v) {
        if (v == null) return null;
        String s = String.valueOf(v);
        switch on t {
            when DOUBLE, CURRENCY, PERCENT { return Decimal.valueOf(s); }
            when INTEGER { return Integer.valueOf(s); }
            when BOOLEAN { return Boolean.valueOf(s); }
            when DATE { return Date.valueOf(s); }
            when DATETIME { return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class); }
            when else { return s; }
        }
    }
}
