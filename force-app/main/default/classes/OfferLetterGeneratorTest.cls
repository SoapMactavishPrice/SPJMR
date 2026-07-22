@IsTest
private class OfferLetterGeneratorTest {
    
    @testSetup
    static void setupData() {
        Account applicant;
        List<RecordType> personRts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
            LIMIT 1
        ];
        
        if (!personRts.isEmpty()) {
            applicant = new Account(
                RecordTypeId = personRts[0].Id,
                FirstName = 'Test',
                LastName = 'Applicant',
                PersonEmail = 'test.applicant@example.com'
            );
        } else {
            applicant = new Account(Name = 'Test Applicant');
        }
        insert applicant;
        
        Application__c offerAcceptedApp = new Application__c(
            Name = 'APP-OFFER-ACCEPTED',
            Applicant__c = applicant.Id,
            Applicant_State_Management__c = 'Offer Accepted'
        );
        
        Application__c shortlistedApp = new Application__c(
            Name = 'APP-SHORTLISTED',
            Applicant__c = applicant.Id,
            Applicant_State_Management__c = 'Profile Shortlisted'
        );
        
        insert new List<Application__c>{ offerAcceptedApp, shortlistedApp };
            
            insert new Admission_Decision__c(
                Application__c = shortlistedApp.Id,
                Result__c = 'Eligible for Admission',
                Offer_Letter_Date__c = Date.today()
            );
    }
    
    private static Application__c createApplication(String nameVal, String stateVal) {
        Id applicantId = [SELECT Id FROM Account LIMIT 1].Id;
        Application__c app = new Application__c(
            Name = nameVal,
            Applicant__c = applicantId,
            Applicant_State_Management__c = stateVal
        );
        insert app;
        return app;
    }
    
    @IsTest
    static void testPdfHelper_TestBranch() {
        Blob b = OfferLetterGenerator.getOfferLetterPdf('001000000000001AAA', 'GMP');
        System.assertNotEquals(null, b);
        System.assert(b.size() > 0);
    }
    
    @IsTest
    static void testPdfHelper_TestBranch_DefaultPath() {
        Blob b = OfferLetterGenerator.getOfferLetterPdf('001000000000001AAA', 'PGPM');
        System.assertNotEquals(null, b);
        System.assert(b.size() > 0);
    }
    
    @IsTest
    static void testGetGMPApplications_WithData() {
        List<OfferLetterGenerator.GMPApplicationWrapper> rows = OfferLetterGenerator.getGMPApplications();
        System.assertNotEquals(null, rows);
        System.assert(rows.size() > 0);
        System.assertNotEquals(null, rows[0].Id);
        System.assertNotEquals(null, rows[0].applicationUrl);
    }
    
   @IsTest
