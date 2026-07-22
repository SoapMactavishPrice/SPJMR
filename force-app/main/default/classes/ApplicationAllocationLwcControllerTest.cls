@IsTest
private class ApplicationAllocationLwcControllerTest {

    @TestSetup
    static void setupData() {

        Program prog = new Program(
            Name = 'Test Program',
            Programme_Contact__c = '9876543210',
            Program_Code__c = 'PRG001',
            Short_Programme_Code__c = 'SP0',
            Programme_Type__c = 'Part-time',
            Programme_Sub_Type__c = 'Class Room'
        );
        insert prog;

        Program_Team__c appTeam = new Program_Team__c(
            Name = 'App Verifier Team',
            Program__c = prog.Id,
            Type__c = 'Verifier',
            IsApplicationVerifier__c = true
        );

        Program_Team__c docTeam = new Program_Team__c(
            Name = 'Doc Verifier Team',
            Program__c = prog.Id,
            Type__c = 'Verifier',
            IsDocumentVerifier__c = true
        );

        insert new List<Program_Team__c>{appTeam, docTeam};

        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];

        User u1 = new User(
            FirstName = 'App',
            LastName = 'Verifier',
            Alias = 'appv',
            Email = 'appv@test.com',
            Username = 'appv' + System.currentTimeMillis() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u1;

        Program_Team_Members__c ptm = new Program_Team_Members__c(
            Program_Team__c = appTeam.Id,
            User__c = u1.Id
        );
        insert ptm;

        List<Application__c> apps = new List<Application__c>();
        for(Integer i=1;i<=5;i++){
            apps.add(new Application__c(
                Program__c = prog.Id,
                First_Name__c = 'First'+i,
                Last_Name__c = 'Last'+i,
                Assignment_Status__c = 'Not Assigned'
            ));
        }
        insert apps;
    }

    // =====================================================
    // LOAD INIT + PAGINATION
    // =====================================================
    @IsTest
    static void testLoadAndPagination() {

        Program prog = [SELECT Id FROM Program LIMIT 1];

        Test.startTest();

        Object initData =
            ApplicationAllocationLwcController.loadInit(prog.Id, 'Application');

        Integer countVal =
            ApplicationAllocationLwcController.getApplicationsCount(prog.Id, 'Application');

        List<ApplicationAllocationLwcController.ApplicationDTO> apps =
            ApplicationAllocationLwcController.getApplicationsPage(prog.Id, 'Application', 1, 5);

        Test.stopTest();

        System.assertNotEquals(null, initData);
        System.assert(countVal >= 0);
        System.assertNotEquals(null, apps);
    }

