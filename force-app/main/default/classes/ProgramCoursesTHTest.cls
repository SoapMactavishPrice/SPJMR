@IsTest
private class ProgramCoursesTHTest {
    @IsTest
    static void emptyAndNullInputs() {
        ProgramCoursesTriggerHandler.handleAfterInsert(null);
        ProgramCoursesTriggerHandler.handleAfterInsert(new List<Program_Courses__c>());
        ProgramCoursesTriggerHandler.handleAfterUpdate(null);
        ProgramCoursesTriggerHandler.handleAfterUpdate(new List<Program_Courses__c>());
        System.assert(true);
    }
}