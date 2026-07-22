@IsTest
private class SpecialisationHandlerTest {
    @IsTest
    static void emptyListIsHandled() {
        SpecialisationHandler.validateDuplicateSpecialisation(new List<Specialisation__c>());
    }
    @IsTest
    static void recordsWithoutBatchOrSpecAreHandled() {
        SpecialisationHandler.validateDuplicateSpecialisation(
            new List<Specialisation__c>{ new Specialisation__c() }
        );
    }
}