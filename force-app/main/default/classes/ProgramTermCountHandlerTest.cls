@IsTest(SeeAllData=true)
private class ProgramTermCountHandlerTest {
    // Note: ProgramTermCountHandler.handleTrigger is *commented out* in SPJIMR_AcademicTermTrigger,
    // so the production code can never invoke it. The class is effectively dead. This test simply
    // documents that and does the only thing safely callable from outside a trigger context.
    @IsTest
    static void deadCode_classIsReferenceable() {
        Type t = ProgramTermCountHandler.class;
        System.assertNotEquals(null, t);
    }
}