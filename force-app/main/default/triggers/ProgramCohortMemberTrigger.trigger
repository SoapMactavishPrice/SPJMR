trigger ProgramCohortMemberTrigger on ProgramCohortMember (before insert, before update, after insert) {
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        SPJIMR_ProgramCodeCopyHandler.syncProgramCohortMember(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        ProgramCohortMemberHandler.afterInsert(Trigger.new);
    }
}