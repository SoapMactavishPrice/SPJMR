/**
 * LWC controller for the Withdrawal Request approve / reject quick actions.
 *
 * This flow now runs on the STANDARD Salesforce Approval Process
 * ('Withdrawal_Request_Approval_Process'):
 *
 *   - WithdrawalRequestTrigger -> WithdrawalApprovalService.submitForApproval
 *     submits every new 'Applied' request and stamps
 *     Current_Approver_User__c / Current_Approver_Ids__c / Current_Role__c
 *     ('Programme Office'). Step 1 of the process assigns to
 *     Current_Approver_User__c via a related-user field.
 *
 *   - processApproval() below finds the pending ProcessInstanceWorkitem and
 *     drives it with Approval.process (Approve / Reject), then mirrors the
 *     outcome onto Status__c and the audit fields and notifies the student.
 *
 *   - Escalation is optional. When the Programme Office approver checks the
 *     "send to Chairperson" box, we set Escalate_To_Chairperson__c = true and
 *     route the step-1 approval to the Deputy Chairperson team members; the
 *     process's conditional step 2 then runs. Unchecked, step 2 is skipped and
 *     the request is finalised after step 1.
 *
 * Chairperson approvers are Program_Team_Members__c with
 * Role__c = 'Deputy Chairperson' (same mapping the Deferment flow uses),
 * resolved via WithdrawalApprovalService.getProgrammeApprovers.
 */
