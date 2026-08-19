// Approval actions record per-step remarks into approval history.
@SuppressWarnings('PMD.ApexCRUDViolation')
// Justification: system-context approval controller. Approvers act on leave applications, approval
// work items and programme team setup they do not own; access is gated by Current_Approver_Ids__c
// (see assertCurrentUserIsApprover) rather than by the running user's object permissions.
public without sharing class LeaveApprovalActionController {

    /** Last swallowed async deputy-submit error, for test assertions and troubleshooting. */
    @TestVisible private static String lastDeputySubmitError;

    /** AuraHandledException constructor message is often lost; setMessage() is required for LWC. */
    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    // ================= GET ROLE =================
    @AuraEnabled
    public static String getCurrentUserRole(Id leaveId){
        try{
            if(leaveId == null){
                throw auraError('Record Id is missing');
            }

            Leave_Application__c rec = [
                SELECT Current_Role_Name__c
                FROM Leave_Application__c
                WHERE Id = :leaveId
                LIMIT 1
            ];

            return rec.Current_Role_Name__c;

        } catch(AuraHandledException ahe){
            throw ahe;
        } catch(Exception e){
            throw auraError('Role Error: ' + e.getMessage());
        }
    }

    /**
     * True when logged-in user Id is present in Current_Approver_Ids__c.
     * Used by LWC action buttons (Approve / Reject / Mark Incomplete).
     */
    @AuraEnabled
    public static Boolean isCurrentUserApprover(Id leaveId) {
        try {
            if (leaveId == null) {
                throw auraError('Record Id is missing');
            }
            Leave_Application__c rec = [
                SELECT Current_Approver_Ids__c
                FROM Leave_Application__c
                WHERE Id = :leaveId
                LIMIT 1
            ];
            return isUserInApproverIds(rec.Current_Approver_Ids__c, UserInfo.getUserId());
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw auraError('Approver check failed: ' + e.getMessage());
        }
    }

    /** Which Approve / Reject / Incomplete buttons the logged-in user may see. */
    public class ApproverActionVisibility {
        @AuraEnabled public Boolean isApprover;
        @AuraEnabled public Boolean showApprove;
        @AuraEnabled public Boolean showReject;
        @AuraEnabled public Boolean showIncomplete;
    }

    @AuraEnabled(cacheable=true)
    public static ApproverActionVisibility getApproverActionVisibility(Id leaveId) {
        ApproverActionVisibility vis = new ApproverActionVisibility();
        vis.isApprover = false;
        vis.showApprove = false;
        vis.showReject = false;
        vis.showIncomplete = false;

        if (leaveId == null) {
            return vis;
        }

        Leave_Application__c rec = [
            SELECT Status__c, Current_Role_Name__c, Current_Approver_Ids__c
            FROM Leave_Application__c
            WHERE Id = :leaveId
            LIMIT 1
        ];

        Boolean isApprover = isUserInApproverIds(rec.Current_Approver_Ids__c, UserInfo.getUserId());
        vis.isApprover = isApprover;
        if (!isApprover) {
            return vis;
        }

        Boolean statusOk = rec.Status__c == null || !rec.Status__c.equalsIgnoreCase('Incomplete');
        vis.showApprove = statusOk;
        vis.showReject = statusOk;
        vis.showIncomplete =
            rec.Current_Role_Name__c == null ||
            !rec.Current_Role_Name__c.equalsIgnoreCase('Deputy Chairperson');
        return vis;
    }

    private static void assertCurrentUserIsApprover(String approverIdsCsv) {
        if (!isUserInApproverIds(approverIdsCsv, UserInfo.getUserId())) {
            throw auraError('You are not a current approver for this leave application.');
        }
    }

    @TestVisible
    private static Boolean isUserInApproverIds(String approverIds, String userId) {
        if (String.isBlank(approverIds) || String.isBlank(userId)) {
            return false;
        }
        String userId15 = userId.length() >= 15 ? userId.substring(0, 15) : userId;
        String normalized = approverIds.replace('\n', ';').replace(',', ';');
        for (String token : normalized.split(';')) {
            if (String.isBlank(token)) {
                continue;
            }
            String idToken = token.trim();
            if (idToken.equals(userId) || idToken.equals(userId15)) {
                return true;
            }
            if (idToken.startsWith(userId15) || userId.startsWith(idToken)) {
                return true;
            }
        }
        return false;
    }

    // ================= MAIN APPROVAL METHOD =================
    @AuraEnabled
    public static void processLeaveAction(
        Id leaveId,
        String decision,
        String actionType,
        Boolean routeToDeputy,
        String remarks
    ){
        try{

            Boolean sendToDeputy         = false;
            List<Id> deputyUserIds       = new List<Id>();

            Leave_Application__c leaveRec = [
                SELECT Id, Status__c, Current_Role_Name__c, Current_Approver_User__c,
                       Current_Approver_Ids__c, Route_to_Deputy__c,
                       Batch_Enrollment__c, Term_Enrollment__c
                FROM Leave_Application__c
                WHERE Id = :leaveId
                LIMIT 1
            ];

            // Programme of the applying student — drives every approver lookup below.
            Id leaveProgramId = LeaveApproverResolver.resolveProgramId(leaveRec);

            // Only users listed in Current_Approver_Ids__c may process actions
            assertCurrentUserIsApprover(leaveRec.Current_Approver_Ids__c);

            // 🔥 HANDLE INCOMPLETE (DO NOT FORWARD) — top-level catch before work item
            if(decision == 'INCOMPLETE'){

                if(String.isNotBlank(remarks)){
                    leaveRec.Approver_Remarks__c = remarks;
                }

                leaveRec.Status__c         = 'Incomplete';
                leaveRec.Route_to_Deputy__c = false;

                update leaveRec;
                // Permanent Incomplete history row (never overwrites past Incomplete rows)
                LeaveApprovalHistoryController.createIncompleteHistory(
                    leaveId,
                    leaveRec.Current_Role_Name__c + ' Verification',
                    UserInfo.getUserId(),
                    remarks
                );
                return;
            }

            // ================= GET WORK ITEM =================
            // ✅ Find work item by leaveId only — any assigned approver can process
            List<ProcessInstanceWorkitem> workItems = [
                SELECT Id, ActorId
                FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :leaveId
                AND ProcessInstance.Status = 'Pending'
            ];

            if(workItems.isEmpty()){
                throw auraError('No pending approval found for this record.');
            }

            // ✅ Find work item belonging to current user if exists, else take first
            ProcessInstanceWorkitem workItem = workItems[0];
            for(ProcessInstanceWorkitem w : workItems){
                if(w.ActorId == UserInfo.getUserId()){
                    workItem = w;
                    break;
                }
            }

            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItem.Id);

            if(String.isNotBlank(remarks)){
    req.setComments(remarks);
}

            // ================= PROGRAMME OFFICE =================
            if(leaveRec.Current_Role_Name__c == 'Programme Office'){

                if(decision != 'Not Approved'){

                    req.setAction('Approve');

                    // ✅ GET Managers OF THIS STUDENT'S PROGRAMME ONLY
                    List<Id> managerUserIds = LeaveApproverResolver.getApprovers(
                        leaveProgramId,
                        'Manager'
                    );

                    if(managerUserIds.isEmpty()){
                        throw auraError('No Manager found for this programme.');
                    }

                    // ✅ BUILD list of all Manager IDs
                    List<String> managerIdStrings = new List<String>();
                    for(Id managerUserId : managerUserIds){
                        managerIdStrings.add(String.valueOf(managerUserId));
                    }

                    req.setNextApproverIds(managerUserIds);

                    leaveRec.Current_Role_Name__c      = 'Manager';
                    leaveRec.Current_Approver_User__c  = managerUserIds[0]; // first for display
                    leaveRec.Current_Approver_Ids__c   = String.join(managerIdStrings, ';'); // ✅ all manager IDs
                    leaveRec.Status__c                 = 'Submitted - Pending Approval';
                    leaveRec.Route_to_Deputy__c        = false;

                    LeaveApprovalHistoryController.markStepDecided(leaveId, 'Programme Office Verification', 'Approved', UserInfo.getUserId(), remarks);
                    LeaveApprovalHistoryController.createPendingStep(leaveId, 'Manager Verification', managerUserIds);
                } else {

                    req.setAction('Reject');

                    leaveRec.Status__c                 = 'Rejected';
                    leaveRec.Current_Role_Name__c      = null;
                    leaveRec.Current_Approver_User__c  = null;
                    leaveRec.Current_Approver_Ids__c   = null; // ✅ clear on rejection
                    leaveRec.Route_to_Deputy__c        = false;

                    LeaveApprovalHistoryController.markStepDecided(leaveId, 'Programme Office Verification', 'Rejected', UserInfo.getUserId(), remarks);
                }
            }

            // ================= MANAGER =================
            else if(leaveRec.Current_Role_Name__c == 'Manager'){

                // 🔥 HANDLE INCOMPLETE
                if(decision == 'INCOMPLETE'){

                    if(String.isNotBlank(remarks)){
                        leaveRec.Approver_Remarks__c = remarks;
                    }

                    leaveRec.Status__c         = 'Incomplete';
                    leaveRec.Route_to_Deputy__c = false;

                    update leaveRec;
                    LeaveApprovalHistoryController.createIncompleteHistory(
                        leaveId,
                        'Manager Verification',
                        UserInfo.getUserId(),
                        remarks
                    );
                    return;
                }

                // 🔥 Decide ACTION
                if(actionType == 'Reject'){
                    req.setAction('Reject');
                } else {
                    req.setAction('Approve');
                }

                // 🔴 REJECT FLOW
                if(req.getAction() == 'Reject'){

                    // ✅ SAVE REJECT REMARK
                    if(String.isNotBlank(remarks)){
                        leaveRec.Approver_Remarks__c = remarks;
                    }

                    if(decision == 'Not Eligible for Makeup'){
                        leaveRec.Status__c = 'Rejected - Not Eligible for Makeup';
                    } else {
                        leaveRec.Status__c = 'Rejected';
                    }

                    leaveRec.Current_Role_Name__c      = null;
                    leaveRec.Current_Approver_User__c  = null;
                    leaveRec.Current_Approver_Ids__c   = null; // ✅ clear on rejection
                    leaveRec.Route_to_Deputy__c        = false;

                    LeaveApprovalHistoryController.markStepDecided(leaveId, 'Manager Verification', leaveRec.Status__c, UserInfo.getUserId(), remarks);
                }

                // 🟢 APPROVE FLOW
                else{

                    leaveRec.Route_to_Deputy__c = routeToDeputy;

                    // 👉 SEND TO DEPUTY (NOT FINAL)
                    if(routeToDeputy){

                        // ✅ GET Deputy Chairpersons OF THIS STUDENT'S PROGRAMME ONLY
                        deputyUserIds = LeaveApproverResolver.getApprovers(
                            leaveProgramId,
                            'Deputy Chairperson'
                        );

                        if(deputyUserIds.isEmpty()){
                            throw auraError('No Deputy found for this programme.');
                        }

                        // ✅ BUILD list of all Deputy IDs
                        List<String> deputyIdStrings = new List<String>();
                        for(Id deputyUserId : deputyUserIds){
                            deputyIdStrings.add(String.valueOf(deputyUserId));
                        }

                        sendToDeputy = true;

                        req.setNextApproverIds(deputyUserIds);

                        leaveRec.Current_Approver_User__c  = deputyUserIds[0]; // first for display
                        leaveRec.Current_Approver_Ids__c   = String.join(deputyIdStrings, ';'); // ✅ all deputy IDs
                        leaveRec.Current_Role_Name__c      = 'Deputy Chairperson';
                        leaveRec.Status__c                 = 'Submitted - Pending Approval';
                       
                        LeaveApprovalHistoryController.markStepDecided(leaveId, 'Manager Verification', 'Approved', UserInfo.getUserId(), remarks);
                        LeaveApprovalHistoryController.createPendingStep(leaveId, 'Deputy Chairperson Verification', deputyUserIds);
                        // ❌ DO NOT SAVE REMARK (NOT FINAL)
                    }
                    // 👉 FINAL APPROVAL (NO DEPUTY)
                    else{

                        // ✅ SAVE FINAL MANAGER REMARK
                        if(String.isNotBlank(remarks)){
                            leaveRec.Approver_Remarks__c = remarks;
                        }

                        leaveRec.Current_Role_Name__c      = null;
                        leaveRec.Current_Approver_User__c  = null;
                        leaveRec.Current_Approver_Ids__c   = null; // ✅ clear on final approval

                        if(decision == 'Eligible for Makeup'){
                            leaveRec.Status__c = 'Approved - Eligible for Makeup';
                        }
                        else if(decision == 'Not Eligible for Makeup'){
                            leaveRec.Status__c = 'Approved - Not Eligible for Makeup';
                        }
                        else{
                            leaveRec.Status__c = 'Approved';
                        }
                        LeaveApprovalHistoryController.markStepDecided(leaveId, 'Manager Verification', leaveRec.Status__c, UserInfo.getUserId(), remarks);
                    }
                }
            }

            // ================= DEPUTY CHAIRPERSON =================
            else if(leaveRec.Current_Role_Name__c == 'Deputy Chairperson'){

                // 🔥 HANDLE INCOMPLETE
                if(decision == 'INCOMPLETE'){

                    if(String.isNotBlank(remarks)){
                        leaveRec.Approver_Remarks__c = remarks;
                    }

                    leaveRec.Status__c         = 'Incomplete';
                    leaveRec.Route_to_Deputy__c = false;

                    update leaveRec;
                    LeaveApprovalHistoryController.createIncompleteHistory(
                        leaveId,
                        'Deputy Chairperson Verification',
                        UserInfo.getUserId(),
                        remarks
                    );
                    return;
                }

                // 🔥 Decide ACTION
                if(actionType == 'Reject'){
                    req.setAction('Reject');
                } else {
                    req.setAction('Approve');
                }

                // 🔴 REJECT FLOW
                if(req.getAction() == 'Reject'){

                    // ✅ SAVE REJECT REMARK
                    if(String.isNotBlank(remarks)){
                        leaveRec.Approver_Remarks__c = remarks;
                    }

                    if(decision == 'Not Eligible for Makeup'){
                        leaveRec.Status__c = 'Rejected - Not Eligible for Makeup';
                    } else {
                        leaveRec.Status__c = 'Rejected';
                    }
                }

                // 🟢 APPROVE FLOW (FINAL)
                else{

                    // ✅ SAVE FINAL DEPUTY REMARK
                    if(String.isNotBlank(remarks)){
                        leaveRec.Approver_Remarks__c = remarks;
                    }

                    if(decision == 'Eligible for Makeup'){
                        leaveRec.Status__c = 'Approved - Eligible for Makeup';
                    }
                    else if(decision == 'Not Eligible for Makeup'){
                        leaveRec.Status__c = 'Approved - Not Eligible for Makeup';
                    }
                    else{
                        leaveRec.Status__c = 'Approved';
                    }
                }
                LeaveApprovalHistoryController.markStepDecided(leaveId, 'Deputy Chairperson Verification', leaveRec.Status__c, UserInfo.getUserId(), remarks);
                // ✅ FINAL CLEANUP
                leaveRec.Current_Role_Name__c      = null;
                leaveRec.Current_Approver_User__c  = null;
                leaveRec.Current_Approver_Ids__c   = null; // ✅ clear on deputy final action
                leaveRec.Route_to_Deputy__c        = false;
            }

            // ================= SAVE LEAVE RECORD =================
            update leaveRec;

            // ✅ PROCESS APPROVAL WORK ITEM
            Approval.process(req);

            // ✅ FETCH UPDATED DATA FOR EMAIL
            Leave_Application__c updatedLeave = [
                SELECT Id, Name, Status__c, Reason__c, Approver_Remarks__c, OwnerId
                FROM Leave_Application__c
                WHERE Id = :leaveId
            ];

            String status = updatedLeave.Status__c != null ? updatedLeave.Status__c.toLowerCase() : '';

            Boolean isFinalApproved =
                status == 'approved' ||
                status.contains('approved - eligible') ||
                status.contains('approved - not eligible');

            Boolean isRejected   = status.contains('rejected');
            Boolean isIncomplete = status.contains('incomplete');

            if(isFinalApproved || isRejected || isIncomplete){
                sendLeaveEmail(updatedLeave);
            }

            // ✅ ROUTE TO DEPUTY ASYNC — pass all deputy IDs as CSV string
            if(sendToDeputy && !deputyUserIds.isEmpty()){
                List<String> deputyIdStrings = new List<String>();
                for(Id dId : deputyUserIds){
                    deputyIdStrings.add(String.valueOf(dId));
                }
                submitToDeputyAsync(leaveId, String.join(deputyIdStrings, ','));
            }

        } catch(AuraHandledException ahe){
            // Re-throw as-is so LWC receives the real message (e.g. "No Manager found").
            // Wrapping with new AuraHandledException(e.getMessage()) returns "Script-thrown exception".
            throw ahe;
        } catch(Exception e){
            throw auraError(e.getMessage());
        }
    }

    // ================= STUDENT DASHBOARD =================
    @AuraEnabled(cacheable=true)
    public static List<Leave_Application__c> getStudentLeaves(Id userId){

        return [
            SELECT Id,
                   Name,
                   Status__c,
                   Current_Role_Name__c,
                   Reason__c,
                   Approver_Remarks__c,
                   Start_Date__c,
                   End_Date__c,
                   Leave_Type__c,
                   CreatedDate
            FROM Leave_Application__c
            WHERE CreatedById = :userId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }

    // ================= GET FILES =================
    @AuraEnabled
    public static List<Map<String, String>> getFilesWithData(Id recordId){

        List<Map<String, String>> files = new List<Map<String, String>>();

        for(ContentDocumentLink cdl : [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ]){

            ContentVersion cv = [
                SELECT VersionData, FileExtension
                FROM ContentVersion
                WHERE Id = :cdl.ContentDocument.LatestPublishedVersionId
                LIMIT 1
            ];

            String base64Data = EncodingUtil.base64Encode(cv.VersionData);

            files.add(new Map<String, String>{
                'id'        => cdl.ContentDocumentId,
                'name'      => cdl.ContentDocument.Title,
                'extension' => cv.FileExtension,
                'data'      => base64Data
            });
        }

        return files;
    }

    // ================= UPDATE LEAVE =================
    @AuraEnabled
    public static void updateLeave(
        Id leaveId,
        Date startDate,
        Date endDate,
        String leaveType,
        String remarks
    ){
        Leave_Application__c leaveRec = [
            SELECT Id, Status__c, Current_Role_Name__c, Batch_Enrollment__c, Term_Enrollment__c
            FROM Leave_Application__c
            WHERE Id = :leaveId
            LIMIT 1
        ];

        Boolean wasIncomplete =
            String.isNotBlank(leaveRec.Status__c) &&
            leaveRec.Status__c.equalsIgnoreCase('Incomplete');
        String roleName = leaveRec.Current_Role_Name__c;

        leaveRec.Start_Date__c  = startDate;
        leaveRec.End_Date__c    = endDate;
        leaveRec.Leave_Type__c  = leaveType;
        leaveRec.Reason__c      = remarks;
        leaveRec.Status__c      = 'Submitted - Pending Approval';

        update leaveRec;

        // After Incomplete, re-submit opens a NEW Pending history row;
        // previous Incomplete rows stay as separate permanent history.
        if (wasIncomplete && String.isNotBlank(roleName)) {
            // Re-open the pending step against this programme's approvers for that role only.
            List<Id> userIds = LeaveApproverResolver.getApprovers(
                LeaveApproverResolver.resolveProgramId(leaveRec),
                roleName
            );
            LeaveApprovalHistoryController.createPendingStep(
                leaveId,
                roleName + ' Verification',
                userIds
            );
        }
    }

    // ================= FILE UPLOAD =================
    @AuraEnabled
    public static void uploadFile(Id recordId, String fileName, String base64Data){

        try{
            Blob body = EncodingUtil.base64Decode(base64Data);

            ContentVersion cv  = new ContentVersion();
            cv.Title           = fileName;
            cv.PathOnClient    = fileName;
            cv.VersionData     = body;
            insert cv;

            // Get ContentDocumentId
            cv = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :cv.Id
                LIMIT 1
            ];

            ContentDocumentLink link       = new ContentDocumentLink();
            link.ContentDocumentId         = cv.ContentDocumentId;
            link.LinkedEntityId            = recordId;
            link.ShareType                 = 'V';
            link.Visibility                = 'AllUsers';
            insert link;

        } catch(AuraHandledException ahe){
            throw ahe;
        } catch(Exception e){
            throw auraError('File Upload Error: ' + e.getMessage());
        }
    }

    // ================= SEND EMAIL =================
    private static void sendLeaveEmail(Leave_Application__c leaveRec){

        User u = [
            SELECT Id, Email, Name
            FROM User
            WHERE Id = :leaveRec.OwnerId
            LIMIT 1
        ];

        if(u.Email == null){
            return;
        }

        String subject = 'Leave Application Update - ' + leaveRec.Name;

        String body =
            'Hello ' + u.Name + ',\n\n' +
            'Your leave application has been updated.\n\n' +
            'Leave No: '  + leaveRec.Name      + '\n' +
            'Status: '    + leaveRec.Status__c  + '\n' +
            'Remarks: ' + (leaveRec.Approver_Remarks__c != null ? leaveRec.Approver_Remarks__c : '-') + '\n\n' +
            'Regards,\nSPJIMR';

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ u.Email });
        mail.setSubject(subject);
        mail.setPlainTextBody(body);

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }

    // ================= FUTURE METHOD — SUBMIT TO ALL DEPUTIES =================
    @future
    public static void submitToDeputyAsync(Id leaveId, String deputyUserIdsCSV){
        try{
            // ✅ Convert CSV string back to List<Id>
            List<Id> deputyIds = new List<Id>();
            for(String s : deputyUserIdsCSV.split(',')){
                if(String.isNotBlank(s)){
                    deputyIds.add((Id)s.trim());
                }
            }

            if(deputyIds.isEmpty()){
                return;
            }

            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(leaveId);
            // ✅ ALL deputies receive the work item
            req.setNextApproverIds(deputyIds);
            Approval.process(req);

        } catch(Exception e){
            // Best-effort async submit: the leave is already routed to the deputies via
            // Current_Approver_Ids__c, so a failed work-item creation must not fail the job.
            lastDeputySubmitError = e.getMessage();
        }
    }
}