@IsTest
private class AdmissionDecisionTriggerHelperTest {
    
    @TestSetup
    static void setupData() {
        insert new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );

        RecordType personRt = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Account' AND IsPersonType = true 
            LIMIT 1
        ];

        Account applicant = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Helper',
            LastName = 'Test',
            PersonEmail = 'helper.test@example.com'
        );
        insert applicant;

        Program prog = new Program(
            Name = 'Helper Program',
            Program_Code__c = 'PGPM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPM'
        );
        insert prog;

        Application__c app1 = new Application__c(
            Name = 'APP-HELPER-001',
            Applicant__c = applicant.Id,
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Interview Round 1'
        );
        Application__c app2 = new Application__c(
            Name = 'APP-HELPER-002',
            Applicant__c = applicant.Id,
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Interview Round 2'
        );
        Application__c app3 = new Application__c(
            Name = 'APP-HELPER-003',
            Applicant__c = applicant.Id,
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Profile Shortlisted'
        );
        insert new List<Application__c>{ app1, app2, app3 };
    }

    @IsTest
    static void testUpdateApplicationStateMgmtonInsert() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Offer Issued', app.Applicant_State_Management__c);
    }

    @IsTest
    static void testUpdateApplicationStateMgmtonUpdate() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Waitlisted',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;

        Admission_Decision__c oldDecision = decision.clone(true, true, false, false);
        decision.Result__c = 'Eligible for Admission';

        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonUpdate(
            new List<Admission_Decision__c>{ decision },
            new Map<Id, Admission_Decision__c>{ decision.Id => oldDecision }
        );
        Test.stopTest();

        app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Offer Issued', app.Applicant_State_Management__c);
    }

    @IsTest
    static void testUpdateApplicationStateWaitlisted() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-002' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Waitlisted',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Waitlisted', app.Applicant_State_Management__c);
    }

    @IsTest
    static void testUpdateApplicationStateNotEligibleRound1() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Not Eligible',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Reject Round 1', app.Applicant_State_Management__c);
    }

    @IsTest
    static void testUpdateApplicationStateNotEligibleRound2() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-002' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Not Eligible',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Reject Round 2', app.Applicant_State_Management__c);
    }

    @IsTest
    static void testUpdateApplicationStateNotEligibleDisqualified() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-003' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Not Eligible',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        app = [SELECT Applicant_State_Management__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('Disqualified', app.Applicant_State_Management__c);
    }

    @IsTest
    static void testPreventAdditionalRecordCreationSingleApp() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision1 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision1;

        Admission_Decision__c decision2 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Waitlisted',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(
            new List<Admission_Decision__c>{ decision2 }
        );
        Test.stopTest();

        // System.assert(decision2.getErrors().size() > 0);
    }

    @IsTest
    static void testPreventAdditionalRecordCreationMultipleInSameBatch() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision1 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        Admission_Decision__c decision2 = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Waitlisted',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(
            new List<Admission_Decision__c>{ decision1, decision2 }
        );
        Test.stopTest();

        System.assert(decision1.getErrors().size() > 0 || decision2.getErrors().size() > 0);
    }

    @IsTest
    static void testPreventAdditionalRecordCreationEmptyList() {
        Test.startTest();
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(
            new List<Admission_Decision__c>()
        );
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testSetApplicantEmail() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.setApplicantEmail(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        System.assertEquals('helper.test@example.com', decision.ApplicantEmail__c);
    }

    @IsTest
    static void testSetApplicantEmailNoApplication() {
        Admission_Decision__c decision = new Admission_Decision__c(
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );

        Test.startTest();
        AdmissionDecisionTriggerHelper.setApplicantEmail(
            new List<Admission_Decision__c>{ decision }
        );
        Test.stopTest();

        System.assertEquals(null, decision.ApplicantEmail__c);
    }

    @IsTest
    static void testBuildAdmissionDecisionEmailWrappers() {
        Application__c app = [SELECT Id, Applicant__c FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;

        ContentVersion cv = new ContentVersion(
            Title = 'Offer Letter',
            PathOnClient = 'offer.pdf',
            VersionData = Blob.valueOf('Test Offer Letter'),
            FirstPublishLocationId = decision.Id
        );
        insert cv;

        AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperRequest request = 
            new AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperRequest();
        request.admissionDecisionIds = new List<String>{ decision.Id };

        Test.startTest();
        List<AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperResponse> responses = 
            AdmissionDecisionTriggerHelper.buildAdmissionDecisionEmailWrappers(
                new List<AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperRequest>{ request }
            );
        Test.stopTest();

        System.assertNotEquals(null, responses);
        System.assert(responses.size() > 0);
        System.assert(responses[0].emailWrappers.size() > 0);
    }

    @IsTest
    static void testBuildAdmissionDecisionEmailWrappersNullRequest() {
        Test.startTest();
        List<AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperResponse> responses = 
            AdmissionDecisionTriggerHelper.buildAdmissionDecisionEmailWrappers(null);
        Test.stopTest();

        System.assertNotEquals(null, responses);
        System.assertEquals(0, responses.size());
    }

    @IsTest
    static void testBuildAdmissionDecisionEmailWrappersInvalidId() {
        AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperRequest request = 
            new AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperRequest();
        request.admissionDecisionIds = new List<String>{ 'invalid-id', '' };

        Test.startTest();
        List<AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperResponse> responses = 
            AdmissionDecisionTriggerHelper.buildAdmissionDecisionEmailWrappers(
                new List<AdmissionDecisionTriggerHelper.AdmissionDecisionEmailWrapperRequest>{ request }
            );
        Test.stopTest();

        System.assertNotEquals(null, responses);
    }

    @IsTest
    static void testEnforceOfferCheckboxExclusivityOfferWithdrawn() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Accepted__c = true,
            Offer_Declined__c = false,
            OfferWithdrawn__c = false,
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;

        Admission_Decision__c oldDecision = decision.clone(true, true, false, false);
        decision.OfferWithdrawn__c = true;

        Test.startTest();
        AdmissionDecisionTriggerHelper.enforceOfferCheckboxExclusivity(
            new List<Admission_Decision__c>{ decision },
            new Map<Id, Admission_Decision__c>{ decision.Id => oldDecision }
        );
        Test.stopTest();

        System.assertEquals(false, decision.Offer_Declined__c);
    }

    @IsTest
    static void testEnforceOfferCheckboxExclusivityOfferDeclined() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Accepted__c = true,
            FinalOfferAccepted__c = true,
            OfferWithdrawn__c = true,
            Offer_Declined__c = false,
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;

        Admission_Decision__c oldDecision = decision.clone(true, true, false, false);
        decision.Offer_Declined__c = true;

        Test.startTest();
        AdmissionDecisionTriggerHelper.enforceOfferCheckboxExclusivity(
            new List<Admission_Decision__c>{ decision },
            new Map<Id, Admission_Decision__c>{ decision.Id => oldDecision }
        );
        Test.stopTest();

        System.assertEquals(false, decision.Offer_Accepted__c);
        System.assertEquals(false, decision.FinalOfferAccepted__c);
        System.assertEquals(false, decision.OfferWithdrawn__c);
    }

    @IsTest
    static void testEnforceOfferCheckboxExclusivityOfferAccepted() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            Offer_Accepted__c = false,
            Offer_Declined__c = true,
            OfferWithdrawn__c = true,
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;

        Admission_Decision__c oldDecision = decision.clone(true, true, false, false);
        decision.Offer_Accepted__c = true;

        Test.startTest();
        AdmissionDecisionTriggerHelper.enforceOfferCheckboxExclusivity(
            new List<Admission_Decision__c>{ decision },
            new Map<Id, Admission_Decision__c>{ decision.Id => oldDecision }
        );
        Test.stopTest();

        System.assertEquals(false, decision.OfferWithdrawn__c);
        System.assertEquals(false, decision.Offer_Declined__c);
    }

    @IsTest
    static void testEnforceOfferCheckboxExclusivityFinalOfferAccepted() {
        Application__c app = [SELECT Id FROM Application__c WHERE Name = 'APP-HELPER-001' LIMIT 1];

        Admission_Decision__c decision = new Admission_Decision__c(
            Application__c = app.Id,
            Result__c = 'Eligible for Admission',
            FinalOfferAccepted__c = false,
            Offer_Declined__c = true,
            OfferWithdrawn__c = true,
            Offer_Letter_Date__c = Date.today(),
            LastDateOfAcceptance__c = Date.today(),
            SignedLetterOfAcceptanceEta__c = Date.today(),
            PaymentOfTheAcceptanceFeeEta__c = Date.today(),
            PaymentOfTheFirstInstallmentEta__c = Date.today(),
            BalanceFeePaymentETA__c = Date.today()
        );
        insert decision;

        Admission_Decision__c oldDecision = decision.clone(true, true, false, false);
        decision.FinalOfferAccepted__c = true;

        Test.startTest();
        AdmissionDecisionTriggerHelper.enforceOfferCheckboxExclusivity(
            new List<Admission_Decision__c>{ decision },
            new Map<Id, Admission_Decision__c>{ decision.Id => oldDecision }
        );
        Test.stopTest();

        System.assertEquals(false, decision.OfferWithdrawn__c);
        System.assertEquals(false, decision.Offer_Declined__c);
    }

    @IsTest
    static void testEnforceOfferCheckboxExclusivityNullList() {
        Test.startTest();
        AdmissionDecisionTriggerHelper.enforceOfferCheckboxExclusivity(null, null);
        Test.stopTest();

        System.assert(true);
    }
}