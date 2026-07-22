public with sharing class ApplicantDocumentController {

    @AuraEnabled(cacheable=true)
    public static List<DocWrapper> getApplicantDocuments(Id applicationId) {

        List<DocWrapper> results = new List<DocWrapper>();

        List<Document_Details__c> docs = [
            SELECT Id,
                   Name,
                   Document_Review_Status__c,
                   Remarks__c
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            ORDER BY Name
        ];

        for (Document_Details__c d : docs) {
            results.add(new DocWrapper(
                d.Name,
                d.Document_Review_Status__c,
                d.Remarks__c
            ));
        }

        return results;
    }

    public class DocWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String remarks;

        public DocWrapper(String name, String status, String remarks) {
            this.name = name;
            this.status = status;
            this.remarks = remarks;
        }
    }
}