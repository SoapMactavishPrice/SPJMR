public class LeaveApplicationTriggerHandler {

    private static final Set<String> FINAL_APPROVED_STATUSES = new Set<String>{
        'Approved',
        'Approved - Eligible for Makeup',
        'Approved - Not Eligible for Makeup'
    };
    
    /** Active Programme Office users, for assigning the first approval step. */
    private static List<Id> getProgrammeOfficeUsers() {

        List<Id> userIds = new List<Id>();

        for(Program_Team_Members__c ptm : [
            SELECT User__c
            FROM Program_Team_Members__c
            WHERE Role__c = 'Programme Office'
            AND User__c != null
        ]){
            userIds.add(ptm.User__c);
        }

        return userIds;
    }

    /** Initializes a new leave request into the first approval step. */
    public static void beforeInsert(List<Leave_Application__c> newRecords) {

        List<Id> poUserIds = getProgrammeOfficeUsers();

        for (Leave_Application__c rec : newRecords) {
            rec.Status__c            = 'Submitted - Pending Approval';
            rec.Current_Role_Name__c = 'Programme Office';
            rec.Route_to_Deputy__c   = false;

            if(!poUserIds.isEmpty()){
                rec.Current_Approver_User__c = poUserIds[0];
            }
        }
    }

    /** No-op: submission is handled by LeaveSubmissionController.SubmitLeaveJob. */
    public static void afterInsert(List<Leave_Application__c> newRecords) {
    }

    private static void resyncChangedLeaveWindows(
        List<Leave_Application__c> newList,
        Map<Id, Leave_Application__c> oldMap
    ) {
        Set<Id> movedLeaveIds = new Set<Id>();
        for (Leave_Application__c rec : newList) {
            if (rec == null || rec.Id == null) {
                continue;
            }
            Leave_Application__c oldRec = oldMap.get(rec.Id);
            if (oldRec == null) {
                continue;
            }
            if (rec.Start_Date__c != oldRec.Start_Date__c
                || rec.End_Date__c != oldRec.End_Date__c) {
                movedLeaveIds.add(rec.Id);
            }
        }

        if (!movedLeaveIds.isEmpty()) {
            MissedSessionSyncService.resyncForLeaves(movedLeaveIds);
        }
    }

    /** On final approval, marks the leave's sessions Sanctioned Leave via Missed_Sessions__c. */
    public static void afterUpdate(List<Leave_Application__c> newList, Map<Id, Leave_Application__c> oldMap) {

        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        resyncChangedLeaveWindows(newList, oldMap);

        Set<Id> qualifyingLeaveIds = new Set<Id>();
        Map<Id, String> leaveIdToLeaveType = new Map<Id, String>();

        for (Leave_Application__c rec : newList) {

            if (rec == null || rec.Id == null) {
                continue;
            }

            Leave_Application__c oldRec = oldMap.get(rec.Id);

            if (oldRec == null) {
                continue;
            }

            String newStatus = rec.Status__c;
            String oldStatus = oldRec.Status__c;

            if (newStatus == oldStatus || String.isBlank(newStatus)) {
                continue;
            }

            if (!FINAL_APPROVED_STATUSES.contains(newStatus)) {
                continue;
            }

            qualifyingLeaveIds.add(rec.Id);

            if (String.isNotBlank(rec.Leave_Type__c)) {
                leaveIdToLeaveType.put(rec.Id, rec.Leave_Type__c);
            }
        }

        if (qualifyingLeaveIds.isEmpty()) {
            return;
        }

        List<Missed_Sessions__c> missedRows = [
            SELECT Id, Leave_Application__c, Session_Enrollment__c
            FROM Missed_Sessions__c
            WHERE Leave_Application__c IN :qualifyingLeaveIds
            AND Session_Enrollment__c != NULL
        ];

        if (missedRows.isEmpty()) {
            return;
        }

        Map<Id, String> enrollmentToLeaveType = new Map<Id, String>();
        Set<Id> enrollmentIds = new Set<Id>();

        for (Missed_Sessions__c ms : missedRows) {
            if (ms.Session_Enrollment__c == null || ms.Leave_Application__c == null) {
                continue;
            }
            enrollmentIds.add(ms.Session_Enrollment__c);
            String leaveType = leaveIdToLeaveType.get(ms.Leave_Application__c);
            if (String.isNotBlank(leaveType)) {
                enrollmentToLeaveType.put(ms.Session_Enrollment__c, leaveType);
            }
        }

        if (enrollmentIds.isEmpty()) {
            return;
        }

        Map<Id, Session_Enrollment__c> existingEnrollments = new Map<Id, Session_Enrollment__c>([
            SELECT Id
            FROM Session_Enrollment__c
            WHERE Id IN :enrollmentIds
        ]);

        List<Session_Enrollment__c> toUpdate = new List<Session_Enrollment__c>();
        for (Id seId : existingEnrollments.keySet()) {
            Session_Enrollment__c se = new Session_Enrollment__c(Id = seId, Attendance__c = 'Sanctioned Leave');
            String lt = enrollmentToLeaveType.get(seId);
            if (String.isNotBlank(lt)) {
                se.Leave_Type__c = lt;
            }
            toUpdate.add(se);
        }

        if (toUpdate.isEmpty()) {
            return;
        }

        Database.update(toUpdate, false);
    }
}