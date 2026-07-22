@IsTest(SeeAllData=true)
private class ApplicationProgramAllocatorCtrlTest {
    @IsTest
    static void loadData_nullProgramReturnsEmptyShells() {
        Map<String, Object> out = ApplicationProgramAllocatorController.loadData(null);
        System.assertNotEquals(null, out.get('applications'));
        System.assertNotEquals(null, out.get('verifiers'));
    }
    @IsTest
    static void loadData_withRealProgramRunsAllQueries() {
        List<Program> p = [SELECT Id FROM Program LIMIT 1];
        if (p.isEmpty()) return;
        Map<String, Object> out = ApplicationProgramAllocatorController.loadData(p[0].Id);
        System.assertNotEquals(null, out);
    }
    @IsTest
    static void userWrapperFieldsSetThroughConstructor() {
        ApplicationProgramAllocatorController.UserWrapper w =
            new ApplicationProgramAllocatorController.UserWrapper('a', 'n');
        System.assertEquals('a', w.id);
        System.assertEquals('n', w.name);
    }
}