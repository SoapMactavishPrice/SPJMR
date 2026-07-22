@IsTest
private class DivisionTriggerHandlerTest {
    @IsTest
    static void emptyAndIncompleteRecords() {
        DivisionTriggerHandler.validateSpecialisationType(new List<Division__c>());
        DivisionTriggerHandler.validateSpecialisationType(new List<Division__c>{ new Division__c() });
    }
}