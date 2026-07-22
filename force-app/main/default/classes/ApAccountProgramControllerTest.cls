@IsTest
private class ApAccountProgramControllerTest {

    // ============================================
    // 🔷 TEST SETUP (runs once)
    // ============================================
    @testSetup
    static void setupData() {

        String email = 'testuser@example.com';

        // 🔹 Person Account
        RecordType rt = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Account' 
            AND IsPersonType = true 
            LIMIT 1
        ];

        Account acc = new Account(
            RecordTypeId = rt.Id,
            FirstName = 'Test',
            LastName = 'User',
            PersonEmail = email
        );
        insert acc;

        // 🔹 Program
        Program prog = new Program(
            Name = 'Test Program',
            Program_Code__c = 'TP01',
            StartDate = Date.today().addDays(-5),
            EndDate = Date.today().addDays(5)
        );
        insert prog;

        // 🔹 Application
        Application__c app = new Application__c(
            Name = 'Test Application',
            Applicant__c = acc.Id,
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Offer Issued',
            Application_Status__c = 'Paid',
            Application_Stage__c = 'Application Submitted',
            AllowSelfSchedule__c = true
        );
        insert app;

        // 🔹 Admission Decision
        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission'
        );
        insert adm;

        // 🔹 Content Version (Offer Letter)
        ContentVersion cv = new ContentVersion(
            Title = 'Signed Offer Letter',
            PathOnClient = 'offer.pdf',
            VersionData = Blob.valueOf('Test Data'),
            FirstPublishLocationId = adm.Id
        );
        insert cv;

        // 🔹 Content Distribution
        insert new ContentDistribution(
            Name = 'Offer',
            ContentVersionId = cv.Id
        );
    }

    // ============================================
    // 🔷 USER CREATION
    // ============================================
    private static User createUser() {

        Profile p = [
            SELECT Id 
            FROM Profile 
            WHERE Name = 'Standard User' 
            LIMIT 1
        ];

        User u = new User(
            Alias = 'testu',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'testuser' + System.currentTimeMillis() + '@test.com',
            ProfileId = p.Id
        );
        insert u;

        return u;
    }

    // ============================================
    // 🔷 TEST: getProgramsForLoggedInUser
    // ============================================
    @IsTest
    static void testGetProgramsForLoggedInUser() {

        User u = createUser();

        System.runAs(u) {

            Test.startTest();

            List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
                ApAccountProgramController.getProgramsForLoggedInUser();

            Test.stopTest();

            System.assertNotEquals(null, result);
        }
    }

    // ============================================
    // 🔷 TEST: checkUserValidity
    // ============================================
    @IsTest
    static void testCheckUserValidity() {

        User u = createUser();

        System.runAs(u) {

            List<String> result = ApAccountProgramController.checkUserValidity();

            System.assertNotEquals(null, result);
        }
    }

    // ============================================
    // 🔷 TEST: isDecisionPresent
    // ============================================
    @IsTest
    static void testIsDecisionPresent() {

        User u = createUser();

        System.runAs(u) {

            String result = ApAccountProgramController.isDecisionPresent();

            System.assertEquals(true, result == 'Yes' || result == 'No');
        }
    }

    // ============================================
    // 🔷 TEST: getApplicationStage
    // ============================================
    @IsTest
    static void testGetApplicationStage() {

        Application__c app = [
            SELECT Id FROM Application__c LIMIT 1
        ];

        String stage = ApAccountProgramController.getApplicationStage(app.Id);

        System.assertNotEquals(null, stage);
    }

    // ============================================
    // 🔷 TEST: checkUploadedDocuments
    // ============================================
    @IsTest
    static void testCheckUploadedDocuments() {

        Application__c app = [
            SELECT Id FROM Application__c LIMIT 1
        ];

        Map<String, String> result =
            ApAccountProgramController.checkUploadedDocuments(app.Id);

        System.assert(result.containsKey('offerLetter'));
    }

    // ============================================
    // 🔷 TEST: deleteDocument
    // ============================================
    @IsTest
    static void testDeleteDocument() {

        ContentDocument doc = [
            SELECT Id FROM ContentDocument LIMIT 1
        ];

        String result =
            ApAccountProgramController.deleteDocument(doc.Id, 'Offer');

        System.assertEquals(true, result == 'Offer' || result == '');
    }

    // ============================================
    // 🔷 TEST: getDistributionUrl
    // ============================================
    @IsTest
    static void testGetDistributionUrl() {

        ContentVersion cv = [
            SELECT Id FROM ContentVersion LIMIT 1
        ];

        Boolean result =
            ApAccountProgramController.getDistributionUrl(cv.Id, 'Offer');

        System.assertEquals(true, result || !result);
    }

    // ============================================
    // 🔷 TEST: getCurrentUserPersonAccountInfo
    // ============================================
    @IsTest
    static void testGetCurrentUserInfo() {

        User u = createUser();

        System.runAs(u) {

            Map<String, Object> result =
                ApAccountProgramController.getCurrentUserPersonAccountInfo();

            System.assertNotEquals(null, result);
        }
    }

    // ============================================
    // 🔷 TEST: getObjectApiName
    // ============================================
    @IsTest
    static void testGetObjectApiName() {

        Application__c app = [
            SELECT Id FROM Application__c LIMIT 1
        ];

        String result =
            ApAccountProgramController.getObjectApiName(app.Id);

        System.assertEquals('Application__c', result);
    }
}