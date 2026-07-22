public class ContentDocumentLinkHelper {

    public static void cleanFiles(List<ContentDocumentLink> newLinks) {

        Set<Id> docIds = new Set<Id>();
        String prefix = 'a3F'; // your prefix

        // capture only Document_Details__c links
        for (ContentDocumentLink cdl : newLinks) {
            if (String.valueOf(cdl.LinkedEntityId).startsWith(prefix)) {
                docIds.add(cdl.LinkedEntityId);
            }
        }

        if (docIds.isEmpty()) return;

        cleanFilesAsync(docIds);
    }


    @future
    public static void cleanFilesAsync(Set<Id> docIds) {

        // 1. Document Details with rejection date
        Map<Id, Document_Details__c> docs = new Map<Id, Document_Details__c>(
            [SELECT Id, Rejected_DateTime__c FROM Document_Details__c WHERE Id IN :docIds]
        );

        // 2. All file links
        List<ContentDocumentLink> links = [
            SELECT Id, LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docIds
        ];

        Set<Id> contentIds = new Set<Id>();
        for (ContentDocumentLink l : links) contentIds.add(l.ContentDocumentId);

        // 3. Get file created timestamp
        Map<Id, Datetime> createdMap = new Map<Id, Datetime>();
        for (ContentVersion v : [
            SELECT ContentDocumentId, CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentIds
            AND isLatest = true
        ]) {
            createdMap.put(v.ContentDocumentId, v.CreatedDate);
        }

        List<ContentDocumentLink> toDelete = new List<ContentDocumentLink>();
        List<Document_Details__c> toUpdate = new List<Document_Details__c>();

        // 4. Loop & compare
        for (ContentDocumentLink cdl : links) {

            Document_Details__c d = docs.get(cdl.LinkedEntityId);
            if (d == null || d.Rejected_DateTime__c == null) continue;

            Datetime fileCreated = createdMap.get(cdl.ContentDocumentId);

            // DELETE FILES older than rejection time
            if (fileCreated < d.Rejected_DateTime__c) {
                toDelete.add(cdl);
            } else {
                // new file → update status
                toUpdate.add(new Document_Details__c(
                    Id = d.Id,
                    Document_Review_Status__c = 'Assigned'
                ));
            }
        }

        if (!toDelete.isEmpty()) delete toDelete;
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}