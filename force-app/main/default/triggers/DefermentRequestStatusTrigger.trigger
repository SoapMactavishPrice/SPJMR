trigger DefermentRequestStatusTrigger on Deferment_Request__c (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore) {
        DefermentRequestStatusHandler.applyPendingReEnrollment(Trigger.new);
        DefermentRequestStatusHandler.applyRejoiningComplete(Trigger.new);
        DefermentRequestStatusHandler.rejectNegativeFee(Trigger.new);
        if (Trigger.isUpdate) {
            DefermentRequestStatusHandler.advanceOnRejoiningDetails(
                Trigger.new,
                Trigger.oldMap
            );
            DefermentRequestStatusHandler.enforceStatusOrder(
                Trigger.new,
                Trigger.oldMap
            );
        }
    }
    if (Trigger.isAfter) {
        DefermentRequestStatusHandler.markStudentDeferredOnPendingReEnrollment(
            Trigger.new,
            Trigger.oldMap
        );
        DefermentRequestStatusHandler.markEnrollmentActiveOnRejoiningComplete(
            Trigger.new,
            Trigger.oldMap
        );
        DefermentRequestStatusHandler.mapStudentToRejoiningBatch(
            Trigger.new,
            Trigger.oldMap
        );
    }
}