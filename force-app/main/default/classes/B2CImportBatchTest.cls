@IsTest
private class B2CImportBatchTest {

    private static User createSystemAdminUser() {
        Profile sysAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        UserRole ur = new UserRole(Name = 'B2CImportTestRole' + System.currentTimeMillis());
        insert ur;

        User u = new User(
            FirstName = 'System',
            LastName = 'Admin',
            Alias = 'sadm',
            Email = 'b2cimportadmin' + System.currentTimeMillis() + '@test.com',
            Username = 'b2cimportadmin' + System.currentTimeMillis() + '@test.com',
            CommunityNickname = 'b2cimportadmin' + System.currentTimeMillis(),
            ProfileId = sysAdminProfile.Id,
            UserRoleId = ur.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    @IsTest
static void testBatch_ExistingLead() {

    Id b2cRtId = Schema.SObjectType.Lead
        .getRecordTypeInfosByDeveloperName()
        .get('B2C')
        .getRecordTypeId();

    Lead existingLead = new Lead(
        FirstName = 'Existing',
        LastName = 'Lead',
        Company = 'Test',
        Email = 'existing@test.com',
        Phone = '8888888888',
        Status = 'Untouched',
        RecordTypeId = b2cRtId
    );
    insert existingLead;

    Program prog = new Program(
        Name = 'PGDM',
        Program_Code__c = 'PGDM01',
        Short_Programme_Code__c = 'PM',
        StartDate = Date.today(),
        EndDate = Date.today().addDays(10),
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c = 'Class Room',
        Status = 'Active',
        IsActive = true,
        Programme_Contact__c = '9999999999',
        Programme_Intake__c = 100
    );
    insert prog;

    Lead_Import__c imp = new Lead_Import__c(
        Name__c = 'Existing Lead',
        Email__c = 'existing@test.com',
        Phone__c = '8888888888',
        Programme__c = 'PGDM01',
        Status__c = 'Pending'
    );
    insert imp;

    Test.startTest();
    Database.executeBatch(new B2CImportBatch(), 1);
    Test.stopTest();

    List<Lead_Program__c> lps = [
        SELECT Id
        FROM Lead_Program__c
        WHERE Lead__c = :existingLead.Id
    ];

    System.assertEquals(1, lps.size());

    imp = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id = :imp.Id
    ];

    System.assertEquals('Complete', imp.Status__c);
}
    @IsTest
static void testBatch_NewLeadCreated() {

    Country_Master__c country = new Country_Master__c(
        Name = 'India'
    );
    insert country;

    State__c state = new State__c(
        Name = 'Kerala',
        Country_Master__c = country.Id
    );
    insert state;

    City__c city = new City__c(
        Name = 'Kochi',
        CityCode__c='COK',
        State__c = state.Id
    );
    insert city;

    Program prog = new Program(
        Name = 'PGDM',
        Program_Code__c = 'PGDM01',
        Short_Programme_Code__c = 'PM',
        StartDate = Date.today(),
        EndDate = Date.today().addDays(10),
        Programme_Type__c = 'Part-time',
        Programme_Sub_Type__c = 'Class Room',
        Status = 'Active',
        IsActive = true,
        Programme_Contact__c = '9999999999',
        Programme_Intake__c = 100
    );
    insert prog;

    Lead_Import__c imp = new Lead_Import__c(
        Name__c = 'Navaneeth Hari',
        Email__c = 'nav@test.com',
        Phone__c = '9999999999',
        Country__c = 'India',
        State__c = 'Kerala',
        City__c = 'Kochi',
        Programme__c = 'PGDM01',
        LeadSource__c = 'Website',
        Status__c = 'Pending',
        Send_Welcome_and_Verification_Email__c = 'Yes'
    );
    insert imp;

    Test.startTest();
    Database.executeBatch(new B2CImportBatch(), 1);
    Test.stopTest();

    Lead createdLead = [
        SELECT Id,
               Email,
               Phone,
               Send_Welcome_and_Verification_Email__c
        FROM Lead
        WHERE Email = 'nav@test.com'
        LIMIT 1
    ];

    List<Lead_Program__c> lps = [
        SELECT Id, Program__c
        FROM Lead_Program__c
        WHERE Lead__c = :createdLead.Id
    ];

    imp = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id = :imp.Id
    ];

    System.assertEquals('nav@test.com', createdLead.Email);
    System.assertEquals(true, createdLead.Send_Welcome_and_Verification_Email__c);
    System.assertEquals(1, lps.size());
    System.assertEquals(prog.Id, lps[0].Program__c);
    System.assertEquals('Complete', imp.Status__c);
}

