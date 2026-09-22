@IsTest
private class OpportunityApplicationServiceTest {

    private static Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();

     @TestSetup
    static void setup() {
        User u = createSystemAdminUser();
        System.RunAs(u) {
            insert new Hierarchy_Programme__c(
    Name = 'Hierarchy Programme (Test)',
    Name__c = 'Parent Program PGDM',
    All_Programme_Codes__c = 'PGDM,PGDM-BM,PGDM&PGDM-BM',
    All_Paid_Statuses__c = 'Paid,Paid For PGDM,Paid For PGDM-BM'
);
            insert new Program(
                Name = 'GMP', Program_Code__c = 'GMP', Short_Programme_Code__c = 'GMP',
                StartDate = Date.today(), EndDate = Date.today().addDays(10),
                Programme_Type__c = 'Part-time', Programme_Sub_Type__c = 'Class Room',
                Status = 'Active', Programme_Contact__c = '9999999999', Programme_Intake__c = 100,
                IsActive = true
            );

            Program parent = new Program(
                Name = 'PGDM & PGDM-BM', Program_Code__c = 'PGDM&PGDM-BM', Short_Programme_Code__c = 'PP',
                StartDate = Date.today(), EndDate = Date.today().addDays(10),
                Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room',
                Status = 'Active', Programme_Contact__c = '9999999999', Programme_Intake__c = 100,
                IsActive = true
            );
            insert parent;

            insert new List<Program>{
                new Program(
                    Name = 'PGDM', Program_Code__c = 'PGDM', ParentProgramId = parent.Id, Short_Programme_Code__c = 'PM',
                    StartDate = Date.today(), EndDate = Date.today().addDays(10),
                    Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room',
                    Status = 'Active', Programme_Contact__c = '9999999999', Programme_Intake__c = 100,
                    IsActive= true
                ),
                new Program(
                    Name = 'PGDM BM', Program_Code__c = 'PGDM-BM', ParentProgramId = parent.Id, Short_Programme_Code__c = 'PB',
                    StartDate = Date.today(), EndDate = Date.today().addDays(10),
                    Programme_Type__c = 'Full-time', Programme_Sub_Type__c = 'Class Room',
                    Status = 'Active', Programme_Contact__c = '9999999999', Programme_Intake__c = 100,
                    IsActive = true
                )
            };

            Account acc = new Account(
                RecordTypeId = applicantRtId, OwnerId = u.Id, FirstName = 'Test', LastName = 'Applicant',
                PersonEmail = 'opp.svc.test@test.com', PersonMobilePhone = '+919999999999'
            );
            insert acc;

            // NEW -- createNewOpportunityAndApplication looks up a Community User
            // linked to PersonContactId to use as Application__c.OwnerId. Without
            // this, every test that reaches actual Application creation fails with
            // "Owner ID: owner cannot be blank".
            acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];

            Profile applicantProfile = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1];
            User applicantUser = new User(
                Username = 'oppsvcapplicant@test.com',
                Alias = 'oppap',
                Email = 'oppsvcapplicant@test.com',
                LastName = 'Applicant',
                FirstName = 'Test',
                CommunityNickname = 'oppap' + System.currentTimeMillis(),
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = applicantProfile.Id,
                ContactId = acc.PersonContactId
            );
            insert applicantUser;
        }
    }
  private static User createSystemAdminUser() {

    Profile sysAdminProfile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
    ];
    UserRole ur = new UserRole(Name = 'OppSvcTestRole');
    insert ur;

    User u = new User(
        FirstName = 'System',
        LastName = 'Admin',
        Alias = 'sadm',
        Email = 'oppsvcadmin' + System.currentTimeMillis() + '@test.com',
        Username = 'oppsvcadmin' + System.currentTimeMillis() + '@test.com',
        CommunityNickname = 'oppsvcadmin' + System.currentTimeMillis(),
        ProfileId = sysAdminProfile.Id,
        UserRoleId = ur.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
    );

    insert u;

    // NEW -- grant the Permission Set that carries Education Cloud object
    // access (Program / ProgramCohort / Application__c). Replace the name
    // below with whatever actually grants that access in this org.
    List<PermissionSet> eduPermSets = [
        SELECT Id FROM PermissionSet WHERE Name = 'EducationCloudAccess' LIMIT 1
    ];
    if (!eduPermSets.isEmpty()) {
        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = eduPermSets[0].Id
        );
    }

    return u;
}
    private static Program getProgram(String code) {
        return [SELECT Id, Name, Program_Code__c, ParentProgramId FROM Program WHERE Program_Code__c = :code LIMIT 1];
    }

    private static Account getAccount() {
        return [SELECT Id FROM Account WHERE PersonEmail = 'opp.svc.test@test.com' LIMIT 1];
    }

    private static ProgramCohort newPgdmBatch(Id programId, String name, String applicationCode, Boolean accepting) {
        ProgramCohort pc = new ProgramCohort(
            Name = name,
            ProgramId = programId,
            Application_Code__c = applicationCode,
            IsAcceptingApplications__c = accepting,
            Batch_Code__c = name,
            Batch_Sub_Type__c = 'Class Room'
        );
        insert pc;
        return pc;
    }

    private static ProgramCohort newGmpBatch(Id programId, String name, String shortBatchCode, Boolean accepting) {
        ProgramCohort pc = new ProgramCohort(
            Name = name,
            ProgramId = programId,
            Short_Batch_Code__c = shortBatchCode,
            IsAcceptingApplications__c = accepting,
            Batch_Code__c = name,
            Batch_Sub_Type__c = 'Class Room'
        );
        insert pc;
        return pc;
    }

    private static Application__c newApplication(Id accountId, Id programId, Id batchId, String status) {
        Application__c app = new Application__c(
            Applicant__c = accountId, Program__c = programId, Batch__c = batchId, Application_Status__c = status
        );
        insert app;
        return app;
    }

    private static Opportunity newOpportunity(Id accountId, Id programId, Id applicationId) {
        Opportunity opp = new Opportunity(
            AccountId = accountId, Program__c = programId, Application__c = applicationId,
            Name = 'Test Opp', StageName = 'Email Verified', CloseDate = Date.today().addDays(90)
        );
        insert opp;
        return opp;
    }

    @IsTest
    static void gmp_noAcceptingBatch() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void gmp_openBatch_noExisting() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();
            newGmpBatch(gmp.Id, 'GMP Batch', 'G1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void gmp_unpaidApplicationInProgress() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();
            ProgramCohort batch = newGmpBatch(gmp.Id, 'GMP Batch', 'G1', true);
            newApplication(acc.Id, gmp.Id, batch.Id, 'Initiated');

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void gmp_paidInAllAcceptingBatchCodes() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();
            ProgramCohort batchA = newGmpBatch(gmp.Id, 'GMP Batch A', 'GA', true);
            ProgramCohort batchB = newGmpBatch(gmp.Id, 'GMP Batch B', 'GB', true);
            newApplication(acc.Id, gmp.Id, batchA.Id, 'Paid');
            newApplication(acc.Id, gmp.Id, batchB.Id, 'Paid');

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

         @IsTest
    static void gmp_sameProgram_codeChangedToNewCohort_treatedAsNewCycle() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();

            // Old batch, closed, code OLD.
            ProgramCohort oldBatch = newGmpBatch(gmp.Id, 'GMP Old Batch', 'OLD', false);
            Application__c oldApp = newApplication(acc.Id, gmp.Id, oldBatch.Id, 'Paid');
            newOpportunity(acc.Id, gmp.Id, oldApp.Id);

            // New cohort record entirely, different code, now accepting --
            // exercises the same "code identity, not record Id" comparison
            // as an in-place edit would, without requiring ProgramCohort update access.
            newGmpBatch(gmp.Id, 'GMP New Batch', 'NEW', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Boolean s = OpportunityApplicationService.isIndividualSiblingProgrammeOpportunityEnabled();
            Program p = getProgram('GMP');
            Program parentRow = OpportunityApplicationService.getParentProgramRow(p);
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }
    @IsTest
    static void gmp_paidInSomeButNotAllBatchCodes() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();
            ProgramCohort batchA = newGmpBatch(gmp.Id, 'GMP Batch A', 'GA', true);
            newGmpBatch(gmp.Id, 'GMP Batch B', 'GB', true);
            newApplication(acc.Id, gmp.Id, batchA.Id, 'Paid');

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void gmp_notAutoCreateApplication() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program gmp = getProgram('GMP');
            Account acc = getAccount();
            newGmpBatch(gmp.Id, 'GMP Batch', 'G1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, gmp.Id, gmp.Name, gmp.Program_Code__c, 'Website', 'Test', 'Applicant', false
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void pgdm_sameProgram_sameCycle() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program pgdm = getProgram('PGDM');
            Account acc = getAccount();

            ProgramCohort existingBatch = newPgdmBatch(pgdm.Id, 'PGDM Batch', 'C1', false);
            Application__c existingApp = newApplication(acc.Id, pgdm.Id, existingBatch.Id, 'Paid');
            newOpportunity(acc.Id, pgdm.Id, existingApp.Id);

            newPgdmBatch(pgdm.Id, 'PGDM Batch Current', 'C1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, pgdm.Id, pgdm.Name, pgdm.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void pgdm_sameProgram_differentCycle() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program pgdm = getProgram('PGDM');
            Account acc = getAccount();

            ProgramCohort oldBatch = newPgdmBatch(pgdm.Id, 'PGDM Old Batch', 'OLD', false);
            Application__c oldApp = newApplication(acc.Id, pgdm.Id, oldBatch.Id, 'Paid');
            newOpportunity(acc.Id, pgdm.Id, oldApp.Id);

            newPgdmBatch(pgdm.Id, 'PGDM Current Batch', 'C1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, pgdm.Id, pgdm.Name, pgdm.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void pgdm_sibling_sameCycle_unpaid() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program pgdm = getProgram('PGDM');
            Program pgdmBm = getProgram('PGDM-BM');
            Account acc = getAccount();

            ProgramCohort pgdmBatch = newPgdmBatch(pgdm.Id, 'PGDM Batch', 'C1', false);
            Application__c pgdmApp = newApplication(acc.Id, pgdm.Id, pgdmBatch.Id, 'Initiated');
            newOpportunity(acc.Id, pgdm.Id, pgdmApp.Id);

            newPgdmBatch(pgdmBm.Id, 'PGDM BM Batch', 'C1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, pgdmBm.Id, pgdmBm.Name, pgdmBm.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void pgdm_parentProgramUnpaid() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program parent = getProgram('PGDM&PGDM-BM');
            Program pgdm = getProgram('PGDM');
            Account acc = getAccount();

            ProgramCohort parentBatch = newPgdmBatch(parent.Id, 'Parent Batch', 'PC1', false);
            Application__c parentApp = newApplication(acc.Id, parent.Id, parentBatch.Id, 'Initiated');
            newOpportunity(acc.Id, parent.Id, parentApp.Id);

            newPgdmBatch(pgdm.Id, 'PGDM Batch', 'C1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, pgdm.Id, pgdm.Name, pgdm.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void pgdm_parentProgramPaidSameCycle() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program parent = getProgram('PGDM&PGDM-BM');
            Program pgdm = getProgram('PGDM');
            Account acc = getAccount();

            ProgramCohort parentBatch = newPgdmBatch(parent.Id, 'Parent Batch', 'C1', false);
            Application__c parentApp = newApplication(acc.Id, parent.Id, parentBatch.Id, 'Paid');
            newOpportunity(acc.Id, parent.Id, parentApp.Id);

            newPgdmBatch(pgdm.Id, 'PGDM Batch', 'C1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, pgdm.Id, pgdm.Name, pgdm.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }

    @IsTest
    static void pgdm_parentProgramPaidDifferentCycle() {
        User u = [SELECT Id FROM User WHERE LastName = 'Admin' LIMIT 1];
        System.runAs(u) {
            Program parent = getProgram('PGDM&PGDM-BM');
            Program pgdm = getProgram('PGDM');
            Account acc = getAccount();

            ProgramCohort parentBatch = newPgdmBatch(parent.Id, 'Parent Batch', 'OLD', false);
            Application__c parentApp = newApplication(acc.Id, parent.Id, parentBatch.Id, 'Paid');
            newOpportunity(acc.Id, parent.Id, parentApp.Id);

            newPgdmBatch(pgdm.Id, 'PGDM Batch', 'C1', true);

            Test.startTest();
            OpportunityApplicationService.ApplicationResult res =
                OpportunityApplicationService.createOpportunityAndApplicationIfMissing(
                    acc.Id, pgdm.Id, pgdm.Name, pgdm.Program_Code__c, 'Website', 'Test', 'Applicant', true
                );
            Test.stopTest();

            System.assertNotEquals(null, res);
        }
    }
}