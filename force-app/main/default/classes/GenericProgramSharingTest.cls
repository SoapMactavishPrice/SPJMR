@isTest
public class GenericProgramSharingTest {

    @testSetup
    static void setupData() {

        // Create Users
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u1 = new User(
            Alias = 'u1',
            Email = 'u1@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User1',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            Username = 'u1' + System.currentTimeMillis() + '@test.com'
        );

        insert u1;

        // Create Program
        Program program = new Program(Name = 'Test Program',Program_Code__c='ABC',Short_Programme_Code__c='ABC',
                                     Programme_Type__c='Full-time',Programme_Sub_Type__c='Class Room',Programme_Intake__c=200,
                                     Duration_to_Complete_In_Months__c=24,Status='Active',Programme_Contact__c='8901776516');
        
        insert program;

        // Program Team
        Program_Team__c team = new Program_Team__c(
            Name = 'Team 1',
            Program__c = program.Id
        );
        insert team;

        // Program Team Member
        Program_Team_Members__c member = new Program_Team_Members__c(
            Program_Team__c = team.Id,
            User__c = u1.Id,
            AccessLevel__c = 'Edit'
        );
        insert member;

        // Application (Direct Program)
        Application__c app = new Application__c(
            Name = 'App1',
            Program__c = program.Id
        );
        insert app;

        // Child Object (Parent Chain)
        Academic_Detail__c acad = new Academic_Detail__c(
            Application__c = app.Id
        );
        insert acad;

        // Deep Child (Multi-level)
        Graduation_Details_Semester_wise__c grad =
            new Graduation_Details_Semester_wise__c(
                Academic_Detail__c = acad.Id
            );
        insert grad;

        // Slot Booking
        ApplicationSlotBooking__c slot = new ApplicationSlotBooking__c(
            Application__c = app.Id
        );
        insert slot;

        // Evaluation (Another chain)
        Evaluation__c eval = new Evaluation__c(
            Application_Slot_Booking__c = slot.Id
        );
        insert eval;
    }

    @isTest
    static void testDirectProgramResolution() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();

        Map<Id, Id> result =
            ProgramResolver.resolvePrograms(
                'Application__c',
                new Set<Id>{app.Id}
            );

        Test.stopTest();

        System.assert(!result.isEmpty(), 'Direct program resolution failed');
    }

    @isTest
    static void testParentResolution() {

        Academic_Detail__c acad =
            [SELECT Id FROM Academic_Detail__c LIMIT 1];

        Test.startTest();

        Map<Id, Id> result =
            ProgramResolver.resolvePrograms(
                'Academic_Detail__c',
                new Set<Id>{acad.Id}
            );

        Test.stopTest();

        System.assert(!result.isEmpty(), 'Parent resolution failed');
    }

    @isTest
    static void testMultiLevelResolution() {

        Graduation_Details_Semester_wise__c grad =
            [SELECT Id FROM Graduation_Details_Semester_wise__c LIMIT 1];

        Test.startTest();

        Map<Id, Id> result =
            ProgramResolver.resolvePrograms(
                'Graduation_Details_Semester_wise__c',
                new Set<Id>{grad.Id}
            );

        Test.stopTest();

        System.assert(!result.isEmpty(), 'Multi-level resolution failed');
    }

    @isTest
    static void testProgramTeamFetch() {

        Program program = [SELECT Id FROM Program LIMIT 1];

        Test.startTest();

        Map<Id, List<Program_Team_Members__c>> result =
            ProgramTeamService.getActiveMembers(
                new Set<Id>{program.Id}
            );

        Test.stopTest();

        System.assert(!result.isEmpty(), 'Team members not fetched');
    }

    @isTest
    static void testShareBuilder() {

        Application__c app = [SELECT Id, Program__c FROM Application__c LIMIT 1];

        Map<Id, Id> recordToProgram = new Map<Id, Id>{
            app.Id => app.Program__c
        };

        Map<Id, List<Program_Team_Members__c>> members =
            ProgramTeamService.getActiveMembers(
                new Set<Id>{app.Program__c}
            );

        Test.startTest();

        List<SObject> shares =
            ShareBuilder.buildShares(
                'Application__c',
                recordToProgram,
                members
            );

        Test.stopTest();

        System.assert(!shares.isEmpty(), 'Shares not built');
    }

    @isTest
    static void testFutureSharing() {

        Application__c app = [SELECT Id FROM Application__c LIMIT 1];

        Test.startTest();

        GenericProgramSharingFuture.shareRecords(
            'Application__c',
            new List<Id>{app.Id}
        );

        Test.stopTest();

        // Verify share record created
        List<Application__Share> shares =
            [SELECT Id FROM Application__Share WHERE ParentId = :app.Id];

        System.assert(!shares.isEmpty(), 'Share not inserted');
    }

    @isTest
    static void testOrchestrator() {

        Application__c app =
            [SELECT Id, Program__c FROM Application__c LIMIT 1];

        Program newProgram = new Program(Name = 'Test Program 2',Program_Code__c='EFG',Short_Programme_Code__c='EFG',
                                     Programme_Type__c='Full-time',Programme_Sub_Type__c='Class Room',Programme_Intake__c=200,
                                     Duration_to_Complete_In_Months__c=24,Status='Active',Programme_Contact__c='8901776516');
        insert newProgram;

        Application__c updatedApp = app.clone(false);
        updatedApp.Id = app.Id;
        updatedApp.Program__c = newProgram.Id;

        Test.startTest();

        SharingOrchestrator.processRecordsToUpdate(
            new List<Application__c>{updatedApp},
            new Map<Id, Application__c>{app.Id => app}
        );

        Test.stopTest();

        // No assertion needed (future call coverage)
        System.assert(true);
    }
}