/**
 * @description Mirrors the STUDENT calendar RSVP responses captured on Session_Attendee__c
 *              (by the colleague's SessionAttendeeSync* flow) onto the matching
 *              Session_Enrollment__c record's Invite_Response__c / Invite_Response_Checked__c
 *              fields. This is purely additive: Session_Attendee__c remains the full
 *              per-attendee source of truth; faculty and guest attendees are skipped because
 *              they have no Session_Enrollment__c record.
 *
 *              Attendees are matched to enrollments by (session + lower-cased email), where the
 *              enrollment's student email is
 *              Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail.
 *
 *              CRUD/FLS is suppressed to match the sibling SessionAttendeeSync* classes: the
 *              mirror runs inside the scheduled attendee-sync batch (integration context) and
 *              must persist regardless of the running user's field-level security; the update
 *              is allOrNone=false so a mirror failure can never roll back the parent
 *              Session_Attendee__c write.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class SessionAttendeeMirrorHandler {

    private static final String TYPE_STUDENT     = 'Student';
    private static final String STATUS_ACCEPTED  = 'Accepted';
    private static final String STATUS_DECLINED  = 'Declined';
    private static final String STATUS_TENTATIVE = 'Tentative';
    private static final String RESP_NO_RESPONSE = 'No Response';

    /**
     * @description Trigger entry point. Builds the student response map from the changed
     *              attendee rows, loads their enrollments, and persists any changed responses.
     * @param attendees The Session_Attendee__c rows from Trigger.new (may be null/empty).
     */
    public static void mirrorResponsesToEnrollment(List<Session_Attendee__c> attendees) {
        Map<String, String> responseByKey = buildStudentResponseMap(attendees);
        if (responseByKey.isEmpty()) {
            return;
        }
        List<Session_Enrollment__c> enrollments = queryEnrollments(collectSessionIds(attendees));
        persistResponses(enrollments, responseByKey);
    }

    /**
     * @description Builds a lookup of desired Invite_Response values for STUDENT attendees only.
     * @param attendees The attendee rows to inspect.
     * @return Map keyed by "sessionId:loweredEmail" -> Invite_Response picklist value.
     */
    @TestVisible
    private static Map<String, String> buildStudentResponseMap(List<Session_Attendee__c> attendees) {
        Map<String, String> result = new Map<String, String>();
        if (attendees == null) {
            return result;
        }
        for (Session_Attendee__c att : attendees) {
            if (att.Attendee_Type__c != TYPE_STUDENT) {
                continue;
            }
            if (String.isBlank(att.Attendee_Email__c) || att.Session__c == null) {
                continue;
            }
            result.put(matchKey(att.Session__c, att.Attendee_Email__c), mapResponse(att.Response_Status__c));
        }
        return result;
    }

    /**
     * @description Collects the session ids of the STUDENT attendees in the batch.
     * @param attendees The attendee rows to inspect.
     * @return The distinct session ids to load enrollments for.
     */
    @TestVisible
    private static Set<Id> collectSessionIds(List<Session_Attendee__c> attendees) {
        Set<Id> ids = new Set<Id>();
        if (attendees == null) {
            return ids;
        }
        for (Session_Attendee__c att : attendees) {
            if (att.Attendee_Type__c == TYPE_STUDENT && att.Session__c != null) {
                ids.add(att.Session__c);
            }
        }
        return ids;
    }

    /**
     * @description Loads the enrollments (with the student email path) for the given sessions.
     * @param sessionIds The session ids to query enrollments for.
     * @return The matching Session_Enrollment__c rows (empty when no ids).
     */
    @TestVisible
    private static List<Session_Enrollment__c> queryEnrollments(Set<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return new List<Session_Enrollment__c>();
        }
        return [
            SELECT Id, Session__c, Invite_Response__c,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail
            FROM Session_Enrollment__c
            WHERE Session__c IN :sessionIds
        ];
    }

    /**
     * @description Applies the desired responses to the loaded enrollments and updates only
     *              those whose Invite_Response__c actually changed (allOrNone=false so a single
     *              failure never rolls back the parent attendee write).
     * @param enrollments The enrollments loaded for the affected sessions.
     * @param responseByKey Desired responses keyed by "sessionId:loweredEmail".
     */
    @TestVisible
    private static void persistResponses(List<Session_Enrollment__c> enrollments, Map<String, String> responseByKey) {
        List<Session_Enrollment__c> toUpdate = applyResponses(enrollments, responseByKey);
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    /**
     * @description Pure matcher: returns the enrollments whose Invite_Response__c should change.
     * @param enrollments The enrollments loaded for the affected sessions.
     * @param responseByKey Desired responses keyed by "sessionId:loweredEmail".
     * @return The subset of enrollments with updated Invite_Response__c / Invite_Response_Checked__c.
     */
    @TestVisible
    private static List<Session_Enrollment__c> applyResponses(List<Session_Enrollment__c> enrollments,
                                                              Map<String, String> responseByKey) {
        List<Session_Enrollment__c> changed = new List<Session_Enrollment__c>();
        if (enrollments == null) {
            return changed;
        }
        Datetime nowTs = Datetime.now();
        for (Session_Enrollment__c enr : enrollments) {
            String email = extractEmail(enr);
            if (String.isBlank(email)) {
                continue;
            }
            String desired = responseByKey.get(matchKey(enr.Session__c, email));
            if (desired != null && enr.Invite_Response__c != desired) {
                enr.Invite_Response__c = desired;
                enr.Invite_Response_Checked__c = nowTs;
                changed.add(enr);
            }
        }
        return changed;
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

    /**
     * @description Composite match key so attendees and enrollments join on session + email.
     * @param sessionId The session id.
     * @param email The attendee/student email (any case).
     * @return "sessionId:loweredEmail".
     */
    @TestVisible
    private static String matchKey(Id sessionId, String email) {
        return String.valueOf(sessionId) + ':' + email.toLowerCase();
    }

    /**
     * @description Maps a Session_Attendee__c.Response_Status__c value to the enrollment's
     *              Invite_Response__c picklist. Anything other than the three positive
     *              statuses (e.g. "Needs Action" / blank) becomes "No Response".
     * @param attendeeStatus The Response_Status__c value from Session_Attendee__c.
     * @return The Invite_Response__c picklist value.
     */
    @TestVisible
    private static String mapResponse(String attendeeStatus) {
        if (attendeeStatus == STATUS_ACCEPTED) {
            return STATUS_ACCEPTED;
        }
        if (attendeeStatus == STATUS_DECLINED) {
            return STATUS_DECLINED;
        }
        if (attendeeStatus == STATUS_TENTATIVE) {
            return STATUS_TENTATIVE;
        }
        return RESP_NO_RESPONSE;
    }
}