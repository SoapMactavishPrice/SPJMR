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
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (AcademicTerm record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Programm_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (AcademicTerm record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Programm_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'AcademicTerm',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        ProgramTermCountHandler.handleAfterDelete(Trigger.oldMap);
    }
    
}