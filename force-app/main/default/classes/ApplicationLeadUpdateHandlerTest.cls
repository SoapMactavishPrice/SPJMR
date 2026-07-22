@IsTest
private class ApplicationLeadUpdateHandlerTest {
    @IsTest
    static void emptyListEarlyReturns() {
        ApplicationLeadUpdateHandler.updateLeadFromApplication(new List<Application__c>());
        System.assert(true);
    }
}