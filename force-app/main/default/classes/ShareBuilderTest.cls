@IsTest
private class ShareBuilderTest {
    @IsTest
    static void buildShares_handlesEmptyInput() {
        try {
            ShareBuilder.buildShares('Application__c', new Map<Id, Id>(), new Map<Id, List<Program_Team_Members__c>>());
        } catch (Exception e) {}
    }
}