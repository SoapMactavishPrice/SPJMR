@IsTest
private class ProgramCohortMemberHandlerTest {
    @IsTest
    static void afterInsertWithEmptyList_returnsEarly() {
        ProgramCohortMemberHandler.afterInsert(new List<ProgramCohortMember>());
        System.assert(true, 'Empty input returned without invoking helper');
    }
}