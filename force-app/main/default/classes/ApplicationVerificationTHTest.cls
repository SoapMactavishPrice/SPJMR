@IsTest
private class ApplicationVerificationTHTest {
    @IsTest
    static void emptyListIsHandled() {
        ApplicationVerificationTriggerHandler.afterUpdate(
            new List<Application_Verification__c>(),
            new Map<Id, Application_Verification__c>()
        );
    }
}