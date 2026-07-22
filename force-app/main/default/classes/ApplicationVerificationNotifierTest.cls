@IsTest
public class ApplicationVerificationNotifierTest {

    static Id appVerId;

    @TestSetup
    static void setupData() {

        // -----------------------------------
        // Create Person Account
        // -----------------------------------
        RecordType prt = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];

        Account acc = new Account(
            RecordTypeId = prt.Id,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = 'test@applicant.com'
        );
        insert acc;

        // -----------------------------------
        // Application
        // -----------------------------------
        Application__c app = new Application__c(
            Name = 'Test Application',
            Applicant__c = acc.Id
        );
        insert app;

        // -----------------------------------
        // Application Verification
        // -----------------------------------
        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id
        );
        insert av;

        appVerId = av.Id;
    }

    // --------------------------------------------------
    // NO_DOCS
    // --------------------------------------------------
    @IsTest
    static void testNoDocs() {

        Application_Verification__c av =
            [SELECT Id FROM Application_Verification__c LIMIT 1];

        String result =
            ApplicationVerificationNotifier.notifyApplicant(av.Id);

        System.assertEquals('NO_DOCS', result);
    }

    // --------------------------------------------------
    // PENDING_DOCS
    // --------------------------------------------------
    @IsTest
    static void testPendingDocs() {

        Application_Verification__c av =
            [SELECT Id FROM Application_Verification__c LIMIT 1];

        insert new Document_Details__c(
            Name = 'Doc1',
            Application_Verification__c = av.Id,
            Document_Review_Status__c = 'Assigned'
        );

        String result =
            ApplicationVerificationNotifier.notifyApplicant(av.Id);

        System.assertEquals('PENDING_DOCS', result);
    }

    // --------------------------------------------------
    // ALL VERIFIED
    // --------------------------------------------------
    @IsTest
    static void testAllVerified() {

        Application_Verification__c av =
            [SELECT Id FROM Application_Verification__c LIMIT 1];

        insert new Document_Details__c(
            Name = 'Doc2',
            Application_Verification__c = av.Id,
            Document_Review_Status__c = 'Verified'
        );

        String result =
            ApplicationVerificationNotifier.notifyApplicant(av.Id);

        System.assertEquals(
            'Nothing to notify applicant since all documents are verified',
            result
        );
    }

    // --------------------------------------------------
    // NO_EMAIL
    // --------------------------------------------------
    @IsTest
    static void testNoEmail() {

        Application_Verification__c av =
            [SELECT Id, Application__r.Applicant__c FROM Application_Verification__c LIMIT 1];

        Account acc =
            [SELECT Id FROM Account WHERE Id = :av.Application__r.Applicant__c LIMIT 1];

        acc.PersonEmail = null;
        update acc;

        insert new Document_Details__c(
            Name = 'Doc3',
            Application_Verification__c = av.Id,
            Document_Review_Status__c = 'Rejected'
        );

        String result =
            ApplicationVerificationNotifier.notifyApplicant(av.Id);

        System.assertEquals('NO_EMAIL', result);
    }

    // --------------------------------------------------
    // SUCCESS (Rejected branch)
    // --------------------------------------------------
    @IsTest
    static void testSuccessFlow() {

        Application_Verification__c av =
            [SELECT Id FROM Application_Verification__c LIMIT 1];

        insert new Document_Details__c(
            Name = 'Doc4',
            Application_Verification__c = av.Id,
            Document_Review_Status__c = 'Rejected'
        );

        String result =
            ApplicationVerificationNotifier.notifyApplicant(av.Id);

        System.assertEquals('SUCCESS', result);
    }
}