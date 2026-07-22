trigger CustomNotificationTrigger on CustomNotification__c (before insert) {
CustomNotificationTriggerHandler handler = new CustomNotificationTriggerHandler();
    
    if(trigger.isAfter){
        if(trigger.isInsert){}
    }
}