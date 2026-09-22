@IsTest
private class ApplicationNumberControllerTest {
    @TestSetup
static void setupData() {
    insert new Hierarchy_Programme__c(
        Name = 'Hierarchy Programme (Test)',
        Name__c = 'Parent Program PGDM',
        All_Programme_Codes__c = 'PGDM,PGDM-BM,PGDM&PGDM-BM',
        All_Paid_Statuses__c = 'Paid,Paid For PGDM,Paid For PGDM-BM'
    );
}

    private static Id b2cOppRtId;

    static {
        Schema.RecordTypeInfo rti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('B2C_Opportunity');
        b2cOppRtId = rti != null ? rti.getRecordTypeId() : null;
    }

    private static Program newProgram(String name, String code) {
        return new Program(
            Name = name,
            Program_Code__c = code,
            Short_Programme_Code__c = code.length() > 3 ? code.substring(0, 3) : code,
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
    }

    private static ProgramCohort newCohort(Id programId, String name, String applicationCode, String shortBatchCode, Boolean accepting) {
        return new ProgramCohort(
            Name = name,
            ProgramId = programId,
            Application_Code__c = applicationCode,
            Short_Batch_Code__c = shortBatchCode,
            IsAcceptingApplications__c = accepting,
            Batch_Code__c = name,
            Batch_Sub_Type__c = 'Class Room'
        );
    }

    private static Account newApplicantAccount(String email) {
        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        return new Account(
            RecordTypeId = applicantRtId,
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = email,
            PersonMobilePhone = '9999999999'
        );
    }

    private static Opportunity newOpportunity(Id accountId, Id programId, Id applicationId, String name, String stageName) {
        Opportunity opp = new Opportunity(
            AccountId = accountId,
            Program__c = programId,
            Application__c = applicationId,
            Name = name,
            StageName = stageName,
            CloseDate = Date.today().addDays(30)
        );
        if (b2cOppRtId != null) {
            opp.RecordTypeId = b2cOppRtId;
        }
        return opp;
    }

    // ---------------------------------------------------------------
    // updateNonPaidOpportunities
    // ---------------------------------------------------------------

    @IsTest
    static void updateNonPaidOpportunities_closesNonPaidOpp_leavesPaidOppUntouched() {

        Program gmp = newProgram('GMP', 'GMP');
        insert gmp;

        ProgramCohort cohort = newCohort(gmp.Id, 'GMP Batch', null, 'G1', true);
        insert cohort;

        Account acc = newApplicantAccount('nonpaidopp@test.com');
        insert acc;

        Application__c nonPaidApp = new Application__c(
            Program__c = gmp.Id,
            Batch__c = cohort.Id,
            Application_Status__c = 'Initiated'
        );
        insert nonPaidApp;

        Opportunity nonPaidOpp = newOpportunity(acc.Id, gmp.Id, nonPaidApp.Id, 'Non Paid Opp', 'Prospecting');
        insert nonPaidOpp;

        Application__c paidApp = new Application__c(
            Program__c = gmp.Id,
            Batch__c = cohort.Id,
            Application_Status__c = 'Paid'
        );
        insert paidApp;

        Opportunity paidOpp = newOpportunity(acc.Id, gmp.Id, paidApp.Id, 'Paid Opp', 'Paid');
        insert paidOpp;

        ProgramCohort oldCohort = new ProgramCohort(Id = cohort.Id, IsAcceptingApplications__c = true);
        ProgramCohort newCohortRow = new ProgramCohort(Id = cohort.Id, IsAcceptingApplications__c = false);

        Test.startTest();
        ApplicationNumberController.updateNonPaidOpportunities(
            new List<ProgramCohort>{ newCohortRow },
            new Map<Id, ProgramCohort>{ cohort.Id => oldCohort }
        );
        Test.stopTest();

        Opportunity reloadedNonPaid = [SELECT StageName FROM Opportunity WHERE Id = :nonPaidOpp.Id];
        Opportunity reloadedPaid = [SELECT StageName FROM Opportunity WHERE Id = :paidOpp.Id];

        System.assertEquals('Closed Lost', reloadedNonPaid.StageName);
        System.assertEquals('Paid', reloadedPaid.StageName);
    }

    @IsTest
    static void updateNonPaidOpportunities_noBatchClosed_noOpportunitiesTouched() {

        Program gmp2 = newProgram('GMP2', 'GMP2');
        insert gmp2;

        ProgramCohort cohort = newCohort(gmp2.Id, 'GMP2 Batch', null, 'G2', true);
        insert cohort;

        // Still accepting -> IsAcceptingApplications__c unchanged -> applicationClosedBatchesId stays empty.
        ProgramCohort oldCohort = new ProgramCohort(Id = cohort.Id, IsAcceptingApplications__c = true);
        ProgramCohort newCohortRow = new ProgramCohort(Id = cohort.Id, IsAcceptingApplications__c = true);

        Test.startTest();
        ApplicationNumberController.updateNonPaidOpportunities(
            new List<ProgramCohort>{ newCohortRow },
            new Map<Id, ProgramCohort>{ cohort.Id => oldCohort }
        );
        Test.stopTest();
    }

    // ---------------------------------------------------------------
    // updateApplicationNames
    // ---------------------------------------------------------------

    @IsTest
    static void updateApplicationNames_hierarchyProgram_appendsApplicationCode() {

        Program pgdm = newProgram('PGDM', 'PGDM');
        insert pgdm;

        ProgramCohort cohort = newCohort(pgdm.Id, 'PGDM Batch', 'C1', 'SB1', true);
        insert cohort;

        Application__c app = new Application__c(
            Program__c = pgdm.Id,
            Batch__c = cohort.Id,
            Application_Status__c = 'Initiated',
            Name = 'APP0001'
        );
        insert app;

        Application__c oldApp = new Application__c(Id = app.Id, Application_Status__c = 'Initiated');
        Application__c newApp = new Application__c(
            Id = app.Id,
            Application_Status__c = 'Paid',
            Batch__c = cohort.Id,
            Program__c = pgdm.Id,
            Name = 'APP0001'
        );

        Test.startTest();
        ApplicationNumberController.updateApplicationNames(
            new List<Application__c>{ newApp },
            new Map<Id, Application__c>{ app.Id => oldApp }
        );
        Test.stopTest();

        Application__c reloaded = [SELECT Name FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('APP0001-C1', reloaded.Name);
    }

    @IsTest
    static void updateApplicationNames_nonHierarchyProgram_appendsShortBatchCode() {

        Program gmp3 = newProgram('GMP3', 'GMP3');
        insert gmp3;

        ProgramCohort cohort = newCohort(gmp3.Id, 'GMP3 Batch', null, 'SB2', true);
        insert cohort;

        Application__c app = new Application__c(
            Program__c = gmp3.Id,
            Batch__c = cohort.Id,
            Application_Status__c = 'Initiated',
            Name = 'APP0002'
        );
        insert app;

        Application__c oldApp = new Application__c(Id = app.Id, Application_Status__c = 'Initiated');
        Application__c newApp = new Application__c(
            Id = app.Id,
            Application_Status__c = 'Paid',
            Batch__c = cohort.Id,
            Program__c = gmp3.Id,
            Name = 'APP0002'
        );

        Test.startTest();
        ApplicationNumberController.updateApplicationNames(
            new List<Application__c>{ newApp },
            new Map<Id, Application__c>{ app.Id => oldApp }
        );
        Test.stopTest();

        Application__c reloaded = [SELECT Name FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('APP0002-SB2', reloaded.Name);
    }

    @IsTest
    static void updateApplicationNames_statusUnchanged_noUpdate() {

        Program gmp4 = newProgram('GMP4', 'GMP4');
        insert gmp4;

        ProgramCohort cohort = newCohort(gmp4.Id, 'GMP4 Batch', null, 'SB3', true);
        insert cohort;

        Application__c app = new Application__c(
            Program__c = gmp4.Id,
            Batch__c = cohort.Id,
            Application_Status__c = 'Paid',
            Name = 'APP0003'
        );
        insert app;

        // Old status already 'Paid' too -> status "changed into paid" condition is false -> paidApplicationMap stays empty -> early return.
        Application__c oldApp = new Application__c(Id = app.Id, Application_Status__c = 'Paid');
        Application__c newApp = new Application__c(Id = app.Id, Application_Status__c = 'Paid');

        Test.startTest();
        ApplicationNumberController.updateApplicationNames(
            new List<Application__c>{ newApp },
            new Map<Id, Application__c>{ app.Id => oldApp }
        );
        Test.stopTest();

        Application__c reloaded = [SELECT Name FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('APP0003', reloaded.Name);
    }

    @IsTest
    static void updateApplicationNames_alreadySuffixed_nameUnchanged() {

        Program gmp5 = newProgram('GMP5', 'GMP5');
        insert gmp5;

        ProgramCohort cohort = newCohort(gmp5.Id, 'GMP5 Batch', null, 'SB4', true);
        insert cohort;

        Application__c app = new Application__c(
            Program__c = gmp5.Id,
            Batch__c = cohort.Id,
            Application_Status__c = 'Initiated',
            Name = 'APP0004-OLD'
        );
        insert app;

        Application__c oldApp = new Application__c(Id = app.Id, Application_Status__c = 'Initiated');
        Application__c newApp = new Application__c(
            Id = app.Id,
            Application_Status__c = 'Paid',
            Batch__c = cohort.Id,
            Program__c = gmp5.Id,
            Name = 'APP0004-OLD'
        );

        Test.startTest();
        ApplicationNumberController.updateApplicationNames(
            new List<Application__c>{ newApp },
            new Map<Id, Application__c>{ app.Id => oldApp }
        );
        Test.stopTest();

        // generateApplicationName returns null because Name already contains '-' -> skipped, no update.
        Application__c reloaded = [SELECT Name FROM Application__c WHERE Id = :app.Id];
        System.assertEquals('APP0004-OLD', reloaded.Name);
    }
}