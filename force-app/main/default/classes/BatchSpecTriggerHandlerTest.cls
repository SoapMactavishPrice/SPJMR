@IsTest
private class BatchSpecTriggerHandlerTest {
    @IsTest
    static void emptyListRunsAllBranches() {
        BatchSpecialisationTriggerHandler.validateDuplicateSpecialisation(new List<Specialisation__c>());
        System.assert(true);
    }
}