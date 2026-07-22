@IsTest
public class ApplicationSectionDataControllerTest {
    
    // --------------------------------------------------------
    // Dummy HTTP Mock (required because fetchDynamic does callout)
    // --------------------------------------------------------
    private class DummyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"parents":[], "children":[]}');
            return res;
        }
    }
    
    @TestSetup
    static void setupData() {
        
        Test.setMock(HttpCalloutMock.class, new DummyMock());
        
        // Program
        Program prog = new Program(
            Name = 'Test Program',
            Program_Code__c = 'TP01',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'TP',
            Programme_Contact__c = '9999999999'
        );
        insert prog;
        
        // Application
        Application__c app = new Application__c(
            Name = 'Test App',
            Program__c = prog.Id
        );
        insert app;
        
        // Application Verification
        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id
        );
        insert av;
    }
    
    // --------------------------------------------------------
    // getApplicationId - null branch
    // --------------------------------------------------------
    @IsTest
    static void testGetApplicationId_Null() {
        
        Id result =
            ApplicationSectionDataController.getApplicationId(null);
        
        System.assertEquals(null, result);
    }
    
    // --------------------------------------------------------
    // getApplicationId - positive branch
    // --------------------------------------------------------
    @IsTest
    static void testGetApplicationId_Positive() {
        
        Application_Verification__c av =
            [SELECT Id, Application__c FROM Application_Verification__c LIMIT 1];
        
        Id result =
            ApplicationSectionDataController.getApplicationId(av.Id);
        
        System.assertEquals(av.Application__c, result);
    }
    
    // --------------------------------------------------------
    // fetchAllSections - exception branch
    // --------------------------------------------------------
    @IsTest
    static void testFetchAllSections_Exception() {
        
        Boolean exceptionThrown = false;
        
        try {
            ApplicationSectionDataController.fetchAllSections(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        
        System.assertEquals(true, exceptionThrown);
    }
    
    // --------------------------------------------------------
    // fetchAllSections - positive branch
    // --------------------------------------------------------
    @IsTest
    static void testFetchAllSections_Positive() {
        
        Test.setMock(HttpCalloutMock.class, new DummyMock());
        
        Application__c app =
            [SELECT Id FROM Application__c LIMIT 1];
        
        Test.startTest();
        String result =
            ApplicationSectionDataController.fetchAllSections(app.Id);
        Test.stopTest();
        
        
        
        System.assertNotEquals(null, result);
    }
}