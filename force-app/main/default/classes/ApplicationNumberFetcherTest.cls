@IsTest
private class ApplicationNumberFetcherTest {

    @IsTest
    static void testGetApplicationNumber() {

        Program programme = new Program(
            Name = 'GMP',
            Program_Code__c = 'GMP',
            Programme_Type__c = 'Full-time', 
            Programme_Sub_Type__c = 'Online', 
            Short_Programme_Code__c = '001'
        );

        insert programme;

        // Create test Application record
        Application__c app = new Application__c(
            Name = 'APP-001',
            Program__c = programme.Id
        );
        insert app;

        Test.startTest();

        // Call the method
        ApplicationNumberFetcher.AppInfoWrapper w = ApplicationNumberFetcher.getApplicationNumber(app.Id);

        Test.stopTest();

        // Verify result
        System.assertEquals('APP-001', w.appNumber);
        System.assertEquals('GMP', w.programCode);
    }
}