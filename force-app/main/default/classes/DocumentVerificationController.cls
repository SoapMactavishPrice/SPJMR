public with sharing class DocumentVerificationController {

    // ==============================
    // GET DOCUMENT DETAILS
    // ==============================
    @AuraEnabled(cacheable=true)
    public static List<DocumentWrapper> getDocumentDetails(Id verificationId) {

        List<DocumentWrapper> response = new List<DocumentWrapper>();

        List<Document_Details__c> docs = [
            SELECT Id,
                   Name,
                   Remarks__c,
                   Document_Review_Status__c
            FROM Document_Details__c
            WHERE Application_Verification__c = :verificationId
            ORDER BY Name
        ];

        if (docs.isEmpty()) {
            return response;
        }

        Set<Id> docIds = new Set<Id>();
        for (Document_Details__c d : docs) {
            docIds.add(d.Id);
        }

        Map<Id, List<FileWrapper>> docIdToFiles = new Map<Id, List<FileWrapper>>();

        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId,
                   ContentDocumentId,
                   ContentDocument.LatestPublishedVersion.Id,
                   ContentDocument.LatestPublishedVersion.Title,
                   ContentDocument.LatestPublishedVersion.FileExtension
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docIds
        ];

        for (ContentDocumentLink link : links) {

            FileWrapper fw = new FileWrapper(
                link.ContentDocumentId,
                link.ContentDocument.LatestPublishedVersion.Id,
                link.ContentDocument.LatestPublishedVersion.Title,
                link.ContentDocument.LatestPublishedVersion.FileExtension
            );

            if (!docIdToFiles.containsKey(link.LinkedEntityId)) {
                docIdToFiles.put(link.LinkedEntityId, new List<FileWrapper>());
            }
            docIdToFiles.get(link.LinkedEntityId).add(fw);
        }

        for (Document_Details__c d : docs) {
            response.add(new DocumentWrapper(
                d.Id,
                d.Name,
                d.Remarks__c,
                d.Document_Review_Status__c,
                docIdToFiles.get(d.Id)
            ));
        }

        return response;
    }

    // ==============================
    // UPDATE REVIEW STATUS
    // ==============================
    @AuraEnabled
    public static void updateReviewStatus(Id docId, String status, String remarks) {

        Document_Details__c doc = [
            SELECT Application_Verification__r.Verifier__c,
            Application_Verification__r.Program_Team_Members__c
            FROM Document_Details__c
            WHERE Id = :docId
            LIMIT 1
        ];

        update new Document_Details__c(
            Id = docId,
            Document_Review_Status__c = status,
            Remarks__c = remarks,
            Verified_By__c = doc.Application_Verification__r.Verifier__c,
            Program_Team_Member__c=doc.Application_Verification__r.Program_Team_Members__c
            
        );
    }

    // ==============================
    // WRAPPERS
    // ==============================
    public class DocumentWrapper {
        @AuraEnabled public Id docId;
        @AuraEnabled public String name;
        @AuraEnabled public String remarks;
        @AuraEnabled public String reviewStatus;
        @AuraEnabled public List<FileWrapper> files;

        public DocumentWrapper(
            Id docId,
            String name,
            String remarks,
            String reviewStatus,
            List<FileWrapper> files
        ) {
            this.docId = docId;
            this.name = name;
            this.remarks = remarks;
            this.reviewStatus = reviewStatus;
            this.files = files != null ? files : new List<FileWrapper>();
        }
    }

    public class FileWrapper {
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id versionId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String previewUrl;
        @AuraEnabled public String downloadUrl;

        public FileWrapper(Id contentDocumentId, Id versionId, String title, String fileExtension) {
            this.contentDocumentId = contentDocumentId;
            this.versionId = versionId;
            this.title = title;
            this.fileExtension = fileExtension;
            this.previewUrl = '/lightning/r/ContentDocument/' + contentDocumentId + '/view';
            this.downloadUrl = '/sfc/servlet.shepherd/version/download/' + versionId;
        }
    }
}