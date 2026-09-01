@isTest
private class BreakInStudyControllerTest {

    /*
     * =============================================================
     * TEST SETUP
     * =============================================================
     * IMPORTANT: The controller now requires the RUNNING USER to be
     * a Programme Manager (Program_Team_Members__c with Role__c =
     * 'Manager') for the Programme tied to the ProgramCohortMember.
     * Without this, every existing test would fail with the new
     * "not authorized" exception. We create that Program Team
     * Member record for the running context user here so the
     * "happy path" tests keep working, and add a dedicated test
     * further down using a DIFFERENT user to exercise the
     * unauthorized branch.
     */
    @testSetup
    static void setupData() {
        Program program = new Program(
            Name = 'MBA Program',
            Program_Code__c = 'MBA001',
            Short_Programme_Code__c = 'MBA',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert program;

        RecordType studentRt = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Student'
            LIMIT 1
        ];

        Account student = new Account(
            RecordTypeId = studentRt.Id,
            FirstName = 'Test',
            LastName = 'Student'
        );
        insert student;

        ProgramCohort cohort = new ProgramCohort(
            Name = 'MBA 2026',
            ProgramId = program.Id,
            Batch_Code__c = 'MBA2026',
            Batch_Sub_Type__c = 'Class Room'
        );
        insert cohort;

        ProgramEnrollment enrollment = new ProgramEnrollment(
            AccountId = student.Id,
            ProgramId = program.Id
            // add any other required fields your org enforces
        );
        insert enrollment;

        ProgramCohortMember pcm = new ProgramCohortMember(
            ProgramCohortId = cohort.Id,
            ProgramEnrollmentId = enrollment.Id   // <-- correct writable field
        );
        insert pcm;

        // NEW: Program Team + Program Team Member so the RUNNING
        // context user (the one @testSetup and @isTest methods run
        // as by default, before any System.runAs) is recognized as
        // the Programme Manager for this Programme.
        Program_Team__c team = new Program_Team__c(
            Name       = 'MBA Programme Team',
            Program__c = program.Id
        );
        insert team;

        insert new Program_Team_Members__c(
            Program_Team__c = team.Id,
            Role__c         = 'Manager',
            User__c         = UserInfo.getUserId()
        );
    }


    /*
     * =============================================================
     * HAPPY PATH: running user IS the Programme Manager
     * =============================================================
     */
    @isTest
    static void testCreateDefermentRequest() {

        ProgramCohortMember pcm =
            [SELECT Id FROM ProgramCohortMember LIMIT 1];

        Test.startTest();

        Id requestId =
            BreakInStudyController.createDefermentRequest(
                pcm.Id,
                System.now(),
                System.now().addDays(5),
                1000
            );

        Test.stopTest();

        System.assertNotEquals(null, requestId);

        Deferment_Request__c req = [
            SELECT Id,
                   Program_Cohort_Member__c,
                   Batch__c,
                   Programme__c,
                   Account__c,
                   Deferment_Application_Fee__c
            FROM Deferment_Request__c
            WHERE Id = :requestId
        ];

        System.assertEquals(pcm.Id, req.Program_Cohort_Member__c);
        System.assertEquals(1000, req.Deferment_Application_Fee__c);
    }


    /*
     * =============================================================
     * NULL PROGRAM COHORT MEMBER
     * =============================================================
     */
    @isTest
    static void testNullProgramCohortMember() {

        Test.startTest();

        try {

            BreakInStudyController.createDefermentRequest(
                null,
                System.now(),
                System.now().addDays(1),
                100
            );

            System.assert(false, 'Expected exception for null Program Cohort Member Id.');

        } catch (AuraHandledException ex) {

            System.assert(
                ex.getMessage().contains('Program Cohort Member Id is required.'),
                'Unexpected message: ' + ex.getMessage()
            );
        }

        Test.stopTest();
    }


