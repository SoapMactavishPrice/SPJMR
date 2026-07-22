trigger CampusTrigger on Campus__c (before insert, before update) {
    SPJIMR_ProgramCodeCopyHandler.syncCampus(Trigger.new, Trigger.oldMap);
}