trigger SPJIMRDivisionTrigger on Division__c (after insert, after update, after delete, after undelete, before insert, before update) {
    
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete || Trigger.isDelete)) {
        SPJIMRDivisionTriggerHandler.updateTermDivisionCounts(
            Trigger.new,
            Trigger.old,
            Trigger.isInsert,
            Trigger.isUpdate,
            Trigger.isDelete,
            Trigger.isUndelete
        );
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        SPJIMRDivisionTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isBefore && (Trigger.isUpdate || Trigger.isInsert)) {
        SPJIMRDivisionTriggerHandler.syncBatchFromTerm(Trigger.new);
        SPJIMRDivisionCodeHandler.updateDivisionCodes(Trigger.new);
        SPJIMRDivisionTriggerHandler.validateDuplicateDivision(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isInsert) {
        TermTriggerHandler.assignSequentialNames(Trigger.new);
    }
    
     if (Trigger.isBefore && (Trigger.isUpdate || Trigger.isInsert)) {
        SPJIMR_ProgramCodeCopyHandler.syncDivision(Trigger.new, Trigger.oldMap);
    }
}