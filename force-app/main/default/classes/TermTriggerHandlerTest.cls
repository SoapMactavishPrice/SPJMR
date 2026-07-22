@IsTest
private class TermTriggerHandlerTest {
    @IsTest
    static void assignSequentialNames_emptyAndNullDgPath() {
        TermTriggerHandler.assignSequentialNames(new List<Division__c>());
        // No Division_Group__c on records -> early skip
        TermTriggerHandler.assignSequentialNames(new List<Division__c>{ new Division__c() });
    }
}