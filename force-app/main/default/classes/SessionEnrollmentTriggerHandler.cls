/**
 * Sends Portal_Notification__c records when Session_Enrollment__c.Attendance__c
 * changes to Absent, Late, or Sanctioned Leave (matches portal bell in spjimr_header).
 * Covers batch updates (e.g. AttendanceMarkingBatch) and manual edits.
 */
public without sharing class SessionEnrollmentTriggerHandler {

    private static final String NOTIF_TITLE = 'Attendance update';

    /**
     * Inserts one portal notification per enrollment row whose attendance
     * changed to a target status, for the learner on Academic_Term_Enrollment__c.
     */
    public static void handleAttendanceChanged(
        Map<Id, Session_Enrollment__c> newMap,
        Map<Id, Session_Enrollment__c> oldMap
    ) {
        Set<Id> enrollmentIds = new Set<Id>();

        for (Id seId : newMap.keySet()) {
            Session_Enrollment__c newRec = newMap.get(seId);
            Session_Enrollment__c oldRec = oldMap.get(seId);
            if (valuesEqual(newRec.Attendance__c, oldRec.Attendance__c)) {
                continue;
            }
            if (isTargetAttendanceStatus(newRec.Attendance__c)) {
                enrollmentIds.add(seId);
            }
        }

        if (enrollmentIds.isEmpty()) {
            return;
        }

        List<Session_Enrollment__c> rows = [
            SELECT Id,
                   Attendance__c,
                   Session__c,
                   Session__r.Name,
                   Academic_Term_Enrollment__r.LearnerAccountId
            FROM Session_Enrollment__c
            WHERE Id IN :enrollmentIds
        ];

        List<Portal_Notification__c> toInsert = new List<Portal_Notification__c>();

        for (Session_Enrollment__c se : rows) {
            Id learnerId = se.Academic_Term_Enrollment__r.LearnerAccountId;
            if (learnerId == null || se.Session__c == null) {
                continue;
            }

            String sessionName = String.isNotBlank(se.Session__r.Name)
                ? se.Session__r.Name
                : 'your session';
            String statusLabel = attendanceLabelForMessage(se.Attendance__c);
            String body =
                'Your attendance has been marked as ' +
                statusLabel +
                ' for "' +
                sessionName +
                '".';

            toInsert.add(
                new Portal_Notification__c(
                    Title__c = NOTIF_TITLE,
                    Body__c = body,
                    Recipient_Account__c = learnerId,
                    Is_Read__c = false,
                    Session__c = se.Session__c
                )
            );
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static Boolean valuesEqual(String a, String b) {
        String ta = a == null ? '' : a.trim();
        String tb = b == null ? '' : b.trim();
        return ta.equalsIgnoreCase(tb);
    }

    /**
     * True when the stored value should trigger a student notification.
     */
    private static Boolean isTargetAttendanceStatus(String attendance) {
        if (String.isBlank(attendance)) {
            return false;
        }
        String s = attendance.trim().toLowerCase();
        if (s == 'absent' || s == 'a') {
            return true;
        }
        if (s == 'late') {
            return true;
        }
        if (
            s == 'sanctioned leave' ||
            s == 'sanctioned' ||
            s == 'sl'
        ) {
            return true;
        }
        return false;
    }

    /**
     * Human-readable status for the notification body (uses org picklist text when sensible).
     */
    private static String attendanceLabelForMessage(String attendance) {
        if (String.isBlank(attendance)) {
            return 'updated';
        }
        String s = attendance.trim().toLowerCase();
        if (s == 'absent' || s == 'a') {
            return 'Absent';
        }
        if (s == 'late') {
            return 'Late';
        }
        if (s == 'sanctioned leave' || s == 'sanctioned' || s == 'sl') {
            return 'Sanctioned Leave';
        }
        return attendance.trim();
    }
}