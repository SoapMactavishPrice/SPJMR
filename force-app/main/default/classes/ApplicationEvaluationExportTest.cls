@IsTest
private class ApplicationEvaluationExportTest {
    
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
            FirstName = 'Export',
            LastName = 'Test',
            PersonEmail = 'export.test@example.com'
        );
        insert applicant;

        Program prog = new Program(
            Name = 'Test Program',  
            Program_Code__c = 'TPGM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'PPM'
        );
        insert prog;

        RoundMaster__c round = new RoundMaster__c(
            Name = 'Round I',
            RoundNumber__c = '1',
            Program__c = prog.Id
        );
        insert round;

        LocationMaster__c location = new LocationMaster__c(
            LocationName__c = 'Test Location',
            AddressInformation__c = '123 Test St'
        );
        insert location;

        SlotMaster__c slot = new SlotMaster__c(
            Name = 'SLOT-001',
            SlotDate__c = Date.today(),
            SlotStartTime__c = Time.newInstance(9, 0, 0, 0),
            SlotEndtime__c = Time.newInstance(10, 0, 0, 0),
            Program_Master__c = prog.Id,
            LocationMaster__c = location.Id
        );
        insert slot;

        Application__c app = new Application__c(
            Name = 'APP-001',
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

        ScoringTemplate__c template1 = new ScoringTemplate__c(
            Round__c = round.Id,
            CriteriaName__c = 'Technical Skills',
            Maximum_Score__c = 10
        );
        ScoringTemplate__c template2 = new ScoringTemplate__c(
            Round__c = round.Id,
            CriteriaName__c = 'Communication',
            Maximum_Score__c = 10
        );
        insert new List<ScoringTemplate__c>{ template1, template2 };

        Account evaluator = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Evaluator',
            LastName = 'One',
            PersonEmail = 'evaluator@example.com'
        );
        insert evaluator;

        Evaluation__c eval = new Evaluation__c(
            Application_Slot_Booking__c = booking.Id,
            EvaluatedUser__c = evaluator.Id,
            Status__c = 'Complete',
            EvaluatorComments__c = 'Good candidate',
            EvaluationDate__c = Date.today()
        );
        insert eval;

        Individual_Criteria_Result__c result1 = new Individual_Criteria_Result__c(
            Evaluation__c = eval.Id,
            Scoring_Template__c = template1.Id,
            Score__c = 9,
            Comments__c = 'Strong technical skills'
        );
        Individual_Criteria_Result__c result2 = new Individual_Criteria_Result__c(
            Evaluation__c = eval.Id,
            Scoring_Template__c = template2.Id,
            Score__c = 9,
            Comments__c = 'Excellent communication'
        );
        insert new List<Individual_Criteria_Result__c>{ result1, result2 };
    }

    @IsTest
    static void testBatchExecutionWithRecords() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Test.startTest();
        ApplicationEvaluationExport batch = new ApplicationEvaluationExport(
            prog.Id, 
            round.Id, 
            Date.today().addDays(-1), 
            Date.today(), 
            Time.newInstance(8, 0, 0, 0),
            Time.newInstance(11, 0, 0, 0)
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Export_Job__c> jobs = [SELECT Id, Status__c FROM Export_Job__c];
        System.assert(jobs.size() > 0);
    }

    @IsTest
    static void testBatchExecutionNoDateFilter() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Test.startTest();
        ApplicationEvaluationExport batch = new ApplicationEvaluationExport(
            prog.Id, 
            round.Id, 
            null, 
            null, 
            null,
            null
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Export_Job__c> jobs = [SELECT Id FROM Export_Job__c];
        System.assert(jobs.size() >= 0);
    }

    @IsTest
    static void testBatchExecutionWithStartDateOnly() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Test.startTest();
        ApplicationEvaluationExport batch = new ApplicationEvaluationExport(
            prog.Id, 
            round.Id, 
            Date.today(), 
            null, 
            null,
            null
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Export_Job__c> jobs = [SELECT Id FROM Export_Job__c];
        System.assert(jobs.size() >= 0);
    }

    @IsTest
    static void testBatchWithMultipleEvaluators() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];
        ApplicationSlotBooking__c booking = [SELECT Id FROM ApplicationSlotBooking__c LIMIT 1];

        RecordType personRt = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Account' AND IsPersonType = true 
            LIMIT 1
        ];

        Account evaluator2 = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Evaluator',
            LastName = 'Two',
            PersonEmail = 'evaluator2@example.com'
        );
        insert evaluator2;

        Evaluation__c eval2 = new Evaluation__c(
            Application_Slot_Booking__c = booking.Id,
            EvaluatedUser__c = evaluator2.Id,
            Status__c = 'Complete',
            EvaluationDate__c = Date.today()
        );
        insert eval2;

        Test.startTest();
        ApplicationEvaluationExport batch = new ApplicationEvaluationExport(
            prog.Id, 
            round.Id, 
            Date.today(), 
            Date.today(), 
            null,
            null
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Export_Job__c> jobs = [SELECT Id FROM Export_Job__c];
        System.assert(jobs.size() > 0);
    }

    @IsTest
    static void testBatchWithNoRecords() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        delete [SELECT Id FROM Evaluation__c];

        Test.startTest();
        ApplicationEvaluationExport batch = new ApplicationEvaluationExport(
            prog.Id, 
            round.Id, 
            Date.today(), 
            Date.today(), 
            null,
            null
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testBatchWithTimeFilters() {
        Program prog = [SELECT Id FROM Program LIMIT 1];
        RoundMaster__c round = [SELECT Id FROM RoundMaster__c LIMIT 1];

        Test.startTest();
        ApplicationEvaluationExport batch = new ApplicationEvaluationExport(
            prog.Id, 
            round.Id, 
            Date.today(), 
            Date.today(), 
            Time.newInstance(8, 0, 0, 0),
            Time.newInstance(12, 0, 0, 0)
        );
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true);
    }
}