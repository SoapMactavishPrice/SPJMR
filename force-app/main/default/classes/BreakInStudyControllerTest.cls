@isTest
private class BreakInStudyControllerTest {

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
}
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

            System.assert(false);

        } catch (AuraHandledException ex) {

           // System.assert(ex.getMessage().contains('Program Cohort Member Id is required.'));

        }

        Test.stopTest();
    }

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

            System.assert(false);

        } catch (AuraHandledException ex) {
    System.debug('ACTUAL MESSAGE >>> ' + ex.getMessage());
    System.assert(ex.getMessage().contains('End Date'));

        }

        Test.stopTest();
    }

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

            System.assert(false);

        } catch (AuraHandledException ex) {

           // System.assert( ex.getMessage().contains('Please enter both Start Date'));

        }

        Test.stopTest();
    }
}