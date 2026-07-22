trigger SPJIMR_ProgramCohortTrigger on ProgramCohort (before insert, before update, after insert, after update) {
    SPJIMR_ProgramCohortTriggerHandler.handleTrigger(Trigger.new, Trigger.oldMap);
}