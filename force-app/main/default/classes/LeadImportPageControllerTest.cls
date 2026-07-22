@IsTest
private class LeadImportPageControllerTest {
    @IsTest
    static void startBatchSetsMessage() {
        LeadImportPageController c = new LeadImportPageController();
        Test.startTest();
        PageReference pr = c.startBatch();
        Test.stopTest();
        System.assertEquals(null, pr);
        System.assertNotEquals(null, c.message);
    }
}