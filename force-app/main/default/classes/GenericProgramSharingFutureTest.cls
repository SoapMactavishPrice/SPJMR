@IsTest
private class GenericProgramSharingFutureTest {
    @IsTest
    static void earlyReturnsOnBlankOrEmpty() {
        Test.startTest();
        GenericProgramSharingFuture.shareRecords(null, null);
        GenericProgramSharingFuture.shareRecords('', new List<Id>());
        GenericProgramSharingFuture.shareRecords('Application__c', new List<Id>());
        Test.stopTest();
    }
    @IsTest
    static void withFakeIds_runsResolverAndShortCircuits() {
        // Fake Application Ids - the @future runs but ProgramResolver returns empty, so the
        // subsequent isEmpty() check returns early. Covers the resolver-call line.
        String fake = Schema.SObjectType.Application__c.getKeyPrefix() + '000000000001';
        Test.startTest();
        GenericProgramSharingFuture.shareRecords('Application__c', new List<Id>{ (Id) fake });
        Test.stopTest();
    }
}