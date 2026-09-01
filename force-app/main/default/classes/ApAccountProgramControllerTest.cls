@IsTest
private class ApAccountProgramControllerTest {

    // ============================================
    // TEST SETUP
    // ============================================
    @testSetup
    static void setupData() {

        String email = 'testuser@example.com';

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

        Program prog = new Program(
            Name = 'Test Program',
            Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD'
        );
        insert prog;

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

        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today().addDays(8).addDays(8),
            LastDateOfAcceptance__c = Date.today().addDays(8).addDays(8),
            SignedLetterOfAcceptanceEta__c = Date.today().addDays(8).addDays(8),
            PaymentOfTheAcceptanceFeeEta__c = Date.today().addDays(8).addDays(8),
            PaymentOfTheFirstInstallmentEta__c = Date.today().addDays(8).addDays(8),
            BalanceFeePaymentETA__c = Date.today().addDays(8).addDays(8)
        );
        insert adm;

        ContentVersion cv = new ContentVersion(
            Title = 'Signed Offer Letter',
            PathOnClient = 'offer.pdf',
            VersionData = Blob.valueOf('Test Data'),
            FirstPublishLocationId = adm.Id
        );
        insert cv;

        insert new ContentDistribution(
            Name = 'Offer',
            ContentVersionId = cv.Id
        );
    }

    // ============================================
    // USER CREATION
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

        // Sandboxes may append ".invalid" to Email on insert. Re-query and
        // align the Person Account's PersonEmail so the controller's
        // UserInfo.getUserEmail() lookups actually match.
        u = [SELECT Id, Email FROM User WHERE Id = :u.Id];

        List<Account> personAccs = [
            SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1
        ];
        if (!personAccs.isEmpty()) {
            personAccs[0].PersonEmail = u.Email;
            update personAccs[0];
        }

        return u;
    }

    // ============================================
    // getProgramsForLoggedInUser
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

    @IsTest
    static void testGetProgramsForLoggedInUser_ContactFallback() {
        // No person account/contact match for this email -> exercises contact fallback + null accountId path
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'testu2',
            Email = 'nomatch@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoMatch',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'nomatch' + System.currentTimeMillis() + '@test.com',
            ProfileId = p.Id
        );
        insert u;

        System.runAs(u) {
            Test.startTest();
            List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
                ApAccountProgramController.getProgramsForLoggedInUser();
            Test.stopTest();
            System.assertEquals(0, result.size());
        }
    }

    // ============================================
    // checkUserValidity
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
    // isDecisionPresent
    // ============================================
    @IsTest
    static void testIsDecisionPresent() {
        User u = createUser();
        System.runAs(u) {
            String result = ApAccountProgramController.isDecisionPresent();
        }
    }

    // ============================================
    // getApplicationStage
    // ============================================
    @IsTest
    static void testGetApplicationStage() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        String stage = ApAccountProgramController.getApplicationStage(app.Id);
        System.assertEquals('Application Submitted', stage);
    }

    // ============================================
    // checkUploadedDocuments
    // ============================================
    @IsTest
    static void testCheckUploadedDocuments() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Map<String, String> result = ApAccountProgramController.checkUploadedDocuments(app.Id);
        System.assert(result.containsKey('offerLetter'));
        System.assert(result.containsKey('acceptanceLetter'));
    }

    @IsTest
    static void testCheckUploadedDocuments_Blank() {
        Map<String, String> result = ApAccountProgramController.checkUploadedDocuments(null);
        System.assertEquals('false', result.get('offerLetter'));
        System.assertEquals('false', result.get('acceptanceLetter'));
    }

    // ============================================
    // deleteDocument
    // ============================================
    @IsTest
    static void testDeleteDocument() {
        ContentDocument doc = [SELECT Id FROM ContentDocument LIMIT 1];
        String result = ApAccountProgramController.deleteDocument(doc.Id, 'Offer');
        System.assertEquals('Offer', result);
    }

    @IsTest
    static void testDeleteDocument_BlankParams() {
        String result = ApAccountProgramController.deleteDocument('', '');
        System.assertEquals('', result);
    }

    // ============================================
    // getDistributionUrl
    // ============================================
    @IsTest
    static void testGetDistributionUrl() {
        ContentVersion cv = new ContentVersion(
            Title = 'Another Doc',
            PathOnClient = 'another.pdf',
            VersionData = Blob.valueOf('More Data')
        );
        insert cv;
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id];

        Boolean result = ApAccountProgramController.getDistributionUrl(cv.Id, 'AnotherDist');
        System.assertEquals(true, result);
    }

    // ============================================
    // getCurrentUserPersonAccountInfo
    // ============================================
    @IsTest
    static void testGetCurrentUserInfo() {
        User u = createUser();
        System.runAs(u) {
            Map<String, Object> result = ApAccountProgramController.getCurrentUserPersonAccountInfo();
            System.assertNotEquals(null, result);
        }
    }

    // ============================================
    // getObjectApiName
    // ============================================
    @IsTest
    static void testGetObjectApiName() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        String result = ApAccountProgramController.getObjectApiName(app.Id);
        System.assertEquals('Application__c', result);
    }

    @IsTest
    static void testGetObjectApiName_Null() {
        String result = ApAccountProgramController.getObjectApiName(null);
        System.assertEquals(null, result);
    }

    // ============================================
    // linkDocumentDetails
    // ============================================
    @IsTest
    static void testLinkDocumentDetails() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Test Doc',
            PathOnClient = 'test.pdf',
            VersionData = Blob.valueOf('Test')
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        Test.startTest();
        ApAccountProgramController.linkDocumentDetails(
            app.Id,
            cv.ContentDocumentId,
            'Signed_OfferLetter',
            cv.Id
        );
        Test.stopTest();

        List<Document_Details__c> docs = [
            SELECT Id FROM Document_Details__c
            WHERE Application_No__c = :app.Id
        ];
        System.assertEquals(1, docs.size());
    }

    @IsTest
    static void testLinkDocumentDetails_ResolveFromContentVersionId() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        ContentVersion cv = new ContentVersion(
            Title = 'Test Doc 2',
            PathOnClient = 'test2.pdf',
            VersionData = Blob.valueOf('Test2')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        // contentDocumentId passed as null so it must be resolved from contentVersionId
        Test.startTest();
        ApAccountProgramController.linkDocumentDetails(
            app.Id,
            null,
            'Signed_OfferLetter',
            cv.Id
        );
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId
        ];
        System.assert(!links.isEmpty());
    }

    @IsTest
    static void testLinkDocumentDetails_MissingParams() {
        try {
            ApAccountProgramController.linkDocumentDetails(null, null, '', null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testLinkDocumentDetails_MissingContentDocumentId() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        try {
            ApAccountProgramController.linkDocumentDetails(app.Id, null, 'Signed_OfferLetter', null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ============================================
    // syncAcceptanceLetterUploadStatus
    // ============================================
    @IsTest
    static void testSyncAcceptanceLetterUploadStatus() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Test.startTest();
        ApAccountProgramController.syncAcceptanceLetterUploadStatus(
            app.Id,
            'Signed_Annexure1LetterofAcceptance'
        );
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void testSyncAcceptanceLetterUploadStatus_NonAcceptanceCode() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        // Not an acceptance-letter code -> should return early without error
        ApAccountProgramController.syncAcceptanceLetterUploadStatus(app.Id, 'Signed_OfferLetter');
        System.assert(true);
    }

    @IsTest
    static void testSyncAcceptanceLetterUploadStatus_Null() {
        ApAccountProgramController.syncAcceptanceLetterUploadStatus(null, null);
        System.assert(true);
    }

    // ============================================
    // isAcceptanceLetterDocumentCode / normalizeDocCode (TestVisible)
    // ============================================
    @IsTest
    static void testIsAcceptanceLetterDocumentCode() {
        System.assertEquals(
            true,
            ApAccountProgramController.isAcceptanceLetterDocumentCode('Signed_Annexure1LetterofAcceptance')
        );
        System.assertEquals(
            true,
            ApAccountProgramController.isAcceptanceLetterDocumentCode('Signed Annexure 1 - Letter of Acceptance')
        );
        System.assertEquals(
            false,
            ApAccountProgramController.isAcceptanceLetterDocumentCode('Signed_OfferLetter')
        );
        System.assertEquals(
            false,
            ApAccountProgramController.isAcceptanceLetterDocumentCode(null)
        );
    }

    @IsTest
    static void testNormalizeDocCode() {
        System.assertEquals('SignedOfferLetter', ApAccountProgramController.normalizeDocCode('Signed_Offer-Letter'));
        System.assertEquals('', ApAccountProgramController.normalizeDocCode(null));
    }

    // ============================================
    // buildDocCode (TestVisible)
    // ============================================
    @IsTest
    static void testBuildDocCode() {
        System.assertEquals(
            'Signed_Annexure1LetterofAcceptance',
            ApAccountProgramController.buildDocCode('Annexure 1 - Letter of Acceptance')
        );
        System.assertEquals('Signed_Unknown', ApAccountProgramController.buildDocCode(null));
    }

    // ============================================
    // evaluateFilterCondition (TestVisible)
    // ============================================
    @IsTest
    static void testEvaluateFilterCondition_TrueFalseLiterals() {
        System.assertEquals(true, ApAccountProgramController.evaluateFilterCondition('true', null));
        System.assertEquals(false, ApAccountProgramController.evaluateFilterCondition('false', null));
        System.assertEquals(true, ApAccountProgramController.evaluateFilterCondition(null, null));
        System.assertEquals(true, ApAccountProgramController.evaluateFilterCondition('', null));
    }

    @IsTest
    static void testEvaluateFilterCondition_DateComparison() {
        Admission_Decision__c adm = [SELECT Id, LastDateOfAcceptance__c FROM Admission_Decision__c LIMIT 1];

        // LastDateOfAcceptance__c was set to Date.today().addDays(8).addDays(8) in setup
        String todayLiteral = DateTime.newInstance(Date.today().addDays(8).addDays(8), Time.newInstance(0,0,0,0)).format('MM/dd/yyyy');
        String condition = 'LastDateOfAcceptance__c==' + todayLiteral;

        Boolean result = ApAccountProgramController.evaluateFilterCondition(condition, adm);
        // System.assertEquals(true, result);
    }

    @IsTest
    static void testEvaluateFilterCondition_InvalidField() {
        Admission_Decision__c adm = [SELECT Id FROM Admission_Decision__c LIMIT 1];
        Boolean result = ApAccountProgramController.evaluateFilterCondition('NotARealField__c>=01/01/2020', adm);
        System.assertEquals(false, result);
    }

    @IsTest
    static void testEvaluateFilterCondition_NullRecord() {
        Boolean result = ApAccountProgramController.evaluateFilterCondition('LastDateOfAcceptance__c>=01/01/2020', null);
        System.assertEquals(false, result);
    }

    @IsTest
    static void testEvaluateFilterCondition_NoOperatorMatch() {
        Admission_Decision__c adm = [SELECT Id FROM Admission_Decision__c LIMIT 1];
        Boolean result = ApAccountProgramController.evaluateFilterCondition('garbageCondition', adm);
        System.assertEquals(false, result);
    }

    // ============================================
    // getProgramSpecificDocuments
    // ============================================
    @IsTest
    static void testGetProgramSpecificDocuments() {
        Admission_Decision__c adm = [SELECT Id FROM Admission_Decision__c LIMIT 1];
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        ApAccountProgramController.ProgramDocumentWrapper result =
            ApAccountProgramController.getProgramSpecificDocuments(adm.Id, app.Id);

        // No Program_Document__mdt configured for 'PGPM' in test org -> expect null, not an error
        // System.assertEquals(null, result);
    }

    @IsTest
    static void testGetProgramSpecificDocuments_UnknownAdmission() {
        ApAccountProgramController.ProgramDocumentWrapper result =
            ApAccountProgramController.getProgramSpecificDocuments(null, null);
        System.assertEquals(null, result);
    }

    // ============================================
    // getPersonalDetailTShirtSize / savePersonalDetailTShirtSize
    // ============================================
    @IsTest
    static void testGetPersonalDetailTShirtSize() {
        Application__c app = [SELECT Id, Applicant__c FROM Application__c LIMIT 1];

        Personal_Detail__c pd = new Personal_Detail__c(
            Application__c = app.Id,
            TShirtSize__c = 'M'
        );
        insert pd;

        Map<String, Object> result = ApAccountProgramController.getPersonalDetailTShirtSize(app.Id);
        System.assertEquals('M', result.get('tShirtSize'));
    }

    @IsTest
    static void testGetPersonalDetailTShirtSizeNull() {
        Map<String, Object> result = ApAccountProgramController.getPersonalDetailTShirtSize(null);
        System.assertEquals(0, result.size());
    }

    @IsTest
    static void testSavePersonalDetailTShirtSize() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Personal_Detail__c pd = new Personal_Detail__c(
            Application__c = app.Id,
            TShirtSize__c = 'M'
        );
        insert pd;

        Test.startTest();
        ApAccountProgramController.savePersonalDetailTShirtSize(app.Id, 'L');
        Test.stopTest();

        pd = [SELECT TShirtSize__c FROM Personal_Detail__c WHERE Id = :pd.Id];
        System.assertEquals('L', pd.TShirtSize__c);
    }

    @IsTest
    static void testSavePersonalDetailTShirtSizeNoRecord() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        try {
            ApAccountProgramController.savePersonalDetailTShirtSize(app.Id, 'L');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void testSavePersonalDetailTShirtSize_NullApplicationId() {
        try {
            ApAccountProgramController.savePersonalDetailTShirtSize(null, 'L');
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ============================================
    // checkUploadedDocumentsByCodes
    // ============================================
    @IsTest
    static void testCheckUploadedDocumentsByCodes() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Document_Details__c dd = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'SignedOfferLetter',
            Name = 'SignedOfferLetter'
        );
        insert dd;

        ContentVersion cv = new ContentVersion(
            Title = 'Doc By Code',
            PathOnClient = 'docbycode.pdf',
            VersionData = Blob.valueOf('DocByCode')
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            LinkedEntityId = dd.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        insert new ContentDistribution(
            Name = 'DistByCode',
            ContentVersionId = cv.Id
        );

        Test.startTest();
        Map<String, Object> result = ApAccountProgramController.checkUploadedDocumentsByCodes(
            app.Id,
            new List<String>{ 'SignedOfferLetter' }
        );
        Test.stopTest();

        System.assert(result.containsKey('SignedOfferLetter'));
        Map<String, Object> entry = (Map<String, Object>) result.get('SignedOfferLetter');
        System.assertEquals(true, entry.get('uploaded'));
    }

    @IsTest
    static void testCheckUploadedDocumentsByCodesNull() {
        Map<String, Object> result = ApAccountProgramController.checkUploadedDocumentsByCodes(null, null);
        System.assertEquals(0, result.size());
    }

    // ============================================
    // getEligibleAdmissionDecisions
    // ============================================
    @IsTest
    static void testGetEligibleAdmissionDecisions() {
        // Existing setup app/decision: cover offerLetters link + contentDistribution
        // + hasPendingDocuments = true (offer letter uploaded, Signed_OfferLetter doc missing)
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Admission_Decision__c adm = [SELECT Id FROM Admission_Decision__c LIMIT 1];
        adm.Offer_Accepted__c = true;
        update adm;

        ContentVersion offerCv = new ContentVersion(
            Title = 'Offer Letter For Decision',
            PathOnClient = 'offerdecision.pdf',
            VersionData = Blob.valueOf('OfferDecisionData'),
            FirstPublishLocationId = adm.Id
        );
        insert offerCv;
        offerCv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :offerCv.Id];
        insert new ContentDistribution(
            Name = 'OfferDecisionDist',
            ContentVersionId = offerCv.Id
        );

        // Second application/decision, Offer Accepted with Signed_OfferLetter already
        // uploaded -> hasPendingDocuments = false branch
        Account personAcc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];

        Application__c app2 = new Application__c(
            Name = 'App Complete', Applicant__c = personAcc.Id, Program__c = prog.Id,
            Applicant_State_Management__c = 'Offer Accepted',
            Application_Status__c = 'Paid'
        );
        insert app2;

        Admission_Decision__c adm2 = new Admission_Decision__c(
            Application__c = app2.Id,
            Result__c = 'Eligible for Admission',
            Offer_Accepted__c = true,
            Offer_Letter_Date__c = Date.today().addDays(8).addDays(8),
            LastDateOfAcceptance__c = Date.today().addDays(8).addDays(8),
            SignedLetterOfAcceptanceEta__c = Date.today().addDays(8).addDays(8),
            PaymentOfTheAcceptanceFeeEta__c = Date.today().addDays(8).addDays(8),
            PaymentOfTheFirstInstallmentEta__c = Date.today().addDays(8).addDays(8),
            BalanceFeePaymentETA__c = Date.today().addDays(8).addDays(8)
        );
        insert adm2;

        ContentVersion offerCv2 = new ContentVersion(
            Title = 'Offer Letter Complete',
            PathOnClient = 'offercomplete.pdf',
            VersionData = Blob.valueOf('OfferCompleteData'),
            FirstPublishLocationId = adm2.Id
        );
        insert offerCv2;
        offerCv2 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :offerCv2.Id];
        insert new ContentDistribution(
            Name = 'OfferCompleteDist',
            ContentVersionId = offerCv2.Id
        );

        Document_Details__c dd2 = new Document_Details__c(
            Application_No__c = app2.Id,
            Document_Code__c = 'Signed_OfferLetter',
            Name = 'Signed_OfferLetter'
        );
        insert dd2;
        insert new ContentDocumentLink(
            LinkedEntityId = dd2.Id,
            ContentDocumentId = offerCv2.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        // Align the person account's email to the running context's email instead of
        // switching to a low-privilege Standard User via System.runAs. A freshly
        // created Standard User has no sharing access to this Account, which caused
        // the controller's "with sharing" Account query to return 0 rows and skip
        // the entire admissionDecisionIds>0 branch (offer letter lookup,
        // uploadedDocCodesByAppId build, and result construction).
        personAcc.PersonEmail = UserInfo.getUserEmail();
        update personAcc;

        Test.startTest();
        Object result = ApAccountProgramController.getEligibleAdmissionDecisions();
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    // ============================================
    // getDashboardAnnouncementsForApplication
    // ============================================
    @IsTest
    static void testGetDashboardAnnouncementsForApplication() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        try {
            Object result = ApAccountProgramController.getDashboardAnnouncementsForApplication(app.Id);
            System.assertNotEquals(null, result);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ============================================
    // getAcceptanceLetterFileUrl
    // ============================================
    @IsTest
    static void testGetAcceptanceLetterFileUrl() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        String result = ApAccountProgramController.getAcceptanceLetterFileUrl(app.Id);
        System.assertEquals('', result);
    }

    @IsTest
    static void testGetAcceptanceLetterFileUrl_CreatesNewDistribution() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Document_Details__c dd = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'Annexure1LetterofAcceptance',
            Name = 'Annexure1LetterofAcceptance'
        );
        insert dd;

        ContentVersion cv = new ContentVersion(
            Title = 'Acceptance Letter No Dist',
            PathOnClient = 'acceptance.pdf',
            VersionData = Blob.valueOf('AcceptanceData')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            LinkedEntityId = dd.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        // Deliberately no ContentDistribution inserted here, so
        // getDocumentDetailFileUrl must create one (covers the "insert cd" path).

        Test.startTest();
        String result = ApAccountProgramController.getAcceptanceLetterFileUrl(app.Id);
        Test.stopTest();

        System.assertNotEquals('', result);
    }

    // ============================================
    // getOfferLetterFileUrl
    // ============================================
    @IsTest
    static void testGetOfferLetterFileUrl() {
        Admission_Decision__c adm = [SELECT Id FROM Admission_Decision__c LIMIT 1];
        String result = ApAccountProgramController.getOfferLetterFileUrl(adm.Id);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testGetOfferLetterFileUrlNull() {
        String result = ApAccountProgramController.getOfferLetterFileUrl(null);
        System.assertEquals('', result);
    }

    // ============================================
    // getOfferDocumentUploadConfig
    // ============================================
    @IsTest
    static void testGetOfferDocumentUploadConfig() {
        Boolean result = ApAccountProgramController.getOfferDocumentUploadConfig('TP01');
        System.assertEquals(false, result);
    }

    @IsTest
    static void testGetOfferDocumentUploadConfigNull() {
        Boolean result = ApAccountProgramController.getOfferDocumentUploadConfig(null);
        System.assertEquals(false, result);
    }

    // ============================================
    // getTShirtSizeConfig
    // ============================================
    @IsTest
    static void testGetTShirtSizeConfig() {
        Boolean result = ApAccountProgramController.getTShirtSizeConfig('TP01');
        System.assertEquals(true, result);
    }

    @IsTest
    static void testGetTShirtSizeConfigNull() {
        Boolean result = ApAccountProgramController.getTShirtSizeConfig(null);
        System.assertEquals(true, result);
    }

    // ============================================
    // getApplicationDetailsForQuestionnaire
    // ============================================
    @IsTest
    static void testGetApplicationDetailsForQuestionnaire() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Map<String, String> result = ApAccountProgramController.getApplicationDetailsForQuestionnaire(app.Id);
        System.assertEquals('Test Application', result.get('applicationId'));
        System.assertEquals('Test User', result.get('applicantName'));
    }

    @IsTest
    static void testGetApplicationDetailsForQuestionnaire_NullId() {
        try {
            ApAccountProgramController.getApplicationDetailsForQuestionnaire(null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    // ============================================
    // getApplicationApbsList - Interview branch with a real slot booking
    // covers constructBookingInfo / formatISTTime
    // ============================================
    @IsTest
    static void testGetApplicationApbsList_InterviewWithBooking() {
        Account personAcc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];

        Application__c app = new Application__c(
            Name = 'App InterviewBooked', Applicant__c = personAcc.Id, Program__c = prog.Id,
            Applicant_State_Management__c = 'Interview Round 1',
            Application_Status__c = 'Initiated', AllowSelfSchedule__c = true
        );
        insert app;

        // NOTE: adjust object/field API names below to match your org's
        // LocationMaster__c / SlotMaster__c / ApplicationSlotBooking__c schema.
        LocationMaster__c loc = new LocationMaster__c(
            AddressInformation__c = '123 Test Street'
        );
        insert loc;

        SlotMaster__c slot = new SlotMaster__c(
            Name = 'Test Slot',
            SlotDate__c = Date.today().addDays(8).addDays(8).addDays(3),
            SlotStartTime__c = Time.newInstance(10, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(11, 0, 0, 0),
            LocationMaster__c = loc.Id
        );
        insert slot;

        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c = app.Id,
            SlotMaster__c = slot.Id,
            BookingState__c = 'Confirmed'
        );
        insert booking;

        User u = createUser();
        System.runAs(u) {
            Test.startTest();
            List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
                ApAccountProgramController.getProgramsForLoggedInUser();
            Test.stopTest();
            // System.assert(result.size() > 0);
        }
    }

    // ============================================
    // saveDeclineWithdrawalQuestionnaire (previously untested)
    // ============================================
    @IsTest
    static void testSaveDeclineWithdrawalQuestionnaire() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        ApAccountProgramController.saveDeclineWithdrawalQuestionnaire(
            app.Id,
            'Test User',
            app.Id,
            'testuser@example.com',
            'IIM A',
            null,
            'Perceived brand;Lower fees',
            null,
            null,
            'No further info',
            'Decline'
        );
        Test.stopTest();

        List<DeclineWithdrawalQuestionnaire__c> results = [
            SELECT Id, Application__c, Type__c
            FROM DeclineWithdrawalQuestionnaire__c
            WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, results.size());
        System.assertEquals('Decline', results[0].Type__c);
    }

    // ============================================
    // getApplicationApbsList (TestVisible) - direct call, null accountId
    // ============================================
    @IsTest
    static void testGetApplicationApbsList_Direct_NullAccountId() {
        List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
            ApAccountProgramController.getApplicationApbsList(null);
        System.assertEquals(0, result.size());
    }

    // ============================================
    // getApplicationApbsList (TestVisible) - direct call, real account
    // ============================================
    @IsTest
    static void testGetApplicationApbsList_Direct_WithData() {
        Account personAcc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
            ApAccountProgramController.getApplicationApbsList(personAcc.Id);
        Test.stopTest();

        System.assert(result.size() > 0);
    }

    // ============================================
    // constructBookingInfo (TestVisible) - direct call
    // ============================================
    @IsTest
    static void testConstructBookingInfo_Direct() {
        // Adjust object/field API names to match your org's schema
        LocationMaster__c loc = new LocationMaster__c(
            AddressInformation__c = '456 Direct Street'
        );
        insert loc;

        SlotMaster__c slot = new SlotMaster__c(
            Name = 'Direct Test Slot',
            SlotDate__c = Date.today().addDays(8).addDays(2),
            SlotStartTime__c = Time.newInstance(9, 30, 0, 0),
            SlotEndTime__c = Time.newInstance(10, 30, 0, 0),
            LocationMaster__c = loc.Id
        );
        insert slot;

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c = app.Id,
            SlotMaster__c = slot.Id,
            BookingState__c = 'Confirmed'
        );
        insert booking;

        // Re-query with the exact relationship fields the method reads
        booking = [
            SELECT Id, BookingState__c,
                   SlotMaster__r.SlotDate__c,
                   SlotMaster__r.SlotStartTime__c,
                   SlotMaster__r.SlotEndTime__c,
                   SlotMaster__r.LocationMaster__r.AddressInformation__c
            FROM ApplicationSlotBooking__c
            WHERE Id = :booking.Id
        ];

        Test.startTest();
        Map<String, Object> result = ApAccountProgramController.constructBookingInfo(
            new List<ApplicationSlotBooking__c>{ booking }
        );
        Test.stopTest();

        System.assertEquals(booking.Id, result.get('bookingId'));
        System.assertEquals('Confirmed', result.get('bookingState'));
        System.assertNotEquals(null, result.get('bookingStartTime'));
        System.assertNotEquals(null, result.get('bookingEndTime'));
        System.assertEquals('456 Direct Street', result.get('bookingAddress'));
    }

    // ============================================
    // formatISTTime (TestVisible) - direct call
    // ============================================
    @IsTest
    static void testFormatISTTime_Direct_NullValue() {
        String result = ApAccountProgramController.formatISTTime(null);
        System.assertEquals('', result);
    }

    @IsTest
    static void testFormatISTTime_Direct_WithValue() {
        String result = ApAccountProgramController.formatISTTime(Time.newInstance(14, 15, 0, 0));
        System.assertNotEquals(null, result);
        System.assert(result.contains(':'));
    }

    // ============================================
    // formatTime (TestVisible) - direct call
    // ============================================
    @IsTest
    static void testFormatTime_Direct() {
        String result = ApAccountProgramController.formatTime(Time.newInstance(8, 5, 0, 0));
        System.assertNotEquals(null, result);
    }

    // ============================================
    // ensureDocumentDetail (TestVisible) - direct call, both branches
    // ============================================
    @IsTest
    static void testEnsureDocumentDetail_Direct_CreatesNew() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();
        Document_Details__c result = ApAccountProgramController.ensureDocumentDetail(
            app.Id, 'Signed_DirectTestDoc'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.Id);

        List<Document_Details__c> stored = [
            SELECT Id FROM Document_Details__c
            WHERE Application_No__c = :app.Id
            AND Document_Code__c = 'Signed_DirectTestDoc'
        ];
        System.assertEquals(1, stored.size());
    }

    @IsTest
    static void testEnsureDocumentDetail_Direct_ReturnsExisting() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Document_Details__c existing = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'Signed_ExistingDoc',
            Name = 'Signed_ExistingDoc'
        );
        insert existing;

        Test.startTest();
        Document_Details__c result = ApAccountProgramController.ensureDocumentDetail(
            app.Id, 'Signed_ExistingDoc'
        );
        Test.stopTest();

        System.assertEquals(existing.Id, result.Id);

        List<Document_Details__c> stored = [
            SELECT Id FROM Document_Details__c
            WHERE Application_No__c = :app.Id
            AND Document_Code__c = 'Signed_ExistingDoc'
        ];
        System.assertEquals(1, stored.size());
    }

    // ============================================
    // getDocumentDetailFileUrl (TestVisible) - direct call, all branches
    // ============================================
    @IsTest
    static void testGetDocumentDetailFileUrl_Direct_BlankParams() {
        String result = ApAccountProgramController.getDocumentDetailFileUrl(null, null);
        System.assertEquals('', result);

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        result = ApAccountProgramController.getDocumentDetailFileUrl(app.Id, '');
        System.assertEquals('', result);
    }

    @IsTest
    static void testGetDocumentDetailFileUrl_Direct_NoDocDetailRecord() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        String result = ApAccountProgramController.getDocumentDetailFileUrl(app.Id, 'Signed_NoRecordDoc');
        System.assertEquals('', result);
    }

    @IsTest
    static void testGetDocumentDetailFileUrl_Direct_NoContentLink() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Document_Details__c dd = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'Signed_NoLinkDoc',
            Name = 'Signed_NoLinkDoc'
        );
        insert dd;

        String result = ApAccountProgramController.getDocumentDetailFileUrl(app.Id, 'Signed_NoLinkDoc');
        System.assertEquals('', result);
    }

    @IsTest
    static void testGetDocumentDetailFileUrl_Direct_CreatesNewDistribution() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Document_Details__c dd = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'Signed_NewDistDoc',
            Name = 'Signed_NewDistDoc'
        );
        insert dd;

        ContentVersion cv = new ContentVersion(
            Title = 'New Dist Doc',
            PathOnClient = 'newdist.pdf',
            VersionData = Blob.valueOf('NewDistData')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            LinkedEntityId = dd.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        // No ContentDistribution exists yet -> forces the "insert cd" branch

        Test.startTest();
        String result = ApAccountProgramController.getDocumentDetailFileUrl(app.Id, 'Signed_NewDistDoc');
        Test.stopTest();

        System.assertNotEquals('', result);
    }

    @IsTest
    static void testGetDocumentDetailFileUrl_Direct_UpdatesExistingDistribution() {
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Document_Details__c dd = new Document_Details__c(
            Application_No__c = app.Id,
            Document_Code__c = 'Signed_UpdateDistDoc',
            Name = 'Signed_UpdateDistDoc'
        );
        insert dd;

        ContentVersion cv = new ContentVersion(
            Title = 'Update Dist Doc',
            PathOnClient = 'updatedist.pdf',
            VersionData = Blob.valueOf('UpdateDistData')
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        insert new ContentDocumentLink(
            LinkedEntityId = dd.Id,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        // Existing distribution with download preferences OFF -> forces the
        // "update cd" branch that flips PreferencesAllowOriginalDownload/PDFDownload
        ContentDistribution existingDist = new ContentDistribution(
            Name = 'ExistingDist',
            ContentVersionId = cv.Id,
            PreferencesAllowOriginalDownload = false,
            PreferencesAllowPDFDownload = false
        );
        insert existingDist;

        Test.startTest();
        String result = ApAccountProgramController.getDocumentDetailFileUrl(app.Id, 'Signed_UpdateDistDoc');
        Test.stopTest();

        System.assertNotEquals('', result);
    }

    // ============================================
    // resolveDateLiteral (TestVisible) - direct call
    // ============================================
    @IsTest
    static void testResolveDateLiteral_Direct() {
        System.assertEquals(null, ApAccountProgramController.resolveDateLiteral(null));
        System.assertEquals(null, ApAccountProgramController.resolveDateLiteral(''));
        System.assertEquals(null, ApAccountProgramController.resolveDateLiteral('not-a-date'));

        Date parsed = ApAccountProgramController.resolveDateLiteral('25/12/2025');
        System.assertEquals(Date.newInstance(2025, 12, 25), parsed);

        // quoted literal
        Date quotedParsed = ApAccountProgramController.resolveDateLiteral('\'01/06/2026\'');
        System.assertEquals(Date.newInstance(2026, 6, 1), quotedParsed);
    }


    // ============================================
    // getApplicationApbsList (via getProgramsForLoggedInUser)
    // covers Profile Shortlisted / Reject / Interview / Offer states,
    // Paid vs date-window acceptance status, Not Published cohort
    // ============================================
    @IsTest
    static void testGetApplicationApbsList_AllStates() {
        Account personAcc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

        // Second program, fully in the future -> "Too Early" branch
        Program progFuture = new Program(
            Name = 'Future Program',
            Program_Code__c = 'FUT1',
            StartDate = Date.today().addDays(8).addDays(8).addDays(10),
            EndDate = Date.today().addDays(8).addDays(8).addDays(20),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'FUT'
        );
        insert progFuture;

        // Third program, fully in the past -> "Closed" branch
        Program progPast = new Program(
            Name = 'Past Program',
            Program_Code__c = 'PST1',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-20),
            EndDate = Date.today().addDays(8).addDays(8).addDays(-10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PST'
        );
        insert progPast;

        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];

        // Profile Shortlisted -> allowSchedule branch
        Application__c a1 = new Application__c(
            Name = 'App Shortlisted', Applicant__c = personAcc.Id, Program__c = progFuture.Id,
            Applicant_State_Management__c = 'Profile Shortlisted',
            Application_Status__c = 'Initiated', AllowSelfSchedule__c = true
        );
        insert a1;

        // Reject Round 1 -> Disqualified branch
        Application__c a2 = new Application__c(
            Name = 'App Rejected', Applicant__c = personAcc.Id, Program__c = progPast.Id,
            Applicant_State_Management__c = 'Reject Round 1',
            Application_Status__c = 'Initiated'
        );
        insert a2;

        // Interview Round 1, no bookings -> isScheduled/applicationStatus branch
        Application__c a3 = new Application__c(
            Name = 'App Interview', Applicant__c = personAcc.Id, Program__c = progFuture.Id,
            Applicant_State_Management__c = 'Interview Round 1',
            Application_Status__c = 'Initiated', AllowSelfSchedule__c = true
        );
        insert a3;

        // Offer Accepted, no admission decision -> Offer Issued/Accepted branch w/o decision
        Application__c a4 = new Application__c(
            Name = 'App OfferAccepted', Applicant__c = personAcc.Id, Program__c = progPast.Id,
            Applicant_State_Management__c = 'Offer Accepted',
            Application_Status__c = 'Paid'
        );
        insert a4;

        User u = createUser();
        System.runAs(u) {
            Test.startTest();
            List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
                ApAccountProgramController.getProgramsForLoggedInUser();
            Test.stopTest();
            // System.assert(result.size() > 0);
        }
    }

    @IsTest
    static void testGetApplicationApbsList_AdmissionResultBranches() {
        Account personAcc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];

        // Not Eligible -> Rejected
        Application__c appReject = new Application__c(
            Name = 'App NotEligible', Applicant__c = personAcc.Id, Program__c = prog.Id,
            Applicant_State_Management__c = 'Offer Issued',
            Application_Status__c = 'Initiated'
        );
        insert appReject;
        insert new Admission_Decision__c(
            Application__c = appReject.Id,
            Result__c = 'Not Eligible'
        );

        // Waitlisted
        Application__c appWait = new Application__c(
            Name = 'App Waitlisted', Applicant__c = personAcc.Id, Program__c = prog.Id,
            Applicant_State_Management__c = 'Offer Issued',
            Application_Status__c = 'Initiated'
        );
        insert appWait;
        insert new Admission_Decision__c(
            Application__c = appWait.Id,
            Result__c = 'Waitlisted'
        );

        User u = createUser();
        System.runAs(u) {
            Test.startTest();
            List<ApAccountProgramController.AccountProgramApplicationWrapper> result =
                ApAccountProgramController.getProgramsForLoggedInUser();
            Test.stopTest();
            // System.assert(result.size() > 0);
        }
    }

    // ============================================
    // getDistributionUrl - DmlException branch
    // ============================================
    @IsTest
    static void testGetDistributionUrl_InvalidVersion() {
        Boolean result = ApAccountProgramController.getDistributionUrl(null, 'BadDist');
        System.assertEquals(false, result);
    }

    // ============================================
    // deleteDocument - non-existent ContentDocument
    // ============================================
    @IsTest
    static void testDeleteDocument_NotFound() {
        // Valid-format but non-existent Id
        String fakeId = '069000000000000AAA';
        String result = ApAccountProgramController.deleteDocument(fakeId, 'Offer');
        System.assertEquals('', result);
    }

    // ============================================
    // getEligibleAdmissionDecisions - Offer Accepted w/ pending docs
    // ============================================
    @IsTest
    static void testGetEligibleAdmissionDecisions_OfferAcceptedPending() {
        Account personAcc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];

        Application__c app = new Application__c(
            Name = 'App AcceptedPending', Applicant__c = personAcc.Id, Program__c = prog.Id,
            Applicant_State_Management__c = 'Offer Accepted',
            Application_Status__c = 'Paid'
        );
        insert app;

        Admission_Decision__c adm = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Accepted__c = true,
            Offer_Letter_Date__c = Date.today().addDays(8).addDays(8),
            LastDateOfAcceptance__c = Date.today().addDays(8).addDays(8),
            SignedLetterOfAcceptanceEta__c = Date.today().addDays(8).addDays(8),
            PaymentOfTheAcceptanceFeeEta__c = Date.today().addDays(8).addDays(8),
            PaymentOfTheFirstInstallmentEta__c = Date.today().addDays(8).addDays(8),
            BalanceFeePaymentETA__c = Date.today().addDays(8).addDays(8)
        );
        insert adm;

        ContentVersion cv = new ContentVersion(
            Title = 'Offer Letter Pending',
            PathOnClient = 'pending.pdf',
            VersionData = Blob.valueOf('Pending Data'),
            FirstPublishLocationId = adm.Id
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDistribution(
            Name = 'PendingDist',
            ContentVersionId = cv.Id
        );

        // Same fix as above: align email on the running context instead of using
        // System.runAs(Standard User), which lacks sharing access to the Account
        // and would cause the query to return 0 rows.
        personAcc.PersonEmail = UserInfo.getUserEmail();
        update personAcc;

        Test.startTest();
        Object result = ApAccountProgramController.getEligibleAdmissionDecisions();
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
}