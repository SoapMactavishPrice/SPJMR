trigger UserTrigger on User (after insert,before insert) {
    UserTriggerHandler handler = new UserTriggerHandler();
    if(trigger.isBefore && trigger.isInsert){
        handler.handlerBeforeInsert(trigger.New);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        handler.handleAfterInsert(Trigger.New,Trigger.Old,Trigger.NewMap,Trigger.OldMap);   
        UserTriggerHandler.assignPermissionSetOnInsert(Trigger.new);
    }
}