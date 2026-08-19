/**
 * @description Submits a newly created leave application into the approval process, assigning it
 * to the Programme Office approvers of the student's own programme.
 */
public with sharing class LeaveSubmissionController {

    /** Last swallowed approval-submit error, for test assertions and troubleshooting. */
    @TestVisible private static String lastSubmitError;

    private static final String ROLE_PROGRAMME_OFFICE = 'Programme Office';

    /**
     * @description Queueable that resolves the programme's Programme Office approvers and submits
     * the leave for approval. Runs async so the submitting transaction stays small.
     */
    public class SubmitLeaveJob implements Queueable {

        Id leaveId;

        /**
         * @description Creates the job for one leave application.
         * @param leaveId Leave application to submit.
         */
        public SubmitLeaveJob(Id leaveId){
            this.leaveId = leaveId;
        }

        /**
         * @description Resolves programme-scoped approvers, stamps them on the leave and submits
         * it for approval.
         * @param context Queueable context supplied by the platform.
         */
        public void execute(QueueableContext context){

            List<Leave_Application__c> leaves = [
                SELECT Id, Batch_Enrollment__c, Term_Enrollment__c
                FROM Leave_Application__c
                WHERE Id = :leaveId
                LIMIT 1
            ];

            if(leaves.isEmpty()){
                lastSubmitError = 'Leave application ' + leaveId + ' no longer exists.';
                return;
            }

            Leave_Application__c leaveRec = leaves[0];

            // Programme Office approvers for THIS student's programme only.
            Id programId = LeaveApproverResolver.resolveProgramId(leaveRec);
            List<Id> poUserIds = LeaveApproverResolver.getApprovers(programId, ROLE_PROGRAMME_OFFICE);

            if(poUserIds.isEmpty()){
                lastSubmitError = 'No Programme Office approver mapped for programme ' + programId;
                return;
            }

            List<String> poIdStrs = new List<String>();
            for(Id poUserId : poUserIds){
                poIdStrs.add(String.valueOf(poUserId));
            }

            leaveRec.Status__c                = 'Submitted - Pending Approval';
            leaveRec.Current_Role_Name__c     = ROLE_PROGRAMME_OFFICE;
            leaveRec.Current_Approver_User__c = poUserIds[0];
            leaveRec.Current_Approver_Ids__c  = String.join(poIdStrs, ';');
            update leaveRec;

            LeaveApprovalHistoryController.createSubmittedStep(leaveRec.Id, UserInfo.getUserId());
            LeaveApprovalHistoryController.createPendingStep(
                leaveRec.Id,
                'Programme Office Verification',
                poUserIds
            );

            // Approval step is "Manually Chosen"; all programme approvers get the work item.
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(leaveRec.Id);
            req.setComments('Auto submitted via Queueable');
            req.setNextApproverIds(poUserIds);

            try{
                Approval.process(req);
            } catch(Exception e){
                lastSubmitError = e.getMessage();
            }
        }
    }
}