@IsTest
private class ProgramCourseHandlerTest {
    @IsTest
    static void emptyAndIncompleteRecords() {
        ProgramCourseHandler.preventDuplicates(new List<Program_Courses__c>());
        ProgramCourseHandler.preventDuplicates(new List<Program_Courses__c>{ new Program_Courses__c() });
    }
}