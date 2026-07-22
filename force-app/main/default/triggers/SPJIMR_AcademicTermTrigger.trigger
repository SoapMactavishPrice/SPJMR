trigger SPJIMR_AcademicTermTrigger on AcademicTerm (before insert,after insert, before update, after update, after delete) {
    if (Trigger.isBefore) {
        SPJIMR_AcademicTermTriggerHandler.syncProgramCodeFromProgram(Trigger.new, Trigger.oldMap);
        TermTriggerSeriesHandler.handleTrigger(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        SPJIMR_AcademicTermTriggerHandler.handleTrigger(Trigger.new, Trigger.oldMap);
    }
   if (Trigger.isAfter && Trigger.isInsert) {
        ProgramTermCountHandler.handleAfterInsert(Trigger.new);
        AcademicTermTriggerHandler.handleAutoPromotion(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        ProgramTermCountHandler.handleAfterDelete(Trigger.oldMap);
    }
    
}