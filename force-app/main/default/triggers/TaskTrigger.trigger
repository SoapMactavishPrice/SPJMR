trigger TaskTrigger on Task (before insert, before update,after insert) {

    TaskTriggerHandler handler = new TaskTriggerHandler();
   /*
    if(trigger.isInsert || trigger.isUpdate){
        TaskTriggerHelper.updateCompanyOnTaskB2B(Trigger.new);
    }
    if(trigger.isInsert && trigger.isAfter){
       TaskTriggerHelper.createFollowUpTaskB2C(Trigger.new);
    }
    */
    
    
    if (Trigger.isBefore) {
        if (Trigger.isInsert) handler.beforeInsert(Trigger.new);
        if (Trigger.isUpdate) handler.beforeUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
        if (Trigger.isDelete) handler.beforeDelete(Trigger.old, Trigger.oldMap);
    }
    if (Trigger.isAfter) {
        if (Trigger.isInsert) handler.afterInsert(Trigger.new, Trigger.newMap);
        if (Trigger.isUpdate) handler.afterUpdate(Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap);
    }

        
     
        if (Trigger.isDelete) handler.afterDelete(Trigger.old, Trigger.oldMap);
        if (Trigger.isUndelete) handler.afterUndelete(Trigger.new, Trigger.newMap);
    
}