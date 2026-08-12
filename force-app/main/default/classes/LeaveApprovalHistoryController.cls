// Approval history — each decision is a permanent separate row (Incomplete never overwritten).
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

    @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryRow> getApprovalHistory(Id leaveId) {

        List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();

        if (leaveId == null) {
            return rows;
        }

        Leave_Application__c leave = [
            SELECT Current_Role_Name__c, Status__c, Approver_Remarks__c, CreatedBy.Name
            FROM Leave_Application__c
            WHERE Id = :leaveId
            LIMIT 1
        ];

        List<Approval_History__c> history = [
            SELECT Step_Name__c, Date__c, Status__c, Assigned_To__c, Approved_By__c, Remark__c, CreatedDate
            FROM Approval_History__c
            WHERE Leave_Application__c = :leaveId
            ORDER BY Date__c ASC NULLS LAST, CreatedDate ASC
        ];

        if (!history.isEmpty()) {
            List<String> processRemarks = getProcessStepRemarks(leaveId);
            Integer decidedIndex = 0;

            Boolean leaveIsIncomplete =
                String.isNotBlank(leave.Status__c) &&
                leave.Status__c.equalsIgnoreCase('Incomplete');

            // Find last open row needing Incomplete label (legacy Pending not yet updated)
            Integer lastOpenPendingIndex = -1;
            if (leaveIsIncomplete && String.isNotBlank(leave.Current_Role_Name__c)) {
                String openStep = leave.Current_Role_Name__c + ' Verification';
                for (Integer i = history.size() - 1; i >= 0; i--) {
                    if (history[i].Step_Name__c == openStep &&
                        history[i].Status__c == 'Pending') {
                        lastOpenPendingIndex = i;
                        break;
                    }
                }
            }

            for (Integer i = 0; i < history.size(); i++) {
                Approval_History__c h = history[i];
                ApprovalHistoryRow row = new ApprovalHistoryRow();
                row.stepName   = h.Step_Name__c;
                row.stepDate   = h.Date__c != null ? h.Date__c : h.CreatedDate;
                row.status     = h.Status__c;
                // Never show auto names like User176… — use real names
                row.assignedTo = resolveAssignedToDisplay(h.Assigned_To__c, h.Step_Name__c);
                row.approvedBy = resolvePersonNameDisplay(h.Approved_By__c);
                // Prefer permanently stored per-step remark (works for Incomplete)
                row.remark     = String.isNotBlank(h.Remark__c) ? h.Remark__c : '';

                // Permanent Incomplete history rows — never merge away
                if (h.Status__c == 'Incomplete') {
                    // Fall back to leave-level remarks only when this is the open Incomplete and field empty
                    if (String.isBlank(row.remark) &&
                        leaveIsIncomplete &&
                        String.isNotBlank(leave.Approver_Remarks__c) &&
                        String.isNotBlank(leave.Current_Role_Name__c) &&
                        h.Step_Name__c == leave.Current_Role_Name__c + ' Verification') {
                        row.remark = leave.Approver_Remarks__c;
                    }
                } else if (i == lastOpenPendingIndex) {
                    // Legacy: leave Incomplete but history still Pending → show as Incomplete row
                    row.status = 'Incomplete';
                    if (String.isBlank(row.remark)) {
                        row.remark = leave.Approver_Remarks__c;
                    }
                } else if (String.isBlank(row.remark) &&
                    h.Status__c != null &&
                    h.Status__c != 'Submitted' &&
                    h.Status__c != 'Pending' &&
                    decidedIndex < processRemarks.size()) {
                    row.remark = processRemarks[decidedIndex];
                    decidedIndex++;
                } else if (h.Status__c != null &&
                    h.Status__c != 'Submitted' &&
                    h.Status__c != 'Pending' &&
                    decidedIndex < processRemarks.size()) {
                    // Consume process remarks index even when Remark__c already set
                    decidedIndex++;
                }

                rows.add(row);
            }

            // Leave is Incomplete and NO Incomplete/Pending open step in history — append Incomplete row
            if (leaveIsIncomplete &&
                String.isNotBlank(leave.Current_Role_Name__c) &&
                !hasOpenIncompleteOrPending(rows, leave.Current_Role_Name__c + ' Verification')) {
                ApprovalHistoryRow incompleteRow = new ApprovalHistoryRow();
                incompleteRow.stepName   = leave.Current_Role_Name__c + ' Verification';
                incompleteRow.status     = 'Incomplete';
                incompleteRow.stepDate   = System.now();
                incompleteRow.approvedBy = '';
                incompleteRow.remark     = leave.Approver_Remarks__c;
                incompleteRow.assignedTo = getAssignedNamesForStep(leave.Current_Role_Name__c + ' Verification');
                rows.add(incompleteRow);
            }

            return rows;
        }

        return buildFromProcessInstance(leaveId, leave);
    }

    private static Boolean hasOpenIncompleteOrPending(List<ApprovalHistoryRow> rows, String stepName) {
        for (ApprovalHistoryRow r : rows) {
            if (r.stepName == stepName &&
                (r.status == 'Incomplete' || r.status == 'Pending')) {
                return true;
            }
        }
        return false;
    }

    private static List<String> getProcessStepRemarks(Id leaveId) {
        List<String> remarks = new List<String>();
        for (ProcessInstanceStep step : [
            SELECT StepStatus, Comments
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId = :leaveId
            ORDER BY CreatedDate ASC
        ]) {
            if (step.StepStatus == 'Started' &&
                step.Comments != null &&
                step.Comments.contains('Auto submitted')) {
                continue;
            }
            if (step.StepStatus == 'Started') {
                continue;
            }
            remarks.add(step.Comments);
        }
        return remarks;
    }

    private static List<ApprovalHistoryRow> buildFromProcessInstance(
        Id leaveId,
        Leave_Application__c leave
    ) {
        List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();

        ApprovalHistoryRow submittedRow = new ApprovalHistoryRow();
        submittedRow.stepName   = 'Approval Request Submitted';
        submittedRow.status     = 'Submitted';
        submittedRow.approvedBy = '';
        submittedRow.remark     = '';
        submittedRow.assignedTo = leave.CreatedBy != null ? leave.CreatedBy.Name : '';
        rows.add(submittedRow);

        List<ProcessInstanceStep> steps = [
            SELECT Id, StepStatus, Comments, Actor.Name, CreatedDate, StepNodeId
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId = :leaveId
            ORDER BY CreatedDate ASC
        ];

        Set<Id> nodeIds = new Set<Id>();
        for (ProcessInstanceStep s : steps) {
            if (s.StepNodeId != null) {
                nodeIds.add(s.StepNodeId);
            }
        }

        Map<Id, ProcessNode> nodeMap = new Map<Id, ProcessNode>();
        if (!nodeIds.isEmpty()) {
            nodeMap = new Map<Id, ProcessNode>([
                SELECT Id, Name
                FROM ProcessNode
                WHERE Id IN :nodeIds
            ]);
        }

        for (ProcessInstanceStep step : steps) {
            if (step.StepStatus == 'Started' &&
                step.Comments != null &&
                step.Comments.contains('Auto submitted')) {
                continue;
            }

            ApprovalHistoryRow row = new ApprovalHistoryRow();
            row.stepName =
                nodeMap.containsKey(step.StepNodeId)
                    ? nodeMap.get(step.StepNodeId).Name
                    : '';

            String roleName = '';
            if (String.isNotBlank(row.stepName)) {
                if (row.stepName.contains('Programme Office')) {
                    roleName = 'Programme Office';
                } else if (row.stepName.contains('Manager')) {
                    roleName = 'Manager';
                } else if (row.stepName.contains('Deputy')) {
                    roleName = 'Deputy Chairperson';
                }
            }

            if (String.isNotBlank(roleName)) {
                List<Id> userIds = new List<Id>();
                for (Program_Team_Members__c ptm : [
                    SELECT User__c
                    FROM Program_Team_Members__c
                    WHERE Role__c = :roleName
                    AND User__c != null
                ]) {
                    userIds.add(ptm.User__c);
                }
                row.assignedTo = getUserNames(userIds);
            }

            row.stepDate   = step.CreatedDate;
            row.status     = step.StepStatus;
            row.approvedBy = step.Actor != null ? step.Actor.Name : '';
            row.remark     = step.Comments;
            rows.add(row);
        }

        if (String.isNotBlank(leave.Current_Role_Name__c)) {
            ApprovalHistoryRow openRow = new ApprovalHistoryRow();
            openRow.stepName   = leave.Current_Role_Name__c + ' Verification';
            openRow.approvedBy = '';
            openRow.remark     = '';

            Boolean isIncomplete =
                String.isNotBlank(leave.Status__c) &&
                leave.Status__c.equalsIgnoreCase('Incomplete');

            if (isIncomplete) {
                openRow.status = 'Incomplete';
                openRow.remark = leave.Approver_Remarks__c;
            } else {
                openRow.status = 'Pending';
            }

            List<Id> userIds = new List<Id>();
            for (Program_Team_Members__c ptm : [
                SELECT User__c
                FROM Program_Team_Members__c
                WHERE Role__c = :leave.Current_Role_Name__c
                AND User__c != null
            ]) {
                userIds.add(ptm.User__c);
            }
            openRow.assignedTo = getUserNames(userIds);
            rows.add(openRow);
        }

        return rows;
    }

    // =========================================================
    // WRITE — each Incomplete is a permanent separate history row
    // =========================================================

    public static void createSubmittedStep(Id leaveId, Id submittedById) {
        Approval_History__c rec = new Approval_History__c();
        rec.Leave_Application__c = leaveId;
        rec.Step_Name__c   = 'Approval Request Submitted';
        rec.Status__c      = 'Submitted';
        rec.Date__c        = System.now();
        rec.Assigned_To__c = getUserNames(new List<Id>{ submittedById });
        rec.Approved_By__c = '';
        insert rec;
    }

    public static void createPendingStep(Id leaveId, String stepName, List<Id> assignedToIds) {
        Approval_History__c rec = new Approval_History__c();
        rec.Leave_Application__c = leaveId;
        rec.Step_Name__c   = stepName;
        rec.Status__c      = 'Pending';
        rec.Date__c        = System.now();
        // Prefer team-member names by role (avoids User176… labels); fall back to Id lookup
        String roleNames = getAssignedNamesForStep(stepName);
        rec.Assigned_To__c = String.isNotBlank(roleNames)
            ? roleNames
            : getUserNames(assignedToIds);
        rec.Approved_By__c = '';
        insert rec;
    }

    /**
     * Always APPENDS a permanent Incomplete history row (never overwrites existing rows).
     * Deletes open Pending for that step so the same row cannot later be changed to Approved.
     * Previous Incomplete / Approved / Rejected rows for any step stay forever end-to-end.
     */
    public static void createIncompleteHistory(Id leaveId, String stepName, Id approverId) {
        createIncompleteHistory(leaveId, stepName, approverId, null);
    }

    public static void createIncompleteHistory(Id leaveId, String stepName, Id approverId, String remark) {
        String approverName = approverId != null
            ? getUserNames(new List<Id>{ approverId })
            : '';
        String assignedNames = getAssignedNamesForStep(stepName);

        // Close open Pending for this step (delete — do not convert Pending→Incomplete on same row)
        List<Approval_History__c> openPending = [
            SELECT Id, Assigned_To__c
            FROM Approval_History__c
            WHERE Leave_Application__c = :leaveId
            AND Step_Name__c = :stepName
            AND Status__c = 'Pending'
            ORDER BY CreatedDate DESC
        ];
        if (!openPending.isEmpty()) {
            if (String.isNotBlank(openPending[0].Assigned_To__c)) {
                assignedNames = openPending[0].Assigned_To__c;
            }
            delete openPending;
        }

        // Permanent Incomplete history entry — never updated later by Approve/Reject
        Approval_History__c incomplete = new Approval_History__c();
        incomplete.Leave_Application__c = leaveId;
        incomplete.Step_Name__c   = stepName;
        incomplete.Status__c      = 'Incomplete';
        incomplete.Date__c        = System.now();
        incomplete.Approved_By__c = approverName;
        incomplete.Assigned_To__c = assignedNames;
        incomplete.Remark__c      = remark;
        insert incomplete;
    }

    // Backward-compatible overload (no remark)
    public static void markStepDecided(Id leaveId, String stepName, String status, Id approverId) {
        markStepDecided(leaveId, stepName, status, approverId, null);
    }

    /**
     * Closes only the latest Pending step.
     * Never updates Incomplete / Approved / Rejected permanently wrong — Incomplete is append-only.
     */
    public static void markStepDecided(Id leaveId, String stepName, String status, Id approverId, String remark) {
        // Incomplete has its own append-only method (preserves remark on that row)
        if (String.isNotBlank(status) && status.equalsIgnoreCase('Incomplete')) {
            createIncompleteHistory(leaveId, stepName, approverId, remark);
            return;
        }

        // Only the open Pending may become Approved / Rejected / other — Incomplete is never touched
        List<Approval_History__c> recs = [
            SELECT Id, Status__c, Approved_By__c, Assigned_To__c, Date__c, Remark__c
            FROM Approval_History__c
            WHERE Leave_Application__c = :leaveId
            AND Step_Name__c = :stepName
            AND Status__c = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        String approverName = approverId != null
            ? getUserNames(new List<Id>{ approverId })
            : '';

        if (recs.isEmpty()) {
            // No open Pending — insert a new decided row (past Incomplete rows stay separate)
            Approval_History__c rec = new Approval_History__c();
            rec.Leave_Application__c = leaveId;
            rec.Step_Name__c   = stepName;
            rec.Status__c      = status;
            rec.Date__c        = System.now();
            rec.Approved_By__c = approverName;
            rec.Assigned_To__c = getAssignedNamesForStep(stepName);
            rec.Remark__c      = remark;
            insert rec;
            return;
        }

        Approval_History__c rec = recs[0];
        rec.Status__c = status;
        rec.Date__c   = System.now();
        if (String.isNotBlank(approverName)) {
            rec.Approved_By__c = approverName;
        }
        if (String.isNotBlank(remark)) {
            rec.Remark__c = remark;
        }
        update rec;
    }

    private static String getAssignedNamesForStep(String stepName) {
        if (String.isBlank(stepName)) {
            return '';
        }
        String roleName = '';
        if (stepName.contains('Programme Office')) {
            roleName = 'Programme Office';
        } else if (stepName.contains('Manager')) {
            roleName = 'Manager';
        } else if (stepName.contains('Deputy')) {
            roleName = 'Deputy Chairperson';
        }
        if (String.isBlank(roleName)) {
            return '';
        }
        List<Id> userIds = new List<Id>();
        for (Program_Team_Members__c ptm : [
            SELECT User__c
            FROM Program_Team_Members__c
            WHERE Role__c = :roleName
            AND User__c != null
        ]) {
            userIds.add(ptm.User__c);
        }
        return getUserNames(userIds);
    }

    /** Replace stored User176… labels with real names from the step's team role. */
    private static String resolveAssignedToDisplay(String stored, String stepName) {
        if (looksLikeGeneratedUserLabel(stored)) {
            String fromRole = getAssignedNamesForStep(stepName);
            if (String.isNotBlank(fromRole)) {
                return fromRole;
            }
        }
        if (String.isBlank(stored)) {
            String fromRole = getAssignedNamesForStep(stepName);
            if (String.isNotBlank(fromRole)) {
                return fromRole;
            }
        }
        return stored;
    }

    private static String resolvePersonNameDisplay(String stored) {
        if (looksLikeGeneratedUserLabel(stored)) {
            return '';
        }
        return stored;
    }

    /** True when text contains Experience Cloud-style names: User17624170508238202718 */
    private static Boolean looksLikeGeneratedUserLabel(String s) {
        if (String.isBlank(s)) {
            return false;
        }
        return Pattern.compile('(?i)\\bUser\\d{8,}').matcher(s).find();
    }

    private static String getUserNames(List<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return '';
        }
        List<String> names = new List<String>();
        for (User u : [
            SELECT Name, FirstName, LastName, Username
            FROM User
            WHERE Id IN :userIds
        ]) {
            names.add(formatUserDisplayName(u));
        }
        return String.join(names, ', ');
    }

    /** Prefer readable first+last; never use bare auto User#### labels when better data exists. */
    private static String formatUserDisplayName(User u) {
        if (u == null) {
            return '';
        }
        Boolean nameIsGenerated =
            String.isNotBlank(u.Name) &&
            Pattern.compile('(?i)^User\\d+$').matcher(u.Name).matches();

        if (String.isNotBlank(u.FirstName) && String.isNotBlank(u.LastName)) {
            String full = (u.FirstName + ' ' + u.LastName).trim();
            if (!looksLikeGeneratedUserLabel(full)) {
                return full;
            }
        }
        if (String.isNotBlank(u.Name) && !nameIsGenerated) {
            return u.Name;
        }
        if (String.isNotBlank(u.LastName) && !looksLikeGeneratedUserLabel(u.LastName)) {
            return u.LastName;
        }
        if (String.isNotBlank(u.Username)) {
            return u.Username.contains('@')
                ? u.Username.substringBefore('@')
                : u.Username;
        }
        return String.isNotBlank(u.Name) ? u.Name : '';
    }
}