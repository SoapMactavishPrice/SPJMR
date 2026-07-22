/**
 * @description Pre-save conflict check for the Academic Scheduler: reads a faculty's Google
 *          Calendar for the exact window of a proposed session and reports any BUSY
 *          overlapping event, so a faculty cannot be double-booked before the session is
 *          saved. Read-only — no Salesforce writes. Impersonates the faculty (service account
 *          + domain-wide delegation), the same auth used by GoogleCalendarInboundService.
 *
 * @note    Fail-open: any auth/API error returns no conflicts rather than blocking the save
 *          on a transient problem — the scheduler is never stuck because Google is down.
 */
// ApexSuggestUsingNamedCred suppressed: reuses the existing service-account JWT auth
// (GoogleAuthService) that the rest of the calendar integration uses.
@SuppressWarnings('PMD.ApexSuggestUsingNamedCred')
public with sharing class FacultyCalendarConflictService {

    private static final String CALENDARS_URL = 'https://www.googleapis.com/calendar/v3/calendars/';
    private static final Integer MAX_RESULTS = 50;
    private static final String STATUS_CANCELLED = 'cancelled';
    private static final String TRANSPARENCY_FREE = 'transparent';
    private static final String RESPONSE_DECLINED = 'declined';

    /** @description One busy calendar event overlapping the proposed session window. */
    public class BusyEvent {
        @AuraEnabled public String eventId { get; set; }
        @AuraEnabled public String summary { get; set; }
        @AuraEnabled public Datetime startTime { get; set; }
        @AuraEnabled public Datetime endTime { get; set; }
    }

    /**
     * @description Reads facultyEmail's calendar between [windowStart, windowEnd) and returns
     *          the BUSY events overlapping it. Performs one Google callout.
     * @param facultyEmail The faculty's Workspace email (impersonation subject + calendar id).
     * @param windowStart Proposed session start.
     * @param windowEnd Proposed session end.
     * @return Overlapping busy events (empty when none, or on any handled error).
     */
    public static List<BusyEvent> findOverlaps(String facultyEmail, Datetime windowStart, Datetime windowEnd) {
        return findOverlaps(facultyEmail, windowStart, windowEnd, null);
    }

    /**
     * @description Reads facultyEmail's calendar between [windowStart, windowEnd) and returns
     *          the BUSY events overlapping it, skipping the session's own Google event.
     * @param facultyEmail The faculty's Workspace email (impersonation subject + calendar id).
     * @param windowStart Proposed session start.
     * @param windowEnd Proposed session end.
     * @param excludeEventId The current session's Google event id to ignore (null on create).
     * @return Overlapping busy events (empty when none, or on any handled error).
     */
    public static List<BusyEvent> findOverlaps(
        String facultyEmail, Datetime windowStart, Datetime windowEnd, String excludeEventId
    ) {
        List<BusyEvent> result = new List<BusyEvent>();
        if (String.isBlank(facultyEmail) || windowStart == null || windowEnd == null) {
            return result;
        }
        try {
            String token = GoogleAuthService.getAccessToken(facultyEmail);
            if (String.isBlank(token)) {
                return result; // fail-open: can't authenticate → don't block the save
            }
            HttpResponse res = new Http().send(buildRequest(facultyEmail, token, windowStart, windowEnd));
            if (res.getStatusCode() != 200) {
                return result; // fail-open on transient / API errors
            }
            Object rawItems = ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('items');
            return overlappingBusy(rawItems, facultyEmail, windowStart, windowEnd, excludeEventId);
        } catch (Exception e) {
            return result; // fail-open
        }
    }

    /**
     * @description Pure filter: from an events.list items[] keeps timed, non-cancelled,
     *          non-free, non-declined events that actually overlap [windowStart, windowEnd).
     *          No callout/SOQL.
     * @param rawItems The 'items' value from the events.list response.
     * @param facultyEmail The faculty whose attendee responseStatus is checked for declined.
     * @param windowStart Proposed session start.
     * @param windowEnd Proposed session end.
     * @return The overlapping busy events.
     */
    @TestVisible
    private static List<BusyEvent> overlappingBusy(
        Object rawItems, String facultyEmail, Datetime windowStart, Datetime windowEnd, String excludeEventId
    ) {
        List<BusyEvent> result = new List<BusyEvent>();
        if (!(rawItems instanceof List<Object>) || windowStart == null || windowEnd == null) {
            return result;
        }
        String emailLc = String.isBlank(facultyEmail) ? '' : facultyEmail.toLowerCase().trim();
        for (Object o : (List<Object>) rawItems) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> ev = (Map<String, Object>) o;
            String gid = (String) ev.get('id');
            if (String.isNotBlank(excludeEventId) && excludeEventId == gid) {
                continue; // the session's own event — not a conflict with itself
            }
            if (STATUS_CANCELLED.equalsIgnoreCase((String) ev.get('status'))) {
                continue;
            }
            if (TRANSPARENCY_FREE.equalsIgnoreCase((String) ev.get('transparency'))) {
                continue; // marked Free — not busy
            }
            if (facultyDeclined(ev, emailLc)) {
                continue;
            }
            Datetime st = timedInstant(ev.get('start'));
            Datetime en = timedInstant(ev.get('end'));
            if (st == null || en == null) {
                continue; // all-day / malformed — out of scope
            }
            if (st < windowEnd && en > windowStart) { // genuine overlap
                BusyEvent b = new BusyEvent();
                b.eventId = gid;
                b.summary = (String) ev.get('summary');
                b.startTime = st;
                b.endTime = en;
                result.add(b);
            }
        }
        return result;
    }

    /**
     * @description Whether the faculty declined this event (so it is not a real conflict).
     * @param ev The raw Google event map.
     * @param emailLc The faculty's lower-cased email.
     * @return True when an attendee matching the faculty has responseStatus 'declined'.
     */
    private static Boolean facultyDeclined(Map<String, Object> ev, String emailLc) {
        Object rawAtt = ev.get('attendees');
        if (!(rawAtt instanceof List<Object>) || String.isBlank(emailLc)) {
            return false;
        }
        for (Object o : (List<Object>) rawAtt) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> att = (Map<String, Object>) o;
            String attEmail = (String) att.get('email');
            Boolean isSelf = att.get('self') == true;
            if ((attEmail != null && attEmail.toLowerCase().trim() == emailLc) || isSelf) {
                return RESPONSE_DECLINED.equalsIgnoreCase((String) att.get('responseStatus'));
            }
        }
        return false;
    }

    /**
     * @description Parses a Google event start/end node to a timed instant. Returns null for
     *          all-day events (which carry 'date' but no 'dateTime') and malformed nodes.
     * @param node The 'start' or 'end' object from a Google event.
     * @return The instant, or null when the node is all-day / missing a dateTime.
     */
    private static Datetime timedInstant(Object node) {
        if (!(node instanceof Map<String, Object>)) {
            return null;
        }
        String dt = (String) ((Map<String, Object>) node).get('dateTime');
        return parseRfc3339(dt);
    }

    /**
     * @description Builds the events.list GET request bounded to the proposed session window.
     * @param facultyEmail The calendar id (Workspace user email).
     * @param token A valid OAuth access token for that calendar.
     * @param windowStart Lower time bound.
     * @param windowEnd Upper time bound.
     * @return The prepared HttpRequest.
     */
    private static HttpRequest buildRequest(
        String facultyEmail, String token, Datetime windowStart, Datetime windowEnd
    ) {
        String timeMin = windowStart.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + 'Z';
        String timeMax = windowEnd.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + 'Z';
        String endpoint = CALENDARS_URL
            + EncodingUtil.urlEncode(facultyEmail, 'UTF-8') + '/events'
            + '?singleEvents=true&showDeleted=false&orderBy=startTime'
            + '&maxResults=' + MAX_RESULTS
            + '&timeMin=' + EncodingUtil.urlEncode(timeMin, 'UTF-8')
            + '&timeMax=' + EncodingUtil.urlEncode(timeMax, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        return req;
    }

    /**
     * @description Parses an RFC 3339 timestamp (e.g. 2026-07-16T02:00:00+05:30) to a UTC
     *          instant. Mirrors GoogleCalendarInboundService's parser.
     * @param value The RFC 3339 string.
     * @return The instant, or null when blank / malformed.
     */
    private static Datetime parseRfc3339(String value) {
        if (String.isBlank(value) || value.length() < 19) {
            return null;
        }
        try {
            Integer year = Integer.valueOf(value.substring(0, 4));
            Integer month = Integer.valueOf(value.substring(5, 7));
            Integer day = Integer.valueOf(value.substring(8, 10));
            Integer hour = Integer.valueOf(value.substring(11, 13));
            Integer minute = Integer.valueOf(value.substring(14, 16));
            Integer second = Integer.valueOf(value.substring(17, 19));
            Datetime wall = Datetime.newInstanceGmt(year, month, day, hour, minute, second);
            return wall.addMinutes(-offsetMinutes(value.substring(19)));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Parses the timezone offset tail of an RFC 3339 string into minutes.
     * @param tail The part after the seconds, e.g. 'Z', '+05:30', '.000+05:30', '-08:00'.
     * @return The offset in minutes (0 for UTC / 'Z' / absent).
     */
    private static Integer offsetMinutes(String tail) {
        if (String.isBlank(tail)) {
            return 0;
        }
        String t = tail;
        if (t.startsWith('.')) {
            Integer i = 1;
            while (i < t.length() && t.substring(i, i + 1).isNumeric()) {
                i++;
            }
            t = t.substring(i);
        }
        if (String.isBlank(t) || t == 'Z') {
            return 0;
        }
        Integer sign = t.startsWith('-') ? -1 : 1;
        String hhmm = t.substring(1);
        Integer oh = Integer.valueOf(hhmm.substring(0, 2));
        Integer om = Integer.valueOf(hhmm.substring(3, 5));
        return sign * (oh * 60 + om);
    }
}