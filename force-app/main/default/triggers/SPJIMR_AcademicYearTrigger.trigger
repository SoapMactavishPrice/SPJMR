trigger SPJIMR_AcademicYearTrigger on AcademicYear (after update) {
    SPJIMR_AcademicYearTriggerHandler.handleTrigger(Trigger.new, Trigger.oldMap);
}