trigger AcademicTermEnrollmentTrigger on AcademicTermEnrollment (before insert, before update) {
    SPJIMR_ProgramCodeCopyHandler.syncAcademicTermEnrollment(Trigger.new, Trigger.oldMap);
}