public without sharing class LeaveApprovalHistoryController {

    // =========================================================
    // READ — used by LWC
    // =========================================================

    public class ApprovalHistoryRow {
        @AuraEnabled public String stepName;
        @AuraEnabled public Datetime stepDate;
        @AuraEnabled public String status;
        @AuraEnabled public String assignedTo;
        @AuraEnabled public String approvedBy;
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryRow> getApprovalHistory(Id leaveId) {

        List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();

        if (leaveId == null) {
            return rows;
        }

        for (Approval_History__c h : [
            SELECT Step_Name__c, Date__c, Status__c, Assigned_To__c, Approved_By__c
            FROM Approval_History__c
            WHERE Leave_Application__c = :leaveId
            ORDER BY Date__c DESC, CreatedDate DESC
        ]) {
            ApprovalHistoryRow row = new ApprovalHistoryRow();
            row.stepName   = h.Step_Name__c;
            row.stepDate   = h.Date__c;
            row.status     = h.Status__c;
            row.assignedTo = h.Assigned_To__c;
            row.approvedBy = h.Approved_By__c;
            rows.add(row);
        }

        return rows;
    }

    // =========================================================
    // WRITE — called from LeaveSubmissionController
    //         and LeaveApprovalActionController
    // =========================================================

    public static void createSubmittedStep(Id leaveId, Id submittedById){
        Approval_History__c rec = new Approval_History__c();
        rec.Leave_Application__c = leaveId;
        rec.Step_Name__c   = 'Approval Request Submitted';
        rec.Status__c      = 'Submitted';
        rec.Date__c        = System.now();
        rec.Assigned_To__c = getUserNames(new List<Id>{ submittedById });
        rec.Approved_By__c = '';
        insert rec;
    }

    public static void createPendingStep(Id leaveId, String stepName, List<Id> assignedToIds){
        Approval_History__c rec = new Approval_History__c();
        rec.Leave_Application__c = leaveId;
        rec.Step_Name__c   = stepName;
        rec.Status__c      = 'Pending';
        rec.Date__c        = System.now();
        rec.Assigned_To__c = getUserNames(assignedToIds);
        rec.Approved_By__c = '';
        insert rec;
    }

    public static void markStepDecided(Id leaveId, String stepName, String status, Id approverId){
        List<Approval_History__c> recs = [
            SELECT Id, Approved_By__c
            FROM Approval_History__c
            WHERE Leave_Application__c = :leaveId
            AND Step_Name__c = :stepName
            AND Status__c = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if(recs.isEmpty()) return;

        Approval_History__c rec = recs[0];
        rec.Status__c = status;
        rec.Date__c   = System.now();
        if(approverId != null){
            rec.Approved_By__c = getUserNames(new List<Id>{ approverId });
        }
        update rec;
    }

    private static String getUserNames(List<Id> userIds){
        if(userIds == null || userIds.isEmpty()) return '';
        List<String> names = new List<String>();
        for(User u : [SELECT Name FROM User WHERE Id IN :userIds]){
            names.add(u.Name);
        }
        return String.join(names, ', ');
    }
}