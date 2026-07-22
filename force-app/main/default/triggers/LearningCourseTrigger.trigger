trigger LearningCourseTrigger on LearningCourse (before insert, before update) {
    
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            LearningCourseHandler.validateUniqueCourseNumber(Trigger.new, Trigger.oldMap);
        }
    }
}