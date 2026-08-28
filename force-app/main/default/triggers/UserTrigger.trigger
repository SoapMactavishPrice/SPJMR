trigger UserTrigger on User (after insert,before insert, after update) {
    UserTriggerHandler handler = new UserTriggerHandler();
    if(trigger.isBefore && trigger.isInsert){
        handler.handlerBeforeInsert(trigger.New);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        handler.handleAfterInsert(Trigger.New,Trigger.Old,Trigger.NewMap,Trigger.OldMap);   
        UserTriggerHandler.assignPermissionSetOnInsert(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        UserTriggerHelper.updateApplicantAndOpenApplication(Trigger.new, Trigger.oldMap);
    }
}