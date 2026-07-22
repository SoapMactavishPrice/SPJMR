/**
 * @description RSVP read-back (Target 1): maps a Google Calendar event's attendee
 *          responseStatus directly onto the matching Session_Enrollment__c.Invite_Response__c
 *          for a session's enrolled students. Replaces the Session_Attendee__c staging object.
 *          The parallel faculty read-back (Session_Faculty__c) lives in SessionFacultyRsvpService.
 *
 *          Read-back uses the ORGANIZER's calendar copy (the impersonated user in
 *          Google_Calendar_Config__mdt) — the only copy that reliably exposes each
 *          attendee's responseStatus.
 *
 * @note    Callout/DML ordering — parseResponses() is pure (no SOQL/DML) so callers can
 *          run all Calendar callouts first, collect the parsed maps, then call
 *          applyToEnrollments() once. Apex forbids a callout after uncommitted DML.
 */
// ApexCRUDViolation suppressed: system-context sync of external calendar data onto
// enrollments governed by their Master-Detail parent Session__c.
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class SessionRsvpSyncService {

    private static final String RESP_ACCEPTED  = 'Accepted';
    private static final String RESP_DECLINED  = 'Declined';
    private static final String RESP_TENTATIVE = 'Tentative';
    private static final String RESP_NONE      = 'No Response';

    /**
     * @description Parses a Google event's attendees[] into a map of lower-cased email →
     *          Invite_Response picklist value. Pure — no SOQL/DML — so it is safe to call
     *          between Calendar callouts.
     * @param eventMap The parsed Google event (from GoogleCalendarService.getCalendarEvent).
     * @return Map of emailLc → Invite_Response value (empty when there are no attendees).
     */
    public static Map<String, String> parseResponses(Map<String, Object> eventMap) {
        Map<String, String> byEmail = new Map<String, String>();
        if (eventMap == null) {
            return byEmail;
        }
        Object rawAttendees = eventMap.get('attendees');
        if (!(rawAttendees instanceof List<Object>)) {
            return byEmail;
        }
        for (Object o : (List<Object>) rawAttendees) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> att = (Map<String, Object>) o;
            String email = (String) att.get('email');
            // Skip blanks and meeting rooms / resources (resource=true).
            if (String.isBlank(email) || att.get('resource') == true) {
                continue;
            }
            byEmail.put(email.toLowerCase().trim(), mapResponse((String) att.get('responseStatus')));
        }
        return byEmail;
    }

    /**
     * @description Writes parsed responses onto the enrolled students' Session_Enrollment__c
     *          rows, updating only those whose Invite_Response__c actually changed. DML only —
     *          call AFTER all Calendar callouts. Non-student Google attendees never match an
     *          enrollment and are ignored.
     * @param responsesBySession Map of sessionId → (emailLc → Invite_Response value).
     */
    public static void applyToEnrollments(Map<Id, Map<String, String>> responsesBySession) {
        if (responsesBySession == null || responsesBySession.isEmpty()) {
            return;
        }
        List<Session_Enrollment__c> enrollments = [
            SELECT Id, Session__c, Invite_Response__c,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail
            FROM   Session_Enrollment__c
            WHERE  Session__c IN :responsesBySession.keySet()
        ];
        persist(matchResponses(enrollments, responsesBySession));
    }

    /**
     * @description Updates the changed enrollments. allOrNone=false so a single bad row
     *          never rolls back the rest of the batch. DML seam for tests.
     * @param toUpdate The enrollments whose Invite_Response__c changed.
     */
    @TestVisible
    private static void persist(List<Session_Enrollment__c> toUpdate) {
        if (toUpdate != null && !toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Pure matcher: returns the enrollments whose Invite_Response__c should
     *          change, given the desired responses. No SOQL/DML — the DML seam for tests.
     * @param enrollments The enrollments loaded for the affected sessions.
     * @param responsesBySession Map of sessionId → (emailLc → Invite_Response value).
     * @return The subset of enrollments with updated Invite_Response__c / Invite_Response_Checked__c.
     */
    @TestVisible
    private static List<Session_Enrollment__c> matchResponses(
        List<Session_Enrollment__c> enrollments,
        Map<Id, Map<String, String>> responsesBySession
    ) {
        List<Session_Enrollment__c> changed = new List<Session_Enrollment__c>();
        if (enrollments == null || responsesBySession == null) {
            return changed;
        }
        Datetime nowTs = Datetime.now();
        for (Session_Enrollment__c enr : enrollments) {
            Map<String, String> forSession = responsesBySession.get(enr.Session__c);
            String email = extractEmail(enr);
            if (forSession == null || String.isBlank(email)) {
                continue;
            }
            String desired = forSession.get(email.toLowerCase().trim());
            if (desired != null && enr.Invite_Response__c != desired) {
                enr.Invite_Response__c = desired;
                enr.Invite_Response_Checked__c = nowTs;
                changed.add(enr);
            }
        }
        return changed;
    }

    /**
     * @description Maps a Google responseStatus to the Invite_Response__c picklist.
     * @param googleStatus accepted / declined / tentative / needsAction.
     * @return The matching picklist value; defaults to 'No Response'.
     */
    @TestVisible
    private static String mapResponse(String googleStatus) {
        if (String.isBlank(googleStatus)) {
            return RESP_NONE;
        }
        String s = googleStatus.toLowerCase().trim();
        if (s == 'accepted')  { return RESP_ACCEPTED; }
        if (s == 'declined')  { return RESP_DECLINED; }
        if (s == 'tentative') { return RESP_TENTATIVE; }
        return RESP_NONE;
    }

    /**
     * @description Null-safe traversal to the enrollment student's Person Account email.
     * @param enr The enrollment row (with the relationship path selected).
     * @return The student's PersonEmail, or null when any step of the path is missing.
     */
    @TestVisible
    private static String extractEmail(Session_Enrollment__c enr) {
        if (enr.Division_Enrollment__r == null
            || enr.Division_Enrollment__r.Academic_Term_Enrollment__r == null
            || enr.Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount == null) {
            return null;
        }
        return enr.Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail;
    }
}