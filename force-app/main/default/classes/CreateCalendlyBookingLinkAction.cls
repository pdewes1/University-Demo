/**
 * Agent action: creates a single-use Calendly booking link on the running advisor's
 * advising event type (User.Calendly_Event_Type_URI__c), pre-filled with the student's
 * name and email when a student is given.
 */
public with sharing class CreateCalendlyBookingLinkAction {

    public class Request {
        @InvocableVariable(label='Student Record Id' description='Optional Student (Contact) Id; pre-fills the booking form with the student\'s name and email.')
        public String studentRecordId;
    }

    public class Response {
        @InvocableVariable(label='Success' description='True when a booking link was created.')
        public Boolean success;
        @InvocableVariable(label='Booking URL' description='Single-use Calendly booking link (valid for one booking).')
        public String bookingUrl;
        @InvocableVariable(label='Message' description='Status or error message.')
        public String message;
    }

    @InvocableMethod(label='Create Calendly Booking Link' description='Creates a single-use Calendly link for booking a meeting with the advisor.')
    public static List<Response> create(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.success = false;
            try {
                res.bookingUrl = createForCurrentAdvisor(req.studentRecordId);
                res.success = true;
                res.message = 'Single-use booking link created.';
            } catch (Exception e) {
                res.message = 'Could not create a Calendly link: ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    // Shared with DraftStudentEmailAction. Throws when the advisor has no event type or Calendly fails.
    public static String createForCurrentAdvisor(String studentRecordId) {
        User advisor = [SELECT Calendly_Event_Type_URI__c FROM User WHERE Id = :UserInfo.getUserId()];
        if (String.isBlank(advisor.Calendly_Event_Type_URI__c)) {
            throw new CalendlyService.CalendlyException('No Calendly event type is set on your user record (Calendly Event Type URI).');
        }
        String name, email;
        if (String.isNotBlank(studentRecordId)) {
            List<Contact> s = [SELECT Name, Email, OwnerId FROM Contact WHERE Id = :studentRecordId WITH USER_MODE LIMIT 1];
            if (s.isEmpty() || s[0].OwnerId != UserInfo.getUserId()) {
                throw new CalendlyService.CalendlyException('There is no student record owned by you with that information.');
            }
            name = s[0].Name;
            email = s[0].Email;
        }
        String url = CalendlyService.createSingleUseLink(advisor.Calendly_Event_Type_URI__c);
        return CalendlyService.withPrefill(url, name, email);
    }
}
