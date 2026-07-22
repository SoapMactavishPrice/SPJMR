public class DocumentDetailsReuploadNotifier {

 /*  public static void processReuploads(
        List<Document_Details__c> newList,
        Map<Id, Document_Details__c> oldMap
    ) {

        Set<Id> appIds = new Set<Id>();

        // Detect reupload event
        for (Document_Details__c d : newList) {

            Boolean wasIncomplete = false;
            Boolean nowComplete = false;

            if (oldMap != null && oldMap.containsKey(d.Id)) {
                wasIncomplete = (oldMap.get(d.Id).AllDocumentsUploaded__c == false);
                nowComplete = (d.AllDocumentsUploaded__c == true);
            } else {
                // Insert case
                nowComplete = (d.AllDocumentsUploaded__c == true);
            }

            if (nowComplete) {
                appIds.add(d.Application_No__c);
            }
        }

        if (appIds.isEmpty()) return;

        // Query assigned verification records in "Rejected" state
        List<Application_Verification__c> verToUpdate = [
            SELECT Id, Application__c, Verifier__c, Status__c
            FROM Application_Verification__c
            WHERE Application__c IN :appIds
            AND Status__c = 'Rejected'
        ];

        if (verToUpdate.isEmpty()) return;

        // Reset status to Assigned
        for (Application_Verification__c av : verToUpdate) {
            av.Status__c = 'Assigned';
        }

        update verToUpdate;

        // Send email
        DocumentDetailsEmailHandler.sendVerifierNotification(verToUpdate);
 */   
}