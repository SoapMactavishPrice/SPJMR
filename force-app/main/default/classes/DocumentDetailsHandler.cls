public class DocumentDetailsHandler {

 /*  public static void sendEmailOnReupload(List<Document_Details__c> newList, Map<Id, Document_Details__c> oldMap) {

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        // Fetch your template
        EmailTemplate t = [
            SELECT Id 
            FROM EmailTemplate 
            WHERE DeveloperName = 'VERIFIER_NOTIFIER'
            LIMIT 1
        ];

        for (Document_Details__c doc : newList) {
            Document_Details__c oldDoc = oldMap.get(doc.Id);

            // Condition: Rejected → Assigned
            if (oldDoc.Document_Review_Status__c == 'Rejected' &&
                doc.Document_Review_Status__c == 'Assigned') {

                Id verifierId = doc.Verified_By__c; // your user lookup

                if (verifierId != null) {

                    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                    mail.setTemplateId(t.Id);
                    mail.setTargetObjectId(verifierId);
                    mail.setSaveAsActivity(false);

                    // ❌ DO NOT SET WhatId → causes error for User emails  
                    // mail.setWhatId(doc.Id);

                    emails.add(mail);
                }
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }*/
}