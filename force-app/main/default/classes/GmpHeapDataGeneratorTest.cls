@IsTest(SeeAllData=true)
private class GmpHeapDataGeneratorTest {

    @IsTest
    static void verifyGeneratorAndExportRuntime() {
        try {
            Test.startTest();

            GmpHeapDataGenerator.generate(300);

            List<Id> appIds = new List<Id>();
            for (Application__c app : [
                SELECT Id
                FROM Application__c
                WHERE Name LIKE 'GMP-STRESS-%'
            ]) {
                appIds.add(app.Id);
            }

            System.assert(!appIds.isEmpty(), 'Generator created no applications');

            Database.executeBatch(
                new GmpCsvExportBatch(appIds),
                300
            );

            Test.stopTest();

        } catch (Exception e) {
            System.debug('FAIL: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            System.assert(false, e.getMessage());
        }
    }
}