public without sharing class WithdrawalApprovalController {

    private static final String ROLE_PROGRAMME_OFFICE = 'Programme Office';
    private static final String ROLE_CHAIRPERSON = 'Chairperson';
    private static final String CHAIRPERSON_TEAM_ROLE = 'Deputy Chairperson';

    private static final String STATUS_APPLIED = 'Applied';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String STATUS_RECALLED = 'Recalled';
    private static final String STATUS_CLEARANCE = 'Clearance & Exit';
    private static final String STATUS_FINAL_APPROVAL = 'Final Approval';
    private static final String STATUS_FINAL_REJECTION = 'Final Rejection';
    private static final String STATUS_WITHDRAWAL = 'Withdrawal';
    private static final String STATUS_PENDING_CHAIRPERSON = 'Accepted (PO Review)';

    // Prevents duplicate student emails in the same transaction when both
    // processApproval() and the after-update trigger would notify.
    private static Set<Id> studentNotifySentIds = new Set<Id>();
    // Prevents duplicate recalled-approver emails when recallRequest + trigger both fire.
    private static Set<Id> recalledApproverNotifySentIds = new Set<Id>();

    /** Which Approve / Reject buttons the logged-in user may see on the record page. */
    public class ApproverActionVisibility {
        @AuraEnabled public Boolean isApprover;
        @AuraEnabled public Boolean showApprove;
        @AuraEnabled public Boolean showReject;
        @AuraEnabled public Boolean showRecall;
        @AuraEnabled public Boolean showEscalateOption;
    }

    /**
     * Used by the record-page LWC before opening Approve / Reject / Recalled.
     * Must match button visibility (including Recalled for PO after escalate to Chairperson).
     */
    @AuraEnabled
    public static Boolean isCurrentUserApprover(Id recordId) {
        ApproverActionVisibility vis = getApproverActionVisibility(recordId);
        return vis.showApprove || vis.showReject || vis.showRecall;
    }

    @AuraEnabled(cacheable=true)
    public static ApproverActionVisibility getApproverActionVisibility(Id recordId) {
        ApproverActionVisibility vis = new ApproverActionVisibility();
        vis.isApprover = false;
        vis.showApprove = false;
        vis.showReject = false;
        vis.showRecall = false;
        vis.showEscalateOption = false;

        if (recordId == null) {
            return vis;
        }

        List<Withdrawal_Request__c> reqs = [
            SELECT Status__c, Current_Role__c, Current_Approver_Ids__c, Programme_Master__c
            FROM Withdrawal_Request__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (reqs.isEmpty()) {
            return vis;
        }

        Withdrawal_Request__c req = reqs[0];
        Boolean isApprover = isUserInApproverIds(req.Current_Approver_Ids__c, UserInfo.getUserId());
        // After PO escalates / final approve, Recalled must still show for Programme Office
        // + Chairperson without enabling Approve/Reject for those users incorrectly.
        Boolean canRecallAsPoOrChairTeam =
            (req.Status__c == STATUS_PENDING_CHAIRPERSON
                || req.Status__c == STATUS_APPROVED
                || req.Status__c == STATUS_CLEARANCE)
            && isUserInApproverIds(
                joinIds(collectRecallEligibleApproverIds(req.Programme_Master__c)),
                UserInfo.getUserId()
            );

        vis.isApprover = isApprover;
        if (!isApprover && !canRecallAsPoOrChairTeam) {
            return vis;
        }

        // Approve / Reject only while an approval step is actually pending.
        // Not on Clearance & Exit / Approved / etc. (those show Recalled only).
        if (isApprover
            && (req.Status__c == STATUS_APPLIED
                || req.Status__c == STATUS_PENDING_CHAIRPERSON)) {
            vis.showApprove = true;
            vis.showReject = true;
            vis.showEscalateOption = ROLE_PROGRAMME_OFFICE.equals(req.Current_Role__c);
        }

        // Recalled button only.
        if (req.Status__c == STATUS_APPLIED) {
            if (isApprover) {
                vis.showRecall = true;
            }
        } else if (canRecallAsPoOrChairTeam) {
            vis.showRecall = true;
        }

        return vis;
    }

    /**
     * Hook for status-field updates: Approved / Rejected / Clearance & Exit.
     * Does not change approval routing or steps.
     */
    public static void notifyStudentsOnStatusChange(
        List<Withdrawal_Request__c> newList,
        Map<Id, Withdrawal_Request__c> oldMap
    ) {
        if (newList == null || oldMap == null || newList.isEmpty()) {
            return;
        }
        for (Withdrawal_Request__c req : newList) {
            Withdrawal_Request__c oldReq = oldMap.get(req.Id);
            if (oldReq == null) {
                continue;
            }
            Boolean becameApproved =
                req.Status__c == STATUS_APPROVED && oldReq.Status__c != STATUS_APPROVED;
            Boolean becameRejected =
                req.Status__c == STATUS_REJECTED && oldReq.Status__c != STATUS_REJECTED;
            Boolean becameClearance =
                req.Status__c == STATUS_CLEARANCE && oldReq.Status__c != STATUS_CLEARANCE;
            Boolean becameRecalled =
                req.Status__c == STATUS_RECALLED && oldReq.Status__c != STATUS_RECALLED;
            Boolean becameFinalApproval =
                req.Status__c == STATUS_FINAL_APPROVAL && oldReq.Status__c != STATUS_FINAL_APPROVAL;
            Boolean becameFinalRejection =
                req.Status__c == STATUS_FINAL_REJECTION && oldReq.Status__c != STATUS_FINAL_REJECTION;
            Boolean becameWithdrawal =
                req.Status__c == STATUS_WITHDRAWAL && oldReq.Status__c != STATUS_WITHDRAWAL;

            if (becameClearance) {
                notifyStudentClearanceChecklist(req);
                notifyClearanceApprovers(req);
                continue;
            }
            if (becameRecalled) {
                // Approver Ids are usually cleared on recall - use pre-update values.
                String approverIdsRaw = String.isNotBlank(req.Current_Approver_Ids__c)
                    ? req.Current_Approver_Ids__c
                    : oldReq.Current_Approver_Ids__c;
                notifyRecalledApprovers(req, approverIdsRaw);
                continue;
            }
            if (becameFinalApproval) {
                notifyStudentFinalApproval(req);
                continue;
            }
            if (becameFinalRejection) {
                notifyStudentFinalRejection(req);
                continue;
            }
            if (becameWithdrawal) {
                notifyStudentWithdrawalCompleted(req);
                continue;
            }
            if (!becameApproved && !becameRejected) {
                continue;
            }
            String headline = becameApproved
                ? 'Your withdrawal request has been approved.'
                : 'Your withdrawal request has been rejected.';
            notifyStudent(req, req.Remarks__c, headline);
        }
    }

    @AuraEnabled
    public static void processApproval(Id recordId, String action, String comments, Boolean escalateToChairperson) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('Withdrawal Request Id is required.');
            }
            if (action != 'APPROVE' && action != 'REJECT' && action != 'RECALL') {
                throw new AuraHandledException('Invalid approval action.');
            }
            if (String.isBlank(comments)) {
                throw new AuraHandledException('Comments are required before you can proceed.');
            }

            List<Withdrawal_Request__c> requestList = [
                SELECT Id, Name, Programme_Master__c, Programme_Master__r.Name, Status__c,
                       Current_Role__c, Current_Approver_User__c, Current_Approver_Ids__c,
                       Escalate_To_Chairperson__c,
                       Student__c, Student__r.Name,
                       Application_ID__c, Roll_Number__c, Reason_for_Withdrawal__c
                FROM Withdrawal_Request__c
                WHERE Id = :recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (requestList.isEmpty()) {
                throw new AuraHandledException('Withdrawal Request not found.');
            }
            Withdrawal_Request__c req = requestList[0];

            Boolean canActAsApprover = isCurrentUserAnApprover(req.Current_Approver_Ids__c);
            // After escalate, Current_Approver_Ids__c is Chairperson-only; PO may still recall.
            Boolean canRecallAsPoOrChairTeam =
                action == 'RECALL'
                && (req.Status__c == STATUS_PENDING_CHAIRPERSON
                    || req.Status__c == STATUS_APPROVED
                    || req.Status__c == STATUS_CLEARANCE)
                && isUserInApproverIds(
                    joinIds(collectRecallEligibleApproverIds(req.Programme_Master__c)),
                    UserInfo.getUserId()
                );

            if (!canActAsApprover && !canRecallAsPoOrChairTeam) {
                throw new AuraHandledException('You are not an authorized approver for this request.');
            }

            if (action == 'RECALL') {
                // Approved / Clearance may have no pending work item; Accepted (PO Review) still does.
                Id workItemId = (req.Status__c == STATUS_APPROVED
                        || req.Status__c == STATUS_CLEARANCE)
                    ? findPendingWorkItemIdIfAny(recordId)
                    : findPendingWorkItemId(recordId);
                recallRequest(req, workItemId, comments);
                return;
            }

            if (!canActAsApprover) {
                throw new AuraHandledException('You are not an authorized approver for this request.');
            }

            Id workItemId = findPendingWorkItemId(recordId);

            if (action == 'REJECT') {
                rejectRequest(req, workItemId, comments);
                return;
            }

            // APPROVE
            if (req.Current_Role__c == ROLE_PROGRAMME_OFFICE) {
                approveAsProgrammeOffice(req, workItemId, comments, escalateToChairperson == true);
                return;
            }
            if (req.Current_Role__c == ROLE_CHAIRPERSON) {
                approveAsChairperson(req, workItemId, comments);
                return;
            }

            throw new AuraHandledException('This request is not currently awaiting your approval.');

        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'WITHDRAWAL APPROVAL ERROR: '
                + ex.getTypeName() + ' | ' + ex.getMessage()
                + ' | line=' + ex.getLineNumber() + ' | stack=' + ex.getStackTraceString());
            throw new AuraHandledException('Approval error: ' + ex.getMessage());
        }
    }

    // =================================================================
    // READ - custom Approval History for the record page LWC
    // (styled like the Leave / Deferment approval-history components,
    //  built from the standard ProcessInstanceStep / -Workitem records)
    // =================================================================

    public class ApprovalHistoryRow {
        @AuraEnabled public String stepId;
        @AuraEnabled public String stepName;
        @AuraEnabled public Datetime actionDate;
        @AuraEnabled public String status;
        @AuraEnabled public String assignedTo;
        @AuraEnabled public String approvedBy;
        @AuraEnabled public String remarks;
    }

    @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryRow> getApprovalHistory(Id recordId) {
        List<ApprovalHistoryRow> rows = new List<ApprovalHistoryRow>();
        if (recordId == null) {
            return rows;
        }

        List<Withdrawal_Request__c> reqs = [
            SELECT Id, CreatedDate, CreatedBy.Name, Status__c, Current_Role__c,
                   Programme_Master__c, Student__c, Student__r.Name,
                   Remarks__c, Approved_By__r.Name, Approval_Date__c
            FROM Withdrawal_Request__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (reqs.isEmpty()) {
            return rows;
        }
        Withdrawal_Request__c req = reqs[0];

        String poNames = approverNames(req.Programme_Master__c, ROLE_PROGRAMME_OFFICE);
        String chairNames = approverNames(req.Programme_Master__c, CHAIRPERSON_TEAM_ROLE);
        String studentName = (req.Student__r != null && String.isNotBlank(req.Student__r.Name))
            ? req.Student__r.Name
            : (req.CreatedBy != null ? req.CreatedBy.Name : 'Student');

        // 1. Submitted
        ApprovalHistoryRow submitted = new ApprovalHistoryRow();
        submitted.stepId = 'SUBMITTED_' + recordId;
        submitted.stepName = 'Approval Request Submitted';
        submitted.status = 'Submitted';
        submitted.assignedTo = studentName;
        submitted.approvedBy = '';
        submitted.remarks = '-';
        submitted.actionDate = req.CreatedDate;
        rows.add(submitted);

        // 2. Completed steps
        List<ProcessInstanceStep> steps = [
            SELECT Id, StepStatus, Comments, Actor.Name, CreatedDate, StepNodeId
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId = :recordId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];
        Set<Id> nodeIds = new Set<Id>();
        for (ProcessInstanceStep s : steps) {
            if (s.StepNodeId != null) {
                nodeIds.add(s.StepNodeId);
            }
        }
        Map<Id, ProcessNode> nodeMap = nodeIds.isEmpty()
            ? new Map<Id, ProcessNode>()
            : new Map<Id, ProcessNode>([SELECT Id, Name FROM ProcessNode WHERE Id IN :nodeIds]);

        for (ProcessInstanceStep step : steps) {
            if (step.StepStatus == 'Started' || step.StepStatus == 'Submitted') {
                continue;
            }
            ApprovalHistoryRow row = new ApprovalHistoryRow();
            row.stepId = String.valueOf(step.Id);
            row.stepName = nodeMap.containsKey(step.StepNodeId)
                ? nodeMap.get(step.StepNodeId).Name
                : 'Approval Step';
            row.actionDate = step.CreatedDate;
            row.status = step.StepStatus;
            row.approvedBy = step.Actor != null ? step.Actor.Name : '';
            row.remarks = String.isBlank(step.Comments) ? '-' : step.Comments;
            row.assignedTo = assignedNamesForStep(row.stepName, poNames, chairNames);
            rows.add(row);
        }

        // 3. Current pending step (open work item)
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id, CreatedDate
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            AND ProcessInstance.Status = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];
        if (!workItems.isEmpty()) {
            ProcessInstanceWorkitem wi = workItems[workItems.size() - 1];
            String stepName = (req.Current_Role__c == ROLE_CHAIRPERSON)
                ? 'Chairperson Approval'
                : 'Programme Office Verification';
            ApprovalHistoryRow pending = new ApprovalHistoryRow();
            pending.stepId = 'PENDING_' + wi.Id;
            pending.stepName = stepName;
            pending.status = 'Pending';
            pending.approvedBy = '';
            pending.remarks = '-';
            pending.actionDate = wi.CreatedDate;
            pending.assignedTo = assignedNamesForStep(stepName, poNames, chairNames);
            rows.add(pending);
        }

        if (req.Status__c == STATUS_RECALLED) {
            applyRecalledHistoryDisplay(rows, req);
        }

        return rows;
    }

    /**
     * Recall display only — does not change Approve / Reject history rows.
     * Mid-flow recall: Approval.process records Reject → remap that row to Recalled.
     * After final approve: no pending work item / no Reject step → append a Recalled row.
     */
    private static void applyRecalledHistoryDisplay(
        List<ApprovalHistoryRow> rows,
        Withdrawal_Request__c req
    ) {
        String recalledBy = (req.Approved_By__r != null && String.isNotBlank(req.Approved_By__r.Name))
            ? req.Approved_By__r.Name
            : '';
        String remarks = String.isBlank(req.Remarks__c) ? '-' : req.Remarks__c;
        Datetime actionDate = req.Approval_Date__c != null ? req.Approval_Date__c : Datetime.now();

        for (Integer i = rows.size() - 1; i >= 0; i--) {
            ApprovalHistoryRow row = rows[i];
            if (row.status != 'Rejected') {
                continue;
            }
            // Engine used Reject to close the pending step — show as Recalled.
            row.status = STATUS_RECALLED;
            row.remarks = remarks;
            if (String.isNotBlank(recalledBy)) {
                row.approvedBy = recalledBy;
            }
            row.actionDate = actionDate;
            return;
        }

        // Already-approved / clearance recall: keep Approved rows; add Recalled entry.
        ApprovalHistoryRow recalled = new ApprovalHistoryRow();
        recalled.stepId = 'RECALLED_' + String.valueOf(req.Id);
        recalled.stepName = 'Request Recalled';
        recalled.status = STATUS_RECALLED;
        recalled.assignedTo = recalledBy;
        recalled.approvedBy = recalledBy;
        recalled.remarks = remarks;
        recalled.actionDate = actionDate;
        rows.add(recalled);
    }

    private static String approverNames(Id programmeId, String role) {
        List<Id> ids = WithdrawalApprovalService.getProgrammeApprovers(programmeId, role);
        if (ids.isEmpty()) {
            return '';
        }
        List<String> names = new List<String>();
        for (User u : [SELECT Name FROM User WHERE Id IN :ids WITH SYSTEM_MODE]) {
            names.add(u.Name);
        }
        return String.join(names, ', ');
    }

    private static String assignedNamesForStep(String stepName, String poNames, String chairNames) {
        if (String.isBlank(stepName)) {
            return '';
        }
        if (stepName.containsIgnoreCase('Chairperson')) {
            return String.isBlank(chairNames) ? 'Chairperson' : chairNames;
        }
        if (stepName.containsIgnoreCase('Programme Office')) {
            return String.isBlank(poNames) ? 'Programme Office' : poNames;
        }
        return '';
    }

    private static Boolean isCurrentUserAnApprover(String currentApproverIds) {
        return isUserInApproverIds(currentApproverIds, UserInfo.getUserId());
    }

    @TestVisible
    private static Boolean isUserInApproverIds(String approverIds, Id userId) {
        if (String.isBlank(approverIds) || userId == null) {
            return false;
        }
        String userIdStr = String.valueOf(userId);
        String userId15 = userIdStr.length() >= 15 ? userIdStr.substring(0, 15) : userIdStr;
        String normalized = approverIds.replace('\n', ';').replace(',', ';');
        for (String token : normalized.split(';')) {
            if (String.isBlank(token)) {
                continue;
            }
            String idToken = token.trim();
            if (idToken.equals(userIdStr) || idToken.equals(userId15)) {
                return true;
            }
            if (idToken.startsWith(userId15) || userIdStr.startsWith(idToken)) {
                return true;
            }
        }
        return false;
    }

    /**
     * The pending approval work item for this record. Prefers the row assigned
     * to the running user; falls back to the newest pending row. Throws when
     * there is none (request already approved/rejected/recalled, or never
     * submitted).
     */
    private static Id findPendingWorkItemId(Id recordId) {
        Id workItemId = findPendingWorkItemIdIfAny(recordId);
        if (workItemId == null) {
            throw new AuraHandledException(
                'No pending approval step was found for this request - it may already be closed.'
            );
        }
        return workItemId;
    }

    /** Same lookup as findPendingWorkItemId but returns null when none pending. */
    private static Id findPendingWorkItemIdIfAny(Id recordId) {
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            AND ProcessInstance.Status = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        if (workItems.isEmpty()) {
            return null;
        }
        Id currentUserId = UserInfo.getUserId();
        for (ProcessInstanceWorkitem wi : workItems) {
            if (wi.ActorId == currentUserId) {
                return wi.Id;
            }
        }
        return workItems[0].Id;
    }

    private static void rejectRequest(Withdrawal_Request__c req, Id workItemId, String comments) {
        submitDecision(workItemId, 'Reject', comments, null);

        req.Status__c = STATUS_REJECTED;
        req.Remarks__c = comments;
        req.Approved_By__c = UserInfo.getUserId();
        req.Approval_Date__c = Datetime.now();
        req.Current_Role__c = null;
        req.Current_Approver_User__c = null;
        req.Current_Approver_Ids__c = null;
        req.Escalate_To_Chairperson__c = false;

        update as system req;

        notifyStudent(req, comments, 'Your withdrawal request has been rejected.');
    }

    private static void recallRequest(Withdrawal_Request__c req, Id workItemId, String comments) {
        if (workItemId != null) {
            submitDecision(workItemId, 'Reject', comments, null);
        }

        // Capture before clear - after-update trigger also uses oldMap; this is a backup path.
        String approverIdsBeforeClear = req.Current_Approver_Ids__c;

        req.Status__c = STATUS_RECALLED;
        req.Remarks__c = comments;
        req.Approved_By__c = UserInfo.getUserId();
        req.Approval_Date__c = Datetime.now();
        req.Current_Role__c = null;
        req.Current_Approver_User__c = null;
        req.Current_Approver_Ids__c = null;
        req.Escalate_To_Chairperson__c = false;

        try {
            update as system req;
        } catch (DmlException dex) {
            if (dex.getDmlType(0) == StatusCode.ENTITY_IS_LOCKED) {
                Approval.unlock(new List<Id>{ req.Id });
                update as system req;
            } else {
                throw dex;
            }
        }

        notifyStudentRecalled(req);
        notifyRecalledApprovers(req, approverIdsBeforeClear);
    }

    private static void approveAsProgrammeOffice(
        Withdrawal_Request__c req, Id workItemId, String comments, Boolean escalate
    ) {
        if (escalate) {
            List<Id> chairpersonIds =
                WithdrawalApprovalService.getProgrammeApprovers(req.Programme_Master__c, CHAIRPERSON_TEAM_ROLE);
            if (chairpersonIds.isEmpty()) {
                throw new AuraHandledException(
                    'No Chairperson is configured for this Programme, so this request cannot be routed '
                    + 'for second-level approval. Please add a Deputy Chairperson to the Programme Team, '
                    + 'or finalize this request directly instead.'
                );
            }

            // Stamp routing BEFORE Approval.process: step 2 assigns via the
            // Current_Approver_User__c related-user field and its entry criteria
            // reads Escalate_To_Chairperson__c.
            req.Escalate_To_Chairperson__c = true;
            req.Current_Role__c = ROLE_CHAIRPERSON;
            req.Current_Approver_User__c = chairpersonIds[0];
            req.Current_Approver_Ids__c = joinIds(chairpersonIds);
            req.Status__c = STATUS_PENDING_CHAIRPERSON;
            req.Remarks__c = comments;
            update as system req;

            submitDecision(workItemId, 'Approve', comments, chairpersonIds);

            notifyStudent(req, comments,
                'Your withdrawal request has been reviewed and sent to the Chairperson for final approval.');
        } else {
            // Ensure the conditional Chairperson step is skipped.
            req.Escalate_To_Chairperson__c = false;
            update as system req;

            submitDecision(workItemId, 'Approve', comments, null);
            finalizeApproved(req, comments);
        }
    }

    private static void approveAsChairperson(Withdrawal_Request__c req, Id workItemId, String comments) {
        submitDecision(workItemId, 'Approve', comments, null);
        finalizeApproved(req, comments);
    }

    private static void finalizeApproved(Withdrawal_Request__c req, String comments) {
        req.Status__c = STATUS_APPROVED;
        req.Remarks__c = comments;
        req.Approved_By__c = UserInfo.getUserId();
        req.Approval_Date__c = Datetime.now();
        // Clear role / single-user pointer so Approve/Reject routing stays inactive.
        req.Current_Role__c = null;
        req.Current_Approver_User__c = null;
        // Recalled must be available to BOTH Programme Office and Chairperson
        // after escalate+approve (otherwise only chairperson Ids remain).
        req.Current_Approver_Ids__c = joinIds(
            collectRecallEligibleApproverIds(req.Programme_Master__c)
        );

        // finalApprovalRecordLock on the process locks the record the moment the
        // last step is approved; this terminal status write has to get past it.
        try {
            update as system req;
        } catch (DmlException dex) {
            if (dex.getDmlType(0) == StatusCode.ENTITY_IS_LOCKED) {
                Approval.unlock(new List<Id>{ req.Id });
                update as system req;
            } else {
                throw dex;
            }
        }

        notifyStudent(req, comments, 'Your withdrawal request has been approved.');
    }

    /**
     * Users who may see Recalled after Status = Approved: Programme Office +
     * Deputy Chairperson team members for the request's Programme.
     */
    private static List<Id> collectRecallEligibleApproverIds(Id programmeId) {
        Set<Id> eligible = new Set<Id>();
        eligible.addAll(
            WithdrawalApprovalService.getProgrammeApprovers(programmeId, ROLE_PROGRAMME_OFFICE)
        );
        eligible.addAll(
            WithdrawalApprovalService.getProgrammeApprovers(programmeId, CHAIRPERSON_TEAM_ROLE)
        );
        return new List<Id>(eligible);
    }

    /**
     * Drives one approval work item through the standard engine.
     */
    private static void submitDecision(Id workItemId, String engineAction, String comments, List<Id> nextApproverIds) {
        Approval.ProcessWorkitemRequest pwr = new Approval.ProcessWorkitemRequest();
        pwr.setWorkitemId(workItemId);
        pwr.setAction(engineAction);
        if (!String.isBlank(comments)) {
            pwr.setComments(comments);
        }
        if (nextApproverIds != null && !nextApproverIds.isEmpty()) {
            pwr.setNextApproverIds(nextApproverIds);
        }

        Approval.ProcessResult result = Approval.process(pwr);
        if (!result.isSuccess()) {
            String msg = (result.getErrors() != null && !result.getErrors().isEmpty())
                ? result.getErrors()[0].getMessage()
                : 'unknown error';
            throw new AuraHandledException('The approval engine rejected this ' + engineAction.toLowerCase() + ': ' + msg);
        }
    }

    private static String joinIds(List<Id> ids) {
        List<String> strs = new List<String>();
        for (Id i : ids) {
            strs.add(String.valueOf(i));
        }
        return String.join(strs, ',');
    }

    /**
     * Emails users listed in Current_Approver_Ids__c when Status becomes Recalled.
     * Never sent to the student - only those User Ids. Ids must be passed in because
     * recall clears Current_Approver_Ids__c on the record.
     */
    private static void notifyRecalledApprovers(Withdrawal_Request__c req, String approverIdsRaw) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyRecalledApprovers @ '
                + String.valueOf(Datetime.now()) + ' ---');

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP (recalled approvers): request is null.');
                return;
            }
            if (recalledApproverNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP (recalled approvers): already notified in this transaction.');
                return;
            }
            recalledApproverNotifySentIds.add(req.Id);

            List<Withdrawal_Request__c> detailed = [
                SELECT Id, Name, Status__c, Student__c, Student__r.Name,
                       Roll_Number__c, Programme_Master__r.Name
                FROM Withdrawal_Request__c
                WHERE Id = :req.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (detailed.isEmpty()) {
                diagnosticLines.add('STOP (recalled approvers): could not re-query request.');
                return;
            }
            Withdrawal_Request__c detail = detailed[0];

            Set<Id> approverUserIds = parseApproverUserIds(approverIdsRaw);
            diagnosticLines.add('Approver Ids raw=[' + approverIdsRaw
                + '] parsed count=' + approverUserIds.size());

            if (approverUserIds.isEmpty()) {
                diagnosticLines.add('STOP (recalled approvers): no User Ids to notify.');
                return;
            }

            String studentName = (detail.Student__r != null) ? detail.Student__r.Name : '';
            String programmeName = (detail.Programme_Master__r != null)
                ? detail.Programme_Master__r.Name
                : '';
            String rollNumber = detail.Roll_Number__c;
            String referenceNumber = detail.Name;

            Map<Id, User> usersMap = new Map<Id, User>([
                SELECT Id, Name, Email, IsActive, ContactId, Contact.AccountId
                FROM User
                WHERE Id IN :approverUserIds
                AND IsActive = true
                WITH SYSTEM_MODE
            ]);

            Id orgWideEmailAddressId = null;
            List<OrgWideEmailAddress> owaList = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = 'SPJIMR Withdrawal'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!owaList.isEmpty()) {
                orgWideEmailAddressId = owaList[0].Id;
            } else {
                diagnosticLines.add('WARN (recalled approvers): OrgWideEmailAddress '
                    + '\'SPJIMR Withdrawal\' not found - using default sender.');
            }

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Id userId : approverUserIds) {
                User recipient = usersMap.get(userId);
                if (recipient == null) {
                    diagnosticLines.add('SKIP: User ' + userId + ' not found or inactive.');
                    continue;
                }
                if (detail.Student__c != null
                    && recipient.ContactId != null
                    && recipient.Contact != null
                    && recipient.Contact.AccountId == detail.Student__c) {
                    diagnosticLines.add('SKIP: User ' + userId
                        + ' is the student portal user - recalled approver email not sent.');
                    continue;
                }
                if (String.isBlank(recipient.Email)) {
                    diagnosticLines.add('SKIP: User ' + userId + ' has blank Email.');
                    continue;
                }

                String subject =
                    'Withdrawal Request Recalled – Further Processing Stopped ('
                    + programmeName + ') (' + studentName + ')';

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(recipient.Id);
                email.setSaveAsActivity(false);
                if (orgWideEmailAddressId != null) {
                    email.setOrgWideEmailAddressId(orgWideEmailAddressId);
                }
                email.setSubject(subject);
                email.setPlainTextBody(
                    'Dear Team,\n\n'
                    + 'The withdrawal request for the following student has been recalled. '
                    + 'Accordingly, further processing of the withdrawal request and related '
                    + 'clearance activities should be stopped.\n\n'
                    + 'Student Name: ' + studentName + '\n'
                    + 'Student ID: ' + (String.isBlank(rollNumber) ? '-' : rollNumber) + '\n'
                    + 'Programme: ' + programmeName + '\n'
                    + 'Withdrawal Request Reference Number: ' + referenceNumber + '\n'
                    + 'Request Status: Recalled\n\n'
                    + 'Please discontinue any pending withdrawal-related activities and update '
                    + 'the relevant records/status in the system, as applicable.\n\n'
                    + 'The student\'s status has been restored.\n\n'
                    + 'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                    + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                    + '<div style="padding:20px;">'
                    + '<p style="font-weight:bold;">Dear Team,</p>'
                    + '<p>The withdrawal request for the following student has been recalled. '
                    + 'Accordingly, further processing of the withdrawal request and related '
                    + 'clearance activities should be stopped.</p>'
                    + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                    + buildEmailRow('Student Name', studentName)
                    + buildEmailRow('Student ID', rollNumber)
                    + buildEmailRow('Programme', programmeName)
                    + buildEmailRow('Withdrawal Request Reference Number', referenceNumber)
                    + buildEmailRow('Request Status', 'Recalled')
                    + '</table>'
                    + '<p style="margin-top:16px;">Please discontinue any pending withdrawal-related activities '
                    + 'and update the relevant records/status in the system, as applicable.</p>'
                    + '<p>The student\'s status has been restored.</p>'
                    + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                    + '</div></div>'
                );
                emails.add(email);
            }

            if (emails.isEmpty()) {
                diagnosticLines.add('STOP (recalled approvers): no eligible recipient emails prepared.');
                return;
            }

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
            Integer sent = 0;
            for (Messaging.SendEmailResult r : results) {
                if (r.isSuccess()) {
                    sent++;
                } else {
                    for (Messaging.SendEmailError err : r.getErrors()) {
                        diagnosticLines.add('Recalled approver email FAILED: '
                            + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
            diagnosticLines.add('Recalled approver emails sent: ' + sent + ' of ' + emails.size() + '.');

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR,
                'WithdrawalApprovalController.notifyRecalledApprovers failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Emails users listed in Current_Approver_Ids__c when Status becomes
     * Clearance & Exit. Never sent to the student - only those User Ids.
     */
    private static void notifyClearanceApprovers(Withdrawal_Request__c req) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyClearanceApprovers @ '
                + String.valueOf(Datetime.now()) + ' ---');

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP (clearance approvers): request is null.');
                return;
            }

            List<Withdrawal_Request__c> detailed = [
                SELECT Id, Name, Status__c, Student__c, Student__r.Name,
                       Roll_Number__c, Programme_Master__r.Name, Current_Approver_Ids__c
                FROM Withdrawal_Request__c
                WHERE Id = :req.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (detailed.isEmpty()) {
                diagnosticLines.add('STOP (clearance approvers): could not re-query request.');
                return;
            }
            Withdrawal_Request__c detail = detailed[0];

            // Prefer Ids from the triggering update (may be stamped in same save).
            String approverIdsRaw = String.isNotBlank(req.Current_Approver_Ids__c)
                ? req.Current_Approver_Ids__c
                : detail.Current_Approver_Ids__c;
            Set<Id> approverUserIds = parseApproverUserIds(approverIdsRaw);
            diagnosticLines.add('Current_Approver_Ids__c raw=[' + approverIdsRaw
                + '] parsed count=' + approverUserIds.size());

            if (approverUserIds.isEmpty()) {
                diagnosticLines.add('STOP (clearance approvers): no User Ids in Current_Approver_Ids__c.');
                return;
            }

            String studentName = (detail.Student__r != null) ? detail.Student__r.Name : '';
            String programmeName = (detail.Programme_Master__r != null)
                ? detail.Programme_Master__r.Name
                : '';
            String rollNumber = detail.Roll_Number__c;
            String referenceNumber = detail.Name;

            Map<Id, User> usersMap = new Map<Id, User>([
                SELECT Id, Name, Email, IsActive, ContactId, Contact.AccountId, UserType
                FROM User
                WHERE Id IN :approverUserIds
                AND IsActive = true
                WITH SYSTEM_MODE
            ]);

            Id orgWideEmailAddressId = null;
            List<OrgWideEmailAddress> owaList = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE DisplayName = 'SPJIMR Withdrawal'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!owaList.isEmpty()) {
                orgWideEmailAddressId = owaList[0].Id;
            } else {
                diagnosticLines.add('WARN (clearance approvers): OrgWideEmailAddress '
                    + '\'SPJIMR Withdrawal\' not found - using default sender.');
            }

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (Id userId : approverUserIds) {
                User recipient = usersMap.get(userId);
                if (recipient == null) {
                    diagnosticLines.add('SKIP: User ' + userId + ' not found or inactive.');
                    continue;
                }
                // Never send this departmental clearance email to the student portal user.
                if (detail.Student__c != null
                    && recipient.ContactId != null
                    && recipient.Contact != null
                    && recipient.Contact.AccountId == detail.Student__c) {
                    diagnosticLines.add('SKIP: User ' + userId
                        + ' is the student portal user - clearance approver email not sent.');
                    continue;
                }
                if (String.isBlank(recipient.Email)) {
                    diagnosticLines.add('SKIP: User ' + userId + ' has blank Email.');
                    continue;
                }

                String subject =
                    'Withdrawal Clearance Initiation – (' + programmeName + ') ' + studentName;

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(recipient.Id);
                email.setSaveAsActivity(false);
                if (orgWideEmailAddressId != null) {
                    email.setOrgWideEmailAddressId(orgWideEmailAddressId);
                }
                email.setSubject(subject);
                email.setPlainTextBody(
                    'Dear Team,\n\n'
                    + 'A withdrawal request for the following student has been accepted, '
                    + 'and the clearance process is now required to be initiated.\n\n'
                    + 'Student Name: ' + studentName + '\n'
                    + 'Student ID: ' + (String.isBlank(rollNumber) ? '-' : rollNumber) + '\n'
                    + 'Programme: ' + programmeName + '\n'
                    + 'Withdrawal Request Reference Number: ' + referenceNumber + '\n'
                    + 'Request Status: Approved\n\n'
                    + 'You are requested to review the student\'s records and complete '
                    + 'the applicable clearance process from your department.\n\n'
                    + 'Please update the clearance status in the system upon completion.\n\n'
                    + 'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                    + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                    + '<div style="padding:20px;">'
                    + '<p style="font-weight:bold;">Dear Team,</p>'
                    + '<p>A withdrawal request for the following student has been accepted, '
                    + 'and the clearance process is now required to be initiated.</p>'
                    + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                    + buildEmailRow('Student Name', studentName)
                    + buildEmailRow('Student ID', rollNumber)
                    + buildEmailRow('Programme', programmeName)
                    + buildEmailRow('Withdrawal Request Reference Number', referenceNumber)
                    + buildEmailRow('Request Status', 'Approved')
                    + '</table>'
                    + '<p style="margin-top:16px;">You are requested to review the student\'s records and complete '
                    + 'the applicable clearance process from your department.</p>'
                    + '<p>Please update the clearance status in the system upon completion.</p>'
                    + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                    + '</div></div>'
                );
                emails.add(email);
            }

            if (emails.isEmpty()) {
                diagnosticLines.add('STOP (clearance approvers): no eligible recipient emails prepared.');
                return;
            }

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
            Integer sent = 0;
            for (Messaging.SendEmailResult r : results) {
                if (r.isSuccess()) {
                    sent++;
                } else {
                    for (Messaging.SendEmailError err : r.getErrors()) {
                        diagnosticLines.add('Clearance approver email FAILED: '
                            + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                }
            }
            diagnosticLines.add('Clearance approver emails sent: ' + sent + ' of ' + emails.size() + '.');

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR,
                'WithdrawalApprovalController.notifyClearanceApprovers failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    private static Set<Id> parseApproverUserIds(String approverIds) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(approverIds)) {
            return ids;
        }
        String normalized = approverIds.replace('\n', ';').replace(',', ';');
        for (String token : normalized.split(';')) {
            if (String.isBlank(token)) {
                continue;
            }
            try {
                ids.add(Id.valueOf(token.trim()));
            } catch (Exception e) {
                // Ignore non-Id tokens.
            }
        }
        return ids;
    }

    /**
     * Withdrawal status: email-only to the student (portal access revoked).
     * No portal bell / custom notification - access is being revoked.
     */
    private static void notifyStudentWithdrawalCompleted(Withdrawal_Request__c req) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyStudentWithdrawalCompleted @ '
                + String.valueOf(Datetime.now()) + ' ---');

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP: request is null - cannot notify.');
                return;
            }
            if (studentNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP: student already notified for this request in the current transaction.');
                return;
            }
            studentNotifySentIds.add(req.Id);

            List<Withdrawal_Request__c> detailed = [
                SELECT Id, Name, Status__c, Student__c, Student__r.Name, Programme_Master__r.Name
                FROM Withdrawal_Request__c
                WHERE Id = :req.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (detailed.isEmpty()) {
                diagnosticLines.add('STOP: could not re-query request ' + req.Id + '.');
                return;
            }
            Withdrawal_Request__c detail = detailed[0];
            diagnosticLines.add('Request ' + detail.Id + ' Student__c=' + detail.Student__c);

            if (detail.Student__c == null) {
                diagnosticLines.add('STOP: Student__c is null on this request - cannot notify.');
                return;
            }

            String referenceNumber = detail.Name;
            String programmeName = (detail.Programme_Master__r != null)
                ? detail.Programme_Master__r.Name
                : '';

            List<User> studentUsers = [
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :detail.Student__c)
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            diagnosticLines.add('Active portal Users found for this Student Account: ' + studentUsers.size());

            if (studentUsers.isEmpty()) {
                diagnosticLines.add('STOP: no active portal User found for Account ' + detail.Student__c
                    + ' - check that a Contact exists for this Account with an active User attached.');
                return;
            }
            User studentUser = studentUsers[0];
            String studentName = String.isNotBlank(studentUser.Name)
                ? studentUser.Name
                : (detail.Student__r != null ? detail.Student__r.Name : 'Student');
            diagnosticLines.add('Resolved student User: ' + studentUser.Id + ' (' + studentName
                + ') Email=' + studentUser.Email);

            if (String.isBlank(studentUser.Email)) {
                diagnosticLines.add('STOP (email): student User has a blank Email field - cannot send.');
                return;
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(studentUser.Id);
            email.setSaveAsActivity(false);
            email.setSubject('ERP & LMS Portal Access Revoked – ' + studentName);
            email.setPlainTextBody(
                'Dear ' + studentName + ',\n\n'
                + 'Your withdrawal process has been completed. Accordingly, your access to the '
                + 'ERP Student Portal has been revoked.\n\n'
                + 'Request Reference Number: ' + referenceNumber + '\n'
                + 'Programme: ' + programmeName + '\n'
                + 'Withdrawal Status: Completed\n'
                + 'Portal Access: Revoked\n\n'
                + 'You will no longer be able to access the ERP Student Portal using your student credentials.\n\n'
                + 'This is an automated notification. Please do not reply to this email.'
            );
            email.setHtmlBody(
                '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                + '<div style="padding:20px;">'
                + '<p style="font-weight:bold;">Dear ' + studentName.escapeHtml4() + ',</p>'
                + '<p>Your withdrawal process has been completed. Accordingly, your access to the '
                + 'ERP Student Portal has been revoked.</p>'
                + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                + buildEmailRow('Request Reference Number', referenceNumber)
                + buildEmailRow('Programme', programmeName)
                + buildEmailRow('Withdrawal Status', 'Completed')
                + buildEmailRow('Portal Access', 'Revoked')
                + '</table>'
                + '<p style="margin-top:16px;">You will no longer be able to access the ERP Student Portal '
                + 'using your student credentials.</p>'
                + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                + '</div></div>'
            );

            List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ email }, false
            );
            for (Messaging.SendEmailResult r : results) {
                if (!r.isSuccess()) {
                    for (Messaging.SendEmailError err : r.getErrors()) {
                        diagnosticLines.add('Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                    }
                } else {
                    diagnosticLines.add('Withdrawal completed email sent successfully to ' + studentUser.Email + '.');
                }
            }

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR,
                'WithdrawalApprovalController.notifyStudentWithdrawalCompleted failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Final Rejection student email + portal bell when Status becomes Final Rejection.
     * Remarks come from Final_Rejection_Remark__c. Email uses the purple header + table UI shell.
     */
    private static void notifyStudentFinalRejection(Withdrawal_Request__c req) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyStudentFinalRejection @ '
                + String.valueOf(Datetime.now()) + ' ---');

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP: request is null - cannot notify.');
                return;
            }
            if (studentNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP: student already notified for this request in the current transaction.');
                return;
            }
            studentNotifySentIds.add(req.Id);

            List<Withdrawal_Request__c> detailed = [
                SELECT Id, Name, Status__c, Student__c, Student__r.Name, Programme_Master__r.Name,
                       Final_Rejection_Remark__c
                FROM Withdrawal_Request__c
                WHERE Id = :req.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (detailed.isEmpty()) {
                diagnosticLines.add('STOP: could not re-query request ' + req.Id + '.');
                return;
            }
            Withdrawal_Request__c detail = detailed[0];
            diagnosticLines.add('Request ' + detail.Id + ' Student__c=' + detail.Student__c);

            if (detail.Student__c == null) {
                diagnosticLines.add('STOP: Student__c is null on this request - cannot notify.');
                return;
            }

            String referenceNumber = detail.Name;
            String programmeName = (detail.Programme_Master__r != null)
                ? detail.Programme_Master__r.Name
                : '';
            String rejectionRemarks = String.isNotBlank(detail.Final_Rejection_Remark__c)
                ? detail.Final_Rejection_Remark__c
                : '';
            String portalBody =
                'Your withdrawal request ' + referenceNumber
                + ' could not be finalized after clearance and has been rejected.';

            insertStudentPortalBell(
                detail,
                'Withdrawal Request Not Finalized',
                portalBody,
                diagnosticLines
            );

            List<User> studentUsers = [
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :detail.Student__c)
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            diagnosticLines.add('Active portal Users found for this Student Account: ' + studentUsers.size());

            if (studentUsers.isEmpty()) {
                diagnosticLines.add('STOP: no active portal User found for Account ' + detail.Student__c
                    + ' - check that a Contact exists for this Account with an active User attached.');
                return;
            }
            User studentUser = studentUsers[0];
            String studentName = String.isNotBlank(studentUser.Name)
                ? studentUser.Name
                : (detail.Student__r != null ? detail.Student__r.Name : 'Student');
            diagnosticLines.add('Resolved student User: ' + studentUser.Id + ' (' + studentName
                + ') Email=' + studentUser.Email);

            List<CustomNotificationType> notificationTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Withdrawal_Request_Notification'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (notificationTypes.isEmpty()) {
                diagnosticLines.add('WARN: no CustomNotificationType found with DeveloperName='
                    + '\'Withdrawal_Request_Notification\' - custom notification SKIPPED.');
            } else {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypes[0].Id);
                    notification.setTitle('Withdrawal Request Not Finalized');
                    notification.setBody(portalBody);
                    notification.setTargetId(detail.Id);
                    notification.send(new Set<String>{ String.valueOf(studentUser.Id) });
                    diagnosticLines.add('Custom notification sent to ' + studentUser.Id + '.');
                } catch (Exception notifEx) {
                    diagnosticLines.add('Custom notification send FAILED: ' + notifEx.getMessage());
                }
            }

            if (String.isBlank(studentUser.Email)) {
                diagnosticLines.add('STOP (email): student User has a blank Email field - cannot send.');
            } else {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(studentUser.Id);
                email.setSaveAsActivity(false);
                email.setSubject('Withdrawal Request Not Finalized – ' + referenceNumber);
                email.setPlainTextBody(
                    'Dear ' + studentName + ',\n\n'
                    + 'Your withdrawal request has been reviewed following the completion of the clearance process. '
                    + 'The withdrawal could not be finalized and has been rejected.\n\n'
                    + 'Request Reference Number: ' + referenceNumber + '\n'
                    + 'Programme: ' + programmeName + '\n'
                    + 'Request Status: Rejected\n'
                    + 'Remarks: ' + rejectionRemarks + '\n\n'
                    + 'Please review the remarks provided above for further details. '
                    + 'If any further action is required from your end, you will be notified separately.\n\n'
                    + 'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                    + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                    + '<div style="padding:20px;">'
                    + '<p style="font-weight:bold;">Dear ' + studentName.escapeHtml4() + ',</p>'
                    + '<p>Your withdrawal request has been reviewed following the completion of the clearance process. '
                    + 'The withdrawal could not be finalized and has been rejected.</p>'
                    + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                    + buildEmailRow('Request Reference Number', referenceNumber)
                    + buildEmailRow('Programme', programmeName)
                    + buildEmailRow('Request Status', 'Rejected')
                    + buildEmailRow('Remarks', rejectionRemarks)
                    + '</table>'
                    + '<p style="margin-top:16px;">Please review the remarks provided above for further details. '
                    + 'If any further action is required from your end, you will be notified separately.</p>'
                    + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                    + '</div></div>'
                );

                List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email }, false
                );
                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            diagnosticLines.add('Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                        }
                    } else {
                        diagnosticLines.add('Final Rejection email sent successfully to ' + studentUser.Email + '.');
                    }
                }
            }

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR,
                'WithdrawalApprovalController.notifyStudentFinalRejection failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Final Approval student email + portal bell when Status becomes Final Approval.
     * Email uses the same purple header + table UI shell.
     */
    private static void notifyStudentFinalApproval(Withdrawal_Request__c req) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyStudentFinalApproval @ '
                + String.valueOf(Datetime.now()) + ' ---');

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP: request is null - cannot notify.');
                return;
            }
            if (studentNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP: student already notified for this request in the current transaction.');
                return;
            }
            studentNotifySentIds.add(req.Id);

            List<Withdrawal_Request__c> detailed = [
                SELECT Id, Name, Status__c, Student__c, Student__r.Name, Programme_Master__r.Name
                FROM Withdrawal_Request__c
                WHERE Id = :req.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (detailed.isEmpty()) {
                diagnosticLines.add('STOP: could not re-query request ' + req.Id + '.');
                return;
            }
            Withdrawal_Request__c detail = detailed[0];
            diagnosticLines.add('Request ' + detail.Id + ' Student__c=' + detail.Student__c);

            if (detail.Student__c == null) {
                diagnosticLines.add('STOP: Student__c is null on this request - cannot notify.');
                return;
            }

            String referenceNumber = detail.Name;
            String programmeName = (detail.Programme_Master__r != null)
                ? detail.Programme_Master__r.Name
                : '';
            String portalBody =
                'Your withdrawal request ' + referenceNumber
                + ' has received final approval and the withdrawal process has been completed.';

            insertStudentPortalBell(
                detail,
                'Withdrawal Process Completed',
                portalBody,
                diagnosticLines
            );

            List<User> studentUsers = [
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :detail.Student__c)
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            diagnosticLines.add('Active portal Users found for this Student Account: ' + studentUsers.size());

            if (studentUsers.isEmpty()) {
                diagnosticLines.add('STOP: no active portal User found for Account ' + detail.Student__c
                    + ' - check that a Contact exists for this Account with an active User attached.');
                return;
            }
            User studentUser = studentUsers[0];
            String studentName = String.isNotBlank(studentUser.Name)
                ? studentUser.Name
                : (detail.Student__r != null ? detail.Student__r.Name : 'Student');
            diagnosticLines.add('Resolved student User: ' + studentUser.Id + ' (' + studentName
                + ') Email=' + studentUser.Email);

            List<CustomNotificationType> notificationTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Withdrawal_Request_Notification'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (notificationTypes.isEmpty()) {
                diagnosticLines.add('WARN: no CustomNotificationType found with DeveloperName='
                    + '\'Withdrawal_Request_Notification\' - custom notification SKIPPED.');
            } else {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypes[0].Id);
                    notification.setTitle('Withdrawal Process Completed');
                    notification.setBody(portalBody);
                    notification.setTargetId(detail.Id);
                    notification.send(new Set<String>{ String.valueOf(studentUser.Id) });
                    diagnosticLines.add('Custom notification sent to ' + studentUser.Id + '.');
                } catch (Exception notifEx) {
                    diagnosticLines.add('Custom notification send FAILED: ' + notifEx.getMessage());
                }
            }

            if (String.isBlank(studentUser.Email)) {
                diagnosticLines.add('STOP (email): student User has a blank Email field - cannot send.');
            } else {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(studentUser.Id);
                email.setSaveAsActivity(false);
                email.setSubject('Withdrawal Process Completed – ' + referenceNumber);
                email.setPlainTextBody(
                    'Dear ' + studentName + ',\n\n'
                    + 'This is to confirm that your withdrawal request has received final approval '
                    + 'and the withdrawal process has been successfully completed.\n\n'
                    + 'Request Reference Number: ' + referenceNumber + '\n'
                    + 'Programme: ' + programmeName + '\n'
                    + 'Request Status: Withdrawal Completed\n\n'
                    + 'No further action is required from your end in relation to the withdrawal request.\n\n'
                    + 'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                    + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                    + '<div style="padding:20px;">'
                    + '<p style="font-weight:bold;">Dear ' + studentName.escapeHtml4() + ',</p>'
                    + '<p>This is to confirm that your withdrawal request has received final approval '
                    + 'and the withdrawal process has been successfully completed.</p>'
                    + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                    + buildEmailRow('Request Reference Number', referenceNumber)
                    + buildEmailRow('Programme', programmeName)
                    + buildEmailRow('Request Status', 'Withdrawal Completed')
                    + '</table>'
                    + '<p style="margin-top:16px;">No further action is required from your end in relation '
                    + 'to the withdrawal request.</p>'
                    + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                    + '</div></div>'
                );

                List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email }, false
                );
                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            diagnosticLines.add('Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                        }
                    } else {
                        diagnosticLines.add('Final Approval email sent successfully to ' + studentUser.Email + '.');
                    }
                }
            }

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR,
                'WithdrawalApprovalController.notifyStudentFinalApproval failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Clearance & Exit student email + portal bell when Status becomes Clearance & Exit.
     * Approve / reject / recall notification methods are left unchanged.
     * Email uses the same purple header + table UI shell.
     */
    private static void notifyStudentClearanceChecklist(Withdrawal_Request__c req) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyStudentClearanceChecklist @ '
                + String.valueOf(Datetime.now()) + ' ---');

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP: request is null - cannot notify.');
                return;
            }
            if (studentNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP: student already notified for this request in the current transaction.');
                return;
            }
            studentNotifySentIds.add(req.Id);

            List<Withdrawal_Request__c> detailed = [
                SELECT Id, Name, Status__c, Student__c, Student__r.Name, Programme_Master__r.Name
                FROM Withdrawal_Request__c
                WHERE Id = :req.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (detailed.isEmpty()) {
                diagnosticLines.add('STOP: could not re-query request ' + req.Id + '.');
                return;
            }
            Withdrawal_Request__c detail = detailed[0];
            diagnosticLines.add('Request ' + detail.Id + ' Student__c=' + detail.Student__c);

            if (detail.Student__c == null) {
                diagnosticLines.add('STOP: Student__c is null on this request - cannot notify.');
                return;
            }

            String referenceNumber = detail.Name;
            String programmeName = (detail.Programme_Master__r != null)
                ? detail.Programme_Master__r.Name
                : '';
            String statusValue = String.isNotBlank(detail.Status__c)
                ? detail.Status__c
                : STATUS_CLEARANCE;
            String portalBody =
                'A clearance checklist has been generated for your withdrawal request '
                + referenceNumber
                + '. Please complete the required actions within 2 working days.';

            insertStudentPortalBell(
                detail,
                'Clearance Checklist Assigned',
                portalBody,
                diagnosticLines
            );

            List<User> studentUsers = [
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :detail.Student__c)
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            diagnosticLines.add('Active portal Users found for this Student Account: ' + studentUsers.size());

            if (studentUsers.isEmpty()) {
                diagnosticLines.add('STOP: no active portal User found for Account ' + detail.Student__c
                    + ' - check that a Contact exists for this Account with an active User attached.');
                return;
            }
            User studentUser = studentUsers[0];
            String studentName = String.isNotBlank(studentUser.Name)
                ? studentUser.Name
                : (detail.Student__r != null ? detail.Student__r.Name : 'Student');
            diagnosticLines.add('Resolved student User: ' + studentUser.Id + ' (' + studentName
                + ') Email=' + studentUser.Email);

            List<CustomNotificationType> notificationTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Withdrawal_Request_Notification'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (notificationTypes.isEmpty()) {
                diagnosticLines.add('WARN: no CustomNotificationType found with DeveloperName='
                    + '\'Withdrawal_Request_Notification\' - custom notification SKIPPED.');
            } else {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypes[0].Id);
                    notification.setTitle('Clearance Checklist Assigned');
                    notification.setBody(portalBody);
                    notification.setTargetId(detail.Id);
                    notification.send(new Set<String>{ String.valueOf(studentUser.Id) });
                    diagnosticLines.add('Custom notification sent to ' + studentUser.Id + '.');
                } catch (Exception notifEx) {
                    diagnosticLines.add('Custom notification send FAILED: ' + notifEx.getMessage());
                }
            }

            if (String.isBlank(studentUser.Email)) {
                diagnosticLines.add('STOP (email): student User has a blank Email field - cannot send.');
            } else {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(studentUser.Id);
                email.setSaveAsActivity(false);
                email.setSubject('Clearance Checklist Assigned – ' + referenceNumber);
                email.setPlainTextBody(
                    'Dear ' + studentName + ',\n\n'
                    + 'A clearance checklist has been generated for your withdrawal request '
                    + 'and is now available for completion.\n\n'
                    + 'Request Reference Number: ' + referenceNumber + '\n'
                    + 'Programme: ' + programmeName + '\n'
                    + 'Request Status: ' + statusValue + '\n\n'
                    + 'Please log in to the system to view the clearance checklist and complete '
                    + 'the required actions within 2 working days.\n\n'
                    + 'You will be notified once the clearance process is completed or if any '
                    + 'further action is required from your end.\n\n'
                    + 'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                    + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                    + '<div style="padding:20px;">'
                    + '<p style="font-weight:bold;">Dear ' + studentName.escapeHtml4() + ',</p>'
                    + '<p>A clearance checklist has been generated for your withdrawal request '
                    + 'and is now available for completion.</p>'
                    + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                    + buildEmailRow('Request Reference Number', referenceNumber)
                    + buildEmailRow('Programme', programmeName)
                    + buildEmailRow('Request Status', statusValue)
                    + '</table>'
                    + '<p style="margin-top:16px;">Please log in to the system to view the clearance checklist '
                    + 'and complete the required actions within 2 working days.</p>'
                    + '<p>You will be notified once the clearance process is completed or if any '
                    + 'further action is required from your end.</p>'
                    + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                    + '</div></div>'
                );

                List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email }, false
                );
                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            diagnosticLines.add('Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                        }
                    } else {
                        diagnosticLines.add('Clearance email sent successfully to ' + studentUser.Email + '.');
                    }
                }
            }

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR,
                'WithdrawalApprovalController.notifyStudentClearanceChecklist failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Recall-only student email + portal bell (PO or Chairperson).
     * Approve / reject notifyStudent content and layout are left unchanged.
     * Email uses the same purple header + table UI shell as approve/reject.
     */
    private static void notifyStudentRecalled(Withdrawal_Request__c req) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyStudentRecalled @ ' + String.valueOf(Datetime.now()) + ' ---');
            diagnosticLines.add('Request ' + req.Id + ' Student__c=' + req.Student__c);

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP: request is null - cannot notify.');
                return;
            }
            if (studentNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP: student already notified for this request in the current transaction.');
                return;
            }
            studentNotifySentIds.add(req.Id);

            if (req.Student__c == null) {
                diagnosticLines.add('STOP: Student__c is null on this request - cannot resolve a portal User.');
                return;
            }

            String referenceNumber = req.Name;
            String programmeName = (req.Programme_Master__r != null) ? req.Programme_Master__r.Name : '';
            String portalBody =
                'Your withdrawal request ' + referenceNumber
                + ' has been recalled by the Program Manager. Your student status has been restored.';

            insertStudentPortalBell(
                req,
                'Withdrawal Request Recalled',
                portalBody,
                diagnosticLines
            );

            List<User> studentUsers = [
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :req.Student__c)
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            diagnosticLines.add('Active portal Users found for this Student Account: ' + studentUsers.size());

            if (studentUsers.isEmpty()) {
                diagnosticLines.add('STOP: no active portal User found for Account ' + req.Student__c
                    + ' - check that a Contact exists for this Account with an active User attached.');
                return;
            }
            User studentUser = studentUsers[0];
            String studentName = String.isNotBlank(studentUser.Name)
                ? studentUser.Name
                : (req.Student__r != null ? req.Student__r.Name : 'Student');
            diagnosticLines.add('Resolved student User: ' + studentUser.Id + ' (' + studentName
                + ') Email=' + studentUser.Email);

            List<CustomNotificationType> notificationTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Withdrawal_Request_Notification'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (notificationTypes.isEmpty()) {
                diagnosticLines.add('WARN: no CustomNotificationType found with DeveloperName='
                    + '\'Withdrawal_Request_Notification\' - custom notification SKIPPED.');
            } else {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypes[0].Id);
                    notification.setTitle('Withdrawal Request Recalled');
                    notification.setBody(portalBody);
                    notification.setTargetId(req.Id);
                    notification.send(new Set<String>{ String.valueOf(studentUser.Id) });
                    diagnosticLines.add('Custom notification sent to ' + studentUser.Id + '.');
                } catch (Exception notifEx) {
                    diagnosticLines.add('Custom notification send FAILED: ' + notifEx.getMessage());
                }
            }

            if (String.isBlank(studentUser.Email)) {
                diagnosticLines.add('STOP (email): student User has a blank Email field - cannot send.');
            } else {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(studentUser.Id);
                email.setSaveAsActivity(false);
                email.setSubject('Withdrawal Request Recalled – ' + referenceNumber);
                email.setPlainTextBody(
                    'Dear ' + studentName + ',\n\n'
                    + 'Your withdrawal request has been recalled by the Program Manager. '
                    + 'As a result, your student status has been restored.\n\n'
                    + 'Request Reference Number: ' + referenceNumber + '\n'
                    + 'Programme: ' + programmeName + '\n'
                    + 'Request Status: Recalled\n'
                    + 'Student Status: Restored\n\n'
                    + 'No further action is required from your end at this stage.\n\n'
                    + 'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">'
                    + '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>'
                    + '<div style="padding:20px;">'
                    + '<p style="font-weight:bold;">Dear ' + studentName.escapeHtml4() + ',</p>'
                    + '<p>Your withdrawal request has been recalled by the Program Manager. '
                    + 'As a result, your student status has been restored.</p>'
                    + '<table style="width:100%;border-collapse:collapse;margin-top:12px;">'
                    + buildEmailRow('Request Reference Number', referenceNumber)
                    + buildEmailRow('Programme', programmeName)
                    + buildEmailRow('Request Status', 'Recalled')
                    + buildEmailRow('Student Status', 'Restored')
                    + '</table>'
                    + '<p style="margin-top:16px;">No further action is required from your end at this stage.</p>'
                    + '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>'
                    + '</div></div>'
                );

                List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email }, false
                );
                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            diagnosticLines.add('Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                        }
                    } else {
                        diagnosticLines.add('Recall email sent successfully to ' + studentUser.Email + '.');
                    }
                }
            }

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, 'WithdrawalApprovalController.notifyStudentRecalled failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Sends Email + portal header bell to the student when their request is
     * approved/rejected/escalated (PO or Chairperson).
     * Recall uses notifyStudentRecalled instead. Portal bell uses Portal_Notification__c
     * (same object as Photo Upload / Attendance in spjimr_header).
     */
    private static void notifyStudent(Withdrawal_Request__c req, String approverComments, String headline) {
        List<String> diagnosticLines = new List<String>();
        try {
            diagnosticLines.add('--- Approval notifyStudent @ ' + String.valueOf(Datetime.now()) + ' ---');
            diagnosticLines.add('Request ' + req.Id + ' Student__c=' + req.Student__c);

            if (req == null || req.Id == null) {
                diagnosticLines.add('STOP: request is null - cannot notify.');
                return;
            }
            if (studentNotifySentIds.contains(req.Id)) {
                diagnosticLines.add('SKIP: student already notified for this request in the current transaction.');
                return;
            }
            studentNotifySentIds.add(req.Id);

            if (req.Student__c == null) {
                diagnosticLines.add('STOP: Student__c is null on this request - cannot resolve a portal User.');
                return;
            }

            // Portal header bell for PO and Chairperson decisions (email unchanged below).
            String portalBody = String.isNotBlank(req.Name) && !headline.contains(req.Name)
                ? headline.replaceFirst('Your withdrawal request', 'Your withdrawal request ' + req.Name)
                : headline;
            if (!portalBody.contains('Kindly log in')) {
                portalBody += ' Kindly log in to view the full status.';
            }
            insertStudentPortalBell(
                req,
                'Withdrawal Request Update',
                portalBody,
                diagnosticLines
            );

            List<User> studentUsers = [
                SELECT Id, Name, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :req.Student__c)
                AND IsActive = true
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            diagnosticLines.add('Active portal Users found for this Student Account: ' + studentUsers.size());

            if (studentUsers.isEmpty()) {
                diagnosticLines.add('STOP: no active portal User found for Account ' + req.Student__c
                    + ' - check that a Contact exists for this Account with an active User attached.');
                return;
            }
            User studentUser = studentUsers[0];
            diagnosticLines.add('Resolved student User: ' + studentUser.Id + ' (' + studentUser.Name
                + ') Email=' + studentUser.Email);

            List<CustomNotificationType> notificationTypes = [
                SELECT Id FROM CustomNotificationType
                WHERE DeveloperName = 'Withdrawal_Request_Notification'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (notificationTypes.isEmpty()) {
                diagnosticLines.add('WARN: no CustomNotificationType found with DeveloperName='
                    + '\'Withdrawal_Request_Notification\' - custom notification SKIPPED.');
            } else {
                try {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setNotificationTypeId(notificationTypes[0].Id);
                    notification.setTitle('Withdrawal Request Update');
                    notification.setBody(headline);
                    notification.setTargetId(req.Id);
                    notification.send(new Set<String>{ String.valueOf(studentUser.Id) });
                    diagnosticLines.add('Custom notification sent to ' + studentUser.Id + '.');
                } catch (Exception notifEx) {
                    diagnosticLines.add('Custom notification send FAILED: ' + notifEx.getMessage());
                }
            }

            if (String.isBlank(studentUser.Email)) {
                diagnosticLines.add('STOP (email): student User has a blank Email field - cannot send.');
            } else {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(studentUser.Id);
                email.setSaveAsActivity(false);
                email.setSubject('Withdrawal Request Update: ' + req.Name);
                email.setPlainTextBody(
                    'Hi ' + studentUser.Name + ',\n\n' + headline + '\n\n' +
                    'Request: ' + req.Name + '\n' +
                    'Status: ' + req.Status__c + '\n' +
                    'Reason for Withdrawal: ' + (req.Reason_for_Withdrawal__c != null ? req.Reason_for_Withdrawal__c : '-') + '\n' +
                    'Approver Comments: ' + (String.isBlank(approverComments) ? '-' : approverComments) + '\n\n' +
                    'This is an automated notification. Please do not reply to this email.'
                );
                email.setHtmlBody(
                    '<div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #ddd;">' +
                    '<div style="background:#4b2e83;color:#fff;padding:16px 20px;font-size:18px;font-weight:bold;">Withdrawal Request</div>' +
                    '<div style="padding:20px;">' +
                    '<p style="font-weight:bold;">Dear ' + studentUser.Name.escapeHtml4() + ', ' + headline.escapeHtml4() + '</p>' +
                    '<table style="width:100%;border-collapse:collapse;margin-top:12px;">' +
                    buildEmailRow('Request', req.Name) +
                    buildEmailRow('Student Roll Number', req.Roll_Number__c) +
                    buildEmailRow('Student Registration', req.Application_ID__c) +
                    buildEmailRow('Reason for Withdrawal', req.Reason_for_Withdrawal__c) +
                    buildEmailRow('Status', req.Status__c) +
                    buildEmailRow('Approver Comments', approverComments) +
                    '</table>' +
                    '<p style="margin-top:16px;">Kindly log in to the system to view the full status of your request.</p>' +
                    '<p style="color:#c0392b;font-size:12px;">This is an automated notification. Please do not reply to this email.</p>' +
                    '</div></div>'
                );

                List<Messaging.SendEmailResult> results = Messaging.sendEmail(
                    new List<Messaging.SingleEmailMessage>{ email }, false
                );
                for (Messaging.SendEmailResult r : results) {
                    if (!r.isSuccess()) {
                        for (Messaging.SendEmailError err : r.getErrors()) {
                            diagnosticLines.add('Email send FAILED: ' + err.getStatusCode() + ' - ' + err.getMessage());
                        }
                    } else {
                        diagnosticLines.add('Email sent successfully to ' + studentUser.Email + '.');
                    }
                }
            }

        } catch (Exception e) {
            diagnosticLines.add('UNCAUGHT EXCEPTION: ' + e.getMessage() + ' | ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, 'WithdrawalApprovalController.notifyStudent failed: ' + e.getMessage());
        } finally {
            if (req != null) {
                saveDiagnostics(req.Id, diagnosticLines);
            }
        }
    }

    /**
     * Inserts a Portal_Notification__c for the student header bell.
     * Does not send email. Used for PO and Chairperson decisions.
     */
    private static void insertStudentPortalBell(
        Withdrawal_Request__c req,
        String title,
        String body,
        List<String> diagnosticLines
    ) {
        if (req == null || req.Student__c == null || String.isBlank(title)) {
            if (diagnosticLines != null) {
                diagnosticLines.add('SKIP portal bell: missing Student__c or title.');
            }
            return;
        }
        try {
            Database.SaveResult sr = Database.insert(
                new Portal_Notification__c(
                    Title__c = title,
                    Body__c = body,
                    Recipient_Account__c = req.Student__c,
                    Is_Read__c = false
                ),
                false,
                AccessLevel.SYSTEM_MODE
            );
            if (sr.isSuccess()) {
                if (diagnosticLines != null) {
                    diagnosticLines.add('Portal bell inserted: ' + title);
                }
            } else if (diagnosticLines != null) {
                for (Database.Error err : sr.getErrors()) {
                    diagnosticLines.add('Portal bell insert FAILED: '
                        + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        } catch (Exception e) {
            if (diagnosticLines != null) {
                diagnosticLines.add('Portal bell insert EXCEPTION: ' + e.getMessage());
            }
        }
    }

    private static String buildEmailRow(String label, String value) {
        String safeValue = String.isBlank(value) ? '-' : value.escapeHtml4();
        return '<tr>' +
            '<td style="border:1px solid #ddd;padding:8px;font-weight:bold;background:#f5f5f5;width:40%;">' + label + '</td>' +
            '<td style="border:1px solid #ddd;padding:8px;">' + safeValue + '</td>' +
            '</tr>';
    }

    private static void saveDiagnostics(Id requestId, List<String> diagnosticLines) {
        if (requestId == null || diagnosticLines.isEmpty()) {
            return;
        }
        try {
            List<Withdrawal_Request__c> current = [
                SELECT Id, Notification_Debug__c
                FROM Withdrawal_Request__c
                WHERE Id = :requestId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            String existing = (!current.isEmpty() && current[0].Notification_Debug__c != null)
                ? current[0].Notification_Debug__c
                : '';
            String appended = existing + (String.isBlank(existing) ? '' : '\n') + String.join(diagnosticLines, '\n');
            if (appended.length() > 131000) {
                appended = appended.substring(appended.length() - 131000);
            }

            Database.SaveResult sr = Database.update(
                new Withdrawal_Request__c(Id = requestId, Notification_Debug__c = appended),
                false,
                AccessLevel.SYSTEM_MODE
            );
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'Failed to save Notification_Debug__c: '
                        + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        } catch (Exception saveEx) {
            System.debug(LoggingLevel.ERROR, 'saveDiagnostics failed: ' + saveEx.getMessage());
        }
    }
}