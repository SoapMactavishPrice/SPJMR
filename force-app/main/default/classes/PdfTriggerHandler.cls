public class PdfTriggerHandler {

    @future(callout=true)
    public static void processAsync(List<Id> versionIds) {

        Map<Id, Id> versionToParent = new Map<Id, Id>();

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
        ];

        Set<Id> docIds = new Set<Id>();
        for (ContentVersion cv : versions) {
            docIds.add(cv.ContentDocumentId);
        }

        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :docIds
        ]) {

            // 🚫 Skip User
            if (String.valueOf(cdl.LinkedEntityId).startsWith('005')) continue;

            if (!versionToParent.containsKey(cdl.ContentDocumentId)) {
                versionToParent.put(cdl.ContentDocumentId, cdl.LinkedEntityId);
            }
        }

        for (ContentVersion cv : versions) {
            if (versionToParent.containsKey(cv.ContentDocumentId)) {
                System.enqueueJob(
                    new PdfToImageQueueable(
                        new List<Id>{ cv.Id },
                        versionToParent.get(cv.ContentDocumentId)
                    )
                );
            }
        }
    }
}