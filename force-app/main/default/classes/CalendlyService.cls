/**
 * Calendly API v2 client. All calls go through the "Calendly" Named Credential,
 * which injects the bearer token, so no secrets live in code.
 */
public with sharing class CalendlyService {

    public class CalendlyException extends Exception {}

    // Lists event types for a Calendly user URI (https://api.calendly.com/users/{uuid}).
    public static List<Map<String, Object>> listEventTypes(String userUri) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Calendly/event_types?active=true&count=100&user=' + EncodingUtil.urlEncode(userUri, 'UTF-8'));
        req.setMethod('GET');
        Map<String, Object> body = send(req, 200);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Object o : (List<Object>) body.get('collection')) out.add((Map<String, Object>) o);
        return out;
    }

    // Creates a single-use scheduling link for an event type and returns its booking URL.
    public static String createSingleUseLink(String eventTypeUri) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Calendly/scheduling_links');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'max_event_count' => 1,
            'owner' => eventTypeUri,
            'owner_type' => 'EventType'
        }));
        Map<String, Object> body = send(req, 201);
        Map<String, Object> resource = (Map<String, Object>) body.get('resource');
        return resource == null ? null : (String) resource.get('booking_url');
    }

    // Adds Calendly's prefill parameters so the booking form opens with the student's details.
    public static String withPrefill(String bookingUrl, String name, String email) {
        if (String.isBlank(bookingUrl)) return bookingUrl;
        List<String> params = new List<String>();
        if (String.isNotBlank(name)) params.add('name=' + EncodingUtil.urlEncode(name, 'UTF-8'));
        if (String.isNotBlank(email)) params.add('email=' + EncodingUtil.urlEncode(email, 'UTF-8'));
        if (params.isEmpty()) return bookingUrl;
        return bookingUrl + (bookingUrl.contains('?') ? '&' : '?') + String.join(params, '&');
    }

    private static Map<String, Object> send(HttpRequest req, Integer expected) {
        req.setTimeout(20000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != expected) {
            throw new CalendlyException('Calendly returned ' + res.getStatusCode() + ': ' + res.getBody().left(500));
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
}
