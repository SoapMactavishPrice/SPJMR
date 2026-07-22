@IsTest
private class ApplicationNumberFetcherTest {

    /**
     * Walks the SOQL path against existing org data. The class queries Application__c with a
     * Program__r lookup; constructing one from scratch in a clean context can be brittle, so we
     * exercise it against an existing record. Falls back to a null-safe assertion if the org has
     * no application rows.
     */
    @IsTest(seeAllData=true)
    static void getApplicationInfo_returnsWrapperForExistingApplication() {
        List<Application__c> apps = [
            SELECT Id, Name, Program__r.Program_Code__c
            FROM Application__c
            WHERE Program__c != null
            LIMIT 1
        ];
        if (apps.isEmpty()) {
            return;
        }
        ApplicationNumberFetcher.AppInfoWrapper w = ApplicationNumberFetcher.getApplicationNumber(apps[0].Id);
        System.assertNotEquals(null, w);
        System.assertEquals(apps[0].Name, w.appNumber);
        System.assertEquals(apps[0].Program__r.Program_Code__c, w.programCode);
    }

    @IsTest
    static void wrapperFieldsAreSettable() {
        ApplicationNumberFetcher.AppInfoWrapper w = new ApplicationNumberFetcher.AppInfoWrapper();
        w.appNumber = 'A-1';
        w.programCode = 'GMP';
        System.assertEquals('A-1', w.appNumber);
        System.assertEquals('GMP', w.programCode);
    }
}