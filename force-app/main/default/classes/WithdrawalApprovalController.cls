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

    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String STATUS_RECALLED = 'Recalled';
    private static final String STATUS_PENDING_CHAIRPERSON = 'Accepted (PO Review)';

    // Prevents duplicate student emails in the same transaction when both
    // processApproval() and the after-update trigger would notify.
    private static Set<Id> studentNotifySentIds = new Set<Id>();

    /** Which Approve / Reject buttons the logged-in user may see on the record page. */
    public class ApproverActionVisibility {
        @AuraEnabled public Boolean isApprover;
        @AuraEnabled public Boolean showApprove;
        @AuraEnabled public Boolean showReject;
        @AuraEnabled public Boolean showRecall;
        @AuraEnabled public Boolean showEscalateOption;
    }

    /**
     * True when logged-in user Id is present in Current_Approver_Ids__c.
     * Used by the record-page LWC before opening Approve / Reject.
     */
    @AuraEnabled
    public static Boolean isCurrentUserApprover(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Withdrawal Request Id is required.');
        }
        List<Withdrawal_Request__c> reqs = [
            SELECT Current_Approver_Ids__c
            FROM Withdrawal_Request__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (reqs.isEmpty()) {
            throw new AuraHandledException('Withdrawal Request not found.');
        }
        return isUserInApproverIds(reqs[0].Current_Approver_Ids__c, UserInfo.getUserId());
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
            SELECT Status__c, Current_Role__c, Current_Approver_Ids__c
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
        vis.isApprover = isApprover;
        if (!isApprover) {
            return vis;
        }

        if (req.Status__c == STATUS_APPROVED
            || req.Status__c == STATUS_REJECTED
            || req.Status__c == STATUS_RECALLED) {
            return vis;
        }

        vis.showApprove = true;
        vis.showReject = true;
        vis.showRecall = true;
        vis.showEscalateOption = ROLE_PROGRAMME_OFFICE.equals(req.Current_Role__c);
        return vis;
    }

    /**
     * Minimal hook for standard Approve/Reject (status field updates).
     * Sends student email only when Status becomes Approved or Rejected.
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
                SELECT Id, Name, Programme_Master__c, Status__c,
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

            if (!isCurrentUserAnApprover(req.Current_Approver_Ids__c)) {
                throw new AuraHandledException('You are not an authorized approver for this request.');
            }

            Id workItemId = findPendingWorkItemId(recordId);

            if (action == 'REJECT') {
                rejectRequest(req, workItemId, comments);
                return;
            }

            if (action == 'RECALL') {
                recallRequest(req, workItemId, comments);
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
     * Recall closes the approval engine with a Reject step, but the record
     * Status__c is Recalled. Remap the terminal history row for display only.
     */
    private static void applyRecalledHistoryDisplay(
        List<ApprovalHistoryRow> rows,
        Withdrawal_Request__c req
    ) {
        for (Integer i = rows.size() - 1; i >= 0; i--) {
            ApprovalHistoryRow row = rows[i];
            if (row.status != 'Rejected') {
                continue;
            }
            row.status = STATUS_RECALLED;
            if (String.isNotBlank(req.Remarks__c)) {
                row.remarks = req.Remarks__c;
            }
            if (req.Approved_By__r != null && String.isNotBlank(req.Approved_By__r.Name)) {
                row.approvedBy = req.Approved_By__r.Name;
            }
            if (req.Approval_Date__c != null) {
                row.actionDate = req.Approval_Date__c;
            }
            break;
        }
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
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            AND ProcessInstance.Status = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
        if (workItems.isEmpty()) {
            throw new AuraHandledException(
                'No pending approval step was found for this request - it may already be closed.'
            );
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
        submitDecision(workItemId, 'Reject', comments, null);

        req.Status__c = STATUS_RECALLED;
        req.Remarks__c = comments;
        req.Approved_By__c = UserInfo.getUserId();
        req.Approval_Date__c = Datetime.now();
        req.Current_Role__c = null;
        req.Current_Approver_User__c = null;
        req.Current_Approver_Ids__c = null;
        req.Escalate_To_Chairperson__c = false;

        update as system req;

        notifyStudent(req, comments, 'Your withdrawal request has been recalled.');
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
        req.Current_Role__c = null;
        req.Current_Approver_User__c = null;
        req.Current_Approver_Ids__c = null;

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
     * Sends Email + Custom Notification to the student when their request is
     * approved/rejected/escalated. `headline` is the one-line outcome;
     * `approverComments` is what the approver typed. Every step is logged to
     * Notification_Debug__c on the record.
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