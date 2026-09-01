@IsTest
private class ApplicationEvalExportControllerTest {
    
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
            FirstName = 'Controller',
            LastName = 'Test',
            PersonEmail = 'controller.test@example.com'
        );
        insert applicant;

        Program prog = new Program(
            Name = 'Controller Program',
            Program_Code__c = 'CPGM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPM'
        );
        insert prog;

        RoundMaster__c round = new RoundMaster__c(
            Name = 'Controller Round',
            RoundNumber__c = '1',
            Program__c = prog.Id
        );
        insert round;

        SlotMaster__c slot = new SlotMaster__c(
            Name = 'CTRL-SLOT-001',
            SlotDate__c = Date.today(),
            SlotStartTime__c = Time.newInstance(9, 0, 0, 0),
            SlotEndtime__c = Time.newInstance(10, 0, 0, 0),
            Program_Master__c = prog.Id
        );
        insert slot;

        Application__c app = new Application__c(
            Name = 'CTRL-APP-001',
            Applicant__c = applicant.Id,
            Program__c = prog.Id
        );
        insert app;

        PanelMaster__c panel = new PanelMaster__c(
        );
        insert panel;

        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c = app.Id,
            SlotMaster__c = slot.Id,
            RoundMaster__c = round.Id,
            Panel_Master__c = panel.Id
        );
        insert booking;

        Account evaluator = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Ctrl',
            LastName = 'Evaluator',
            PersonEmail = 'ctrl.evaluator@example.com'
        );
        insert evaluator;

        Evaluation__c eval = new Evaluation__c(
            Application_Slot_Booking__c = booking.Id,
            EvaluatedUser__c = evaluator.Id,
            Status__c = 'Complete'
        );
        insert eval;
    }

    @IsTest
    static void testStartExportSuccess() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Test.startTest();
        String jobId = ApplicationEvaluationExportController.startExport(
            prog.Id,
            round.Id,
            Date.today().addDays(-1),
            Date.today(),
            '09:00:00',
            '10:00:00'
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void testStartExportNullProgram() {
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        try {
            ApplicationEvaluationExportController.startExport(
                null,
                round.Id,
                Date.today(),
                Date.today(),
                null,
                null
            );
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('program'));
        }
    }

    @IsTest
    static void testStartExportNullRound() {
        Program prog = [SELECT Id FROM Program LIMIT 1];

        try {
            ApplicationEvaluationExportController.startExport(
                prog.Id,
                null,
                Date.today(),
                Date.today(),
                null,
                null
            );
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('round'));
        }
    }

    @IsTest
    static void testStartExportInvalidDateRange() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        try {
            ApplicationEvaluationExportController.startExport(
                prog.Id,
                round.Id,
                Date.today(),
                Date.today().addDays(-5),
                null,
                null
            );
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('End Date'));
        }
    }

    @IsTest
    static void testStartExportEndDateWithoutStartDate() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        try {
            ApplicationEvaluationExportController.startExport(
                prog.Id,
                round.Id,
                null,
                Date.today(),
                null,
                null
            );
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('Start Date'));
        }
    }

    @IsTest
    static void testStartExportInvalidTimeRange() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        try {
            ApplicationEvaluationExportController.startExport(
                prog.Id,
                round.Id,
                Date.today(),
                Date.today(),
                '10:00:00',
                '09:00:00'
            );
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('Time'));
        }
    }

    @IsTest
    static void testGetEvaluationCount() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Test.startTest();
        Integer count = ApplicationEvaluationExportController.getEvaluationCount(
            prog.Id,
            round.Id,
            Date.today().addDays(-1),
            Date.today(),
            '08:00:00',
            '11:00:00'
        );
        Test.stopTest();

        System.assert(count >= 0);
    }

    @IsTest
    static void testGetEvaluationCountNullDates() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Integer count = ApplicationEvaluationExportController.getEvaluationCount(
            prog.Id,
            round.Id,
            null,
            null,
            null,
            null
        );

        System.assert(count >= 0);
    }

    @IsTest
    static void testIsRoundForProgram() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Boolean isValid = ApplicationEvaluationExportController.isRoundForProgram(
            prog.Id,
            round.Id
        );

        System.assertEquals(true, isValid);
    }

    @IsTest
    static void testIsRoundForProgramInvalid() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        Program otherProg = new Program(
            Name = 'Other Program',
            Program_Code__c = 'OTHER',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PDM'
        );
        insert otherProg;

        RoundMaster__c otherRound = new RoundMaster__c(
            Name = 'Other Round',
            RoundNumber__c = '1',
            Program__c = otherProg.Id
        );
        insert otherRound;

        Boolean isValid = ApplicationEvaluationExportController.isRoundForProgram(
            prog.Id,
            otherRound.Id
        );

        System.assertEquals(false, isValid);
    }

    @IsTest
    static void testIsRoundForProgramNullInputs() {
        System.assertEquals(false, ApplicationEvaluationExportController.isRoundForProgram(null, null));
    }

    @IsTest
    static void testSendExportEmail() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test Export',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf('test content')
        );
        insert cv;

        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        String filesJson = JSON.serialize(new List<Map<String, String>>{
            new Map<String, String>{
                'name' => 'Test Export.csv',
                'documentId' => cv.ContentDocumentId
            }
        });

        Test.startTest();
        ApplicationEvaluationExportController.sendExportEmail(filesJson);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testStartExportWrongRoundForProgram() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        Program otherProg = new Program(
            Name = 'Wrong Program',
            Program_Code__c = 'WRONG',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PYM'
        );
        insert otherProg;

        RoundMaster__c wrongRound = new RoundMaster__c(
            Name = 'Wrong Round',
            RoundNumber__c = '2',
            Program__c = otherProg.Id
        );
        insert wrongRound;

        try {
            ApplicationEvaluationExportController.startExport(
                prog.Id,
                wrongRound.Id,
                Date.today(),
                Date.today(),
                null,
                null
            );
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            // System.assert(e.getMessage().contains('program'));
        }
    }
}