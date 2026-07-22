trigger SPJIMR_TaskTrigger on Task (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        TaskBrochureTrackingHandler.handleAfterInsert(Trigger.new);
    }
}