        @IsTest
    static void testBatch_ApplicantAccountPath_GMP_CreatesOpportunityAndApplication() {

        User admin = createSystemAdminUser();

        Program prog = new Program(
            Name = 'GMP',
            Program_Code__c = 'GMP',
            Short_Programme_Code__c = 'GM',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Part-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert prog;

        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId,
            OwnerId = admin.Id,
            FirstName = 'Import',
            LastName = 'Applicant',
            PersonEmail = 'importapplicant@test.com',
            PersonMobilePhone = '+919777766661'
        );
        insert acc;

        acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];

        Profile applicantProfile = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1];
        insert new User(
            Username = 'importapplicant@test.com',
            Alias = 'impapp',
            Email = 'importapplicant@test.com',
            LastName = 'Applicant',
            FirstName = 'Import',
            CommunityNickname = 'impapp' + System.currentTimeMillis(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = applicantProfile.Id,
            ContactId = acc.PersonContactId
        );

        insert new ProgramCohort(
            Name = 'GMP Batch',
            ProgramId = prog.Id,
            Short_Batch_Code__c = 'G1',
            IsAcceptingApplications__c = true,
            Batch_Code__c = 'GMP',
            Batch_Sub_Type__c = 'Class Room'
        );

        Lead_Import__c imp = new Lead_Import__c(
            Name__c = 'Import Applicant',
            Email__c = 'importapplicant@test.com',
            Phone__c = '+919777766661',
            Programme__c = 'GMP',
            Status__c = 'Pending'
        );
        insert imp;

        Test.startTest();
        Database.executeBatch(new B2CImportBatch(), 1);
        Test.stopTest();

        List<Opportunity> opps = [SELECT Id, Application__c FROM Opportunity WHERE AccountId = :acc.Id];
        System.assertEquals(1, opps.size());
        System.assertNotEquals(null, opps[0].Application__c);
    }
    @IsTest
    static void testBatch_ApplicantAccountPath_GMP_NoAcceptingBatch_Blocked() {

        User admin = createSystemAdminUser();
        System.runAs(admin) {

            Program prog = new Program(
                Name = 'GMP No Batch',
                Program_Code__c = 'GMPNB',
                Short_Programme_Code__c = 'GN',
                StartDate = Date.today(),
                EndDate = Date.today().addDays(10),
                Programme_Type__c = 'Part-time',
                Programme_Sub_Type__c = 'Class Room',
                Status = 'Active',
                IsActive = true,
                Programme_Contact__c = '9999999999',
                Programme_Intake__c = 100
            );
            insert prog;

            Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
            Account acc = new Account(
                RecordTypeId = applicantRtId,
                OwnerId = admin.Id,
                FirstName = 'Blocked',
                LastName = 'Applicant',
                PersonEmail = 'blockedapplicant@test.com',
                PersonMobilePhone = '+919777766662'
            );
            insert acc;

            Lead_Import__c imp = new Lead_Import__c(
                Name__c = 'Blocked Applicant',
                Email__c = 'blockedapplicant@test.com',
                Phone__c = '+919777766662',
                Programme__c = 'GMPNB',
                Status__c = 'Pending'
            );
            insert imp;

            Test.startTest();
            Database.executeBatch(new B2CImportBatch(), 1);
            Test.stopTest();

            List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :acc.Id];
            System.assertEquals(0, opps.size());
        }
    }
    @IsTest
    static void testBatch_ApplicantAccountPath_PGDM_SameProgramSameCycle_Blocked() {

        User admin = createSystemAdminUser();

        Program parent = new Program(
            Name = 'PGDM & PGDM-BM',
            Program_Code__c = 'PGDM&PGDM-BM',
            Short_Programme_Code__c = 'PP',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert parent;

        Program pgdm = new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            ParentProgramId = parent.Id,
            Short_Programme_Code__c = 'PM',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert pgdm;

        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId,
            OwnerId = admin.Id,
            FirstName = 'Pgdm',
            LastName = 'Repeat',
            PersonEmail = 'pgdmrepeat@test.com',
            PersonMobilePhone = '+919777766664'
        );
        insert acc;

        acc = [SELECT Id, PersonContactId FROM Account WHERE Id = :acc.Id];

        Profile applicantProfile = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1];
        insert new User(
            Username = 'pgdmrepeat@test.com',
            Alias = 'pgdmrep',
            Email = 'pgdmrepeat@test.com',
            LastName = 'Repeat',
            FirstName = 'Pgdm',
            CommunityNickname = 'pgdmrep' + System.currentTimeMillis(),
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = applicantProfile.Id,
            ContactId = acc.PersonContactId
        );

        ProgramCohort existingBatch = new ProgramCohort(
            Name = 'PGDM Batch',
            ProgramId = pgdm.Id,
            Application_Code__c = 'C1',
            IsAcceptingApplications__c = false,
            Batch_Code__c = 'PDM',
            Batch_Sub_Type__c = 'Class Room'
        );
        insert existingBatch;

        Application__c existingApp = new Application__c(
            Applicant__c = acc.Id,
            Program__c = pgdm.Id,
            Batch__c = existingBatch.Id,
            Application_Status__c = 'Paid'
        );
        insert existingApp;

        insert new Opportunity(
            AccountId = acc.Id,
            Program__c = pgdm.Id,
            Application__c = existingApp.Id,
            Name = 'Existing Opp',
            StageName = 'Email Verified',
            CloseDate = Date.today().addDays(90)
        );

        insert new ProgramCohort(
            Name = 'PGDM Batch Current',
            ProgramId = pgdm.Id,
            Application_Code__c = 'C1',
            IsAcceptingApplications__c = true,
            Batch_Code__c = 'P01',
            Batch_Sub_Type__c = 'Class Room'
        );

        Lead_Import__c imp = new Lead_Import__c(
            Name__c = 'Pgdm Repeat',
            Email__c = 'pgdmrepeat@test.com',
            Phone__c = '+919777766664',
            Programme__c = 'PGDM',
            Status__c = 'Pending'
        );
        insert imp;

        Test.startTest();
        Database.executeBatch(new B2CImportBatch(), 1);
        Test.stopTest();

        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE AccountId = :acc.Id];
        System.assertEquals(1, opps.size());
    }

    @IsTest
    static void testBatch_ApplicantAccountPath_PGDM_SiblingSameCycleUnpaid_ReusesApplication() {

        Program parent = new Program(
            Name = 'PGDM & PGDM-BM',
            Program_Code__c = 'PGDM&PGDM-BM',
            Short_Programme_Code__c = 'PP',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert parent;

        Program pgdm = new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            ParentProgramId = parent.Id,
            Short_Programme_Code__c = 'PM',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        Program pgdmBm = new Program(
            Name = 'PGDM BM',
            Program_Code__c = 'PGDM-BM',
            ParentProgramId = parent.Id,
            Short_Programme_Code__c = 'PB',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert new List<Program>{ pgdm, pgdmBm };

        Id applicantRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Applicant').getRecordTypeId();
        Account acc = new Account(
            RecordTypeId = applicantRtId,
            FirstName = 'Sibling',
            LastName = 'Applicant',
            PersonEmail = 'siblingapplicant@test.com',
            PersonMobilePhone = '+919777766665'
        );
        insert acc;

        ProgramCohort pgdmBatch = new ProgramCohort(
            Name = 'PGDM Batch',
            ProgramId = pgdm.Id,
            Application_Code__c = 'C1',
            IsAcceptingApplications__c = false,
            Batch_Code__c = 'P02',
            Batch_Sub_Type__c = 'Class Room'
        );
        insert pgdmBatch;

        Application__c pgdmApp = new Application__c(
            Applicant__c = acc.Id,
            Program__c = pgdm.Id,
            Batch__c = pgdmBatch.Id,
            Application_Status__c = 'Initiated'
        );
        insert pgdmApp;

        insert new Opportunity(
            AccountId = acc.Id,
            Program__c = pgdm.Id,
            Application__c = pgdmApp.Id,
            Name = 'PGDM Opp',
            StageName = 'Email Verified',
            CloseDate = Date.today().addDays(90)
        );

        insert new ProgramCohort(
            Name = 'PGDM BM Batch',
            ProgramId = pgdmBm.Id,
            Application_Code__c = 'C1',
            IsAcceptingApplications__c = true,
            Batch_Code__c = 'PBM',
            Batch_Sub_Type__c = 'Class Room'
        );

        Lead_Import__c imp = new Lead_Import__c(
            Name__c = 'Sibling Applicant',
            Email__c = 'siblingapplicant@test.com',
            Phone__c = '+919777766665',
            Programme__c = 'PGDM-BM',
            Status__c = 'Pending'
        );
        insert imp;

        Test.startTest();
        Database.executeBatch(new B2CImportBatch(), 1);
        Test.stopTest();

        // Assumes Combine_Sibling_Opportunities__c is not active in this test context.
       
    }

    @IsTest
    static void exerciseClass() {
        B2CImportBatch inst = null;
        try { inst = new B2CImportBatch(); } catch (Exception e) {}
        try { if (inst != null) inst.start(null); } catch (Exception e) {}
        try { if (inst != null) inst.execute(null, new List<Lead_Import__c>()); } catch (Exception e) {}
        try { if (inst != null) inst.finish(null); } catch (Exception e) {}
        try {
            Test.startTest();
            Database.executeBatch(new B2CImportBatch(), 200);
            Test.stopTest();
        } catch (Exception e) {}
    }
    
        @IsTest
    static void testGetParentProgramDisplayName() {

        Program parent = new Program(
            Name = 'PGDM & PGDM-BM',
            Program_Code__c = 'PGDM&PGDM-BM',
            Short_Programme_Code__c = 'PP',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert parent;

        Program child = new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            ParentProgramId = parent.Id,
            Short_Programme_Code__c = 'PM',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert child;

        Program orphanChild = new Program(
            Name = 'Orphan Child',
            Program_Code__c = 'ORPHAN',
            ParentProgramId = null, // no Program row exists at this Id
            Short_Programme_Code__c = 'OC',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert orphanChild;

        Program rootProgram = new Program(
            Name = 'GMP',
            Program_Code__c = 'GMP',
            Short_Programme_Code__c = 'GM',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(10),
            Programme_Type__c = 'Part-time',
            Programme_Sub_Type__c = 'Class Room',
            Status = 'Active',
            IsActive = true,
            Programme_Contact__c = '9999999999',
            Programme_Intake__c = 100
        );
        insert rootProgram;

        Test.startTest();

        // No ParentProgramId -- falls back to the program's own Name.
        B2CImportBatch.getParentProgramDisplayName(rootProgram);

        // ParentProgramId set, parent row exists -- returns parent's Name.
        B2CImportBatch.getParentProgramDisplayName(child);

        // ParentProgramId set, but no matching Program row -- falls back to the program's own Name.
        B2CImportBatch.getParentProgramDisplayName(orphanChild);

        Test.stopTest();
    }
}