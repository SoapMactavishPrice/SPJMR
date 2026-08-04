@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class MissedSessionSyncService {

    private static final String SANCTIONED_LEAVE = 'Sanctioned Leave';

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
              AND Session_Enrollment__c != NULL
        ]) {
            if (ms.Leave_Application__r == null || ms.Session_Enrollment__r == null) {
                continue;
            }
            Session__c sess = ms.Session_Enrollment__r.Session__r;
            if (sess == null) {
                continue;
            }
            Boolean covered = isCovered(
                ms.Leave_Application__r.Start_Date__c,
                ms.Leave_Application__r.End_Date__c,
                sess.Start_Time__c,
                sess.End_Time__c
            );
            if (!covered) {
                toDelete.add(new Missed_Sessions__c(Id = ms.Id));
                unlinkedEnrollmentIds.add(ms.Session_Enrollment__c);
            }
        }

        if (toDelete.isEmpty()) {
            return;
        }

        Database.delete(toDelete, false);
        clearSanctionedLeave(unlinkedEnrollmentIds);
    }

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
}