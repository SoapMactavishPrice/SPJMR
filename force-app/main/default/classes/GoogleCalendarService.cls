public class GoogleCalendarService {

    public static final String SEND_UPDATES_ALL  = 'all';

    public static final String SEND_UPDATES_NONE = 'none';

    public static GoogleCalendarResponse createCalendarEvent(
        String serviceAccountEmail,
        String privateKey,
        String calendarId,
        GoogleCalendarEvent eventData
    ) {

        return createCalendarEvent(serviceAccountEmail, privateKey, calendarId, eventData, 'admin@quillconsultants.com');
    }

    public static GoogleCalendarResponse createCalendarEvent(
        String serviceAccountEmail,
        String privateKey,
        String calendarId,
        GoogleCalendarEvent eventData,
        String userEmail
    ) {
        return createCalendarEvent(serviceAccountEmail, privateKey, calendarId, eventData, userEmail, SEND_UPDATES_ALL);
    }

    public static GoogleCalendarResponse createCalendarEvent(
        String serviceAccountEmail,
        String privateKey,
        String calendarId,
        GoogleCalendarEvent eventData,
        String userEmail,
        String sendUpdates
    ) {
        return sendEvent('POST', null, calendarId, eventData, userEmail, sendUpdates);
    }

    public static GoogleCalendarResponse updateCalendarEvent(
        String calendarId,
        String eventId,
        GoogleCalendarEvent eventData,
        String userEmail
    ) {
        return updateCalendarEvent(calendarId, eventId, eventData, userEmail, SEND_UPDATES_ALL);
    }

    public static GoogleCalendarResponse updateCalendarEvent(
        String calendarId,
        String eventId,
        GoogleCalendarEvent eventData,
        String userEmail,
        String sendUpdates
    ) {
        if (String.isBlank(eventId)) {
            GoogleCalendarResponse r = new GoogleCalendarResponse();
            r.errorMessage = 'eventId is required to update a calendar event';
            return r;
        }
        return sendEvent('PATCH', eventId, calendarId, eventData, userEmail, sendUpdates);
    }

    public static GoogleCalendarResponse deleteCalendarEvent(
        String calendarId,
        String eventId,
        String userEmail
    ) {
        return deleteCalendarEvent(calendarId, eventId, userEmail, SEND_UPDATES_ALL);
    }

    public static GoogleCalendarResponse deleteCalendarEvent(
        String calendarId,
        String eventId,
        String userEmail,
        String sendUpdates
    ) {
        GoogleCalendarResponse response = new GoogleCalendarResponse();
        try {
            if (String.isBlank(eventId)) {
                response.errorMessage = 'eventId is required to delete a calendar event';
                return response;
            }
            if (String.isBlank(userEmail)) {
                response.errorMessage = 'User email is required for domain-wide delegation';
                return response;
            }

            String token = GoogleAuthService.getAccessToken(userEmail);
            if (String.isBlank(token)) {
                response.errorMessage = 'Failed to obtain access token';
                return response;
            }

            String updates = String.isNotBlank(sendUpdates) ? sendUpdates : SEND_UPDATES_ALL;
            HttpRequest req = new HttpRequest();
            req.setEndpoint(eventEndpoint(calendarId, eventId) + '?sendUpdates=' + updates);
            req.setMethod('DELETE');
            req.setHeader('Authorization', 'Bearer ' + token);

            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();

            if (code == 204 || code == 200 || code == 410) {
                response.success = true;
                response.eventId = eventId;
            } else {
                response.errorMessage = 'HTTP ' + code + ': ' + res.getBody();
                response.responseBody = res.getBody();
            }
        } catch (Exception e) {
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    public static GoogleEventReadResponse getCalendarEvent(
        String calendarId,
        String eventId,
        String userEmail
    ) {
        GoogleEventReadResponse response = new GoogleEventReadResponse();
        try {
            if (String.isBlank(eventId)) {
                response.errorMessage = 'eventId is required to read a calendar event';
                return response;
            }
            if (String.isBlank(userEmail)) {
                response.errorMessage = 'User email is required for domain-wide delegation';
                return response;
            }

            String token = GoogleAuthService.getAccessToken(userEmail);
            if (String.isBlank(token)) {
                response.errorMessage = 'Failed to obtain access token';
                return response;
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(eventEndpoint(calendarId, eventId));
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + token);

            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            response.statusCode = code;

            if (code == 200) {
                response.success = true;
                response.event = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                response.responseBody = res.getBody();
            } else if (code == 404 || code == 410) {

                response.notFound = true;
            } else {
                response.errorMessage = 'HTTP ' + code + ': ' + res.getBody();
                response.responseBody = res.getBody();
            }
        } catch (Exception e) {
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    private static GoogleCalendarResponse sendEvent(
        String method,
        String eventId,
        String calendarId,
        GoogleCalendarEvent eventData,
        String userEmail,
        String sendUpdates
    ) {
        GoogleCalendarResponse response = new GoogleCalendarResponse();

        try {
            if (String.isBlank(userEmail)) {
                response.errorMessage = 'User email is required for domain-wide delegation';
                return response;
            }

            String token = GoogleAuthService.getAccessToken(userEmail);
            if (String.isBlank(token)) {
                response.errorMessage = 'Failed to obtain access token';
                return response;
            }

            Map<String, String> existingResponseByEmail = (method == 'PATCH')
                ? readExistingAttendeeResponses(calendarId, eventId, token)
                : null;

            Map<String, Object> eventMap = buildEventMap(eventData, userEmail, existingResponseByEmail);

            String updates = String.isNotBlank(sendUpdates) ? sendUpdates : SEND_UPDATES_ALL;
            String endpoint = (method == 'PATCH')
                ? eventEndpoint(calendarId, eventId) + '?sendUpdates=' + updates
                : eventEndpoint(calendarId, null) + '?sendUpdates=' + updates;

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod(method);
            req.setHeader('Authorization', 'Bearer ' + token);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(JSON.serialize(eventMap));

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap =
                    (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                response.success = true;
                response.eventId = (String) responseMap.get('id');
                response.htmlLink = (String) responseMap.get('htmlLink');
                response.responseBody = res.getBody();
            } else {
                response.errorMessage = 'HTTP ' + res.getStatusCode() + ': ' + res.getBody();
                response.responseBody = res.getBody();
            }
        } catch (Exception e) {
            response.errorMessage = e.getMessage();
        }

        return response;
    }

    private static Map<String, Object> buildEventMap(
        GoogleCalendarEvent eventData,
        String userEmail,
        Map<String, String> existingResponseByEmail
    ) {
        Map<String, Object> eventMap = new Map<String, Object>{
            'summary' => eventData.summary
        };
        eventMap.put('start', eventData.startDateTime);
        eventMap.put('end', eventData.endDateTime);

        if (String.isNotBlank(eventData.description)) {
            eventMap.put('description', eventData.description);
        }
        if (String.isNotBlank(eventData.location)) {
            eventMap.put('location', eventData.location);
        }

        if (eventData.attendees != null && !eventData.attendees.isEmpty()) {
            List<Map<String, Object>> attendeeList = new List<Map<String, Object>>();
            String userEmailLower = userEmail.toLowerCase().trim();
            for (String attendeeEmail : eventData.attendees) {
                if (String.isBlank(attendeeEmail)) {
                    continue;
                }
                String emailLower = attendeeEmail.toLowerCase().trim();
                if (emailLower.equals(userEmailLower)) {
                    continue;
                }
                Map<String, Object> attendee = new Map<String, Object>{ 'email' => attendeeEmail };

                if (existingResponseByEmail != null
                        && existingResponseByEmail.containsKey(emailLower)) {
                    attendee.put('responseStatus', existingResponseByEmail.get(emailLower));
                }
                attendeeList.add(attendee);
            }

            eventMap.put('attendees', attendeeList);
        } else {

            eventMap.put('attendees', new List<Map<String, Object>>());
        }

        return eventMap;
    }

    private static Map<String, String> readExistingAttendeeResponses(
        String calendarId,
        String eventId,
        String token
    ) {
        Map<String, String> byEmail = new Map<String, String>();
        try {
            if (String.isBlank(eventId) || String.isBlank(token)) {
                return byEmail;
            }
            HttpRequest req = new HttpRequest();
            req.setEndpoint(eventEndpoint(calendarId, eventId));
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + token);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() != 200) {
                return byEmail;
            }
            Map<String, Object> ev = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            Object attObj = ev.get('attendees');
            if (attObj instanceof List<Object>) {
                for (Object o : (List<Object>) attObj) {
                    Map<String, Object> att = (Map<String, Object>) o;
                    String email  = (String) att.get('email');
                    String status = (String) att.get('responseStatus');
                    if (String.isNotBlank(email) && String.isNotBlank(status)) {
                        byEmail.put(email.toLowerCase().trim(), status);
                    }
                }
            }
        } catch (Exception e) {

            String ignored = e.getMessage();
        }
        return byEmail;
    }

    private static String eventEndpoint(String calendarId, String eventId) {
        String url = 'https://www.googleapis.com/calendar/v3/calendars/'
            + EncodingUtil.urlEncode(calendarId, 'UTF-8') + '/events';
        if (String.isNotBlank(eventId)) {
            url += '/' + EncodingUtil.urlEncode(eventId, 'UTF-8');
        }
        return url;
    }

    public class GoogleCalendarResponse {

        public Boolean success { get; set; }

        public String eventId { get; set; }

        public String htmlLink { get; set; }

        public String errorMessage { get; set; }

        public String responseBody { get; set; }

        public GoogleCalendarResponse() {
            this.success = false;
        }
    }

    public class GoogleEventReadResponse {

        public Boolean success { get; set; }

        public Boolean notFound { get; set; }

        public Integer statusCode { get; set; }

        public Map<String, Object> event { get; set; }

        public String errorMessage { get; set; }

        public String responseBody { get; set; }

        public GoogleEventReadResponse() {
            this.success = false;
            this.notFound = false;
        }
    }
}