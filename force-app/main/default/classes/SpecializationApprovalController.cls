public with sharing class SpecializationApprovalController {

    public class ApprovalRecordWrapper {

        @AuraEnabled public Id workItemId;
        @AuraEnabled public Id recordId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String studentName;
        @AuraEnabled public String currentSpecialization;
        @AuraEnabled public String requestedSpecialization;
        @AuraEnabled public Datetime createdDate;

        public ApprovalRecordWrapper( ProcessInstanceWorkitem wi, Specialization_Change_Request__c scr){
            workItemId = wi.Id;
            recordId = scr.Id;
            requestName = scr.Name;
            studentName = scr.Student__r != null ? scr.Student__r.Name : '';
            currentSpecialization =
                scr.Current_Specialization__r != null
                ? scr.Current_Specialization__r.Name
                : '';

            requestedSpecialization =
                scr.New_Specialization__r != null
                ? scr.New_Specialization__r.Name
                : '';

            createdDate = wi.CreatedDate;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalRecordWrapper> getPendingApprovals() {

        List<ApprovalRecordWrapper> results =
            new List<ApprovalRecordWrapper>();

        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id,
                   CreatedDate,
                   ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ActorId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
        ];

        Set<Id> targetIds = new Set<Id>();

        for(ProcessInstanceWorkitem wi : workItems){
            targetIds.add(wi.ProcessInstance.TargetObjectId);
        }

        Map<Id, Specialization_Change_Request__c> requestMap =
            new Map<Id, Specialization_Change_Request__c>(
                [
                    SELECT Id,
                           Name,
                           Student__r.Name,
                           Current_Specialization__r.Name,
                           New_Specialization__r.Name
                    FROM Specialization_Change_Request__c
                    WHERE Id IN :targetIds
                ]
            );

        for(ProcessInstanceWorkitem wi : workItems){

            if(requestMap.containsKey(
                wi.ProcessInstance.TargetObjectId
            )){
                results.add(
                    new ApprovalRecordWrapper(
                        wi,
                        requestMap.get(
                            wi.ProcessInstance.TargetObjectId
                        )
                    )
                );
            }
        }

        return results;
    }

    @AuraEnabled
    public static void approveRequests(List<Id> workItemIds) {

        List<Approval.ProcessWorkitemRequest> requests =
            new List<Approval.ProcessWorkitemRequest>();

        for(Id wiId : workItemIds){

            Approval.ProcessWorkitemRequest req =
                new Approval.ProcessWorkitemRequest();

            req.setWorkitemId(wiId);
            req.setAction('Approve');
            req.setComments(
                'Approved via Bulk Approval Screen'
            );

            requests.add(req);
        }

        Approval.process(requests);
    }

    @AuraEnabled
    public static void rejectRequests(List<Id> workItemIds,String comments) {

        List<Approval.ProcessWorkitemRequest> requests =
            new List<Approval.ProcessWorkitemRequest>();

        for(Id wiId : workItemIds){

            Approval.ProcessWorkitemRequest req =
                new Approval.ProcessWorkitemRequest();

            req.setWorkitemId(wiId);
            req.setAction('Reject');
            req.setComments(comments);

            requests.add(req);
        }

        Approval.process(requests);
    }
}