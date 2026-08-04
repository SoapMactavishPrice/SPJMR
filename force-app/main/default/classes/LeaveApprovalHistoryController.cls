// Approval history with per-step remark support.
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
        @AuraEnabled public String remark;
    }

  /*  @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryRow> getApprovalHistory(Id leaveId) {

        List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();

        if (leaveId == null) {
            return rows;
        }

        for (Approval_History__c h : [
            SELECT Step_Name__c, Date__c, Status__c, Assigned_To__c, Approved_By__c, Remark__c
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
            row.remark     = h.Remark__c;
            rows.add(row);
        }

        return rows;
    }*/

   @AuraEnabled(cacheable=true)
public static List<ApprovalHistoryRow> getApprovalHistory(Id leaveId) {

    List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();

    if (leaveId == null) {
        return rows;
    }

    // Current leave
    Leave_Application__c leave = [
        SELECT Current_Role_Name__c
        FROM Leave_Application__c
        WHERE Id = :leaveId
        LIMIT 1
    ];

    // Submitted Row
    ApprovalHistoryRow submittedRow = new ApprovalHistoryRow();
    submittedRow.stepName = 'Approval Request Submitted';
    submittedRow.status = 'Submitted';
    submittedRow.approvedBy = '';
    submittedRow.remark = '';

    User createdBy = [
        SELECT Name
        FROM User
        WHERE Id IN (
            SELECT CreatedById
            FROM Leave_Application__c
            WHERE Id=:leaveId
        )
    ];

    submittedRow.assignedTo = createdBy.Name;

    rows.add(submittedRow);

    // Completed Approval Steps
    List<ProcessInstanceStep> steps = [
        SELECT Id,
               StepStatus,
               Comments,
               Actor.Name,
               CreatedDate,
               StepNodeId
        FROM ProcessInstanceStep
        WHERE ProcessInstance.TargetObjectId = :leaveId
        ORDER BY CreatedDate ASC
    ];

    Set<Id> nodeIds = new Set<Id>();

    for(ProcessInstanceStep s : steps){
        if(s.StepNodeId != null){
            nodeIds.add(s.StepNodeId);
        }
    }

    Map<Id,ProcessNode> nodeMap = new Map<Id,ProcessNode>();

    if(!nodeIds.isEmpty()){
        nodeMap = new Map<Id,ProcessNode>([
            SELECT Id,Name
            FROM ProcessNode
            WHERE Id IN :nodeIds
        ]);
    }

    for(ProcessInstanceStep step : steps){
        if(step.StepStatus == 'Started' &&
   step.Comments != null &&
   step.Comments.contains('Auto submitted')){
    continue;
}

        ApprovalHistoryRow row = new ApprovalHistoryRow();

        row.stepName =
            nodeMap.containsKey(step.StepNodeId)
            ? nodeMap.get(step.StepNodeId).Name
            : '';


        List<Id> userIds = new List<Id>();

String roleName = '';

if(row.stepName.contains('Programme Office')){
    roleName = 'Programme Office';
}
else if(row.stepName.contains('Manager')){
    roleName = 'Manager';
}
else if(row.stepName.contains('Deputy')){
    roleName = 'Deputy Chairperson';
}

if(roleName != ''){

    for(Program_Team_Members__c ptm : [
        SELECT User__c
        FROM Program_Team_Members__c
        WHERE Role__c = :roleName
        AND User__c != null
    ]){
        userIds.add(ptm.User__c);
    }

    row.assignedTo = getUserNames(userIds);
}    

       row.stepDate = step.CreatedDate;
row.status = step.StepStatus;
row.approvedBy = step.Actor != null ? step.Actor.Name : '';
row.remark = step.Comments;

// Don't overwrite assignedTo here

rows.add(row);
    }

    // Current Pending Step
    if(String.isNotBlank(leave.Current_Role_Name__c)){

        ApprovalHistoryRow pendingRow = new ApprovalHistoryRow();

        pendingRow.stepName = leave.Current_Role_Name__c + ' Verification';
        pendingRow.status = 'Pending';
        pendingRow.approvedBy = '';
        pendingRow.remark = '';

        List<Id> userIds = new List<Id>();

        for(Program_Team_Members__c ptm : [
            SELECT User__c
            FROM Program_Team_Members__c
            WHERE Role__c = :leave.Current_Role_Name__c
            AND User__c != null
        ]){
            userIds.add(ptm.User__c);
        }

        pendingRow.assignedTo = getUserNames(userIds);

        rows.add(pendingRow);
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

    // Backward-compatible overload (no remark)
    public static void markStepDecided(Id leaveId, String stepName, String status, Id approverId){
        markStepDecided(leaveId, stepName, status, approverId, null);
    }

    public static void markStepDecided(Id leaveId, String stepName, String status, Id approverId, String remark){
        List<Approval_History__c> recs = [
            SELECT Id,Status__c, Approved_By__c, Remark__c
            FROM Approval_History__c
            WHERE Leave_Application__c = :leaveId
            AND Step_Name__c = :stepName
            AND Status__c IN ('Pending', 'Incomplete')
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
        if(String.isNotBlank(remark)){
            rec.Remark__c = remark;
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