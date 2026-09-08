@IsTest
private class AdmissionDecisionTriggerHandlerTest {
    private static Integer sequence = 0;

    private static Program createProgram(String programCode) {
        sequence++;
        Program programRecord = new Program(
            Name = 'Admission Trigger Test Program ' + sequence,
            Program_Code__c = programCode,
            Short_Programme_Code__c = 'A' + sequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert programRecord;
        return programRecord;
    }

    private static Application__c createApplication(
        Id programId,
        String applicantState
    ) {
        Id applicantId;
        Id batchId;
        if (programId != null) {
            sequence++;
            Account applicant = new Account(
                RecordTypeId = Schema.SObjectType.Account
                    .getRecordTypeInfosByDeveloperName()
                    .get('Applicant')
                    .getRecordTypeId(),
                FirstName = 'Test',
                LastName = 'Applicant ' + sequence,
                PersonEmail = 'admission.trigger.' + sequence + '@example.com'
            );
            insert applicant;
            applicantId = applicant.Id;

            ProgramCohort batchRecord = new ProgramCohort(
                Name = 'Admission Trigger Batch ' + sequence,
                ProgramId = programId,
                Batch_Code__c = 'ATB' + sequence,
                Batch_Sub_Type__c = 'Class Room',
                Batch_Base_Currency__c = 'INR',
                StartDate = Date.today().addDays(30),
                EndDate = Date.today().addYears(1)
            );
            insert batchRecord;
            batchId = batchRecord.Id;
        }
        Application__c application = new Application__c(
            Program__c = programId,
            Applicant__c = applicantId,
            Batch__c = batchId,
            Applicant_State_Management__c = applicantState
        );
        insert application;
        return application;
    }

    private static Admission_Decision__c eligibleDecision(Id applicationId) {
        return new Admission_Decision__c(
            Application__c = applicationId,
            Result__c = 'Eligible for Admission',
            WaitlistNumber__c = 999,
            Offer_Letter_Date__c = Date.newInstance(2027, 1, 10),
            LastDateOfAcceptance__c = Date.newInstance(2027, 1, 11),
            SignedLetterOfAcceptanceEta__c = Date.newInstance(2027, 1, 12),
            PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2027, 1, 13),
            PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2027, 1, 14),
            BalanceFeePaymentETA__c = Date.newInstance(2027, 1, 15)
        );
    }

    private static void applyEligibleDates(Admission_Decision__c decision) {
        decision.Offer_Letter_Date__c = Date.newInstance(2028, 2, 10);
        decision.LastDateOfAcceptance__c = Date.newInstance(2028, 2, 11);
        decision.SignedLetterOfAcceptanceEta__c = Date.newInstance(2028, 2, 12);
        decision.PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2028, 2, 13);
        decision.PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2028, 2, 14);
        decision.BalanceFeePaymentETA__c = Date.newInstance(2028, 2, 15);
    }

    @IsTest
    static void insertRunsTriggerCleanupStateAndCommunicationPaths() {
        Application__c eligibleApplication = createApplication(null, null);
        Application__c waitlistedApplication = createApplication(null, null);
        Application__c rejectedApplication = createApplication(
            null,
            'Interview Round 1'
        );

        Admission_Decision__c eligible = eligibleDecision(eligibleApplication.Id);
        Admission_Decision__c waitlisted = eligibleDecision(waitlistedApplication.Id);
        waitlisted.Result__c = 'Waitlisted';
        waitlisted.WaitlistNumber__c = 12;
        Admission_Decision__c rejected = eligibleDecision(rejectedApplication.Id);
        rejected.Result__c = 'Not Eligible';

        Test.startTest();
        insert new List<Admission_Decision__c>{ eligible, waitlisted, rejected };
        Test.stopTest();

        Set<Id> decisionIds = new Set<Id>{ eligible.Id, waitlisted.Id, rejected.Id };
        Map<Id, Admission_Decision__c> decisions = new Map<Id, Admission_Decision__c>([
            SELECT Result__c, WaitlistNumber__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c, SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c, BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Id IN :decisionIds
        ]);
        System.assertEquals(null, decisions.get(eligible.Id).WaitlistNumber__c);
        System.assertEquals(Date.newInstance(2027, 1, 10),
            decisions.get(eligible.Id).Offer_Letter_Date__c);
        System.assertEquals(12, decisions.get(waitlisted.Id).WaitlistNumber__c);
        System.assertEquals(null, decisions.get(waitlisted.Id).Offer_Letter_Date__c);
        System.assertEquals(null, decisions.get(rejected.Id).Offer_Letter_Date__c);

        Set<Id> applicationIds = new Set<Id>{
            eligibleApplication.Id,
            waitlistedApplication.Id,
            rejectedApplication.Id
        };
        Map<Id, Application__c> applications = new Map<Id, Application__c>([
            SELECT Applicant_State_Management__c
            FROM Application__c
            WHERE Id IN :applicationIds
        ]);
        System.assertEquals('Offer Issued',
            applications.get(eligibleApplication.Id).Applicant_State_Management__c);
        System.assertEquals('Waitlisted',
            applications.get(waitlistedApplication.Id).Applicant_State_Management__c);
        System.assertEquals('Reject Round 1',
            applications.get(rejectedApplication.Id).Applicant_State_Management__c);
    }

    @IsTest
    static void handlerGroupsConfiguredDecisionCommunication() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id, null);
        Admission_Decision__c persistedDecision = eligibleDecision(application.Id);
        insert persistedDecision;

        Admission_Decision__c waitlistedView = new Admission_Decision__c(
            Id = persistedDecision.Id,
            Application__c = application.Id,
            Result__c = 'Waitlisted',
            WaitlistNumber__c = 10
        );
        AdmissionDecisionTriggerHandler handler =
            new AdmissionDecisionTriggerHandler();

        Test.startTest();
        handler.afterInsert(
            new List<Admission_Decision__c>{ waitlistedView },
            new Map<Id, Admission_Decision__c>{
                waitlistedView.Id => waitlistedView
            }
        );
        Test.stopTest();

        Application__c updatedApplication = [
            SELECT Applicant_State_Management__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
        System.assertEquals(
            'Waitlisted',
            updatedApplication.Applicant_State_Management__c
        );
    }

    @IsTest
    static void updateTransitionsClearInapplicableFields() {
        Application__c fromEligibleApplication = createApplication(null, null);
        Application__c fromWaitlistApplication = createApplication(null, null);
        Admission_Decision__c fromEligible = eligibleDecision(fromEligibleApplication.Id);
        Admission_Decision__c fromWaitlist = new Admission_Decision__c(
            Application__c = fromWaitlistApplication.Id,
            Result__c = 'Waitlisted',
            WaitlistNumber__c = 44
        );
        insert new List<Admission_Decision__c>{ fromEligible, fromWaitlist };

        fromEligible.Result__c = 'Waitlisted';
        fromEligible.WaitlistNumber__c = 45;
        fromWaitlist.Result__c = 'Eligible for Admission';
        applyEligibleDates(fromWaitlist);

        Test.startTest();
        update new List<Admission_Decision__c>{ fromEligible, fromWaitlist };
        Test.stopTest();

        Set<Id> decisionIds = new Set<Id>{ fromEligible.Id, fromWaitlist.Id };
        Map<Id, Admission_Decision__c> updated = new Map<Id, Admission_Decision__c>([
            SELECT Result__c, WaitlistNumber__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c, SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c, BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Id IN :decisionIds
        ]);
        System.assertEquals(null, updated.get(fromEligible.Id).Offer_Letter_Date__c);
        System.assertEquals(45, updated.get(fromEligible.Id).WaitlistNumber__c);
        System.assertEquals(null, updated.get(fromWaitlist.Id).WaitlistNumber__c);
        System.assertEquals(Date.newInstance(2028, 2, 10),
            updated.get(fromWaitlist.Id).Offer_Letter_Date__c);
    }

    @IsTest
    static void unchangedResultStillRunsUpdateTrigger() {
        Application__c application = createApplication(null, null);
        Admission_Decision__c decision = eligibleDecision(application.Id);
        insert decision;

        Test.startTest();
        decision.Offer_Letter_Date__c = Date.newInstance(2027, 3, 10);
        decision.Offer_Accepted__c = true;
        update decision;
        Test.stopTest();

        Admission_Decision__c updated = [
            SELECT Result__c, Offer_Letter_Date__c, Offer_Accepted__c
            FROM Admission_Decision__c
            WHERE Id = :decision.Id
        ];
        System.assertEquals('Eligible for Admission', updated.Result__c);
        System.assertEquals(Date.newInstance(2027, 3, 10), updated.Offer_Letter_Date__c);
        System.assertEquals(true, updated.Offer_Accepted__c);
    }

    @IsTest
    static void preventsDuplicateDecisionsAndCoversDeleteEvents() {
        Application__c application = createApplication(null, null);
        Admission_Decision__c first = new Admission_Decision__c(
            Application__c = application.Id,
            Result__c = 'Waitlisted',
            WaitlistNumber__c = 1
        );
        insert first;

        Admission_Decision__c duplicate = new Admission_Decision__c(
            Application__c = application.Id,
            Result__c = 'Waitlisted',
            WaitlistNumber__c = 2
        );

        Test.startTest();
        Database.SaveResult duplicateResult = Database.insert(duplicate, false);
        delete first;
        undelete first;
        Test.stopTest();

        System.assertEquals(false, duplicateResult.isSuccess());
        System.assert(
            duplicateResult.getErrors()[0].getMessage().contains(
                'Only one Admission Decision record is allowed per Application.'
            )
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Admission_Decision__c WHERE Application__c = :application.Id]
        );
    }

    @IsTest
    static void preventsTwoDecisionsInTheSameInsert() {
        Application__c application = createApplication(null, null);
        List<Admission_Decision__c> duplicates = new List<Admission_Decision__c>{
            new Admission_Decision__c(
                Application__c = application.Id,
                Result__c = 'Waitlisted',
                WaitlistNumber__c = 1
            ),
            new Admission_Decision__c(
                Application__c = application.Id,
                Result__c = 'Waitlisted',
                WaitlistNumber__c = 2
            )
        };

        Database.SaveResult[] results = Database.insert(duplicates, false);

        System.assertEquals(false, results[0].isSuccess());
        System.assertEquals(false, results[1].isSuccess());
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Admission_Decision__c WHERE Application__c = :application.Id]
        );
    }

    @IsTest
    static void blankStagingResultPreservesPreviouslyEnteredValues() {
        Application__c application = createApplication(null, null);
        Admission_Decision__c decision = eligibleDecision(application.Id);
        insert decision;

        Test.startTest();
        decision.Result__c = null;
        decision.WaitlistNumber__c = 33;
        update decision;
        Test.stopTest();

        Admission_Decision__c staged = [
            SELECT Result__c, WaitlistNumber__c, Offer_Letter_Date__c,
                LastDateOfAcceptance__c, SignedLetterOfAcceptanceEta__c,
                PaymentOfTheAcceptanceFeeEta__c,
                PaymentOfTheFirstInstallmentEta__c, BalanceFeePaymentETA__c
            FROM Admission_Decision__c
            WHERE Id = :decision.Id
        ];
        System.assertEquals(null, staged.Result__c);
        System.assertEquals(33, staged.WaitlistNumber__c);
        System.assertEquals(Date.newInstance(2027, 1, 10), staged.Offer_Letter_Date__c);
        System.assertEquals(Date.newInstance(2027, 1, 15), staged.BalanceFeePaymentETA__c);
    }
}