trigger DocumentDetailsTrigger on Document_Details__c (before update, after update,after insert) {

    // BEFORE UPDATE → Set Rejected Date Time
    if (Trigger.isBefore && Trigger.isUpdate) {
        for (Document_Details__c d : Trigger.new) {
            Document_Details__c old = Trigger.oldMap.get(d.Id);

            // Status changed TO Rejected / Change Requested
            if ((d.Document_Review_Status__c == 'Rejected' ||
                 d.Document_Review_Status__c == 'Change Requested') &&
                old.Document_Review_Status__c != d.Document_Review_Status__c)
            {
                d.Rejected_DateTime__c = System.now();
            }
        }
    }
    
    if(trigger.isAfter && trigger.isInsert){
        SharingOrchestrator.handleRecords('Document_Details__c', trigger.newMap.keySet());
    }

    // AFTER UPDATE → Send Reupload Email Notification
    if (Trigger.isAfter && Trigger.isUpdate) {
      DocumentDetailsEmailHandler.sendReuploadNotification(Trigger.new, Trigger.oldMap);
    }
}