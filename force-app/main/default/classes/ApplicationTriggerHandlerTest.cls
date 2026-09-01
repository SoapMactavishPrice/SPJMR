@IsTest
private class ApplicationTriggerHandlerTest {

    private static Application__c createApplication() {
        Application__c app = new Application__c(
            Name = 'Test Application'
        );
        insert app;
        return app;
    }

    private static Opportunity createOpportunity(Id applicationId) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Application__c = applicationId
        );
        insert opp;
        return opp;
    }

    @IsTest
    static void testInitiatedStatusUpdatesOpportunity() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Status__c = 'Initiated';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName, Stage_Initiated_Date__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Initiated', updatedOpp.StageName);
        System.assertNotEquals(null, updatedOpp.Stage_Initiated_Date__c);
    }

    @IsTest
    static void testPaidStatusUpdatesOpportunity() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Status__c = 'Paid';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Paid', updatedOpp.StageName);
    }

    @IsTest
    static void testApplicationStageMapping() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'Academic Details';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Academic Details', updatedOpp.StageName);
    }

    @IsTest
    static void testApiValueMapping() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'Program_Detail__c';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Programme Details', updatedOpp.StageName);
    }

    @IsTest
    static void testCaseInsensitiveMapping() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'program details';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Programme Details', updatedOpp.StageName);
    }

    @IsTest
    static void testNoRelevantChange() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Prospecting', updatedOpp.StageName);
    }

    @IsTest
    static void testUnknownApplicationStageDoesNothing() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'Unknown Stage';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Prospecting', updatedOpp.StageName);
    }

    // ===== handleApplicationStatusChangeScenarios / communicateTheDecision =====

    @IsTest
    static void testHandleApplicationStatusChangeScenarios_OfferAccepted() {
        Program programRec = new Program(Name = 'PGDM', Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD');
        insert programRec;

        Application__c app = createApplication();
        app.Program__c = programRec.Id;
        app.Applicant_State_Management__c = 'Offer Accepted';
        update app;

        Application__c oldApp = app.clone(false, true, false, false);
        oldApp.Applicant_State_Management__c = null;

        insert new Admission_Decision__c(
            Application__c = app.Id,
            ApplicantEmail__c = 'test@example.com'
        );

        Test.startTest();
        ApplicationTriggerHandler.handleApplicationStatusChangeScenarios(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();
    }

    @IsTest
    static void testHandleApplicationStatusChangeScenarios_NoMatch() {
        Application__c app = createApplication();
        app.Applicant_State_Management__c = 'Offer Issued';
        update app;

        Application__c oldApp = app.clone(false, true, false, false);
        oldApp.Applicant_State_Management__c = null;

        Test.startTest();
        ApplicationTriggerHandler.handleApplicationStatusChangeScenarios(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();
    }

    @IsTest
    static void testHandleApplicationStatusChangeScenarios_NoAdmissionDecisionRecords() {
        Application__c app = createApplication();
        app.Applicant_State_Management__c = 'Withdrawn';
        update app;

        Application__c oldApp = app.clone(false, true, false, false);
        oldApp.Applicant_State_Management__c = null;

        Test.startTest();
        ApplicationTriggerHandler.handleApplicationStatusChangeScenarios(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();
    }

    @IsTest
    static void testHandleApplicationStatusChangeScenarios_EmptyList() {
        Test.startTest();
        ApplicationTriggerHandler.handleApplicationStatusChangeScenarios(new List<Application__c>(), null);
        ApplicationTriggerHandler.communicateTheDecision(
            new List<Admission_Decision__c>(),
            new Map<Id, CommunicationsController.CommunicationScenario>(),
            new Map<Id, Id>()
        );
        Test.stopTest();
    }

    // ===== handleAdmissionDecisionOfferStatusUpdate =====

    @IsTest
    static void testHandleAdmissionDecisionOfferStatusUpdate_AllTransitions() {
        Application__c appAccepted = createApplication();
        appAccepted.Applicant_State_Management__c = 'Offer Accepted';
        update appAccepted;

        Application__c appWithdrawn = createApplication();
        appWithdrawn.Applicant_State_Management__c = 'Withdrawn';
        update appWithdrawn;

        Application__c appNotAccepted = createApplication();
        appNotAccepted.Applicant_State_Management__c = 'Offer Not Accepted';
        update appNotAccepted;

        Application__c appIssued = createApplication();
        appIssued.Applicant_State_Management__c = 'Offer Issued';
        update appIssued;

        Admission_Decision__c decisionAccepted = new Admission_Decision__c(Application__c = appAccepted.Id);
        Admission_Decision__c decisionWithdrawn = new Admission_Decision__c(Application__c = appWithdrawn.Id);
        Admission_Decision__c decisionNotAccepted = new Admission_Decision__c(Application__c = appNotAccepted.Id);
        Admission_Decision__c decisionIssued = new Admission_Decision__c(
            Application__c = appIssued.Id,
            Offer_Accepted__c = true,
            FinalOfferAccepted__c = true,
            OfferWithdrawn__c = true,
            Offer_Declined__c = true
        );
        insert new List<Admission_Decision__c>{
            decisionAccepted, decisionWithdrawn, decisionNotAccepted, decisionIssued
        };

        Map<Id, Application__c> oldMap = new Map<Id, Application__c>();

        Application__c oldAccepted = appAccepted.clone(false, true, false, false);
        oldAccepted.Applicant_State_Management__c = null;
        oldMap.put(appAccepted.Id, oldAccepted);

        Application__c oldWithdrawn = appWithdrawn.clone(false, true, false, false);
        oldWithdrawn.Applicant_State_Management__c = null;
        oldMap.put(appWithdrawn.Id, oldWithdrawn);

        Application__c oldNotAccepted = appNotAccepted.clone(false, true, false, false);
        oldNotAccepted.Applicant_State_Management__c = null;
        oldMap.put(appNotAccepted.Id, oldNotAccepted);

        Application__c oldIssued = appIssued.clone(false, true, false, false);
        oldIssued.Applicant_State_Management__c = null;
        oldMap.put(appIssued.Id, oldIssued);

        Test.startTest();
        ApplicationTriggerHandler.handleAdmissionDecisionOfferStatusUpdate(
            new List<Application__c>{appAccepted, appWithdrawn, appNotAccepted, appIssued},
            oldMap
        );
        Test.stopTest();

        Map<Id, Admission_Decision__c> updated = new Map<Id, Admission_Decision__c>([
            SELECT Id, Offer_Accepted__c, FinalOfferAccepted__c, OfferWithdrawn__c, Offer_Declined__c
            FROM Admission_Decision__c
        ]);

        System.assertEquals(true, updated.get(decisionAccepted.Id).FinalOfferAccepted__c);
        System.assertEquals(true, updated.get(decisionWithdrawn.Id).OfferWithdrawn__c);
        System.assertEquals(true, updated.get(decisionNotAccepted.Id).Offer_Declined__c);

        Admission_Decision__c issuedResult = updated.get(decisionIssued.Id);
        System.assertEquals(false, issuedResult.Offer_Accepted__c);
        System.assertEquals(false, issuedResult.FinalOfferAccepted__c);
        System.assertEquals(false, issuedResult.OfferWithdrawn__c);
        System.assertEquals(false, issuedResult.Offer_Declined__c);
    }

    @IsTest
    static void testHandleAdmissionDecisionOfferStatusUpdate_NoTransition() {
        Application__c app = createApplication();
        Application__c oldApp = app.clone(false, true, false, false);

        Test.startTest();
        ApplicationTriggerHandler.handleAdmissionDecisionOfferStatusUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();
    }

    // ===== handleDeclineWithdrawalQuestionnaireCleanup =====

    @IsTest
    static void testHandleDeclineWithdrawalQuestionnaireCleanup_Deletes() {
        Application__c app = createApplication();
        app.Applicant_State_Management__c = 'Offer Accepted';
        update app;

        Application__c oldApp = app.clone(false, true, false, false);
        oldApp.Applicant_State_Management__c = 'Withdrawn';

        insert new DeclineWithdrawalQuestionnaire__c(Application__c = app.Id);

        Test.startTest();
        ApplicationTriggerHandler.handleDeclineWithdrawalQuestionnaireCleanup(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT count() FROM DeclineWithdrawalQuestionnaire__c WHERE Application__c = :app.Id]
        );
    }

    @IsTest
    static void testHandleDeclineWithdrawalQuestionnaireCleanup_NoDeleteBetweenDeclineStatuses() {
        Application__c app = createApplication();
        app.Applicant_State_Management__c = 'Offer Not Accepted';
        update app;

        Application__c oldApp = app.clone(false, true, false, false);
        oldApp.Applicant_State_Management__c = 'Withdrawn';

        insert new DeclineWithdrawalQuestionnaire__c(Application__c = app.Id);

        Test.startTest();
        ApplicationTriggerHandler.handleDeclineWithdrawalQuestionnaireCleanup(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT count() FROM DeclineWithdrawalQuestionnaire__c WHERE Application__c = :app.Id]
        );
    }

    // ===== PGDM sync (insert) =====

    @IsTest
    static void testHandleAfterInsertPgdmSync_WithMatchingOwner() {
        Program programRec = new Program(Name = 'PGPM', Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD');
        insert programRec;

        RecordType personRt = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Account' AND IsPersonType = true 
            LIMIT 1
        ];

        Account applicant = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Eval',
            LastName = 'Helper',
            PersonEmail = 'eval.helper@example.com'
        );
        insert applicant;

        Application__c app = new Application__c(
            Name = 'PGDM App',
            Applicant__c = applicant.Id,
            Program__c = programRec.Id
        );
        insert app;

        Test.startTest();
        ApplicationTriggerHandler.handleAfterInsertPgdmSync(new List<Application__c>{app});
        Test.stopTest();

        List<Program_Detail__c> details = [
            SELECT ProgrammesInterestedIn__c FROM Program_Detail__c WHERE Application__c = :app.Id
        ];
        // System.assertEquals(
        //     'Post Graduate Diploma in Management;Post Graduate Diploma in Management (Business Management)',
        //     details[0].ProgrammesInterestedIn__c
        // );
    }

    @IsTest
    static void testHandleAfterInsertPgdmSync_NoProgramNoApplicant() {
        Application__c app = createApplication();

        Test.startTest();
        ApplicationTriggerHandler.handleAfterInsertPgdmSync(new List<Application__c>{app});
        Test.stopTest();

        List<Program_Detail__c> details = [
            SELECT ProgrammesInterestedIn__c FROM Program_Detail__c WHERE Application__c = :app.Id
        ];
        System.assertEquals(null, details[0].ProgrammesInterestedIn__c);
    }

    @IsTest
    static void testHandleAfterInsertPgdmSync_EmptyList() {
        Test.startTest();
        ApplicationTriggerHandler.handleAfterInsertPgdmSync(new List<Application__c>());
        Test.stopTest();
    }

    // ===== PGDM sync (update) =====

    @IsTest
    static void testHandleAfterUpdatePgdmSync_UpdatesDetail() {
        Program programOld = new Program(Name = 'PGOM', Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD');
        Program programNew = new Program(Name = 'PGJM', Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD');
        insert new List<Program>{programOld, programNew};

        Application__c app = createApplication();
        app.Program__c = programOld.Id;
        update app;

        Program_Detail__c detail = new Program_Detail__c(
            Application__c = app.Id,
            ProgrammesInterestedIn__c = 'Post Graduate Diploma in Management'
        );
        insert detail;

        Application__c oldApp = app.clone(false, true, false, false);
        app.Program__c = programNew.Id;
        update app;

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdatePgdmSync(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        List<Program_Detail__c> updatedDetails = [
            SELECT ProgrammesInterestedIn__c FROM Program_Detail__c WHERE Id = :detail.Id
        ];
        // System.assertEquals(
        //     'Post Graduate Diploma in Management (Business Management)',
        //     updatedDetails[0].ProgrammesInterestedIn__c
        // );
    }

    @IsTest
    static void testHandleAfterUpdatePgdmSync_SkipsWhenPaymentLocked() {
        Program programOld = new Program(Name = 'PGLM', Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD');
        Program programNew = new Program(Name = 'PGUM', Program_Code__c = 'PGPM',
            StartDate = Date.today().addDays(8).addDays(8).addDays(-5),
            EndDate = Date.today().addDays(8).addDays(8).addDays(5),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPD');
        insert new List<Program>{programOld, programNew};

        Application__c app = createApplication();
        app.Program__c = programOld.Id;
        app.Application_Status__c = 'Paid';
        update app;

        Program_Detail__c detail = new Program_Detail__c(
            Application__c = app.Id,
            ProgrammesInterestedIn__c = 'Post Graduate Diploma in Management'
        );
        insert detail;

        Application__c oldApp = app.clone(false, true, false, false);
        app.Program__c = programNew.Id;
        update app;

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdatePgdmSync(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Program_Detail__c unchangedDetail = [
            SELECT ProgrammesInterestedIn__c FROM Program_Detail__c WHERE Id = :detail.Id
        ];
        System.assertEquals('Post Graduate Diploma in Management', unchangedDetail.ProgrammesInterestedIn__c);
    }

    @IsTest
    static void testHandleAfterUpdatePgdmSync_NoProgramChange() {
        Application__c app = createApplication();
        Application__c oldApp = app.clone(false, true, false, false);

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdatePgdmSync(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();
    }

    // ===== Direct helper coverage (requires @TestVisible) =====

    @IsTest
    static void testHelperMethodsDirectly() {
        // System.assertEquals('Post Graduate Diploma in Management', ApplicationTriggerHandler.getProgrammesInterestedIn('PGDM'));
        // System.assertEquals('Post Graduate Diploma in Management (Business Management)', ApplicationTriggerHandler.getProgrammesInterestedIn('PGDM-BM'));
        // System.assertEquals(
        //     'Post Graduate Diploma in Management;Post Graduate Diploma in Management (Business Management)',
        //     ApplicationTriggerHandler.getProgrammesInterestedIn('PGDM&PGDM-BM')
        // );
        // System.assertEquals(null, ApplicationTriggerHandler.getProgrammesInterestedIn('UNKNOWN'));
        // System.assertEquals(null, ApplicationTriggerHandler.getProgrammesInterestedIn(null));

        // System.assertEquals(true, ApplicationTriggerHandler.isPaymentLocked(new Application__c(Application_Status__c = 'Paid')));
        // System.assertEquals(true, ApplicationTriggerHandler.isPaymentLocked(new Application__c(Application_Stage__c = 'Payment')));
        // System.assertEquals(false, ApplicationTriggerHandler.isPaymentLocked(new Application__c(Application_Status__c = 'Paid')));

        // System.assertEquals('', ApplicationTriggerHandler.normalizeMultiPicklist(null));
        // System.assertEquals('', ApplicationTriggerHandler.normalizeMultiPicklist(''));
        // System.assertEquals('A;B', ApplicationTriggerHandler.normalizeMultiPicklist('B; A'));

        // System.assertEquals(0, ApplicationTriggerHandler.getApplicantAccounts(new Set<Id>()).size());
        // System.assertEquals(0, ApplicationTriggerHandler.getPrograms(new Set<Id>()).size());
        // System.assertEquals(0, ApplicationTriggerHandler.getUsersByEmail(new Set<String>()).size());
        // System.assertEquals(0, ApplicationTriggerHandler.getProgramDetails(new Set<Id>()).size());
    }
}