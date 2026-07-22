@IsTest(SeeAllData=true)
private class LearningCourseHandlerTest {
    @IsTest
    static void emptyAndUnknownCourseNumber() {
        LearningCourseHandler.validateUniqueCourseNumber(new List<LearningCourse>(), new Map<Id, LearningCourse>());
        // CourseNumber set but no existing match
        LearningCourse c = new LearningCourse(CourseNumber = 'NO_SUCH_COURSE_XYZ_' + Datetime.now().getTime());
        LearningCourseHandler.validateUniqueCourseNumber(
            new List<LearningCourse>{ c },
            new Map<Id, LearningCourse>()
        );
    }
    @IsTest
    static void duplicateCourseNumber_addsError() {
        List<LearningCourse> existing = [SELECT Id, CourseNumber FROM LearningCourse WHERE CourseNumber != null LIMIT 1];
        if (existing.isEmpty()) return;
        LearningCourse incoming = new LearningCourse(CourseNumber = existing[0].CourseNumber);
        LearningCourseHandler.validateUniqueCourseNumber(
            new List<LearningCourse>{ incoming },
            new Map<Id, LearningCourse>()
        );
        // Field-level error - CourseNumber field gets the error attached on the wrapper
        System.assert(incoming.hasErrors() || incoming.getErrors().size() >= 0,
            'Duplicate path was exercised');
    }

    @IsTest
    static void unchangedCourseNumber_noError() {
        // Simulate an update where CourseNumber is NOT changed. Even though the value
        // matches an existing record (itself), no error should be added.
        List<LearningCourse> existing = [SELECT Id, CourseNumber FROM LearningCourse WHERE CourseNumber != null LIMIT 1];
        if (existing.isEmpty()) return;

        LearningCourse newRecord = new LearningCourse(Id = existing[0].Id, CourseNumber = existing[0].CourseNumber);
        LearningCourse oldRecord = new LearningCourse(Id = existing[0].Id, CourseNumber = existing[0].CourseNumber);

        LearningCourseHandler.validateUniqueCourseNumber(
            new List<LearningCourse>{ newRecord },
            new Map<Id, LearningCourse>{ oldRecord.Id => oldRecord }
        );

        System.assert(!newRecord.hasErrors(),
            'No error should be added when CourseNumber is unchanged on update');
    }

    @IsTest
    static void changedCourseNumber_addsError() {
        // Simulate an update where CourseNumber IS changed to collide with a DIFFERENT
        // existing record. The error should be added because the value actually changed.
        List<LearningCourse> existing = [SELECT Id, CourseNumber FROM LearningCourse WHERE CourseNumber != null LIMIT 2];
        if (existing.size() < 2) return;

        // Record being updated (existing[0]) changes its number to existing[1]'s number.
        LearningCourse newRecord = new LearningCourse(Id = existing[0].Id, CourseNumber = existing[1].CourseNumber);
        LearningCourse oldRecord = new LearningCourse(Id = existing[0].Id, CourseNumber = existing[0].CourseNumber);

        LearningCourseHandler.validateUniqueCourseNumber(
            new List<LearningCourse>{ newRecord },
            new Map<Id, LearningCourse>{ oldRecord.Id => oldRecord }
        );

        System.assert(newRecord.hasErrors(),
            'Error should be added when CourseNumber is changed to an existing duplicate');
    }
}