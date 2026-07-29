// On final approval, syncs leave type and approver remark to session enrollments.
public class LeaveApplicationTriggerHandler {

    /** Final approval outcomes that should sync leave type to related session enrollments. */
    private static final Set<String> FINAL_APPROVED_STATUSES = new Set<String>{
        'Approved',
        'Approved - Eligible for Makeup',
        'Approved - Not Eligible for Makeup'
    };

    // ================= GET ALL PROGRAMME OFFICE USERS =================
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

    // ================= BEFORE INSERT =================
    public static void beforeInsert(List<Leave_Application__c> newRecords) {

        List<Id> poUserIds = getProgrammeOfficeUsers();

        for (Leave_Application__c rec : newRecords) {
            rec.Status__c            = 'Submitted - Pending Approval';
            rec.Current_Role_Name__c = 'Programme Office';
            rec.Route_to_Deputy__c   = false;

            // ✅ Only set display field if PO users exist — not a hard stop
            if(!poUserIds.isEmpty()){
                rec.Current_Approver_User__c = poUserIds[0];
            }
        }
    }

    // ================= AFTER INSERT =================
    public static void afterInsert(List<Leave_Application__c> newRecords) {
        // ✅ Do nothing here — approval submission is handled by
        // LeaveSubmissionController.SubmitLeaveJob (Queueable)
        // which is enqueued from LeaveRequestController.saveLeaveRequest()
    }

    // ================= AFTER UPDATE =================
    /**
     * When status moves to a final approved value, stamp Leave_Type__c on each Session_Enrollment__c
     * linked via Missed_Sessions__c (bulk-safe: 2 SOQL, 1 DML).
     */
    public static void afterUpdate(List<Leave_Application__c> newList, Map<Id, Leave_Application__c> oldMap) {

        if (newList == null || newList.isEmpty() || oldMap == null || oldMap.isEmpty()) {
            return;
        }

        Set<Id> qualifyingLeaveIds       = new Set<Id>();
        Map<Id, String> leaveIdToLeaveType = new Map<Id, String>();
        Map<Id, String> leaveIdToRemark    = new Map<Id, String>();

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

            if (String.isNotBlank(rec.Approver_Remarks__c)) {
                leaveIdToRemark.put(rec.Id, rec.Approver_Remarks__c);
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

        Map<Id, String> enrollmentIdToLeaveType = new Map<Id, String>();
        Map<Id, String> enrollmentIdToRemark    = new Map<Id, String>();

        for (Missed_Sessions__c ms : missedRows) {

            if (ms.Session_Enrollment__c == null || ms.Leave_Application__c == null) {
                continue;
            }

            String leaveType = leaveIdToLeaveType.get(ms.Leave_Application__c);

            if (String.isNotBlank(leaveType)) {
                enrollmentIdToLeaveType.put(ms.Session_Enrollment__c, leaveType);
            }

            String remark = leaveIdToRemark.get(ms.Leave_Application__c);

            if (String.isNotBlank(remark)) {
                enrollmentIdToRemark.put(ms.Session_Enrollment__c, remark);
            }
        }

        if (enrollmentIdToLeaveType.isEmpty() && enrollmentIdToRemark.isEmpty()) {
            return;
        }

        Set<Id> enrollmentIds = new Set<Id>();
        enrollmentIds.addAll(enrollmentIdToLeaveType.keySet());
        enrollmentIds.addAll(enrollmentIdToRemark.keySet());

        Map<Id, Session_Enrollment__c> existingEnrollments = new Map<Id, Session_Enrollment__c>([
            SELECT Id
            FROM Session_Enrollment__c
            WHERE Id IN :enrollmentIds
        ]);

        List<Session_Enrollment__c> toUpdate = new List<Session_Enrollment__c>();

        for (Id seId : existingEnrollments.keySet()) {

            String lt  = enrollmentIdToLeaveType.get(seId);
            String rmk = enrollmentIdToRemark.get(seId);

            if (String.isBlank(lt) && String.isBlank(rmk)) {
                continue;
            }

            Session_Enrollment__c se = new Session_Enrollment__c(Id = seId);

            if (String.isNotBlank(lt)) {
                se.Leave_Type__c = lt;
                se.Attendance__c = 'Sanctioned Leave';
            }

            if (String.isNotBlank(rmk)) {
                se.Remark__c = rmk;
            }

            toUpdate.add(se);
        }

        if (toUpdate.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.update(toUpdate, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'LeaveApplicationTriggerHandler.afterUpdate: Session_Enrollment__c update failed — Id=' +
                            toUpdate[i].Id + ', ' + err.getMessage()
                    );
                }
            }
        }
    }
}