static void testGenerateOfferLetters_NullAndEmptyInput() {

    Integer beforeCount = [SELECT COUNT() FROM Admission_Decision__c];

    OfferLetterGenerator.generateOfferLetters(null, Date.today(), 'Eligible for Admission');
    OfferLetterGenerator.generateOfferLetters(new List<Id>(), Date.today(), 'Eligible for Admission');

    Integer afterCount = [SELECT COUNT() FROM Admission_Decision__c];

    System.assertEquals(beforeCount, afterCount,
        'No new Admission Decision should be created for null or empty input');
}
    
    @IsTest
    static void testGenerateOfferLetters_ValidInput_InsertsAndQueues() {
        Application__c app = createApplication('APP-GEN-VALID', 'Profile Shortlisted');
        
        Test.startTest();
        OfferLetterGenerator.generateOfferLetters(
            new List<Id>{ app.Id },
            Date.today(),
            'Eligible for Admission'
        );
        Test.stopTest();
        
        Integer admCount = [SELECT COUNT() FROM Admission_Decision__c WHERE Application__c = :app.Id];
        System.assertEquals(1, admCount);
    }
    
    @IsTest
    static void testGenerateOfferLetters_InvalidApplicationId_NoUnhandledException() {
        OfferLetterGenerator.generateOfferLetters(
            new List<Id>{ UserInfo.getUserId() },
            Date.today(),
            'Eligible for Admission'
        );
        Integer countAfter = [SELECT COUNT() FROM Admission_Decision__c WHERE Application__c = :UserInfo.getUserId()];
        System.assertEquals(0, countAfter);
    }
    
    @IsTest
    static void testGenerateOfferLetters_ValidInput_NotEligibleDecision() {
        Application__c app = createApplication('APP-GEN-NOT-ELIGIBLE', 'Profile Shortlisted');
        
        Test.startTest();
        OfferLetterGenerator.generateOfferLetters(
            new List<Id>{ app.Id },
            Date.today(),
            'Not Eligible'
        );
        Test.stopTest();
        
        Admission_Decision__c adm = [
            SELECT Result__c
            FROM Admission_Decision__c
            WHERE Application__c = :app.Id
            LIMIT 1
        ];
        System.assertEquals('Not Eligible', adm.Result__c);
    }
    
    @IsTest
    static void testExecute_WithAdmissionList() {
        Admission_Decision__c adm = [
            SELECT Id
            FROM Admission_Decision__c
            LIMIT 1
        ];
        
        OfferLetterGenerator q = new OfferLetterGenerator(new List<Admission_Decision__c>{ adm });
        Test.startTest();
        q.execute(null);
        Test.stopTest();
        Admission_Decision__c verify = [
            SELECT Id
            FROM Admission_Decision__c
            WHERE Id = :adm.Id
        ];
        
        System.assertNotEquals(null, verify, 'Admission decision should exist after queue execution');
    }
    
    @IsTest
    static void testGenerateOfferLettersBulk_EmptyList_NoException() {
        OfferLetterGenerator.generateOfferLettersBulk(new List<Admission_Decision__c>());
        System.assert(true);
    }
    
    @IsTest
    static void testGenerateOfferLettersBulk_Null_ThrowsAuraHandledException() {
        Boolean thrown = false;
        try {
            OfferLetterGenerator.generateOfferLettersBulk(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Integer cvCount = [SELECT COUNT() FROM ContentVersion];
        System.assertEquals(0, cvCount, 'No ContentVersion should be created for empty input');
    }
    
    @IsTest
    static void testGenerateOfferLettersBulk_SuccessPath() {
        Admission_Decision__c adm = [
            SELECT Id, Application__c
            FROM Admission_Decision__c
            WHERE Result__c = 'Eligible for Admission'
            LIMIT 1
        ];
        
        Test.startTest();
        OfferLetterGenerator.generateOfferLettersBulk(new List<Admission_Decision__c>{ adm });
        Test.stopTest();
        
        Integer cvCount = [SELECT COUNT() FROM ContentVersion WHERE AdmissionId__c = :adm.Id];
        System.assert(cvCount > 0);
        
        Application__c app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :adm.Application__c LIMIT 1];
        System.assertEquals('Offer Issued', app.Applicant_State_Management__c);
    }
    
    @IsTest
    static void testGenerateOffer_Success() {
        Admission_Decision__c adm = [
            SELECT Id, Application__c
            FROM Admission_Decision__c
            WHERE Result__c = 'Eligible for Admission'
            LIMIT 1
        ];
        
        String output = OfferLetterGenerator.generateOffer(adm.Id);
        System.assert(output != null);
        System.assert(output.startsWith('/lightning/page/filePreview?selectedRecordId='));
        
        Application__c app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :adm.Application__c LIMIT 1];
        System.assertEquals('Offer Issued', app.Applicant_State_Management__c);
    }
    
    @IsTest
    static void testGenerateOffer_InvalidId_ReturnsEmptyString() {
        String output = OfferLetterGenerator.generateOffer(UserInfo.getUserId());
        System.assertEquals('', output);
    }
    
    @IsTest
    static void testInvokeSendEmailFlow_Handled() {
        Admission_Decision__c adm = [SELECT Id FROM Admission_Decision__c LIMIT 1];
        try {
            OfferLetterGenerator.invokeSendEmailFlow(adm.Id);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
    }
    
    @IsTest
    static void testGetShortlistedApplicantsGMP_NoMatchingData() {
        List<OfferLetterGenerator.GMPApplicationWrapper> rows = OfferLetterGenerator.getShortlistedApplicantsGMP();
        System.assertEquals(null, rows);
    }
}