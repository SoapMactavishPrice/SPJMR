public with sharing class DocumentReviewController {

    @AuraEnabled(cacheable=true)
    public static List<DocumentWrapper> getDocumentDetails(Id verificationId) {

        List<DocumentWrapper> response = new List<DocumentWrapper>();

        // Fetch Document Details
        List<Document_Details__c> docs = [
            SELECT Id, Document_Name__r.Name, Document_Review_Status__c
            FROM Document_Details__c
            WHERE Application_Verification__c = :verificationId
        ];

        Set<Id> docIds = new Set<Id>();
        for (Document_Details__c d : docs) {
            docIds.add(d.Id);
        }

        // Get ContentDocumentLinks
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docIds
        ];

        Map<Id, List<FileWrapper>> fileMap = new Map<Id, List<FileWrapper>>();

        for (ContentDocumentLink link : links) {

            // Fetch latest Version
            ContentVersion cv = [
                SELECT Id, Title, ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId = :link.ContentDocumentId
                ORDER BY VersionNumber DESC
                LIMIT 1
            ];

            if (!fileMap.containsKey(link.LinkedEntityId)) {
                fileMap.put(link.LinkedEntityId, new List<FileWrapper>());
            }

            /* 
               BEST PREVIEW LINK (multi-page preview, works in new tab)
               Does not cause errorduringprocessing.jsp
            */
String previewUrl =
    '/lightning/r/ContentDocument/' + cv.ContentDocumentId + '/view';



String downloadUrl =
    '/sfc/servlet.shepherd/version/download/' + cv.Id;
            fileMap.get(link.LinkedEntityId).add(
                new FileWrapper(cv.Title, previewUrl, downloadUrl)
            );
        }

        for (Document_Details__c d : docs) {
            response.add(
                new DocumentWrapper(
                    d.Id,
                    d.Document_Name__r.Name,
                    d.Document_Review_Status__c,
                    fileMap.containsKey(d.Id) ? fileMap.get(d.Id) : new List<FileWrapper>()
                )
            );
        }

        return response;
    }

    @AuraEnabled
    public static void updateStatus(Id docDetailId, String newStatus) {
        update new Document_Details__c(Id = docDetailId, Document_Review_Status__c = newStatus);
    }


    // Wrapper Classes
    public class DocumentWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public List<FileWrapper> files;

        public DocumentWrapper(Id id, String name, String status, List<FileWrapper> files) {
            this.id = id;
            this.name = name;
            this.status = status;
            this.files = files;
        }
    }

    public class FileWrapper {
        @AuraEnabled public String title;
        @AuraEnabled public String previewUrl;
        @AuraEnabled public String downloadUrl;

        public FileWrapper(String title, String previewUrl, String downloadUrl) {
            this.title = title;
            this.previewUrl = previewUrl;
            this.downloadUrl = downloadUrl;
        }
    }
}