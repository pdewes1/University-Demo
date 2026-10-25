/**
 * Admin utility: lists the Calendly event types for a Calendly user so the right one
 * can be stored on the advisor's User record (Calendly_Event_Type_URI__c).
 */
public with sharing class ListCalendlyEventTypesAction {

    public class Request {
        @InvocableVariable(label='Calendly User URI' description='e.g. https://api.calendly.com/users/{uuid}' required=true)
        public String calendlyUserUri;
    }

    public class Response {
        @InvocableVariable(label='Event Types JSON' description='Name, duration, scheduling URL and URI for each active event type.')
        public String eventTypesJson;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='List Calendly Event Types' description='Admin utility: lists active Calendly event types for a Calendly user.')
    public static List<Response> listTypes(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            try {
                List<Map<String, Object>> slim = new List<Map<String, Object>>();
                for (Map<String, Object> et : CalendlyService.listEventTypes(req.calendlyUserUri)) {
                    slim.add(new Map<String, Object>{
                        'name' => et.get('name'), 'duration' => et.get('duration'),
                        'scheduling_url' => et.get('scheduling_url'), 'uri' => et.get('uri')
                    });
                }
                res.eventTypesJson = JSON.serialize(slim);
                res.message = slim.size() + ' event type(s) found.';
            } catch (Exception e) {
                res.message = e.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}
