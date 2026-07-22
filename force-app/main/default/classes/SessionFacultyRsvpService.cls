/**
 * @description RSVP read-back (Target 1, faculty): maps a Google Calendar event's attendee
 *          responseStatus directly onto the matching Session_Faculty__c.Invite_Response__c
 *          for a session's faculty. The parallel student read-back onto Session_Enrollment__c
 *          lives in SessionRsvpSyncService; both run off the same parsed event map that
 *          SessionAttendeeSyncBatch collects, so faculty RSVP costs no extra callout.
 *
 *          Faculty are matched by the same email used to invite them:
 *          Session_Faculty__c.Session_Faculty__r.PersonEmail (the faculty Account's person
 *          email — see SessionCalendarInviteQueueable.resolveFacultyEmails).
 *
 * @note    Callout/DML ordering — this class does DML only. Its caller runs all Calendar
 *          callouts first, collects the parsed maps, then calls applyToSessionFaculty() once.
 *          Apex forbids a callout after uncommitted DML.
 */
// ApexCRUDViolation suppressed: system-context sync of external calendar data onto the
// Session_Faculty__c junction governed by its parent Session__c.
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class SessionFacultyRsvpService {

    /**
     * @description Writes parsed responses onto the session's faculty (Session_Faculty__c)
     *          rows, updating only those whose Invite_Response__c actually changed. DML only —
     *          call AFTER all Calendar callouts. Non-faculty Google attendees never match a
     *          Session_Faculty__c row and are ignored.
     * @param responsesBySession Map of sessionId → (emailLc → Invite_Response value).
     */
    public static void applyToSessionFaculty(Map<Id, Map<String, String>> responsesBySession) {
        if (responsesBySession == null || responsesBySession.isEmpty()) {
            return;
        }
        List<Session_Faculty__c> facultyRows = [
            SELECT Id, Session__c, Invite_Response__c, Session_Faculty__r.PersonEmail
            FROM   Session_Faculty__c
            WHERE  Session__c IN :responsesBySession.keySet()
        ];
        persist(matchResponses(facultyRows, responsesBySession));
    }

    /**
     * @description Updates the changed faculty rows. allOrNone=false so a single bad row
     *          never rolls back the rest of the batch. DML seam for tests.
     * @param toUpdate The Session_Faculty__c rows whose Invite_Response__c changed.
     */
    @TestVisible
    private static void persist(List<Session_Faculty__c> toUpdate) {
        if (toUpdate != null && !toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Pure matcher: returns the Session_Faculty__c rows whose Invite_Response__c
     *          should change, given the desired responses. No SOQL/DML — the DML seam for tests.
     * @param facultyRows The Session_Faculty__c rows loaded for the affected sessions.
     * @param responsesBySession Map of sessionId → (emailLc → Invite_Response value).
     * @return The subset of rows with updated Invite_Response__c / Invite_Response_Checked__c.
     */
    @TestVisible
    private static List<Session_Faculty__c> matchResponses(
        List<Session_Faculty__c> facultyRows,
        Map<Id, Map<String, String>> responsesBySession
    ) {
        List<Session_Faculty__c> changed = new List<Session_Faculty__c>();
        if (facultyRows == null || responsesBySession == null) {
            return changed;
        }
        Datetime nowTs = Datetime.now();
        for (Session_Faculty__c fac : facultyRows) {
            Map<String, String> forSession = responsesBySession.get(fac.Session__c);
            String email = extractEmail(fac);
            if (forSession == null || String.isBlank(email)) {
                continue;
            }
            String desired = forSession.get(email.toLowerCase().trim());
            if (desired != null && fac.Invite_Response__c != desired) {
                fac.Invite_Response__c = desired;
                fac.Invite_Response_Checked__c = nowTs;
                changed.add(fac);
            }
        }
        return changed;
    }

    /**
     * @description Null-safe traversal to the faculty member's Person Account email.
     * @param fac The Session_Faculty__c row (with the relationship path selected).
     * @return The faculty PersonEmail, or null when the faculty Account is missing.
     */
    @TestVisible
    private static String extractEmail(Session_Faculty__c fac) {
        if (fac.Session_Faculty__r == null) {
            return null;
        }
        return fac.Session_Faculty__r.PersonEmail;
    }
}