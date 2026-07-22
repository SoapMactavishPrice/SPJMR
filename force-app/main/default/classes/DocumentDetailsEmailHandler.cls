public class DocumentDetailsEmailHandler {

    public static void sendReuploadNotification(List<Document_Details__c> newList, Map<Id, Document_Details__c> oldMap) {

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // Fetch template once
        Id templateId;
        try {
            templateId = [SELECT Id FROM EmailTemplate WHERE Name = 'Notify Verifier' LIMIT 1].Id;
        } catch (Exception e) {
            // Template missing, skip sending emails
            return;
        }

        for (Document_Details__c doc : newList) {
            Document_Details__c oldDoc = oldMap.get(doc.Id);
            if (oldDoc == null) continue; // safety check

            // Condition: Rejected → Assigned
            if (oldDoc.Document_Review_Status__c == 'Rejected' &&
                doc.Document_Review_Status__c == 'Assigned') {

                if (doc.Application_Verification__c == null) continue; // safety check

                Application_Verification__c av;
                try {
                    av = [
                        SELECT Id, OwnerId
                        FROM Application_Verification__c
                        WHERE Id = :doc.Application_Verification__c
                        LIMIT 1
                    ];
                } catch (Exception e) {
                    continue; // record not found, skip
                }

                if (av.OwnerId == null) continue; // safety check

                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTemplateId(templateId);
                mail.setTargetObjectId(av.OwnerId);
                mail.setSaveAsActivity(false);

                emails.add(mail);
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }
}