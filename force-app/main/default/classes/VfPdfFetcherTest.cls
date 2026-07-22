@IsTest
private class VfPdfFetcherTest {

    @IsTest
    static void testGetVfPdfBlob() {

        // Create dummy Application record
        Application__c app = new Application__c(
            Name = 'Test App'
        );
        insert app;

        Test.startTest();

        Blob resultBlob = VfPdfFetcher.getVfPdfBlob(app.Id);

        Test.stopTest();

        System.assertNotEquals(null, resultBlob);
    }

    @IsTest
    static void testGetVfPdfBase64() {

        Application__c app = new Application__c(
            Name = 'Test App 2'
        );
        insert app;

        Test.startTest();

        String base64String = VfPdfFetcher.getVfPdfBase64(app.Id);

        Test.stopTest();

        System.assertNotEquals(null, base64String);
    }
}