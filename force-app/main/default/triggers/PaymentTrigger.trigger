trigger PaymentTrigger on Payment__c (after insert, after update) {
    if (Trigger.isAfter) {
        PaymentTriggerHandler.updateLeadSubmittedDate(
            Trigger.new,
            Trigger.oldMap
        );
    }
    
    if(trigger.isInsert && trigger.isAfter){
        SharingOrchestrator.handleRecords('Payment__c', trigger.newMap.keySet());
    }
    if(trigger.isAfter){
        if(trigger.isInsert || trigger.isUpdate){
            for(Payment__c p : Trigger.new){
                
                // Check if Payment Type is Application Fee and Status is Paid
                if (p.Payment_Type__c == 'Application Fee' && p.Status__c == 'paid') {
                    
                    // For Update - only send if status changed to paid
                    if (Trigger.isUpdate) {
                        Payment__c oldPayment = Trigger.oldMap.get(p.Id);
                        if (oldPayment.Status__c != 'paid') {
                            PaymentTriggerHandler.sendApplicationFeeConformationEmail(p.Id);
                        }
                    }
                    
                    // For Insert - send directly
                    if (Trigger.isInsert) {
                        PaymentTriggerHandler.sendApplicationFeeConformationEmail(p.Id);
                    }
                }
            }
        }
    }
    
}