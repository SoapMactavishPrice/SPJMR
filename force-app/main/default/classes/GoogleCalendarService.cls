/**
 * @description Service for creating, updating and deleting Google Calendar events
 *              via domain-wide delegation (SE-1047).
 */
public class GoogleCalendarService {

    /**
     * @description Creates a Google Calendar event with proper attendee handling
     * @param serviceAccountEmail The service account email
     * @param privateKey The private key (not used in current implementation, userEmail is used instead)
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventData The event data including attendees
     * @return GoogleCalendarResponse with success status and event details
     */
    public static GoogleCalendarResponse createCalendarEvent(
        String serviceAccountEmail,
        String privateKey,
        String calendarId,
        GoogleCalendarEvent eventData
    ) {
        // Default to the hardcoded user email for backward compatibility
        return createCalendarEvent(serviceAccountEmail, privateKey, calendarId, eventData, 'admin@quillconsultants.com');
    }
    
    /**
     * @description Creates a Google Calendar event with proper attendee handling (with userEmail parameter)
     * @param serviceAccountEmail The service account email
     * @param privateKey The private key (not used in current implementation)
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventData The event data including attendees
     * @param userEmail The email of the user to impersonate (domain-wide delegation)
     * @return GoogleCalendarResponse with success status and event details
     */
    public static GoogleCalendarResponse createCalendarEvent(
        String serviceAccountEmail,
        String privateKey,
        String calendarId,
        GoogleCalendarEvent eventData,
        String userEmail
    ) {
        return sendEvent('POST', null, calendarId, eventData, userEmail);
    }

    /**
     * @description Updates (PATCH) an existing Google Calendar event. Re-sends the
     *              full mapped event, so attendee adds/removes and time/location
     *              edits all propagate. (SE-1047.)
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventId    The Google event id to update
     * @param eventData  The event data
     * @param userEmail  The email of the user to impersonate (domain-wide delegation)
     * @return GoogleCalendarResponse
     */
    public static GoogleCalendarResponse updateCalendarEvent(
        String calendarId,
        String eventId,
        GoogleCalendarEvent eventData,
        String userEmail
    ) {
        if (String.isBlank(eventId)) {
            GoogleCalendarResponse r = new GoogleCalendarResponse();
            r.errorMessage = 'eventId is required to update a calendar event';
            return r;
        }
        return sendEvent('PATCH', eventId, calendarId, eventData, userEmail);
    }

    /**
     * @description Deletes (cancels) a Google Calendar event with sendUpdates=all,
     *              so attendees receive a cancellation. Treats HTTP 204 (and 410
     *              "already deleted") as success. (SE-1047.)
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventId    The Google event id to delete
     * @param userEmail  The email of the user to impersonate (domain-wide delegation)
     * @return GoogleCalendarResponse
     */
    public static GoogleCalendarResponse deleteCalendarEvent(
        String calendarId,
        String eventId,
        String userEmail
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

            HttpRequest req = new HttpRequest();
            req.setEndpoint(eventEndpoint(calendarId, eventId) + '?sendUpdates=all');
            req.setMethod('DELETE');
            req.setHeader('Authorization', 'Bearer ' + token);

            HttpResponse res = new Http().send(req);
            Integer code = res.getStatusCode();
            // 204 No Content = deleted; 410 Gone = already deleted (idempotent success).
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

    /**
     * @description Reads a single Google Calendar event (Events.get) so attendee
     *              RSVP statuses can be read back into Salesforce. Reads MUST use the
     *              organizer's calendar copy (the impersonated user), the only copy
     *              that reliably exposes every attendee's responseStatus. Polling only
     *              (no webhook). (RSVP read-back, Target 1.)
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventId    The Google event id to read
     * @param userEmail  The organizer/impersonated Workspace user (domain-wide delegation)
     * @return GoogleEventReadResponse with the parsed event, or notFound=true when the
     *         event no longer exists (HTTP 404/410) so callers can skip it gracefully.
     */
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
                // Event was deleted on Google's side — caller skips it, no error.
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

    /**
     * @description Shared create/update path. method = 'POST' (create) or 'PATCH'
     *              (update); eventId is null for create.
     * @param method     The HTTP method ('POST' for create, 'PATCH' for update)
     * @param eventId    The Google event id (null for create)
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventData  The event data
     * @param userEmail  The email of the user to impersonate (domain-wide delegation)
     * @return GoogleCalendarResponse with success status and event details
     */
    private static GoogleCalendarResponse sendEvent(
        String method,
        String eventId,
        String calendarId,
        GoogleCalendarEvent eventData,
        String userEmail
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

            // On PATCH (update/publish), read the existing event's attendees so we can
            // preserve each one's RSVP (responseStatus). Without this, re-sending an
            // attendee as {email} only resets them to "needsAction" — which re-invites
            // already-invited faculty and wipes their response. Genuinely new attendees
            // (e.g. students added at publish) are still sent without a status, so they
            // receive the invitation as expected.
            Map<String, String> existingResponseByEmail = (method == 'PATCH')
                ? readExistingAttendeeResponses(calendarId, eventId, token)
                : null;

            Map<String, Object> eventMap = buildEventMap(eventData, userEmail, existingResponseByEmail);

            String endpoint = (method == 'PATCH')
                ? eventEndpoint(calendarId, eventId) + '?sendUpdates=all'
                : eventEndpoint(calendarId, null) + '?sendUpdates=all';

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

    /**
     * @description Builds the Google event JSON body, filtering the impersonated user out of attendees.
     * @param eventData The event data including attendees
     * @param userEmail The email of the user to impersonate (domain-wide delegation)
     * @return Map representing the Google event JSON body
     */
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

        // Attendees — drop the impersonated organiser so we don't invite the
        // calendar owner to their own event.
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
                // Preserve the RSVP of anyone already on the event so a PATCH does not
                // reset them (which would re-invite them and wipe their response).
                if (existingResponseByEmail != null
                        && existingResponseByEmail.containsKey(emailLower)) {
                    attendee.put('responseStatus', existingResponseByEmail.get(emailLower));
                }
                attendeeList.add(attendee);
            }
            // On PATCH this replaces the attendee list, so removals propagate too.
            eventMap.put('attendees', attendeeList);
        } else {
            // Empty list on PATCH clears attendees; harmless on POST.
            eventMap.put('attendees', new List<Map<String, Object>>());
        }

