trigger AcademicYearTrigger on AcademicYear (
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    if (Trigger.isBefore) {

        RollupTriggerHandler.validateDateOverlap(
            Trigger.new
        );
    }
    RollupTriggerHandler.updateBatchLevelData(
        Trigger.isDelete ? Trigger.old : Trigger.new
    );
}