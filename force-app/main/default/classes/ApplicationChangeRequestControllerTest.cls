@IsTest
public class ApplicationChangeRequestControllerTest {

    // ------------------------------------------------------------
    // Dummy Mock (if other triggers do callouts)
    // ------------------------------------------------------------
    private class DummyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true}');
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
            Programme_Contact__c = '9900887766'
        );
        insert prog;

        // Application
        Application__c app = new Application__c(
            Name = 'Test Application',
            Program__c = prog.Id,
            Assignment_Status__c = 'Assigned'
        );
        insert app;

        // Application Verification
        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id,
            Application_Verification_Status__c = 'Assigned'
        );
        insert av;
    }

    // ------------------------------------------------------------
    // getApplicationId
    // ------------------------------------------------------------
    @IsTest
    static void testGetApplicationId() {

        Application_Verification__c av =
            [SELECT Id, Application__c FROM Application_Verification__c LIMIT 1];

        Id result =
            ApplicationChangeRequestController.getApplicationId(av.Id);

        System.assertEquals(av.Application__c, result);
    }

    // ------------------------------------------------------------
    // fetchExistingRequestKeys
    // ------------------------------------------------------------
    @IsTest
    static void testFetchExistingRequestKeys() {

        Application_Verification__c av =
            [SELECT Id, Application__c FROM Application_Verification__c LIMIT 1];

        insert new Application_Change_Request__c(
            Application__c = av.Application__c,
            Section_Label__c = 'Personal Info',
            Field_API__c = 'First_Name__c',
            Status__c = 'Requested'
        );

        List<String> keys =
            ApplicationChangeRequestController.fetchExistingRequestKeys(av.Application__c);

        System.assertEquals(1, keys.size());
        System.assertEquals('Personal Info|First_Name__c|0', keys[0]);
    }

    // ------------------------------------------------------------
    // saveChangeRequests - normal flow
    // ------------------------------------------------------------
    @IsTest
    static void testSaveChangeRequests() {

        Application_Verification__c av =
            [SELECT Id, Application__c FROM Application_Verification__c LIMIT 1];

        List<ApplicationChangeRequestController.ChangeRequestWrapper> wrappers =
            new List<ApplicationChangeRequestController.ChangeRequestWrapper>();

        ApplicationChangeRequestController.ChangeRequestWrapper w =
            new ApplicationChangeRequestController.ChangeRequestWrapper();

        w.sectionLabel = 'Education';
        w.sectionObjectApi = 'Application__c';
        w.fieldLabel = 'Degree';
        w.fieldApi = 'Degree__c';
        w.currentValue = 'B.Com';
        w.remark = 'Incorrect degree';
        w.rowIndex = 1;

        wrappers.add(w);

        String jsonStr = JSON.serialize(wrappers);

        Test.startTest();
        ApplicationChangeRequestController.saveChangeRequests(
            av.Id,
            jsonStr
        );
        Test.stopTest();

        List<Application_Change_Request__c> recs =
            [SELECT Id FROM Application_Change_Request__c
             WHERE Application__c = :av.Application__c];

        System.assertEquals(1, recs.size());
    }

    // ------------------------------------------------------------
    // saveChangeRequests - exception branch
    // ------------------------------------------------------------
    @IsTest
    static void testSaveChangeRequests_Exception() {

        Boolean exceptionThrown = false;

        try {
            ApplicationChangeRequestController.saveChangeRequests(
                '001000000000000AAA',   // fake Id
                '[]'
            );
        } catch (Exception e) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown);
    }
}