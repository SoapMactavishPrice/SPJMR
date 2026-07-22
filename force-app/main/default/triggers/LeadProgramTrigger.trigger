trigger LeadProgramTrigger on Lead_Program__c (after insert,before insert,before update) {
    LeadProgramTriggerHandler handler = new LeadProgramTriggerHandler();
    if(trigger.isBefore){
        if(trigger.isInsert) handler.beforeInsert(Trigger.New);
        if(trigger.isUpdate) handler.beforeUpdate(Trigger.New, Trigger.OldMap, Trigger.NewMap);
    }
    if(trigger.isAfter){
       
        if(trigger.isInsert) handler.afterInsert(Trigger.New, Trigger.NewMap);
    }
}