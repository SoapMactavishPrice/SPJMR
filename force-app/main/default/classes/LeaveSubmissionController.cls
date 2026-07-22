public with sharing class LeaveSubmissionController {

    public class SubmitLeaveJob implements Queueable {

        Id leaveId;

        public SubmitLeaveJob(Id leaveId){
            this.leaveId = leaveId;
        }

        public void execute(QueueableContext context){

            // ✅ GET ALL Programme Office users
            List<Program_Team_Members__c> poList = [
                SELECT User__c
                FROM Program_Team_Members__c
                WHERE Role__c = 'Programme Office'
                AND User__c != null
            ];

            if(poList.isEmpty()){
                System.debug('Programme Office user not found');
                return;
            }

            // ✅ BUILD ID list + semicolon string for Is_Current_Approvar__c formula
            List<Id> poUserIds    = new List<Id>();
            List<String> poIdStrs = new List<String>();
            for(Program_Team_Members__c ptm : poList){
                poUserIds.add(ptm.User__c);
                poIdStrs.add(String.valueOf(ptm.User__c));
            }

            Leave_Application__c leaveRec = [
                SELECT Id
                FROM Leave_Application__c
                WHERE Id = :leaveId
            ];

            leaveRec.Status__c               = 'Submitted - Pending Approval';
            leaveRec.Current_Role_Name__c    = 'Programme Office';
            leaveRec.Current_Approver_User__c = poUserIds[0];
            leaveRec.Current_Approver_Ids__c = String.join(poIdStrs, ';'); // ✅ all PO IDs for button visibility
            update leaveRec;
            
            LeaveApprovalHistoryController.createSubmittedStep(leaveRec.Id, UserInfo.getUserId());
            LeaveApprovalHistoryController.createPendingStep(leaveRec.Id, 'Programme Office Verification', poUserIds);
            // ✅ SUBMIT ONCE — first user as the designated approver
            // Approval process step must be set to "Manually Chosen" 
            // and we pass ALL user IDs via setNextApproverIds
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(leaveRec.Id);
            req.setComments('Auto submitted via Queueable');
            req.setNextApproverIds(poUserIds);

            try{
                Approval.process(req);
            } catch(Exception e){
                System.debug('Approval Submit Error: ' + e.getMessage());
            }
        }
    }
}