    /*
     * =============================================================
     * INVALID DATES (end <= start)
     * =============================================================
     */
    @isTest
    static void testInvalidDates() {

        ProgramCohortMember pcm =
            [SELECT Id FROM ProgramCohortMember LIMIT 1];

        Test.startTest();

        try {

            BreakInStudyController.createDefermentRequest(
                pcm.Id,
                System.now(),
                System.now().addHours(-2),
                100
            );

            System.assert(false, 'Expected exception for invalid dates.');

        } catch (AuraHandledException ex) {
            System.debug('ACTUAL MESSAGE >>> ' + ex.getMessage());
            System.assert(
                ex.getMessage().contains('End Date'),
                'Unexpected message: ' + ex.getMessage()
            );
        }

        Test.stopTest();
    }


    /*
     * =============================================================
     * NULL DATES
     * =============================================================
     */
    @isTest
    static void testNullDates() {

        ProgramCohortMember pcm =
            [SELECT Id FROM ProgramCohortMember LIMIT 1];

        Test.startTest();

        try {

            BreakInStudyController.createDefermentRequest(
                pcm.Id,
                null,
                null,
                100
            );

            System.assert(false, 'Expected exception for null dates.');

        } catch (AuraHandledException ex) {

            System.assert(
                ex.getMessage().contains('Please enter both Start Date'),
                'Unexpected message: ' + ex.getMessage()
            );
        }

        Test.stopTest();
    }


    @isTest
static void testUnauthorizedUser_Throws() {

    // Create a second Programme for which the current user
    // is NOT a Programme Manager.
    Program unauthorizedProgram = new Program(
        Name = 'Unauthorized Programme',
        Program_Code__c = 'UNAUTH001',
        Short_Programme_Code__c = 'UNA',
        Programme_Type__c = 'Full-time',
        Programme_Sub_Type__c = 'Class Room',
        IsActive = true
    );
    insert unauthorizedProgram;


    Account student = [
        SELECT Id
        FROM Account
        LIMIT 1
    ];


    ProgramCohort unauthorizedCohort = new ProgramCohort(
        Name = 'Unauthorized Batch',
        ProgramId = unauthorizedProgram.Id,
        Batch_Code__c = 'UNAUTH2026',
        Batch_Sub_Type__c = 'Class Room'
    );
    insert unauthorizedCohort;


    ProgramEnrollment enrollment = new ProgramEnrollment(
        AccountId = student.Id,
        ProgramId = unauthorizedProgram.Id
    );
    insert enrollment;


    ProgramCohortMember pcm = new ProgramCohortMember(
        ProgramCohortId = unauthorizedCohort.Id,
        ProgramEnrollmentId = enrollment.Id
    );
    insert pcm;


    Test.startTest();

    try {

        BreakInStudyController.createDefermentRequest(
            pcm.Id,
            System.now(),
            System.now().addDays(5),
            1000
        );

        System.assert(
            false,
            'Expected exception for unauthorized user.'
        );

    } catch (AuraHandledException ex) {

        System.assert(
            ex.getMessage().contains('not authorized'),
            'Unexpected message: ' + ex.getMessage()
        );
    }

    Test.stopTest();
}

    @isTest
    static void testExistingDefermentRequest_Throws() {
        ProgramCohortMember pcm = [
            SELECT Id
            FROM ProgramCohortMember
            LIMIT 1
        ];

        BreakInStudyController.createDefermentRequest(
            pcm.Id,
            System.now(),
            System.now().addDays(5),
            1000
        );

        Test.startTest();
        try {
            BreakInStudyController.createDefermentRequest(
                pcm.Id,
                System.now(),
                System.now().addDays(5),
                1000
            );
            System.assert(false, 'Expected an exception for a duplicate request.');
        } catch (AuraHandledException ex) {
            System.assert(
                ex.getMessage().contains('already exists'),
                'Unexpected message: ' + ex.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testUnknownProgramCohortMember_ThrowsHandledError() {
        Id unknownPcmId = Id.valueOf(
            ProgramCohortMember.SObjectType.getDescribe().getKeyPrefix() +
            '000000000000AAA'
        );

        Test.startTest();
        try {
            BreakInStudyController.createDefermentRequest(
                unknownPcmId,
                System.now(),
                System.now().addDays(5),
                1000
            );
            System.assert(false, 'Expected an exception for an unknown cohort member.');
        } catch (AuraHandledException ex) {
            System.assert(
                ex.getMessage().contains('An unexpected error occurred'),
                'Unexpected message: ' + ex.getMessage()
            );
        }
        Test.stopTest();
    }
}