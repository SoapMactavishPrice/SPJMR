@IsTest
public class ApplicantDocumentControllerTest {

    @TestSetup
    static void setupData() {

        Application__c app = new Application__c(
            Name = 'Test Application'
        );
        insert app;

        insert new Document_Details__c(
            Name = 'Doc A',
            Application_No__c = app.Id,
            Document_Review_Status__c = 'Approved',
            Remarks__c = 'All good'
        );

        insert new Document_Details__c(
            Name = 'Doc B',
            Application_No__c = app.Id,
            Document_Review_Status__c = 'Pending',
            Remarks__c = 'Under review'
        );
    }

    // ------------------------------------------------------------
    //  Test documents returned branch
    // ------------------------------------------------------------
    @IsTest
    static void testGetApplicantDocuments() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        List<ApplicantDocumentController.DocWrapper> result =
            ApplicantDocumentController.getApplicantDocuments(app.Id);
        Test.stopTest();

        System.assertEquals(2, result.size());
        System.assertEquals('Doc A', result[0].name);
        System.assertEquals('Approved', result[0].status);
        System.assertEquals('All good', result[0].remarks);
    }

    // ------------------------------------------------------------
    //  Test empty result branch
    // ------------------------------------------------------------
    @IsTest
    static void testNoDocuments() {

        Application__c newApp = new Application__c(
            Name = 'Empty Application'
        );
        insert newApp;

        Test.startTest();
        List<ApplicantDocumentController.DocWrapper> result =
            ApplicantDocumentController.getApplicantDocuments(newApp.Id);
        Test.stopTest();

        System.assertEquals(0, result.size());
    }
}