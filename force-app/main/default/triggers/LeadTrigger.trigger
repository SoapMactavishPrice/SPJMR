trigger LeadTrigger on Lead (after insert, after update,before insert, before update) {
    
   /* if (Trigger.isBefore && Trigger.isInsert) {
        LeadDuplicateHandler.checkBeforeAllDuplicates(Trigger.new);
    } */

   if(trigger.isBefore && trigger.isInsert){
    LeadTriggerHelper.populateEntranceExamPicklistonInsert(Trigger.new);
   }
   if(Trigger.isBefore && Trigger.isUpdate){
    LeadTriggerHelper.populateEntranceExamPicklistOnUpdate(Trigger.oldMap,Trigger.new);
    LeadTriggerHelper.validatePhoneCodeOnEdit(Trigger.newMap,Trigger.OldMap);
    LeadTriggerHelper.validateStagesB2B(Trigger.newMap,Trigger.OldMap);
   }
    if(Trigger.isAfter && Trigger.isUpdate){
        LeadTriggerHelper.sendVerificationEmailOnUpdate(Trigger.newMap, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
       //LeadRoutingService.applyB2cDefaultOwnerIfConfigured(Trigger.new);
       System.enqueueJob(new LeadRoutingService(Trigger.new));
       // LeadTriggerHelper.updateStudentOwnerRole(Trigger.new);
    }
    
   


}