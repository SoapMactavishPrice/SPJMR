/**
 * @description POC — INBOUND Google Calendar → Salesforce sync (reverse of the
 *          Session__c → Google push in GoogleCalendarService/SessionCalendarInvite*).
 *
 *          A student (or faculty) creates an event in Google Calendar and invites a
 *          faculty member or a fellow student. This service reads that calendar via
 *          the existing service-account domain-wide-delegation auth layer
 *          (GoogleAuthService.getAccessToken(calendarEmail)), maps each event to a
 *          Calendar_Meeting__c, and upserts by Google_Event_Id__c so re-runs are
 *          idempotent.
 *
 *          Echo-loop guard: events that Salesforce itself pushed out live on these
 *          same calendars. Any event whose id already exists on a Session__c
 *          (Google_Event_Id__c) is skipped so we don't re-ingest our own pushes.
 *
 * @note    Callout/DML ordering — fetchMeetings() only does the HTTP GET (+ read-only
 *          SOQL, which is legal alongside callouts); persist() does the DML. Callers
 *          that touch several calendars must run every fetchMeetings() first, then a
 *          single persist(), because Apex forbids a callout after uncommitted DML.
 */
// Suppressions (justified):
//  - ApexCRUDViolation: POC system-context ingest of external calendar data into a
//    dedicated POC object; access is governed by object perms on Calendar_Meeting__c.
//  - ApexSuggestUsingNamedCred: the integration deliberately uses a service-account
//    JWT (Approach B, see GoogleAuthService/GoogleJWTService), not a Named Credential.
//  - Cyclomatic/Cognitive/Ncss: RFC 3339 parsing is inherently branchy; kept in small
//    focused helpers rather than one large method.
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexSuggestUsingNamedCred,PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount')
public with sharing class GoogleCalendarInboundService {

    private static final String CALENDARS_URL = 'https://www.googleapis.com/calendar/v3/calendars/';
    private static final Integer MAX_RESULTS = 250;
    private static final String STATUS_SYNCED = 'Synced';
    private static final String SOURCE_GOOGLE = 'Google';
    private static final String SOURCE_SALESFORCE = 'Salesforce';

    /**
     * @description Outcome of an inbound sync: how many meetings were created,
     *          updated or skipped, and any error message.
     */
    public class InboundResult {
        /** @description Count of new Calendar_Meeting__c records created. */
        public Integer created = 0;
        /** @description Count of existing Calendar_Meeting__c records updated. */
        public Integer updated = 0;
        /** @description Count of events skipped (SF-originated, all-day, or malformed). */
        public Integer skipped = 0;
        /** @description Populated when the fetch/persist failed. */
        public String errorMessage;
    }

    /**
     * @description Convenience single-calendar sync: fetch then persist. Suitable
     *          for the webhook path where exactly one calendar changed.
     * @param calendarEmail The Workspace calendar (and impersonation subject) to read.
     * @param sinceUtc Lower bound for the event window; defaults to 1 day ago when null.
     * @return An InboundResult describing what was created/updated/skipped.
     */
    public static InboundResult syncCalendar(String calendarEmail, Datetime sinceUtc) {
        InboundResult result = new InboundResult();
        try {
            List<Calendar_Meeting__c> meetings = fetchMeetings(calendarEmail, sinceUtc);
            return persist(meetings);
        } catch (Exception e) {
            result.errorMessage = e.getMessage();
            return result;
        }
    }

    /**
     * @description Callout-only step: read a calendar's events and map the ingestible
     *          ones to (unsaved) Calendar_Meeting__c records. Does NO DML, so it is
     *          safe to call once per calendar before a single persist().
     * @param calendarEmail The Workspace calendar (and impersonation subject) to read.
     * @param sinceUtc Lower bound for the event window; defaults to 1 day ago when null.
     * @return Unsaved Calendar_Meeting__c records ready to upsert (may be empty).
     */
    public static List<Calendar_Meeting__c> fetchMeetings(String calendarEmail, Datetime sinceUtc) {
        List<Calendar_Meeting__c> meetings = new List<Calendar_Meeting__c>();
        if (String.isBlank(calendarEmail)) {
            throw new InboundException('calendarEmail is required');
        }

        String token = GoogleAuthService.getAccessToken(calendarEmail);
        if (String.isBlank(token)) {
            throw new InboundException('Failed to obtain access token for ' + calendarEmail);
        }

        HttpResponse res = new Http().send(buildListRequest(calendarEmail, token, sinceUtc));
        if (res.getStatusCode() != 200) {
            throw new InboundException('HTTP ' + res.getStatusCode() + ': ' + res.getBody());
        }

        Object rawItems = ((Map<String, Object>) JSON.deserializeUntyped(res.getBody())).get('items');
        if (!(rawItems instanceof List<Object>)) {
            return meetings;
        }
        List<Object> items = (List<Object>) rawItems;
        return toMeetings(items, salesforceOriginatedIds(items));
    }

    /**
     * @description Maps the ingestible events (skipping malformed ids and Salesforce's
     *          own pushed events) to unsaved Calendar_Meeting__c records.
     * @param items The raw event maps from the Calendar API.
     * @param sfEventIds Event ids that Salesforce originated (echo guard).
     * @return The mapped, unsaved meetings.
     */
    private static List<Calendar_Meeting__c> toMeetings(List<Object> items, Set<String> sfEventIds) {
        List<Calendar_Meeting__c> meetings = new List<Calendar_Meeting__c>();
        for (Object o : items) {
            Map<String, Object> ev = (Map<String, Object>) o;
            String gid = (String) ev.get('id');
            if (String.isBlank(gid) || sfEventIds.contains(gid)) {
                continue; // malformed, or Salesforce's own pushed event
            }
            Calendar_Meeting__c m = mapEvent(ev);
            if (m != null) {
                meetings.add(m);
            }
        }
        return meetings;
    }

    /**
     * @description DML-only step: upsert the mapped meetings by Google_Event_Id__c
     *          and report how many were created vs updated. Call after all callouts.
     * @param meetings Unsaved Calendar_Meeting__c records from fetchMeetings().
     * @return An InboundResult with created/updated counts.
     */
    public static InboundResult persist(List<Calendar_Meeting__c> meetings) {
        InboundResult result = new InboundResult();
        if (meetings == null || meetings.isEmpty()) {
            return result;
        }
        Set<String> existing = existingMeetingIds(meetings);
        for (Calendar_Meeting__c m : meetings) {
            if (existing.contains(m.Google_Event_Id__c)) {
                result.updated++;
            } else {
                result.created++;
            }
        }
        Database.upsert(meetings, Calendar_Meeting__c.Google_Event_Id__c, false);
        return result;
    }

    /**
     * @description Builds the events.list GET request for a calendar within a time window.
     * @param calendarEmail The calendar id (Workspace user email).
     * @param token A valid OAuth access token for that calendar.
     * @param sinceUtc Lower bound for the window; defaults to 1 day ago when null.
     * @return The prepared HttpRequest.
     */
    private static HttpRequest buildListRequest(String calendarEmail, String token, Datetime sinceUtc) {
        Datetime since = (sinceUtc != null) ? sinceUtc : Datetime.now().addDays(-1);
        String timeMin = since.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + 'Z';
        String endpoint = CALENDARS_URL
            + EncodingUtil.urlEncode(calendarEmail, 'UTF-8') + '/events'
            + '?singleEvents=true&showDeleted=false&orderBy=startTime'
            + '&maxResults=' + MAX_RESULTS
            + '&timeMin=' + EncodingUtil.urlEncode(timeMin, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + token);
        return req;
    }

    /**
     * @description Of the event ids in the payload, which did Salesforce originate and
     *          must NOT be re-ingested. This covers BOTH outbound pushes:
     *          Session__c → Google (SessionCalendarInviteQueueable) and
     *          Calendar_Meeting__c (Source__c='Salesforce') → Google
     *          (CalendarMeetingInviteQueueable, the student-scheduled meetings). Without
     *          the Calendar_Meeting__c check, a student-scheduled meeting would be
     *          re-ingested here as a fresh Google-sourced copy — an echo loop.
     * @param items The raw event maps from the Calendar API.
     * @return The subset of ids that Salesforce originated.
     */
    private static Set<String> salesforceOriginatedIds(List<Object> items) {
        Set<String> ids = new Set<String>();
        for (Object o : items) {
            Object id = ((Map<String, Object>) o).get('id');
            if (id != null) {
                ids.add((String) id);
            }
        }
        Set<String> sfIds = new Set<String>();
        if (ids.isEmpty()) {
            return sfIds;
        }
        for (Session__c s : [
            SELECT Google_Event_Id__c FROM Session__c WHERE Google_Event_Id__c IN :ids
        ]) {
            if (String.isNotBlank(s.Google_Event_Id__c)) {
                sfIds.add(s.Google_Event_Id__c);
            }
        }
        for (Calendar_Meeting__c cm : [
            SELECT Google_Event_Id__c
            FROM   Calendar_Meeting__c
            WHERE  Google_Event_Id__c IN :ids
              AND  Source__c = :SOURCE_SALESFORCE
        ]) {
            if (String.isNotBlank(cm.Google_Event_Id__c)) {
                sfIds.add(cm.Google_Event_Id__c);
            }
        }
        return sfIds;
    }

    /**
     * @description Which of the candidate meetings already exist (for created/updated counting).
     * @param meetings The mapped meetings about to be upserted.
     * @return The set of Google_Event_Id__c values that already have a record.
     */
    private static Set<String> existingMeetingIds(List<Calendar_Meeting__c> meetings) {
        Set<String> ids = new Set<String>();
        for (Calendar_Meeting__c m : meetings) {
            ids.add(m.Google_Event_Id__c);
        }
        Set<String> found = new Set<String>();
        for (Calendar_Meeting__c e : [
            SELECT Google_Event_Id__c FROM Calendar_Meeting__c WHERE Google_Event_Id__c IN :ids
        ]) {
            found.add(e.Google_Event_Id__c);
        }
        return found;
    }

    /**
     * @description Maps one Google event map to a Calendar_Meeting__c. Returns null for
     *          all-day events (no start.dateTime) which this POC does not ingest.
     * @param ev The raw Google event map.
     * @return A mapped, unsaved Calendar_Meeting__c, or null to skip.
     */
    private static Calendar_Meeting__c mapEvent(Map<String, Object> ev) {
        Map<String, Object> start = (Map<String, Object>) ev.get('start');
        Map<String, Object> ending = (Map<String, Object>) ev.get('end');
        String startStr = (start != null) ? (String) start.get('dateTime') : null;
        String endStr = (ending != null) ? (String) ending.get('dateTime') : null;
        if (String.isBlank(startStr) || String.isBlank(endStr)) {
            return null; // all-day / malformed — out of scope for the POC
        }

        Calendar_Meeting__c m = new Calendar_Meeting__c();
        m.Google_Event_Id__c = (String) ev.get('id');
        m.Subject__c = truncate((String) ev.get('summary'), 255);
        m.Location__c = truncate((String) ev.get('location'), 255);
        m.Meeting_Link__c = truncate((String) ev.get('hangoutLink'), 255);
        m.Start_Time__c = parseRfc3339(startStr);
        m.End_Time__c = parseRfc3339(endStr);
        m.Source__c = SOURCE_GOOGLE;
        m.Sync_Status__c = STATUS_SYNCED;
        m.Event_Status__c = statusLabel((String) ev.get('status'));

        Map<String, Object> organizer = (Map<String, Object>) ev.get('organizer');
        if (organizer != null) {
            m.Organizer_Email__c = (String) organizer.get('email');
        }
        m.Attendee_Emails__c = joinAttendees(ev);
        return m;
    }

    /**
     * @description Joins the event's attendee emails into a comma-separated string.
     * @param ev The raw Google event map.
     * @return Comma-separated attendee emails, or null when there are none.
     */
    private static String joinAttendees(Map<String, Object> ev) {
        Object raw = ev.get('attendees');
        if (!(raw instanceof List<Object>)) {
            return null;
        }
        List<String> emails = new List<String>();
        for (Object a : (List<Object>) raw) {
            Object email = ((Map<String, Object>) a).get('email');
            if (email != null) {
                emails.add((String) email);
            }
        }
        return emails.isEmpty() ? null : String.join(emails, ', ');
    }

    /**
     * @description Maps a Google event status to a Calendar_Meeting__c picklist label.
     * @param status The Google event status (confirmed/tentative/cancelled).
     * @return The matching picklist label, defaulting to 'Confirmed'.
     */
    private static String statusLabel(String status) {
        if (String.isBlank(status)) {
            return 'Confirmed';
        }
        String s = status.toLowerCase();
        if (s == 'cancelled') {
            return 'Cancelled';
        }
        if (s == 'tentative') {
            return 'Tentative';
        }
        return 'Confirmed';
    }

    /**
     * @description Null-safe substring guard for text fields.
     * @param value The candidate value.
     * @param maxLen The maximum length to keep.
     * @return The value trimmed to maxLen, or null when blank.
     */
    private static String truncate(String value, Integer maxLen) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }

    /**
     * @description Parses an RFC 3339 timestamp (e.g. 2026-07-10T14:00:00+05:30 or
     *          ...Z, with optional fractional seconds) into a Datetime instant.
     *          Apex has no built-in RFC 3339 parser, so we read the wall-clock
     *          components as GMT and then subtract the zone offset to get true UTC.
     * @param value The RFC 3339 timestamp string.
     * @return The parsed Datetime, or null when it cannot be parsed.
     */
    @TestVisible
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

            // Wall-clock instant treated as if it were GMT.
            Datetime wall = Datetime.newInstanceGmt(year, month, day, hour, minute, second);

            // Offset: portion after the seconds (ignoring optional fractional part).
            Integer offsetMinutes = offsetMinutes(value.substring(19));
            // wallClock = utc + offset  =>  utc = wallClock - offset
            return wall.addMinutes(-offsetMinutes);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Parses the timezone offset tail of an RFC 3339 string into minutes.
     * @param tail The part after the seconds, e.g. 'Z', '+05:30', '.000+05:30', '-08:00'.
     * @return The offset in minutes (0 for UTC/'Z' or when absent).
     */
    private static Integer offsetMinutes(String tail) {
        if (String.isBlank(tail)) {
            return 0;
        }
        // Drop optional fractional seconds like '.123'.
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
        String hhmm = t.substring(1); // strip sign
        Integer oh = Integer.valueOf(hhmm.substring(0, 2));
        Integer om = (hhmm.length() >= 5) ? Integer.valueOf(hhmm.substring(3, 5)) : 0;
        return sign * (oh * 60 + om);
    }

    /**
     * @description Exception type for inbound-sync failures.
     */
    public class InboundException extends Exception {}
}