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
        @AuraEnabled public Decimal fee;
        @AuraEnabled public Datetime breakStartDateTime;
        @AuraEnabled public Datetime breakEndDateTime;
        @AuraEnabled public Datetime submissionDate;
    }

    @AuraEnabled
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
    @AuraEnabled
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
    ) {
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
                       Account__c,
                       Deferment_Application_Fee__c
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

            Boolean feeApplicable =
                req.Deferment_Application_Fee__c != null &&
                req.Deferment_Application_Fee__c > 0;

            if (String.isBlank(documentsBase64) ||
                String.isBlank(documentsFileName)) {
                throw new AuraHandledException('Documents to Support Request is required.');
            }

            if (String.isBlank(approvalEmailBase64) ||
                String.isBlank(approvalEmailFileName)) {
                throw new AuraHandledException('Approval Email screenshot is required.');
            }

            if (String.isBlank(rejoiningAcceptanceBase64) ||
                String.isBlank(rejoiningAcceptanceFileName)) {
                throw new AuraHandledException('Rejoining Condition Acceptance Email screenshot is required.');
            }

            if (feeApplicable &&
                (String.isBlank(transactionBase64) ||
                 String.isBlank(transactionFileName))) {

                throw new AuraHandledException('Transaction Details screenshot is required.');
            }

            req.Reason_for_Deferment__c = reason;
            req.Status__c = 'Form Submitted';
            req.Student_Submission_Date__c = Datetime.now();

            update as system req;

            List<Map<String, String>> filesToAttach = new List<Map<String, String>>();
            filesToAttach.add(new Map<String, String>{
                'base64' => documentsBase64, 'name' => documentsFileName, 'type' => 'Documents to Support Request'
            });
            filesToAttach.add(new Map<String, String>{
                'base64' => approvalEmailBase64, 'name' => approvalEmailFileName, 'type' => 'Approval Email'
            });
            filesToAttach.add(new Map<String, String>{
                'base64' => rejoiningAcceptanceBase64, 'name' => rejoiningAcceptanceFileName, 'type' => 'Rejoining Condition Acceptance'
            });
            if (feeApplicable) {
                filesToAttach.add(new Map<String, String>{
                    'base64' => transactionBase64, 'name' => transactionFileName, 'type' => 'Transaction Details'
                });
            }

            attachFiles(defermentRequestId, filesToAttach);

            return req.Id;

        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new AuraHandledException('Submit failed: ' + ex.getMessage());
        }
    }

       /**
     * Bulk version of the old per-file attachFile — inserts all ContentVersions
     * in one DML, queries all their ContentDocumentIds in one SOQL, and inserts
     * all ContentDocumentLinks in one DML. Cuts a 4-file submission down from
     * up to 12 sequential DML/SOQL operations to 3, regardless of file count.
     */
    private static void attachFiles(Id parentId, List<Map<String, String>> files) {
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
            insert as system links;
        }
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
}