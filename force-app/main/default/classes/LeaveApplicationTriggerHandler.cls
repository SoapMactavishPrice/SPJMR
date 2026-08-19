/**
 * @description Trigger handler for Leave_Application__c: seeds the first approval step on insert
 * and marks the leave's sessions as Sanctioned Leave once the leave is finally approved.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
// Justification: system-context trigger handler. Routing and attendance sync must run regardless of
// the submitting student's access to programme team setup or to other students' session enrollments.
public without sharing class LeaveApplicationTriggerHandler {

    private static final Set<String> FINAL_APPROVED_STATUSES = new Set<String>{
        'Approved',
        'Approved - Eligible for Makeup',
        'Approved - Not Eligible for Makeup'
    };

    private static final String ROLE_PROGRAMME_OFFICE = 'Programme Office';

    /**
     * @description Initializes a new leave request into the first approval step, resolving the
     * Programme Office approvers of the student's own programme rather than every Programme
     * Office user in the org.
     * @param newRecords Leave applications being inserted.
     */
    public static void beforeInsert(List<Leave_Application__c> newRecords) {

        // Programme is derived per record; index i of programIds matches index i of newRecords.
        List<Id> programIds = LeaveApproverResolver.resolveProgramIds(newRecords);

        Set<Id> distinctProgramIds = new Set<Id>();
        for (Id programId : programIds) {
            if (programId != null) {
                distinctProgramIds.add(programId);
            }
        }

        Map<Id, List<Id>> poByProgram =
            LeaveApproverResolver.getApproversByProgram(distinctProgramIds, ROLE_PROGRAMME_OFFICE);

        for (Integer i = 0; i < newRecords.size(); i++) {
            Leave_Application__c rec = newRecords[i];
            rec.Status__c            = 'Submitted - Pending Approval';
            rec.Current_Role_Name__c = ROLE_PROGRAMME_OFFICE;
            rec.Route_to_Deputy__c   = false;

            List<Id> poUserIds = poByProgram.get(programIds[i]);
            if (poUserIds != null && !poUserIds.isEmpty()) {
                rec.Current_Approver_User__c = poUserIds[0];
            }
        }
    }

    /**
     * @description No-op: submission is handled by LeaveSubmissionController.SubmitLeaveJob.
     * @param newRecords Leave applications that were inserted.
     */
    @SuppressWarnings('PMD.EmptyStatementBlock')
    public static void afterInsert(List<Leave_Application__c> newRecords) {
    }

    /**
     * @description Re-syncs missed sessions for leaves whose date window moved.
     * @param newList Leave applications after update.
     * @param oldMap Leave applications before update, by Id.
     */
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

    /**
     * @description On final approval, marks the leave's sessions Sanctioned Leave via Missed_Sessions__c.
     * @param newList Leave applications after update.
     * @param oldMap Leave applications before update, by Id.
     */
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