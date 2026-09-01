public without sharing class DefermentApprovalController {

    @AuraEnabled
    public static void processApproval(
        Id recordId,
        String action,
        String comments
    ) { try{

        System.debug('=== NEW DEFERMENT APPROVAL CONTROLLER ===');
        System.debug('Record Id: ' + recordId);
        System.debug('Action: ' + action);
        System.debug('Comments: ' + comments);

        if (recordId == null) {
            throw new AuraHandledException(
                'Deferment Request Id is required.'
            );
        }

        if (action != 'APPROVE' && action != 'REJECT') {
            throw new AuraHandledException(
                'Invalid approval action.'
            );
        }

        /*
         * Section 8.1: "On-system ERP approvals require mandatory remarks at
         * each level - blank remarks are not accepted."
         *
         * The Approve/Reject screen already asks for remarks, but nothing
         * behind it did, so an approval reaching this method by any other route
         * was recorded with no remarks against it - permanently, in the
         * approval history.
         */
        if (String.isBlank(comments)) {
            String msg = action == 'REJECT'
                ? 'Please enter your remarks explaining why this Deferment ' +
                  'Request is being rejected. Remarks are mandatory.'
                : 'Please enter your remarks before approving this Deferment ' +
                  'Request. Remarks are mandatory at each approval level.';
            AuraHandledException blank = new AuraHandledException(msg);
            blank.setMessage(msg);
            throw blank;
        }

        /*
         * 1. Get Deferment Request
         *
         * WITH SYSTEM_MODE bypasses the running user's object/field
         * permissions (FLS + CRUD) for this query, while the class-level
         * "without sharing" already bypasses record-level sharing rules.
         */
        List<Deferment_Request__c> requestList = [
            SELECT Id,
                   Name,
                   Programme__c,
                   Status__c,
                   Approval_Status__c,
                   Current_Role__c,
                   Current_Approver_User__c,
                   Current_Approver_Ids__c,
                   Account__c
            FROM Deferment_Request__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (requestList.isEmpty()) {
            throw new AuraHandledException(
                'Deferment Request not found.'
            );
        }

        Deferment_Request__c req = requestList[0];

        System.debug('Request: ' + req.Id);
        System.debug('Programme: ' + req.Programme__c);
        System.debug('Current Role: ' + req.Current_Role__c);
        System.debug(
            'Current Approver: ' +
            req.Current_Approver_User__c
        );

                /*
         * SECURITY CHECK: only a user currently listed as an eligible
         * approver for this round may approve/reject. Blocks any other
         * user — even one with access to this Apex method/LWC — from
         * actioning a request that isn't assigned to them.
         */
        Set<String> eligibleApproverIds = new Set<String>();

        if (!String.isBlank(req.Current_Approver_Ids__c)) {
            eligibleApproverIds.addAll(
                req.Current_Approver_Ids__c.split(',')
            );
        }

        String runningUserId = String.valueOf(UserInfo.getUserId());

        if (!eligibleApproverIds.contains(runningUserId)) {
           String msg = 'You are not authorized to approve or reject this request. ' +
        'It is currently assigned to a different approver.';
    AuraHandledException ex = new AuraHandledException(msg);
    ex.setMessage(msg);
    throw ex;
        }

        /*
         * 2. Find pending approval work item
         */
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id,
                   ActorId,
                   OriginalActorId,
                   ProcessInstanceId,
                   CreatedDate
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];

        System.debug(
            LoggingLevel.ERROR,
            '=== ALL WORK ITEMS FOUND ==='
        );

        for (ProcessInstanceWorkitem wi : workItems) {

            System.debug(LoggingLevel.ERROR, 'WorkItem Id = ' + wi.Id);
            System.debug(LoggingLevel.ERROR, 'ActorId = ' + wi.ActorId);
            System.debug(LoggingLevel.ERROR, 'OriginalActorId = ' + wi.OriginalActorId);
            System.debug(LoggingLevel.ERROR, 'Current User = ' + UserInfo.getUserId());
        }

        if (workItems.isEmpty()) {
            String msg = 'No pending approval work item was found for this request. It may have already been actioned.';
    	AuraHandledException ex = new AuraHandledException(msg);
    	ex.setMessage(msg);
    	throw ex;
        }

        ProcessInstanceWorkitem workItem = workItems[0];

        System.debug('Work Item: ' + workItem.Id);

        /*
         * REJECT
         */
        if (action == 'REJECT') {
            rejectRequest(req, workItem.Id, comments);
            return;
        }

        /*
         * APPROVE
         */
        if (req.Current_Role__c == 'Chairperson') {
            approveChairperson(req, workItem.Id, comments);
            return;
        }

        if (
            req.Current_Role__c == 'Associate Dean' ||
            req.Current_Role__c == 'Dean'
        ) {
            approveFinal(req, workItem.Id, comments);
            return;
        }

        throw new AuraHandledException(
            'Invalid approval role: ' + req.Current_Role__c
        );
    }

    catch (AuraHandledException ex) {
        throw ex;

    } catch (Exception ex) {

        System.debug(
            LoggingLevel.ERROR,
            'DEFERMENT APPROVAL ERROR: ' +
            ex.getTypeName() +
            ' | Message: ' + ex.getMessage() +
            ' | Line: ' + ex.getLineNumber() +
            ' | Stack: ' + ex.getStackTraceString()
        );

        throw new AuraHandledException(
            'Approval error [Line ' + ex.getLineNumber() + ']: ' + ex.getMessage()
        );
    }
    }


    /*
     * =============================================================
     * REJECT
     * =============================================================
     */
    private static void rejectRequest(
        Deferment_Request__c req,
        Id workItemId,
        String comments
    ) {

        Approval.ProcessWorkitemRequest request =
            new Approval.ProcessWorkitemRequest();

        request.setWorkitemId(workItemId);
        request.setAction('Reject');

        

        if (!String.isBlank(comments)) {
            request.setComments(comments);
        }

        System.debug(LoggingLevel.ERROR, '### BEFORE APPROVAL.PROCESS ###');
        System.debug(LoggingLevel.ERROR, 'WorkItemId = ' + workItemId);
        System.debug(LoggingLevel.ERROR, 'RequestId = ' + req.Id);
        System.debug(LoggingLevel.ERROR, 'Current Role = ' + req.Current_Role__c);
        System.debug(LoggingLevel.ERROR, 'Current Approver = ' + req.Current_Approver_User__c);
        System.debug(LoggingLevel.ERROR, 'Programme = ' + req.Programme__c);

        Approval.ProcessResult result = Approval.process(request);

        System.debug(LoggingLevel.ERROR, '### AFTER APPROVAL.PROCESS ###');
        System.debug(LoggingLevel.ERROR, 'Approval success = ' + result.isSuccess());
        System.debug(LoggingLevel.ERROR, 'Approval instance status = ' + result.getInstanceStatus());

        if (!result.isSuccess()) {

            System.debug(LoggingLevel.ERROR, 'Approval process returned FAILURE');

            String errorMessage = 'Failed to reject the Deferment Request.';

            if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                errorMessage += ' ' + result.getErrors()[0].getMessage();
            }

            throw new AuraHandledException(errorMessage);
        }

        String rejectedByRoleLabel = req.Current_Role__c;
Id studentAccountId = req.Account__c;

         req.Status__c = 'Deferment Form Enabled';
        // Section 5 of the process document sends a rejected request back to
        // status #2, "Form Submitted by Applicant" - not back to #1, which
        // makes it look as though the student never applied at all.
        // NOTE: reverted once by an out-of-date deploy on 2026-08-31 and
        // restored. Keep this value.
      //  req.Status__c = 'Form Submitted';

        req.Approval_Status__c = 'Rejected';

        // Was commented out, which left Current_Role__c reading "Associate
        // Dean" after a Level 2 rejection. submitDefermentRequest treats that
        // as "the Chairperson has already approved" and routes the
        // resubmission straight back to the Dean, so the Chairperson never
        // saw the revised application. Section 8.1 requires a rejected
        // request to be resubmitted "for approval from Level 1"; clearing the
        // role lets the routing fall through to the Chairperson, as intended.
        req.Current_Role__c = null;

        req.Current_Approver_User__c = null;
        req.Current_Approver_Ids__c = null;

         update as system req;
         DefermentApprovalNotificationService.notifyStudentOfRejection(
    req.Id,
    studentAccountId,
    rejectedByRoleLabel,
    comments
);
    }


    /*
     * =============================================================
     * CHAIRPERSON APPROVAL
     * =============================================================
     */
       private static void approveChairperson(
        Deferment_Request__c req,
        Id workItemId,
        String comments
    ) {

        List<Id> nextApproverIds = getAllApprovers(req.Programme__c, 'Associate Dean');
        String nextRole = 'Associate Dean';

        if (nextApproverIds.isEmpty()) {
            nextApproverIds = getAllApprovers(req.Programme__c, 'Dean');
            nextRole = 'Dean';
        }

        if (nextApproverIds.isEmpty()) {
            throw new AuraHandledException(
                'No Associate Dean or Dean is configured for this Programme.'
            );
        }

        Approval.ProcessWorkitemRequest approvalRequest =
            new Approval.ProcessWorkitemRequest();

        approvalRequest.setWorkitemId(workItemId);
        approvalRequest.setAction('Approve');

        if (!String.isBlank(comments)) {
            approvalRequest.setComments(comments);
        }

        // NEW: explicitly route to ALL eligible Dean/AD approvers, not just one
        approvalRequest.setNextApproverIds(nextApproverIds);

        Approval.ProcessResult result = Approval.process(approvalRequest);

        if (!result.isSuccess()) {

            String errorMessage = 'Failed to approve Chairperson request.';

            if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                errorMessage += ' ' + result.getErrors()[0].getMessage();
            }

            throw new AuraHandledException(errorMessage);
        }

        req.Status__c = 'Pending Dean\'s / AD\'s Approval';
        req.Approval_Status__c = 'Pending';
        req.Current_Role__c = nextRole;
        req.Current_Approver_User__c = nextApproverIds[0];

        // NEW: store the FULL list, matching how submitDefermentRequest does it
        List<String> nextApproverIdStrings = new List<String>();
        for (Id approverId : nextApproverIds) {
            nextApproverIdStrings.add(String.valueOf(approverId));
        }
        req.Current_Approver_Ids__c = String.join(nextApproverIdStrings, ',');
    
        update as system req;
        // NEW: notify the Associate Dean / Dean that this request now needs their approval
        DefermentApprovalNotificationService.notifyApprovers(req.Id,nextApproverIds,nextRole);
    
    }

    /*
     * =============================================================
     * FINAL APPROVAL
     * =============================================================
     */
    private static void approveFinal(
        Deferment_Request__c req,
        Id workItemId,
        String comments
    ) {

        System.debug(LoggingLevel.ERROR, '=== FINAL APPROVAL START ===');
        System.debug(LoggingLevel.ERROR, 'Record Id = ' + req.Id);
        System.debug(LoggingLevel.ERROR, 'Current Role = ' + req.Current_Role__c);
        System.debug(LoggingLevel.ERROR, 'Current Approver = ' + req.Current_Approver_User__c);
        System.debug(LoggingLevel.ERROR, 'Logged-in User = ' + UserInfo.getUserId());
        System.debug(LoggingLevel.ERROR, 'WorkItem Id = ' + workItemId);

        Approval.ProcessWorkitemRequest request =
            new Approval.ProcessWorkitemRequest();

        request.setWorkitemId(workItemId);
        request.setAction('Approve');

        if (!String.isBlank(comments)) {
            request.setComments(comments);
        }

        System.debug(LoggingLevel.ERROR, '=== BEFORE FINAL APPROVAL.PROCESS ===');

        Approval.ProcessResult result = Approval.process(request);

        System.debug(LoggingLevel.ERROR, '=== AFTER FINAL APPROVAL.PROCESS ===');
        System.debug(LoggingLevel.ERROR, 'Success = ' + result.isSuccess());
        System.debug(LoggingLevel.ERROR, 'Instance Status = ' + result.getInstanceStatus());

        if (!result.isSuccess()) {

            String errorMessage = 'Failed to complete final approval.';

            if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                errorMessage += ' ' + result.getErrors()[0].getMessage();
            }

            throw new AuraHandledException(errorMessage);
        }

        System.debug(LoggingLevel.ERROR, '=== UPDATING FINAL DEFERMENT STATUS ===');

        req.Status__c = 'Rejoining Details';
        req.Approval_Status__c = 'Pending';
        // Both approval levels are done at this point, so the request is
        // Approved, not Pending. Leaving it Pending hid every newly approved
        // request from the nightly "Rejoining Date not recorded" bell and from
        // the Rejoining Date Missing list view, both of which look for
        // Approval Status = Approved.
        // NOTE: reverted once by an out-of-date deploy on 2026-08-31 and
        // restored. Keep this value - six students were stranded by it.
        
        req.Current_Role__c = null;
        req.Current_Approver_User__c = null;
        req.Current_Approver_Ids__c = null;

        update as system req;
        // =============================================================
		// NOTIFY MANAGER AFTER L2 APPROVAL
		// =============================================================
		List<Id> managerIds =getAllApprovers(req.Programme__c,'Manager');

		System.debug(
    	LoggingLevel.ERROR,
    	'Manager IDs after L2 approval = ' + managerIds
		);

		if (!managerIds.isEmpty()) {

    	DefermentApprovalNotificationService.notifyProgrammeManagersAfterL2Approval(req.Id,managerIds);

		} else {

    	System.debug(
        LoggingLevel.ERROR,
        'No Manager found for Programme = ' +
        req.Programme__c);
		}
		
        // NEW: notify student of final approval
		DefermentApprovalNotificationService.notifyStudentOfFinalApproval(
    	req.Id,
    	req.Account__c
		);

        System.debug(LoggingLevel.ERROR, '=== FINAL APPROVAL COMPLETED ===');
    	}
    
        @TestVisible
        private static List<Id> getAllApprovers(
        Id programmeId,
        String role) {
            
        List<Id> approverIds = new List<Id>();

        if (programmeId == null || String.isBlank(role)) {
            return approverIds;
        }

        List<Program_Team_Members__c> members = [
            SELECT User__c
            FROM Program_Team_Members__c
            WHERE Role__c = :role
            AND User__c != null
            AND Program_Team__r.Program__c = :programmeId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];

        for (Program_Team_Members__c member : members) {
            approverIds.add(member.User__c);
        }

        return approverIds;
    }


    	/*
     	* =============================================================
     	* FIND PROGRAMME APPROVER
    	 * =============================================================
     	*/
    	@TestVisible
    	private static Id findApprover(
        Id programmeId,
        String role
    	) {

        System.debug('Finding approver. Programme=' + programmeId + ', Role=' + role);

        if (programmeId == null || String.isBlank(role)) {
            return null;
        }

        List<Program_Team_Members__c> members = [
            SELECT Id,
                   User__c,
                   Role__c,
                   Program_Team__c,
                   Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Role__c = :role
            AND User__c != null
            AND Program_Team__r.Program__c = :programmeId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        System.debug('Approver records found: ' + members.size());

        if (members.isEmpty()) {
            return null;
        }

        System.debug('Approver User: ' + members[0].User__c);

        return members[0].User__c;
    }

}