/**
 * @description Keeps Missed_Sessions__c links between a Leave_Application__c and a
 *              Session_Enrollment__c consistent with the current leave window and
 *              session timings. A link is valid only while the session sits entirely
 *              inside the leave window; anything else is removed so the Leave
 *              Application's Missed Sessions related list never shows stale rows.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class MissedSessionSyncService {

    private static final String SANCTIONED_LEAVE = 'Sanctioned Leave';

    /**
     * Leave Ids captured in a before-delete context, resynced once the delete has
     * committed. Needed because deleting a Session_Enrollment__c nulls the
     * Missed_Sessions__c lookup, so the relationship is unreadable after the fact.
     */
    private static Set<Id> pendingLeaveIds = new Set<Id>();

    /**
     * @description Decides whether a session is fully covered by a leave window.
     * @param leaveStart Leave window start.
     * @param leaveEnd Leave window end.
     * @param sessionStart Session start time.
     * @param sessionEnd Session end time.
     * @return True only when the session sits entirely inside the leave window.
     */
    public static Boolean isCovered(
        Datetime leaveStart,
        Datetime leaveEnd,
        Datetime sessionStart,
        Datetime sessionEnd
    ) {
        if (leaveStart == null || leaveEnd == null || sessionStart == null || sessionEnd == null) {
            return false;
        }
        return sessionStart >= leaveStart && sessionEnd <= leaveEnd;
    }

    /**
     * @description Re-evaluates every Missed_Sessions__c row on the given leaves and
     *              removes the ones no longer covered. A row whose enrollment or
     *              session no longer exists cannot be covered, so it is removed too
     *              rather than skipped — otherwise it stays visible forever.
     * @param leaveIds Leave_Application__c Ids to re-evaluate.
     */
    public static void resyncForLeaves(Set<Id> leaveIds) {
        if (leaveIds == null || leaveIds.isEmpty()) {
            return;
        }

        List<Missed_Sessions__c> toDelete = new List<Missed_Sessions__c>();
        Set<Id> unlinkedEnrollmentIds = new Set<Id>();

        for (Missed_Sessions__c ms : [
            SELECT Id, Session_Enrollment__c,
                   Leave_Application__r.Start_Date__c,
                   Leave_Application__r.End_Date__c,
                   Session_Enrollment__r.Session__r.Start_Time__c,
                   Session_Enrollment__r.Session__r.End_Time__c
            FROM Missed_Sessions__c
            WHERE Leave_Application__c IN :leaveIds
        ]) {
            if (isStillCovered(ms)) {
                continue;
            }
            toDelete.add(new Missed_Sessions__c(Id = ms.Id));
            if (ms.Session_Enrollment__c != null) {
                unlinkedEnrollmentIds.add(ms.Session_Enrollment__c);
            }
        }

        if (toDelete.isEmpty()) {
            return;
        }

        Database.delete(toDelete, false);
        clearSanctionedLeave(unlinkedEnrollmentIds);
    }

    /**
     * @description Tells whether a single link is still justified by its leave window.
     *              A missing leave, enrollment or session all mean "not covered".
     * @param ms The Missed_Sessions__c row with its leave and session fields queried.
     * @return True when the linked session still falls inside the leave window.
     */
    private static Boolean isStillCovered(Missed_Sessions__c ms) {
        if (ms.Leave_Application__r == null || ms.Session_Enrollment__r == null) {
            return false;
        }
        Session__c sess = ms.Session_Enrollment__r.Session__r;
        if (sess == null) {
            return false;
        }
        return isCovered(
            ms.Leave_Application__r.Start_Date__c,
            ms.Leave_Application__r.End_Date__c,
            sess.Start_Time__c,
            sess.End_Time__c
        );
    }

    /**
     * @description Clears Sanctioned Leave attendance on enrollments that just lost
     *              their last excusing link.
     * @param enrollmentIds Session_Enrollment__c Ids whose links were removed.
     */
    private static void clearSanctionedLeave(Set<Id> enrollmentIds) {
        if (enrollmentIds == null || enrollmentIds.isEmpty()) {
            return;
        }

        Set<Id> stillExcused = new Set<Id>();
        for (Missed_Sessions__c ms : [
            SELECT Session_Enrollment__c
            FROM Missed_Sessions__c
            WHERE Session_Enrollment__c IN :enrollmentIds
        ]) {
            stillExcused.add(ms.Session_Enrollment__c);
        }

        List<Session_Enrollment__c> updates = new List<Session_Enrollment__c>();
        for (Session_Enrollment__c se : [
            SELECT Id
            FROM Session_Enrollment__c
            WHERE Id IN :enrollmentIds
              AND Attendance__c = :SANCTIONED_LEAVE
        ]) {
            if (!stillExcused.contains(se.Id)) {
                updates.add(new Session_Enrollment__c(Id = se.Id, Attendance__c = null));
            }
        }

        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }

    /**
     * @description Resyncs links for sessions whose timings were changed, so a
     *              rescheduled or republished session drops out of the Missed
     *              Sessions list when it no longer clashes with the leave.
     * @param newMap Sessions after the update.
     * @param oldMap Sessions before the update.
     */
    public static void handleSessionDateChanges(
        Map<Id, Session__c> newMap,
        Map<Id, Session__c> oldMap
    ) {
        if (newMap == null || newMap.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> rescheduledSessionIds = new Set<Id>();
        for (Session__c sess : newMap.values()) {
            Session__c oldRec = oldMap.get(sess.Id);
            if (oldRec == null) {
                continue;
            }
            if (sess.Start_Time__c != oldRec.Start_Time__c
                || sess.End_Time__c != oldRec.End_Time__c) {
                rescheduledSessionIds.add(sess.Id);
            }
        }

        resyncForSessions(rescheduledSessionIds);
    }

    /**
     * @description Resyncs every leave that has a link into the given sessions.
     * @param sessionIds Session__c Ids to resync against.
     */
    public static void resyncForSessions(Set<Id> sessionIds) {
        if (sessionIds == null || sessionIds.isEmpty()) {
            return;
        }

        Set<Id> leaveIds = new Set<Id>();
        for (Missed_Sessions__c ms : [
            SELECT Leave_Application__c
            FROM Missed_Sessions__c
            WHERE Session_Enrollment__r.Session__c IN :sessionIds
              AND Leave_Application__c != NULL
        ]) {
            leaveIds.add(ms.Leave_Application__c);
        }
        resyncForLeaves(leaveIds);
    }

    /**
     * @description Records the leaves affected by enrollments or sessions that are about
     *              to be deleted. Must run in a before-delete context: once the enrollment
     *              is gone its Missed_Sessions__c lookup is null (deleteConstraint SetNull)
     *              and the row can no longer be traced back to its leave. Deleting a
     *              Session__c cascade-deletes its enrollments without firing their own
     *              delete trigger, which is why sessions are handled here too.
     * @param enrollmentIds Session_Enrollment__c Ids being deleted; may be null.
     * @param sessionIds Session__c Ids being deleted; may be null.
     */
    public static void capturePendingLeaves(Set<Id> enrollmentIds, Set<Id> sessionIds) {
        Set<Id> enrollments = enrollmentIds == null ? new Set<Id>() : enrollmentIds;
        Set<Id> sessions = sessionIds == null ? new Set<Id>() : sessionIds;
        if (enrollments.isEmpty() && sessions.isEmpty()) {
            return;
        }
        for (Missed_Sessions__c ms : [
            SELECT Leave_Application__c
            FROM Missed_Sessions__c
            WHERE Leave_Application__c != NULL
              AND (Session_Enrollment__c IN :enrollments
                   OR Session_Enrollment__r.Session__c IN :sessions)
        ]) {
            pendingLeaveIds.add(ms.Leave_Application__c);
        }
    }

    /**
     * @description Resyncs the leaves captured before a delete and clears the buffer.
     *              Safe to call when nothing was captured.
     */
    public static void resyncPendingLeaves() {
        if (pendingLeaveIds.isEmpty()) {
            return;
        }
        Set<Id> toProcess = pendingLeaveIds.clone();
        pendingLeaveIds.clear();
        resyncForLeaves(toProcess);
    }
}