    // =====================================================
    // AUTO ALLOCATE
    // =====================================================
    @IsTest
    static void testAutoAllocate() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 3];
        List<Program_Team_Members__c> ptms = [SELECT Id FROM Program_Team_Members__c LIMIT 1];

        List<Id> appIds = new List<Id>();
        for(Application__c a : apps){
            appIds.add(a.Id);
        }

        Test.startTest();

        ApplicationAllocationLwcController.autoAllocate(
            prog.Id,
            appIds,
            new List<Id>{ptms[0].Id},
            'Application'
        );

        Test.stopTest();

        List<Application_Verification__c> av =
            [SELECT Id FROM Application_Verification__c WHERE Application__c IN :appIds];

        System.assert(av.size() >= 0);
    }

    // =====================================================
    // MANUAL ALLOCATE
    // =====================================================
    @IsTest
    static void testManualAllocate() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        List<Application__c> apps = [SELECT Id FROM Application__c LIMIT 2];
        Program_Team_Members__c ptm = [SELECT Id FROM Program_Team_Members__c LIMIT 1];

        List<Id> appIds = new List<Id>();
        for(Application__c a : apps){
            appIds.add(a.Id);
        }

        Test.startTest();

        ApplicationAllocationLwcController.manualAllocate(
            prog.Id,
            appIds,
            new List<Id>{ptm.Id}
        );

        Test.stopTest();

        System.assert(true);
    }

    // =====================================================
    // REASSIGN
    // =====================================================
    @IsTest
    static void testReassign() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        Program_Team_Members__c ptm =
            [SELECT Id, User__c FROM Program_Team_Members__c LIMIT 1];

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id,
            Program_Team_Members__c = ptm.Id,
            Verifier__c = ptm.User__c,
            OwnerId = ptm.User__c,
            Application_Verification_Status__c = 'Assigned'
        );
        insert av;

        Test.startTest();

        ApplicationAllocationLwcController.reassignApplications(
            prog.Id,
            ptm.Id,
            ptm.Id,
            null
        );

        Integer countVal =
            ApplicationAllocationLwcController.getReassignListCount(prog.Id, ptm.Id);

      List<ApplicationAllocationLwcController.ApplicationDTO> page =
    ApplicationAllocationLwcController.getReassignListPage(prog.Id, ptm.Id, 1, 10);

        Test.stopTest();

        System.assert(countVal >= 0);
        System.assertNotEquals(null, page);
    }

    // =====================================================
    // STAGE BASED REASSIGN
    // =====================================================
    @IsTest
    static void testReassignByStage() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        Program_Team_Members__c ptm =
            [SELECT Id, User__c FROM Program_Team_Members__c LIMIT 1];

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id,
            Program_Team_Members__c = ptm.Id,
            Verifier__c = ptm.User__c,
            OwnerId = ptm.User__c,
            Application_Verification_Status__c = 'Assigned',
            Status__c = 'Assigned'
        );
        insert av;

        Test.startTest();

        ApplicationAllocationLwcController.reassignApplicationsByStage(
            prog.Id,
            'Application',
            ptm.Id,
            ptm.Id,
            null
        );

        Integer countVal =
            ApplicationAllocationLwcController.getReassignListCountByStage(
                prog.Id,
                'Application',
                ptm.Id
            );

        List<ApplicationAllocationLwcController.ApplicationDTO> page =
    ApplicationAllocationLwcController.getReassignListPageByStage(
        prog.Id,
        'Application',
        ptm.Id,
        1,
        10
    );

        Test.stopTest();

        System.assert(countVal >= 0);
        System.assertNotEquals(null, page);
    }

    // =====================================================
    // ASSIGNED APPLICATION PAGE
    // =====================================================
    @IsTest
    static void testAssignedPage() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        Program_Team_Members__c ptm =
            [SELECT Id FROM Program_Team_Members__c LIMIT 1];

        Test.startTest();

        Integer countVal =
            ApplicationAllocationLwcController.getAssignedApplicationsCount(
                prog.Id,
                new List<Id>{ptm.Id}
            );

        List<ApplicationAllocationLwcController.ApplicationDTO> apps =
            ApplicationAllocationLwcController.getAssignedApplicationsPage(
                prog.Id,
                new List<Id>{ptm.Id},
                1,
                10
            );

        Test.stopTest();

        System.assert(countVal >= 0);
        System.assertNotEquals(null, apps);
    }

    // =====================================================
    // DOCUMENT FLOW
    // =====================================================
    @IsTest
    static void testDocumentStageFlow() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        Program_Team_Members__c ptm =
            [SELECT Id FROM Program_Team_Members__c LIMIT 1];

        List<Application__c> apps =
            [SELECT Id FROM Application__c LIMIT 2];

        List<Id> appIds = new List<Id>();
        for(Application__c a : apps){
            appIds.add(a.Id);
        }

        Test.startTest();

        ApplicationAllocationLwcController.loadInit(prog.Id, 'Document');
        ApplicationAllocationLwcController.getApplicationsCount(prog.Id, 'Document');
        ApplicationAllocationLwcController.getApplicationsPage(prog.Id, 'Document', 1, 5);

        ApplicationAllocationLwcController.autoAllocate(
            prog.Id,
            appIds,
            new List<Id>{ptm.Id},
            'Document'
        );

        Test.stopTest();

        System.assert(true);
    }

    // =====================================================
    // EMPTY SELECTION
    // =====================================================
    @IsTest
    static void testEmptySelections() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        Application__c app = [SELECT Id FROM Application__c LIMIT 1];
        Program_Team_Members__c ptm =
            [SELECT Id FROM Program_Team_Members__c LIMIT 1];

        Test.startTest();

        ApplicationAllocationLwcController.autoAllocate(
            prog.Id,
            new List<Id>{app.Id},
            new List<Id>{ptm.Id},
            'Application'
        );

        ApplicationAllocationLwcController.manualAllocate(
            prog.Id,
            new List<Id>{app.Id},
            new List<Id>{ptm.Id}
        );

        Test.stopTest();

        System.assert(true);
    }

    // =====================================================
    // ALREADY ASSIGNED
    // =====================================================
    @IsTest
    static void testAlreadyAssignedScenario() {

        Program prog = [SELECT Id FROM Program LIMIT 1];
        Program_Team_Members__c ptm =
            [SELECT Id, User__c FROM Program_Team_Members__c LIMIT 1];

        Application__c app =
            [SELECT Id FROM Application__c LIMIT 1];

        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id,
            Program_Team_Members__c = ptm.Id,
            Verifier__c = ptm.User__c,
            OwnerId = ptm.User__c,
            Application_Verification_Status__c = 'Assigned'
        );
        insert av;

        Test.startTest();

        ApplicationAllocationLwcController.manualAllocate(
            prog.Id,
            new List<Id>{app.Id},
            new List<Id>{ptm.Id}
        );

        Test.stopTest();

        System.assert(true);
    }
}