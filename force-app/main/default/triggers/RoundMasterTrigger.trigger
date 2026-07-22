trigger RoundMasterTrigger on RoundMaster__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	RoundMasterTriggerHandler handler = new RoundMasterTriggerHandler();
 	
    
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