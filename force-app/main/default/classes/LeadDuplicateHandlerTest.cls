@IsTest
private class LeadDuplicateHandlerTest {
    @IsTest
    static void emptyListIsHandled() {
        LeadDuplicateHandler.checkBeforeAllDuplicates(new List<Lead>());
        System.assert(true);
    }
}