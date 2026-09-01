/**
 * Supports the student-facing Deferment Request portal component.
 *
 * Design assumption (per requirements): a Deferment_Request__c record is
 * CREATED by the Programme Manager (see BreakInStudyController.createDefermentRequest),
 * with Status__c = 'Deferment Form Enabled', a fee, and a valid Break_Start_Date_Time__c /
 * Break_End_Date_Time__c window. The student never creates a new record — they only
 * ever UPDATE that same record when they submit the portal form (reason + files),
 * moving Status__c to 'Form Submitted'.
 *
 * Declared `without sharing`: this class enforces its own manual authorization
 * (matching Deferment_Request__c.Account__c against the running portal user's
 * resolved Account Id) rather than relying on org-wide sharing rules, since the
 * record is owned internally (by the Programme Manager) but needs to be visible
 * to the student it belongs to.
 */
public without sharing class DefermentRequestController {

    public class DefermentRequestWrapper {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public Decimal fee;
        @AuraEnabled public Datetime breakStartDateTime;
        @AuraEnabled public Datetime breakEndDateTime;
        @AuraEnabled public Datetime submissionDate;
        @AuraEnabled public String windowStatus;
        @AuraEnabled public String windowMessage;
        @AuraEnabled public String l1Remark;
        @AuraEnabled public String l2Remark;
    }

   public class ApprovalHistoryWrapper {
    @AuraEnabled public String stepId;
    @AuraEnabled public String stepName;
    @AuraEnabled public Datetime actionDate;
    @AuraEnabled public String status;
    @AuraEnabled public String assignedTo;
    @AuraEnabled public String approvedBy;
    @AuraEnabled public String remarks;
}

public class DefermentFileWrapper {
    @AuraEnabled public String documentType;
    @AuraEnabled public String base64Data;
    @AuraEnabled public String fileName;
}

public class SubmitDefermentRequestWrapper {
    @AuraEnabled public Id defermentRequestId;
    @AuraEnabled public String reason;
    @AuraEnabled public List<DefermentFileWrapper> files;
}
   /* @AuraEnabled
    public static DefermentRequestWrapper getActiveDefermentRequest() {
        Id accountId = getCurrentStudentAccountId();

        DefermentRequestWrapper wrapper = new DefermentRequestWrapper();

        if (accountId == null) {
            return wrapper;
        }

        Datetime now = Datetime.now();

        List<Deferment_Request__c> requests = [
            SELECT Id,
                   Name,
                   Account__c,
                   Status__c,
                   Reason_for_Deferment__c,
                   Deferment_Application_Fee__c,
                   Break_Start_Date_Time__c,
                   Break_End_Date_Time__c,
                   Student_Submission_Date__c
            FROM Deferment_Request__c
            WHERE Account__c = :accountId
            AND (
                Status__c != 'Deferment Form Enabled'
                OR (
                    Status__c = 'Deferment Form Enabled'
                    AND Break_Start_Date_Time__c <= :now
                    AND Break_End_Date_Time__c >= :now
                )
            )
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (requests.isEmpty()) {
            return wrapper;
        }

        Deferment_Request__c req = requests[0];
        wrapper.recordId = req.Id;
        wrapper.requestNumber = req.Name;
        wrapper.status = req.Status__c;
        wrapper.reason = req.Reason_for_Deferment__c;
        wrapper.fee = req.Deferment_Application_Fee__c;
        wrapper.breakStartDateTime = req.Break_Start_Date_Time__c;
        wrapper.breakEndDateTime = req.Break_End_Date_Time__c;
        wrapper.submissionDate = req.Student_Submission_Date__c;

        return wrapper;
    }*/

    @AuraEnabled
public static DefermentRequestWrapper getActiveDefermentRequest() {

    Id accountId = getCurrentStudentAccountId();

    DefermentRequestWrapper wrapper =
        new DefermentRequestWrapper();

    if (accountId == null) {
        return wrapper;
    }

    Datetime now = Datetime.now();

    List<Deferment_Request__c> requests = [
        SELECT Id,
               Name,
               Account__c,
               Status__c,
               Reason_for_Deferment__c,
               Approval_Status__c,
               Deferment_Application_Fee__c,
               Break_Start_Date_Time__c,
               Break_End_Date_Time__c,
               Student_Submission_Date__c
        FROM Deferment_Request__c
        WHERE Account__c = :accountId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];

    if (requests.isEmpty()) {
        return wrapper;
    }

    Deferment_Request__c req = requests[0];

    wrapper.recordId =
        req.Id;

    wrapper.requestNumber =
        req.Name;

    wrapper.status =
        req.Status__c;

    wrapper.approvalStatus =
        req.Approval_Status__c;    

    wrapper.reason =
        req.Reason_for_Deferment__c;

    wrapper.fee =
        req.Deferment_Application_Fee__c;

    wrapper.breakStartDateTime =
        req.Break_Start_Date_Time__c;

    wrapper.breakEndDateTime =
        req.Break_End_Date_Time__c;

    wrapper.submissionDate =
        req.Student_Submission_Date__c;

    Map<String, String> approvalRemarks =
    getApprovalRemarks(req.Id);

wrapper.l1Remark =
    approvalRemarks.get('L1');

wrapper.l2Remark =
    approvalRemarks.get('L2');

        // ---------------------------------------------------------
    // Determine Deferment Request Window Status
    // ---------------------------------------------------------

    if (
    req.Status__c == 'Pending Chairperson\'s Approval' ||
    req.Status__c == 'Pending Dean\'s / AD\'s Approval'
) {
    wrapper.windowStatus = 'SUBMITTED';

    wrapper.windowMessage =
        'Your Deferment Request has been submitted and is currently under approval.';
}
else if (req.Status__c == 'Rejoining Details') {

    wrapper.windowStatus = 'APPROVED';

    wrapper.windowMessage =
        'Your Deferment Request has been approved.';

}
else if (req.Status__c == 'Deferment Form Enabled') {

    if (
        req.Break_Start_Date_Time__c != null &&
        now < req.Break_Start_Date_Time__c
    ) {

        wrapper.windowStatus = 'NOT_STARTED';

        wrapper.windowMessage =
            'Your Deferment Request window is not open yet. ' +
            'Please wait until the window opens.';

    }

    else if (req.Approval_Status__c == 'Rejected'&&(req.Break_End_Date_Time__c == null || now <= req.Break_End_Date_Time__c)
    ) {

        wrapper.windowStatus = 'REOPENED';

        wrapper.windowMessage =
           'Your Deferment Request has been reopened after rejection. ' +
            'Please check the rejection remarks in the tracker below, update your request, and resubmit.';
    }
    else if (
        req.Break_End_Date_Time__c != null &&
        now > req.Break_End_Date_Time__c
    ) {

        wrapper.windowStatus = 'EXPIRED';

        wrapper.windowMessage =
            'Your Deferment Request window has expired. ' +
            'Please contact the Programme Manager to enable the window again.';

    }
    else if (
        req.Break_Start_Date_Time__c != null &&
        req.Break_End_Date_Time__c != null &&
        now >= req.Break_Start_Date_Time__c &&
        now <= req.Break_End_Date_Time__c
    ) {

        wrapper.windowStatus = 'OPEN';

        wrapper.windowMessage =
            'Your Deferment Request window is currently open. ' +
            'You can submit your request until ' +
            req.Break_End_Date_Time__c.format('dd MMM yyyy, hh:mm a') +
            '.';
    }
}
else {
    // Any status past "Deferment Form Enabled" (No Dues Process
    // Initiated, No Dues Process Complete, Access Removal Complete,
    // Deferment Process Complete, Pending Re-enrollment, etc.) —
    // no window banner needed, the tracker table already shows status.
    wrapper.windowStatus = 'SUBMITTED';
    wrapper.windowMessage = '';
}

    return wrapper;
}
/*
 * =====================================================================
 * NEW METHOD — add to DefermentRequestController
 * Returns documents already attached to this record so the LWC can
 * show them as "already uploaded" instead of forcing re-upload.
 * =====================================================================
 */
@AuraEnabled(cacheable=true)
public static List<Map<String, String>> getUploadedDocuments(Id recordId) {

    List<Map<String, String>> result = new List<Map<String, String>>();

    if (recordId == null) {
        return result;
    }

    List<ContentDocumentLink> links = [
        SELECT ContentDocumentId,
               ContentDocument.Title,
               ContentDocument.FileExtension,
               ContentDocument.LatestPublishedVersionId,
               ContentDocument.CreatedDate
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :recordId
        WITH SYSTEM_MODE
        ORDER BY ContentDocument.CreatedDate DESC
    ];

    for (ContentDocumentLink link : links) {

        String fullTitle = link.ContentDocument.Title;
        String documentType = fullTitle;
        String fileName = fullTitle;

        Integer sepIndex = fullTitle.indexOf(' - ');
        if (sepIndex > -1) {
            documentType = fullTitle.substring(0, sepIndex);
            fileName = fullTitle.substring(sepIndex + 3);
        }

        Map<String, String> doc = new Map<String, String>();
        doc.put('documentType', documentType);
        doc.put('fileName', fileName);
        doc.put('contentDocumentId', link.ContentDocumentId);
        doc.put('contentVersionId', link.ContentDocument.LatestPublishedVersionId);
        doc.put('fileExtension', link.ContentDocument.FileExtension);

        result.add(doc);
    }

    return result;
}

/**
 * Resolves the first active Programme Team Member for the given
 * programme and role.
 *
 * Chairperson level:
 *     Program_Team_Members__c.Role__c = 'Chairperson'
 *
 * Associate Dean level:
 *     Program_Team_Members__c.Role__c = 'Associate Dean'
 */
private static List<Id> getProgrammeApprovers(
    Id programmeId,
    String teamMemberRole
) {
    List<Id> approverIds = new List<Id>();

    if (programmeId == null || String.isBlank(teamMemberRole)) {
        return approverIds;
    }

    List<Program_Team_Members__c> members = [
        SELECT Id,
               User__c,
               Role__c,
               Program_Team__r.Program__c
        FROM Program_Team_Members__c
        WHERE Role__c = :teamMemberRole
        AND User__c != NULL
        AND Program_Team__r.Program__c = :programmeId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate ASC
    ];

    for (Program_Team_Members__c member : members) {
        approverIds.add(member.User__c);
    }

    return approverIds;
}

    /**
     * Updates the EXISTING Deferment_Request__c record (created by the Programme
     * Manager) with the student's reason and attaches whichever files were provided.
     * Never inserts a new record.
     *
     * File params are optional except documentsBase64/documentsFileName, matching
     * the "all fields mandatory except when fee = 0" rule already enforced client-side —
     * server-side re-validation of that is included below as a safety net.
     */
  /*  @AuraEnabled
    public static String submitDefermentRequest(
        Id defermentRequestId,
        String reason,
        String documentsBase64,
        String documentsFileName,
        String approvalEmailBase64,
        String approvalEmailFileName,
        String rejoiningAcceptanceBase64,
        String rejoiningAcceptanceFileName,
        String transactionBase64,
        String transactionFileName
    ) {*/
  @AuraEnabled
public static String submitDefermentRequest(String requestJson) {

    if (String.isBlank(requestJson)) {
        throw new AuraHandledException('No request data received by the server (requestJson was empty).');
    }

    SubmitDefermentRequestWrapper request;
    try {
        request = (SubmitDefermentRequestWrapper) JSON.deserialize(requestJson, SubmitDefermentRequestWrapper.class);
    } catch (Exception parseEx) {
        throw new AuraHandledException('Could not parse request data: ' + parseEx.getMessage());
    }

    if (request == null) {
        throw new AuraHandledException('Request data was empty after parsing.');
    }

    Id defermentRequestId = request.defermentRequestId;
    String reason = request.reason;
    

    Map<String, DefermentFileWrapper> filesByType = new Map<String, DefermentFileWrapper>();
    if (request.files != null) {
        for (DefermentFileWrapper f : request.files) {
            if (f != null && !String.isBlank(f.documentType)) {
                filesByType.put(f.documentType, f);
            }
        }
    }
    String documentsBase64 = filesByType.containsKey('Documents to Support Request') ? filesByType.get('Documents to Support Request').base64Data : null;
    String documentsFileName = filesByType.containsKey('Documents to Support Request') ? filesByType.get('Documents to Support Request').fileName : null;
    String approvalEmailBase64 = filesByType.containsKey('Approval Email (Screenshot) with Rejoining Condition') ? filesByType.get('Approval Email (Screenshot) with Rejoining Condition').base64Data : null;
String approvalEmailFileName = filesByType.containsKey('Approval Email (Screenshot) with Rejoining Condition') ? filesByType.get('Approval Email (Screenshot) with Rejoining Condition').fileName : null;
String rejoiningAcceptanceBase64 = filesByType.containsKey('Rejoining Condition Acceptance Email Screenshot') ? filesByType.get('Rejoining Condition Acceptance Email Screenshot').base64Data : null;
String rejoiningAcceptanceFileName = filesByType.containsKey('Rejoining Condition Acceptance Email Screenshot') ? filesByType.get('Rejoining Condition Acceptance Email Screenshot').fileName : null;
String transactionBase64 = filesByType.containsKey('Transaction Details (Screenshot)') ? filesByType.get('Transaction Details (Screenshot)').base64Data : null;
String transactionFileName = filesByType.containsKey('Transaction Details (Screenshot)') ? filesByType.get('Transaction Details (Screenshot)').fileName : null;

        try {
            if (defermentRequestId == null) {
                throw new AuraHandledException('No active deferment request found to update.');
            }

            if (String.isBlank(reason)) {
                throw new AuraHandledException('Reason for Deferment is required.');
            }

            Id accountId = getCurrentStudentAccountId();

            List<Deferment_Request__c> matches = [
                SELECT Id,
                       Name,
                       Account__c,
                       Programme__c,
                       Deferment_Application_Fee__c,
                       OwnerId,
                       Current_Role__c,
                       Break_Start_Date_Time__c,
           Break_End_Date_Time__c
                FROM Deferment_Request__c
                WHERE Id = :defermentRequestId
                WITH SYSTEM_MODE
                LIMIT 1
            ];

            if (matches.isEmpty() ||
                accountId == null ||
                matches[0].Account__c != accountId) {

                throw new AuraHandledException('You are not authorized to update this request.');
            }

            Deferment_Request__c req = matches[0];

            // The window's CLOSING date was checked, but not its OPENING date,
            // so a submission made before the window opened went straight
            // through to the Chairperson. The screen already tells the student
            // "your window is not open yet"; this makes that true.
            if (req.Break_Start_Date_Time__c != null &&
    Datetime.now() < req.Break_Start_Date_Time__c) {
    throw new AuraHandledException(
        'Your deferment window has not opened yet. You can submit this request from ' +
        req.Break_Start_Date_Time__c.format('dd MMM yyyy, hh:mm a') + '.'
    );
}

            if (req.Break_End_Date_Time__c != null &&
    Datetime.now() > req.Break_End_Date_Time__c) {
    throw new AuraHandledException(
        'The deferment window has closed. You can no longer submit or resubmit this request.'
    );
}
Set<String> existingDocumentTypes = new Set<String>();

for (ContentDocumentLink existingLink : [
    SELECT ContentDocument.Title
    FROM ContentDocumentLink
    WHERE LinkedEntityId = :defermentRequestId
    WITH SYSTEM_MODE
]) {
    String title = existingLink.ContentDocument.Title;
    Integer sepIndex = title.indexOf(' - ');
    existingDocumentTypes.add(
        sepIndex > -1 ? title.substring(0, sepIndex) : title
    );
}

Boolean hasExistingDocuments =
    existingDocumentTypes.contains('Documents to Support Request');

Boolean hasExistingApprovalEmail =
    existingDocumentTypes.contains('Approval Email (Screenshot) with Rejoining Condition');

Boolean hasExistingRejoiningAcceptance =
    existingDocumentTypes.contains('Rejoining Condition Acceptance Email Screenshot');

Boolean hasExistingTransaction =
    existingDocumentTypes.contains('Transaction Details (Screenshot)');

Boolean feeApplicable =
    req.Deferment_Application_Fee__c != null &&
    req.Deferment_Application_Fee__c > 0;


            if (!hasExistingDocuments &&
    (String.isBlank(documentsBase64) || String.isBlank(documentsFileName))) {
    throw new AuraHandledException('Documents to Support Request is required.');
}

if (!hasExistingApprovalEmail &&
    (String.isBlank(approvalEmailBase64) || String.isBlank(approvalEmailFileName))) {
    throw new AuraHandledException('Approval Email screenshot is required.');
}

if (!hasExistingRejoiningAcceptance &&
    (String.isBlank(rejoiningAcceptanceBase64) || String.isBlank(rejoiningAcceptanceFileName))) {
    throw new AuraHandledException('Rejoining Condition Acceptance Email screenshot is required.');
}

if (feeApplicable &&
    !hasExistingTransaction &&
    (String.isBlank(transactionBase64) || String.isBlank(transactionFileName))) {
    throw new AuraHandledException('Transaction Details screenshot is required.');
}

           /*
 * ---------------------------------------------------------
 * RESOLVE FIRST APPROVER
 *
 * Chairperson business role is configured in
 * Program_Team_Members__c as:
 *
 *     Role__c = 'Chairperson'
 * ---------------------------------------------------------
 */
Boolean isResubmissionAfterDeanRejection =
    req.Current_Role__c == 'Associate Dean' || req.Current_Role__c == 'Dean';

String resolvedRoleForRouting =
    isResubmissionAfterDeanRejection ? req.Current_Role__c : 'Chairperson';

List<Id> nextApproverIds = getProgrammeApprovers(req.Programme__c, resolvedRoleForRouting);

if (nextApproverIds.isEmpty()) {
    throw new AuraHandledException(
        'No ' + resolvedRoleForRouting + ' is configured for this Programme.'
    );
}

req.Reason_for_Deferment__c = reason;
req.Student_Submission_Date__c = Datetime.now();
req.Approval_Status__c = 'Pending';

if (isResubmissionAfterDeanRejection) {
    // Chairperson already approved earlier — skip straight back to Dean/AD.
    req.Status__c = 'Pending Dean\'s / AD\'s Approval';
    req.Current_Role__c = resolvedRoleForRouting; // unchanged, but explicit
} else {
    // First-time submission, or Chairperson rejected — start at Chairperson.
    req.Status__c = 'Pending Chairperson\'s Approval';
    req.Current_Role__c = 'Chairperson';
}

req.Current_Approver_User__c = nextApproverIds[0];

List<String> nextApproverIdStrings = new List<String>();
for (Id approverId : nextApproverIds) {
    nextApproverIdStrings.add(String.valueOf(approverId));
}
req.Current_Approver_Ids__c = String.join(nextApproverIdStrings, ',');

update as system req;


Approval.ProcessSubmitRequest submitRequest = new Approval.ProcessSubmitRequest();
submitRequest.setObjectId(req.Id);
submitRequest.setSubmitterId(req.OwnerId);
submitRequest.setNextApproverIds(nextApproverIds);
submitRequest.setProcessDefinitionNameOrId('Deferment_Request_Approval_Process');

Approval.ProcessResult submitResult = Approval.process(submitRequest);



if (!submitResult.isSuccess()) {
    throw new AuraHandledException('Failed to submit for approval.');
}

System.debug('ABOUT TO CALL NOTIFY APPROVERS. recordId=' + req.Id + ' approverIds=' + nextApproverIds + ' role=' + resolvedRoleForRouting);
// Notify whichever approver level this submission/resubmission just routed to.
// Handles first-time submission and every resubmission-after-rejection case,
// since nextApproverIds/resolvedRoleForRouting already reflect the correct level.
DefermentApprovalNotificationService.notifyApprovers(
    req.Id, nextApproverIds, resolvedRoleForRouting
);

System.debug('FINISHED CALLING NOTIFY APPROVERS');

                     List<Map<String, String>> filesToAttach = new List<Map<String, String>>();

if (!String.isBlank(documentsBase64) && !String.isBlank(documentsFileName)) {
    filesToAttach.add(new Map<String, String>{
        'base64' => documentsBase64, 'name' => documentsFileName, 'type' => 'Documents to Support Request'
    });
}

if (!String.isBlank(approvalEmailBase64) && !String.isBlank(approvalEmailFileName)) {
    filesToAttach.add(new Map<String, String>{
        'base64' => approvalEmailBase64, 'name' => approvalEmailFileName, 'type' => 'Approval Email (Screenshot) with Rejoining Condition'
    });
}

if (!String.isBlank(rejoiningAcceptanceBase64) && !String.isBlank(rejoiningAcceptanceFileName)) {
    filesToAttach.add(new Map<String, String>{
        'base64' => rejoiningAcceptanceBase64, 'name' => rejoiningAcceptanceFileName, 'type' => 'Rejoining Condition Acceptance Email Screenshot'
    });
}

if (feeApplicable &&
    !String.isBlank(transactionBase64) && !String.isBlank(transactionFileName)) {
    filesToAttach.add(new Map<String, String>{
        'base64' => transactionBase64, 'name' => transactionFileName, 'type' => 'Transaction Details (Screenshot)'
    });
}

if (!filesToAttach.isEmpty()) {
    attachFiles(defermentRequestId, filesToAttach);
}

            return req.Id;

        } catch (AuraHandledException ex) {
            throw ex;
        } /*catch (Exception ex) {
            throw new AuraHandledException('Submit failed: ' + ex.getMessage());
        }*/
        catch (Exception ex) {
    System.debug(LoggingLevel.ERROR,
        'DEFERMENT SUBMIT ERROR: ' +
        ex.getTypeName() +
        ' | ' +
        ex.getMessage() +
        ' | line=' +
        ex.getLineNumber() +
        ' | stack=' +
        ex.getStackTraceString()
    );

    throw new AuraHandledException(ex.getTypeName() + ': ' + ex.getMessage());
        }
    }

       /**
     * Bulk version of the old per-file attachFile — inserts all ContentVersions
     * in one DML, queries all their ContentDocumentIds in one SOQL, and inserts
     * all ContentDocumentLinks in one DML. Cuts a 4-file submission down from
     * up to 12 sequential DML/SOQL operations to 3, regardless of file count.
     */
   /* private static void attachFiles(Id parentId, List<Map<String, String>> files) {
        List<ContentVersion> versions = new List<ContentVersion>();

        for (Map<String, String> f : files) {
            String base64Data = f.get('base64');
            String fileName = f.get('name');
            String documentType = f.get('type');

            if (String.isBlank(base64Data) || String.isBlank(fileName)) {
                continue;
            }

            ContentVersion cv = new ContentVersion();
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.Title = documentType + ' - ' + fileName;
            // Do not associate the file with the Experience Cloud Network.
// The file will be linked to the Deferment Request below.
cv.NetworkId = null;
            cv.PathOnClient = fileName;
            versions.add(cv);
        }

        if (versions.isEmpty()) {
            return;
        }

        insert as system versions;

        Set<Id> versionIds = new Set<Id>();
        for (ContentVersion cv : versions) {
            versionIds.add(cv.Id);
        }

        Map<Id, ContentVersion> savedVersionsById = new Map<Id, ContentVersion>([
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
            WITH SYSTEM_MODE
        ]);

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : versions) {
            ContentVersion saved = savedVersionsById.get(cv.Id);
            if (saved == null || saved.ContentDocumentId == null) {
                continue;
            }

            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = saved.ContentDocumentId;
            cdl.LinkedEntityId = parentId;
            cdl.ShareType = 'V';
            cdl.Visibility = 'AllUsers';
            links.add(cdl);
        }

        if (!links.isEmpty()) {
           /* insert as system links;
           insert links;
        }
    }*/

    private static void attachFiles(
    Id parentId,
    List<Map<String, String>> files
) {
    Id networkId;

    List<Network> networks = [
        SELECT Id
        FROM Network
        LIMIT 1
    ];

    if (!networks.isEmpty()) {
        networkId = networks[0].Id;
    }

    Set<String> typesToReplace = new Set<String>();

    for (Map<String, String> f : files) {
        String type = f.get('type');
        String base64Data = f.get('base64');
        String fileName = f.get('name');

        if (!String.isBlank(type) &&
            !String.isBlank(base64Data) &&
            !String.isBlank(fileName)) {

            typesToReplace.add(type);
        }
    }

    if (!typesToReplace.isEmpty()) {
        deleteExistingDocumentsByType(parentId, typesToReplace);
    }

    List<ContentVersion> versions = new List<ContentVersion>();

    for (Map<String, String> f : files) {
        String base64Data = f.get('base64');
        String fileName = f.get('name');
        String documentType = f.get('type');

        if (String.isBlank(base64Data) || String.isBlank(fileName)) {
            continue;
        }

        ContentVersion cv = new ContentVersion();
        cv.VersionData = EncodingUtil.base64Decode(base64Data);
        cv.Title = documentType + ' - ' + fileName;
        cv.PathOnClient = fileName;
        cv.FirstPublishLocationId = parentId;

        if (networkId != null) {
            cv.NetworkId = networkId;
        }

        versions.add(cv);
    }

    if (versions.isEmpty()) {
        return;
    }

    insert as system versions;
}

private static void deleteExistingDocumentsByType(
    Id parentId,
    Set<String> typesToReplace
) {
    List<ContentDocumentLink> existingLinks = [
        SELECT ContentDocumentId,
               ContentDocument.Title
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :parentId
        WITH SYSTEM_MODE
    ];

    Set<Id> contentDocumentIdsToDelete = new Set<Id>();

    for (ContentDocumentLink link : existingLinks) {

        String title = link.ContentDocument.Title;
        Integer sepIndex = title.indexOf(' - ');
        String docType = sepIndex > -1 ? title.substring(0, sepIndex) : title;

        if (typesToReplace.contains(docType)) {
            contentDocumentIdsToDelete.add(link.ContentDocumentId);
        }
    }

    if (contentDocumentIdsToDelete.isEmpty()) {
        return;
    }

    List<ContentDocument> docsToDelete = [
        SELECT Id
        FROM ContentDocument
        WHERE Id IN :contentDocumentIdsToDelete
        WITH SYSTEM_MODE
    ];

    delete as system docsToDelete;
}

@AuraEnabled
public static Map<String, String> getApprovalRemarks(Id recordId) {

    Map<String, String> remarks = new Map<String, String>{
        'L1' => '',
        'L2' => ''
    };

    if (recordId == null) {
        return remarks;
    }

    // NEW: need the record's Programme__c to scope the role lookup correctly
    List<Deferment_Request__c> requestList = [
        SELECT Id, Programme__c
        FROM Deferment_Request__c
        WHERE Id = :recordId
        WITH SYSTEM_MODE
        LIMIT 1
    ];

    if (requestList.isEmpty()) {
        return remarks;
    }

    Id programmeId = requestList[0].Programme__c;

    List<ProcessInstanceStep> steps = [
        SELECT Id, StepStatus, Comments, ActorId, Actor.Name, CreatedDate
        FROM ProcessInstanceStep
        WHERE ProcessInstance.TargetObjectId = :recordId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate ASC
    ];

    Set<Id> actorIds = new Set<Id>();
    for (ProcessInstanceStep step : steps) {
        if (step.ActorId != null) {
            actorIds.add(step.ActorId);
        }
    }

    if (actorIds.isEmpty()) {
        return remarks;
    }

    // FIXED: scoped to THIS Programme, matching getApprovalHistory's logic
    List<Program_Team_Members__c> members = [
        SELECT User__c, Role__c
        FROM Program_Team_Members__c
        WHERE User__c IN :actorIds
        AND Role__c IN ('Chairperson', 'Associate Dean', 'Dean')
        AND Program_Team__r.Program__c = :programmeId
        WITH SYSTEM_MODE
    ];

    Map<Id, String> userRoleMap = new Map<Id, String>();
    for (Program_Team_Members__c member : members) {
        userRoleMap.put(member.User__c, member.Role__c);
    }

    for (ProcessInstanceStep step : steps) {
        if (String.isBlank(step.Comments)) {
            continue;
        }

        String role = userRoleMap.get(step.ActorId);

        if (role == 'Chairperson') {
            remarks.put('L1', step.Comments);
        } else if (role == 'Associate Dean' || role == 'Dean') {
            remarks.put('L2', step.Comments);
        }
    }

    return remarks;
}
    /**
     * Confirmed relationship: portal User -> Contact -> Contact.AccountId gives the
     * student's Account, matched directly against Deferment_Request__c.Account__c
     * (which BreakInStudyController populates from ProgramCohortMember.ProgramEnrolleeId).
     */
    private static Id getCurrentStudentAccountId() {
        List<User> users = [
            SELECT AccountId, ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if (users.isEmpty()) {
            return null;
        }

        if (users[0].AccountId != null) {
            return users[0].AccountId;
        }

        if (users[0].Contact != null) {
            return users[0].Contact.AccountId;
        }

        return null;
    }

    private static String getProgrammeApproverNames(
    Id programmeId,
    String teamMemberRole
) {
    if (programmeId == null || String.isBlank(teamMemberRole)) {
        return '';
    }

    List<Program_Team_Members__c> members = [
        SELECT User__c,
               User__r.Name,
               Role__c
        FROM Program_Team_Members__c
        WHERE Role__c = :teamMemberRole
        AND User__c != null
        AND Program_Team__r.Program__c = :programmeId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate ASC
    ];

    List<String> names = new List<String>();

    for (Program_Team_Members__c member : members) {
        if (member.User__r != null &&
            !String.isBlank(member.User__r.Name)) {

            names.add(member.User__r.Name);
        }
    }

    return String.join(names, ', ');
}

  @AuraEnabled(cacheable=true)
public static List<ApprovalHistoryWrapper> getApprovalHistory(Id recordId) {

    List<ApprovalHistoryWrapper> history = new List<ApprovalHistoryWrapper>();

    if (recordId == null) {
        return history;
    }

    Deferment_Request__c request = [
        SELECT Id,
               CreatedDate,
               Student_Submission_Date__c,
               Status__c,
               Current_Role__c,
               Account__c,
               Account__r.Name,
               Programme__c
        FROM Deferment_Request__c
        WHERE Id = :recordId
        WITH SYSTEM_MODE
        LIMIT 1
    ];

    String studentName = 'Student';

    if (request.Account__r != null && !String.isBlank(request.Account__r.Name)) {
        studentName = request.Account__r.Name;
    }

    String chairpersonNames = getProgrammeApproverNames(request.Programme__c, 'Chairperson');
    String associateDeanNames = getProgrammeApproverNames(request.Programme__c, 'Associate Dean');
    String deanNames = getProgrammeApproverNames(request.Programme__c, 'Dean');

  /*  List<String> level2Names = new List<String>();
    if (!String.isBlank(associateDeanNames)) level2Names.add(associateDeanNames);
    if (!String.isBlank(deanNames)) level2Names.add(deanNames);
    String level2ApproverNames = String.join(level2Names, ', ');*/
    // Mirrors the exact same precedence rule as
    // DefermentApprovalController.approveChairperson(): Associate Dean is
    // used whenever present on the Programme Team; Dean is only ever the
    // fallback when no Associate Dean exists. A request is NEVER routed to
    // both simultaneously, so the history display must not show both names
    // combined even if both roles happen to be configured on the team.
    String level2ApproverNames;
    String level2RoleLabel;

    if (!String.isBlank(associateDeanNames)) {
    level2ApproverNames = associateDeanNames;
    level2RoleLabel = 'Associate Dean';
    } else {
    level2ApproverNames = deanNames;
    level2RoleLabel = 'Dean';
}

    /*
     * ---------------------------------------------------------
     * STEP 1 - DEFERMENT REQUEST SUBMITTED
     * ---------------------------------------------------------
     */
    ApprovalHistoryWrapper submittedStep = new ApprovalHistoryWrapper();
    submittedStep.stepId = 'SUBMITTED_' + recordId;
    submittedStep.stepName = 'Deferment Request Submitted';
    submittedStep.status = 'Submitted';
    submittedStep.assignedTo = studentName;
    submittedStep.approvedBy = '';
    submittedStep.remarks = '-';
    submittedStep.actionDate =
        request.Student_Submission_Date__c != null ? request.Student_Submission_Date__c : request.CreatedDate;

    history.add(submittedStep);

    /*
     * ---------------------------------------------------------
     * GET COMPLETED APPROVAL STEPS (across all rounds)
     * ---------------------------------------------------------
     */
    Id latestProcessInstanceId;
    List<ProcessInstance> latestInstances = [
        SELECT Id
        FROM ProcessInstance
        WHERE TargetObjectId = :recordId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate DESC
        LIMIT 1
    ];
    if (!latestInstances.isEmpty()) {
        latestProcessInstanceId = latestInstances[0].Id;
    }

    List<ProcessInstanceStep> approvalSteps = [
        SELECT Id, StepStatus, Comments, ActorId, Actor.Name, CreatedDate
        FROM ProcessInstanceStep
        WHERE ProcessInstance.TargetObjectId = :recordId
        WITH SYSTEM_MODE
        ORDER BY CreatedDate ASC
    ];

    Set<Id> chairpersonUserIds = new Set<Id>();
    Set<Id> level2UserIds = new Set<Id>();

    for (Program_Team_Members__c member : [
        SELECT User__c, Role__c
        FROM Program_Team_Members__c
        WHERE User__c != null
        AND Program_Team__r.Program__c = :request.Programme__c
        AND Role__c IN ('Chairperson', 'Associate Dean', 'Dean')
        WITH SYSTEM_MODE
    ]) {
        if (member.Role__c == 'Chairperson') {
            chairpersonUserIds.add(member.User__c);
        } else {
            level2UserIds.add(member.User__c);
        }
    }

    // "Last action wins" per role slot — a resubmission's new round replaces
    // the old rejected row for that same role instead of adding a new one.
    ApprovalHistoryWrapper chairpersonItem;
    ApprovalHistoryWrapper deanItem;

    for (ProcessInstanceStep step : approvalSteps) {

        if (step.StepStatus == 'Started' || step.StepStatus == 'Submitted') {
            continue;
        }

        ApprovalHistoryWrapper item = new ApprovalHistoryWrapper();
        item.stepId = String.valueOf(step.Id);
        item.actionDate = step.CreatedDate;
        item.status = step.StepStatus;
        item.approvedBy = step.Actor != null ? step.Actor.Name : '';
        item.remarks = String.isBlank(step.Comments) ? '-' : step.Comments;

        if (step.ActorId != null && chairpersonUserIds.contains(step.ActorId)) {

            item.stepName = 'Chairperson Verification';
            item.assignedTo = String.isBlank(chairpersonNames) ? 'Chairperson' : chairpersonNames;
            chairpersonItem = item;

        } else if (step.ActorId != null && level2UserIds.contains(step.ActorId)) {

    item.stepName = level2RoleLabel + ' Verification';
    item.assignedTo = String.isBlank(level2ApproverNames) ? level2RoleLabel : level2ApproverNames;
    deanItem = item;
        }
    }

    /*
     * ---------------------------------------------------------
     * GET CURRENT PENDING APPROVAL
     * ---------------------------------------------------------
     */
        List<ProcessInstanceWorkitem> workItems = new List<ProcessInstanceWorkitem>();
    if (latestProcessInstanceId != null) {
        workItems = [
            SELECT Id, ActorId, Actor.Name, CreatedDate
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstanceId = :latestProcessInstanceId
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];
    }

    if (!workItems.isEmpty()) {

        ProcessInstanceWorkitem currentWorkItem = workItems[0];

        ApprovalHistoryWrapper pendingItem = new ApprovalHistoryWrapper();
        pendingItem.stepId = 'PENDING_' + currentWorkItem.Id;
        pendingItem.status = 'Pending';
        pendingItem.approvedBy = '';
        pendingItem.remarks = '-';
        pendingItem.actionDate = currentWorkItem.CreatedDate;
        if (request.Current_Role__c == 'Associate Dean' || request.Current_Role__c == 'Dean') {

            pendingItem.stepName = level2RoleLabel + ' Verification';
    pendingItem.assignedTo =
        String.isBlank(level2ApproverNames) ? level2RoleLabel : level2ApproverNames;

            // CHANGED: only show Pending if this level has no prior completed action yet.
            // If it was previously Rejected, keep showing that row as-is.
            if (deanItem == null) {
                deanItem = pendingItem;
            }

        } else {

            pendingItem.stepName = 'Chairperson Verification';
            pendingItem.assignedTo =
                String.isBlank(chairpersonNames) ? 'Chairperson' : chairpersonNames;

            // CHANGED: only show Pending if this level has no prior completed action yet.
            // If it was previously Rejected, keep showing that row as-is.
            if (chairpersonItem == null) {
                chairpersonItem = pendingItem;
            }
        }
    }

    Boolean chairpersonRejected = chairpersonItem != null && chairpersonItem.status == 'Rejected';

    if (chairpersonItem != null) {
        history.add(chairpersonItem);
    }

    if (deanItem != null && !chairpersonRejected) {
        history.add(deanItem);
    }

    return history;
}


}