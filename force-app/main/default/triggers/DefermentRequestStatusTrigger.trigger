/**
 * @description Keeps the Deferment Request status tracker moving on its own:
 *              a request that reaches "Deferment Process Complete" is parked
 *              straight away at "Pending Re-enrollment", the stage the
 *              rejoining reminders read; and one that reaches "Student Record
 *              Reactivated" places the student in the batch they are rejoining,
 *              keeping their existing Roll Number.
 *
 *              Deliberately separate from DefermentRequestTrigger, which sends
 *              the "Break in Study Option Enabled" e-mail.
 */
trigger DefermentRequestStatusTrigger on Deferment_Request__c (
    before insert,
    before update,
    after insert,
    after update
) {
    if (Trigger.isBefore) {

        DefermentRequestStatusHandler.applyPendingReEnrollment(Trigger.new);

        DefermentRequestStatusHandler.rejectNegativeFee(Trigger.new);

        // After the rewrite above, so the order check sees the status that is
        // actually about to be saved.
        if (Trigger.isUpdate) {
            DefermentRequestStatusHandler.enforceStatusOrder(
                Trigger.new,
                Trigger.oldMap
            );
        }
    }

    // After the record is saved, because this one inserts a batch enrolment.
    if (Trigger.isAfter) {
        DefermentRequestStatusHandler.mapStudentToRejoiningBatch(
            Trigger.new,
            Trigger.oldMap
        );
    }
}