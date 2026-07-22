trigger ProgramTrigger on Program (before insert, before update ,after update){
    
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            ProgramTriggerHandler.preventDuplicateShortProgrammeCode(
                Trigger.new,
                Trigger.oldMap
            );
            /*975 Start*/
            ProgramTriggerHandler.validateShortProgrammeCodeModification(
                Trigger.new,
                Trigger.oldMap
            );
            /*975 End*/
        }
    }
    if (Trigger.isAfter && Trigger.isUpdate) {

        ProgramCurrencySyncHandler.updateRelatedCurrencies(
            Trigger.new,
            Trigger.oldMap
        );
    }
}