        return eventMap;
    }

    /**
     * @description Reads the current attendees of an existing event so their RSVP
     *              (responseStatus) can be preserved on a PATCH. Reuses the already
     *              obtained access token to avoid an extra auth callout. Best-effort:
     *              on any failure it returns an empty map (no preservation).
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventId    The Google event id being updated
     * @param token      A valid OAuth access token for the impersonated user
     * @return Map of lower-cased attendee email → responseStatus
     */
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
            // Best-effort: if we can't read existing responses, fall back to no preservation.
            String ignored = e.getMessage();
        }
        return byEmail;
    }

    /**
     * @description Builds the events endpoint URL: /calendars/{calId}/events
     *              (+ /{eventId} when eventId is provided).
     * @param calendarId The calendar ID (e.g., 'primary')
     * @param eventId    The Google event id (null/blank to omit)
     * @return The fully-qualified Google Calendar events endpoint URL
     */
    private static String eventEndpoint(String calendarId, String eventId) {
        String url = 'https://www.googleapis.com/calendar/v3/calendars/'
            + EncodingUtil.urlEncode(calendarId, 'UTF-8') + '/events';
        if (String.isNotBlank(eventId)) {
            url += '/' + EncodingUtil.urlEncode(eventId, 'UTF-8');
        }
        return url;
    }

    /**
     * @description Response wrapper class for Google Calendar API calls
     */
    public class GoogleCalendarResponse {
        /** @description Whether the Calendar API call succeeded. */
        public Boolean success { get; set; }
        /** @description The Google Calendar event id returned by the API. */
        public String eventId { get; set; }
        /** @description The htmlLink to the created/updated event. */
        public String htmlLink { get; set; }
        /** @description Error message when the call did not succeed. */
        public String errorMessage { get; set; }
        /** @description Raw response body from the Calendar API. */
        public String responseBody { get; set; }
        
        /**
         * @description Constructs a response with success defaulted to false.
         */
        public GoogleCalendarResponse() {
            this.success = false;
        }
    }

    /**
     * @description Response wrapper for reading a single Google Calendar event
     *              (Events.get), used by the RSVP read-back sync.
     */
    public class GoogleEventReadResponse {
        /** @description Whether the read succeeded (HTTP 200). */
        public Boolean success { get; set; }
        /** @description True when the event no longer exists (HTTP 404/410). */
        public Boolean notFound { get; set; }
        /** @description HTTP status code returned by the Calendar API. */
        public Integer statusCode { get; set; }
        /** @description Parsed event body (includes attendees[]) when success. */
        public Map<String, Object> event { get; set; }
        /** @description Error message when the read did not succeed. */
        public String errorMessage { get; set; }
        /** @description Raw response body from the Calendar API. */
        public String responseBody { get; set; }

        /**
         * @description Constructs a response with success/notFound defaulted to false.
         */
        public GoogleEventReadResponse() {
            this.success = false;
            this.notFound = false;
        }
    }
}