trigger SessionDivisionTrigger on Session_Division__c (before insert, before update) {
    SPJIMR_ProgramCodeCopyHandler.syncSessionDivision(Trigger.new, Trigger.oldMap);
}