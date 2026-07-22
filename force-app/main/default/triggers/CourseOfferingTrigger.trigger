trigger CourseOfferingTrigger on CourseOffering (after insert) {
if (Trigger.isAfter && Trigger.isInsert) {
      CourseOfferingHandler.handleCourseOfferingAfterInsert(Trigger.new);
}
}