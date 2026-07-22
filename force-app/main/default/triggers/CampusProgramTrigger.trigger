trigger CampusProgramTrigger on CampusProgram__c (before insert, before update) {
    SPJIMR_ProgramCodeCopyHandler.syncCampusProgram(Trigger.new, Trigger.oldMap);
}