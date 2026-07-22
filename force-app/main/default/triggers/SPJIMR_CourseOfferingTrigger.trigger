trigger SPJIMR_CourseOfferingTrigger on CourseOffering (after insert, before delete) {
    if (Trigger.isAfter && Trigger.isInsert) {
        SPJIMRCourseOfferingTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isDelete) {
        SPJIMRCourseOfferingTriggerHandler.handleBeforeDelete(Trigger.old);
    }
}