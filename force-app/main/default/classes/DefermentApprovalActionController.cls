public without sharing class DefermentApprovalActionController {

  /*  @AuraEnabled
    public static void processApproval(
        Id recordId,
        String action,
        String comments
    ) {
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

        // ---------------------------------------------------------
        // GET DEFERMENT REQUEST
        // ---------------------------------------------------------

       List<Deferment_Request__c> requests = [
    SELECT Id,
           Name,
           Programme__c,
           Status__c,
           Approval_Status__c,
           Current_Role__c,
           Current_Approver_User__c,
           Current_Approver_Ids__c
    FROM Deferment_Request__c
    WHERE Id = :recordId
    WITH SYSTEM_MODE
    LIMIT 1
];

if (requests.isEmpty()) {
    throw new AuraHandledException(
        'Deferment Request could not be found for record Id: ' +
        String.valueOf(recordId)
    );
}

Deferment_Request__c req = requests[0];

        // ---------------------------------------------------------
        // SECURITY CHECK
        // ---------------------------------------------------------

        if (
            req.Current_Approver_User__c == null ||
            req.Current_Approver_User__c != UserInfo.getUserId()
        ) {
            throw new AuraHandledException(
                'You are not the current approver for this request.'
            );
        }

        // ---------------------------------------------------------
        // GET CURRENT APPROVAL WORK ITEM
        // ---------------------------------------------------------

        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id,
                   ProcessInstanceId,
                   ActorId,
                   OriginalActorId,
                   ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            AND ActorId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (workItems.isEmpty()) {
            throw new AuraHandledException(
                'No pending approval request was found for this user.'
            );
        }

        ProcessInstanceWorkitem workItem = workItems[0];

        // =========================================================
        // REJECT
        // =========================================================

        if (action == 'REJECT') {

            Approval.ProcessWorkitemRequest rejectRequest =
                new Approval.ProcessWorkitemRequest();

            rejectRequest.setWorkitemId(workItem.Id);
            rejectRequest.setAction('Reject');

            if (!String.isBlank(comments)) {
                rejectRequest.setComments(comments);
            }

            Approval.ProcessResult rejectResult =
                Approval.process(rejectRequest);

            if (!rejectResult.isSuccess()) {
                throw new AuraHandledException(
                    'Failed to reject the Deferment Request.'
                );
            }

            /*
             * Business status after rejection.
             */
        /*  req.Status__c =
                'Deferment Form Enabled';

            req.Approval_Status__c =
                'Rejected';

            req.Current_Role__c =
                null;

            req.Current_Approver_User__c =
                null;

            req.Current_Approver_Ids__c =
                null;

            update as system req;

            return;
        }

        // =========================================================
        // APPROVE
        // =========================================================

        String currentRole =
            req.Current_Role__c;

        // ---------------------------------------------------------
        // CHAIRPERSON APPROVAL
        // ---------------------------------------------------------

        if (currentRole == 'Chairperson') {

            handleChairpersonApproval(
                req,
                workItem.Id,
                comments
            );

            return;
        }

        // ---------------------------------------------------------
        // ASSOCIATE DEAN / DEAN APPROVAL
        // ---------------------------------------------------------

        if (
            currentRole == 'Associate Dean' ||
            currentRole == 'Dean'
        ) {

            handleFinalApproval(
                req,
                workItem.Id,
                comments
            );

            return;
        }

        throw new AuraHandledException(
            'Invalid current approval role: ' +
            currentRole
        );
    }*/

    @AuraEnabled
public static void processApproval(
    Id recordId,
    String action,
    String comments
) {
    try {

        System.debug(
            LoggingLevel.ERROR,
            '### NEW DEFERMENT APPROVAL CONTROLLER VERSION 2026-08-24 ###'
        );

        System.debug('===== DEFERMENT APPROVAL START =====');
        System.debug('recordId = ' + recordId);
        System.debug('action = ' + action);
        System.debug('comments = ' + comments);

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

        System.debug('===== BEFORE DEFERMENT QUERY =====');

        List<Deferment_Request__c> requests = [
            SELECT Id,
                   Name,
                   Programme__c,
                   Status__c,
                   Approval_Status__c,
                   Current_Role__c,
                   Current_Approver_User__c,
                   Current_Approver_Ids__c
            FROM Deferment_Request__c
            WHERE Id = :recordId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        System.debug(
            'Deferment requests found = ' + requests.size()
        );

        if (requests.isEmpty()) {
            throw new AuraHandledException(
                'Deferment Request could not be found for record Id: ' +
                String.valueOf(recordId)
            );
        }

        Deferment_Request__c req = requests[0];

        System.debug('Request Id = ' + req.Id);
        System.debug('Programme = ' + req.Programme__c);
        System.debug('Current Role = ' + req.Current_Role__c);
        System.debug(
            'Current Approver = ' +
            req.Current_Approver_User__c
        );

        System.debug('===== BEFORE SECURITY CHECK =====');

        if (
            req.Current_Approver_User__c == null ||
            req.Current_Approver_User__c != UserInfo.getUserId()
        ) {
            throw new AuraHandledException(
                'You are not the current approver for this request.'
            );
        }

        System.debug('===== SECURITY CHECK PASSED =====');

        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id,
                   ProcessInstanceId,
                   ActorId,
                   OriginalActorId,
                   ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :recordId
            AND ActorId = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.debug(
            'Work items found = ' + workItems.size()
        );

        if (workItems.isEmpty()) {
            throw new AuraHandledException(
                'No pending approval request was found for this user.'
            );
        }

        ProcessInstanceWorkitem workItem = workItems[0];

        System.debug(
            'Work Item Id = ' + workItem.Id
        );

        if (action == 'REJECT') {

    Approval.ProcessWorkitemRequest rejectRequest =
        new Approval.ProcessWorkitemRequest();

    rejectRequest.setWorkitemId(workItem.Id);
    rejectRequest.setAction('Reject');

    if (!String.isBlank(comments)) {
        rejectRequest.setComments(comments);
    }

    Approval.ProcessResult result =
        Approval.process(rejectRequest);

    if (!result.isSuccess()) {
        throw new AuraHandledException(
            'Failed to reject the Deferment Request.'
        );
    }

    req.Status__c = 'Deferment Form Enabled';
    req.Approval_Status__c = 'Rejected';
    req.Current_Role__c = null;
    req.Current_Approver_User__c = null;
    req.Current_Approver_Ids__c = null;

    update as system req;

    return;
}

String currentRole = req.Current_Role__c;

if (currentRole == 'Chairperson') {

    handleChairpersonApproval(
        req,
        workItem.Id,
        comments
    );

    return;
}

if (
    currentRole == 'Associate Dean' ||
    currentRole == 'Dean'
) {

    handleFinalApproval(
        req,
        workItem.Id,
        comments
    );

    return;
}

throw new AuraHandledException(
    'Invalid current approval role: ' + currentRole
);

    } catch (AuraHandledException ex) {

        throw ex;

    } catch (Exception ex) {

        System.debug(
            LoggingLevel.ERROR,
            '===== DEFERMENT APPROVAL EXCEPTION ====='
        );

        System.debug(
            LoggingLevel.ERROR,
            'TYPE: ' + ex.getTypeName()
        );

        System.debug(
            LoggingLevel.ERROR,
            'MESSAGE: ' + ex.getMessage()
        );

        System.debug(
            LoggingLevel.ERROR,
            'LINE: ' + ex.getLineNumber()
        );

        System.debug(
            LoggingLevel.ERROR,
            'STACK: ' + ex.getStackTraceString()
        );

        throw new AuraHandledException(
            'Approval failed at line ' +
            ex.getLineNumber() +
            ': ' +
            ex.getMessage()
        );
    }
}


    // =============================================================
    // CHAIRPERSON APPROVAL
    // =============================================================

    private static void handleChairpersonApproval(
        Deferment_Request__c req,
        Id workItemId,
        String comments
    ) {

        /*
         * First check whether Associate Dean exists
         * for this Programme.
         */
        Id associateDeanId =
            getProgrammeApprover(
                req.Programme__c,
                'Associate Dean'
            );

        Id nextApproverId;
        String nextRole;

        if (associateDeanId != null) {

            nextApproverId =
                associateDeanId;

            nextRole =
                'Associate Dean';

        } else {

            /*
             * No Associate Dean assigned.
             * Route directly to Dean.
             */
            Id deanId =
                getProgrammeApprover(
                    req.Programme__c,
                    'Dean'
                );

            if (deanId == null) {
                throw new AuraHandledException(
                    'No Associate Dean or Dean is configured for this Programme.'
                );
            }

            nextApproverId =
                deanId;

            nextRole =
                'Dean';
        }

        // ---------------------------------------------------------
        // APPROVE CURRENT WORK ITEM
        // ---------------------------------------------------------

        Approval.ProcessWorkitemRequest approveRequest =
            new Approval.ProcessWorkitemRequest();

        approveRequest.setWorkitemId(workItemId);
        approveRequest.setAction('Approve');

        if (!String.isBlank(comments)) {
            approveRequest.setComments(comments);
        }

        /*
         * The Approval Process Step 2 uses:
         *
         * Related User →
         * Current Approver User
         *
         * Therefore update the field BEFORE Salesforce
         * moves to the next approval step.
         */
        req.Status__c =
            'Pending Dean\'s / AD\'s Approval';

        req.Approval_Status__c =
            'Pending';

        req.Current_Role__c =
            nextRole;

        req.Current_Approver_User__c =
            nextApproverId;

        req.Current_Approver_Ids__c =
            String.valueOf(nextApproverId);

        update as system req;

        /*
         * Approve Chairperson's work item.
         */
        Approval.ProcessResult result =
            Approval.process(approveRequest);

        if (!result.isSuccess()) {

            throw new AuraHandledException(
                'Failed to approve the Chairperson approval.'
            );
        }
    }


    // =============================================================
    // FINAL APPROVAL
    // Associate Dean OR Dean
    // =============================================================

    private static void handleFinalApproval(
        Deferment_Request__c req,
        Id workItemId,
        String comments
    ) {

        Approval.ProcessWorkitemRequest approveRequest =
            new Approval.ProcessWorkitemRequest();

        approveRequest.setWorkitemId(workItemId);
        approveRequest.setAction('Approve');

        if (!String.isBlank(comments)) {
            approveRequest.setComments(comments);
        }

        /*
         * Final business status.
         */
        // req.Status__c = 'Rejoining Details';
        // Not a member of the restricted Status__c picklist, so the
        // update was rejected and the final approval could never save.
        req.Status__c =
            'Rejoining Details Updated';

        req.Approval_Status__c =
            'Approved';

        req.Current_Role__c =
            null;

        req.Current_Approver_User__c =
            null;

        req.Current_Approver_Ids__c =
            null;

        update as system req;

        Approval.ProcessResult result =
            Approval.process(approveRequest);

        if (!result.isSuccess()) {

            throw new AuraHandledException(
                'Failed to complete the final approval.'
            );
        }
    }


    // =============================================================
    // FIND PROGRAMME APPROVER
    // =============================================================

    private static Id getProgrammeApprover(
        Id programmeId,
        String role
    ) {

        if (
            programmeId == null ||
            String.isBlank(role)
        ) {
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
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        if (members.isEmpty()) {
            return null;
        }

        return members[0].User__c;
    }
}