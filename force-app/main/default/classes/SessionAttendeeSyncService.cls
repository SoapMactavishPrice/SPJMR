/**
 * @description RSVP read-back (Target 1): maps a Google Calendar event's attendee
 *          list + response statuses onto Session_Attendee__c child records of a
 *          Session__c, and persists them idempotently by Attendee_Key__c.
 *
 *          Read-back uses the ORGANIZER's calendar copy (the impersonated user in
 *          Google_Calendar_Config__mdt) — the only copy that reliably exposes each
 *          attendee's responseStatus, and the same account the outbound push
 *          organizes events as (see GoogleCalendarService / SessionCalendarInviteQueueable).
 *
 * @note    Callout/DML ordering — mapAttendees() is pure (no SOQL/DML) so callers can
 *          run all Calendar callouts first, collect rows, then call persistBySession()
 *          once. Apex forbids a callout after uncommitted DML.
 */
// ApexCRUDViolation suppressed: system-context sync of external calendar data into a
// dedicated child object; access is governed by the Master-Detail parent Session__c.
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class SessionAttendeeSyncService {

    private static final String STATUS_ACCEPTED     = 'Accepted';
    private static final String STATUS_DECLINED     = 'Declined';
    private static final String STATUS_TENTATIVE    = 'Tentative';
    private static final String STATUS_NEEDS_ACTION = 'Needs Action';

    private static final String TYPE_FACULTY = 'Faculty';
    private static final String TYPE_STUDENT = 'Student';
    private static final String TYPE_OTHER   = 'Other';

    /**
     * @description Maps a raw Google event's attendees[] to (unsaved) Session_Attendee__c
     *          rows for one session. Pure — no SOQL/DML — so it is safe to call between
     *          Calendar callouts.
     * @param sessionId The parent Session__c id.
     * @param eventMap The parsed Google event (from GoogleCalendarService.getCalendarEvent).
     * @param facultyEmails Lower-cased faculty emails for this session (for typing); may be null.
     * @param studentEmails Lower-cased student emails for this session (for typing); may be null.
     * @return Unsaved Session_Attendee__c rows keyed by Attendee_Key__c (may be empty).
     */
    public static List<Session_Attendee__c> mapAttendees(
        Id sessionId,
        Map<String, Object> eventMap,
        Set<String> facultyEmails,
        Set<String> studentEmails
    ) {
        List<Session_Attendee__c> rows = new List<Session_Attendee__c>();
        if (sessionId == null || eventMap == null) {
            return rows;
        }
        Object rawAttendees = eventMap.get('attendees');
        if (!(rawAttendees instanceof List<Object>)) {
            return rows;
        }

        Datetime now = Datetime.now();
        Set<String> seenKeys = new Set<String>();
        for (Object o : (List<Object>) rawAttendees) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> att = (Map<String, Object>) o;
            String email = (String) att.get('email');
            if (String.isBlank(email)) {
                continue;
            }
            // Skip meeting rooms / resources — they appear as attendees with resource=true.
            if (att.get('resource') == true) {
                continue;
            }

            String emailLc = email.toLowerCase().trim();
            String key = buildKey(sessionId, emailLc);
            if (seenKeys.contains(key)) {
                continue; // de-dup within one event
            }
            seenKeys.add(key);

            Session_Attendee__c row = new Session_Attendee__c();
            row.Session__c          = sessionId;
            row.Attendee_Email__c   = email;
            row.Response_Status__c  = mapResponseStatus((String) att.get('responseStatus'));
            row.Attendee_Type__c    = resolveType(emailLc, facultyEmails, studentEmails);
            row.Is_Organizer__c     = (att.get('organizer') == true);
            row.Response_Comment__c = truncate((String) att.get('comment'), 255);
            row.Last_Synced__c      = now;
            row.Attendee_Key__c     = key;
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description Persists mapped attendee rows for the given sessions: deletes rows
     *          that are no longer on the event and upserts the current ones by
     *          Attendee_Key__c. DML only — call AFTER all Calendar callouts.
     * @param rowsBySession Map of sessionId → mapped rows (only sessions read successfully).
     */
    public static void persistBySession(Map<Id, List<Session_Attendee__c>> rowsBySession) {
        if (rowsBySession == null || rowsBySession.isEmpty()) {
            return;
        }

        List<Session_Attendee__c> toUpsert = new List<Session_Attendee__c>();
        Set<String> desiredKeys = new Set<String>();
        for (List<Session_Attendee__c> rows : rowsBySession.values()) {
            if (rows == null) {
                continue;
            }
            for (Session_Attendee__c r : rows) {
                toUpsert.add(r);
                desiredKeys.add(r.Attendee_Key__c);
            }
        }

        // Delete stale rows: still on a synced session but no longer on the Google event.
        List<Session_Attendee__c> toDelete = new List<Session_Attendee__c>();
        for (Session_Attendee__c existing : [
            SELECT Id, Attendee_Key__c
            FROM   Session_Attendee__c
            WHERE  Session__c IN :rowsBySession.keySet()
        ]) {
            if (!desiredKeys.contains(existing.Attendee_Key__c)) {
                toDelete.add(existing);
            }
        }

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toUpsert.isEmpty()) {
            upsert toUpsert Attendee_Key__c;
        }
    }

    /**
     * @description Maps a Google responseStatus to the Session_Attendee__c picklist.
     * @param googleStatus accepted / declined / tentative / needsAction.
     * @return The matching picklist value; defaults to Needs Action (Awaiting).
     */
    @TestVisible
    private static String mapResponseStatus(String googleStatus) {
        if (String.isBlank(googleStatus)) {
            return STATUS_NEEDS_ACTION;
        }
        String s = googleStatus.toLowerCase().trim();
        if (s == 'accepted')  { return STATUS_ACCEPTED; }
        if (s == 'declined')  { return STATUS_DECLINED; }
        if (s == 'tentative') { return STATUS_TENTATIVE; }
        return STATUS_NEEDS_ACTION;
    }

    /**
     * @description Composite external-id key for idempotent upsert.
     * @param sessionId The parent session id.
     * @param emailLc The lower-cased attendee email.
     * @return sessionId:email.
     */
    @TestVisible
    private static String buildKey(Id sessionId, String emailLc) {
        return String.valueOf(sessionId) + ':' + emailLc;
    }

    /**
     * @description Classifies an attendee email as Faculty / Student / Other using the
     *          session's known participant emails.
     * @param emailLc Lower-cased attendee email.
     * @param facultyEmails Lower-cased faculty emails (may be null).
     * @param studentEmails Lower-cased student emails (may be null).
     * @return 'Faculty', 'Student', or 'Other'.
     */
    private static String resolveType(String emailLc, Set<String> facultyEmails, Set<String> studentEmails) {
        if (facultyEmails != null && facultyEmails.contains(emailLc)) {
            return TYPE_FACULTY;
        }
        if (studentEmails != null && studentEmails.contains(emailLc)) {
            return TYPE_STUDENT;
        }
        return TYPE_OTHER;
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
}