@IsTest
private class EvaluationTriggerHelperTest {
    
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
            FirstName = 'Eval',
            LastName = 'Helper',
            PersonEmail = 'eval.helper@example.com'
        );
        insert applicant;

        Application__c app = new Application__c(
            Name = 'EVAL-APP-001',
            Applicant__c = applicant.Id
        );
        insert app;

        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c = app.Id
        );
        insert booking;

        Account evaluator = new Account(
            RecordTypeId = personRt.Id,
            FirstName = 'Eval',
            LastName = 'User',
            PersonEmail = 'eval.user@example.com'
        );
        insert evaluator;

        Evaluation__c eval = new Evaluation__c(
            Application_Slot_Booking__c = booking.Id,
            EvaluatedUser__c = evaluator.Id,
            Status__c = 'Pending'
        );
        insert eval;
    }

    @IsTest
    static void testUpdateEvaluationDateBasedOnStatusComplete() {
        Evaluation__c eval = [SELECT Id, Status__c, EvaluationDate__c FROM Evaluation__c LIMIT 1];
        
        Evaluation__c oldEval = eval.clone(true, true, false, false);
        oldEval.Status__c = 'Pending';
        
        eval.Status__c = 'Complete';

        Map<Id, Evaluation__c> oldMap = new Map<Id, Evaluation__c>{ eval.Id => oldEval };

        Test.startTest();
        EvaluationTriggerHelper.updateEvaluationDateBasedOnStatus(
            new List<Evaluation__c>{ eval },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(Date.today(), eval.EvaluationDate__c);
    }

    @IsTest
    static void testUpdateEvaluationDateBasedOnStatusNoChange() {
        Evaluation__c eval = [SELECT Id, Status__c, EvaluationDate__c FROM Evaluation__c LIMIT 1];
        eval.Status__c = 'Pending';
        update eval;
        
        eval = [SELECT Id, Status__c, EvaluationDate__c FROM Evaluation__c WHERE Id = :eval.Id];
        
        Evaluation__c oldEval = eval.clone(true, true, false, false);
        oldEval.Status__c = 'Pending';

        Map<Id, Evaluation__c> oldMap = new Map<Id, Evaluation__c>{ eval.Id => oldEval };

        Test.startTest();
        EvaluationTriggerHelper.updateEvaluationDateBasedOnStatus(
            new List<Evaluation__c>{ eval },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(null, eval.EvaluationDate__c);
    }

    @IsTest
    static void testUpdateEvaluationDateBasedOnStatusAlreadyComplete() {
        Evaluation__c eval = [SELECT Id, Status__c FROM Evaluation__c LIMIT 1];
        eval.Status__c = 'Complete';
        eval.EvaluationDate__c = Date.today().addDays(-1);
        update eval;
        
        eval = [SELECT Id, Status__c, EvaluationDate__c FROM Evaluation__c WHERE Id = :eval.Id];
        
        Evaluation__c oldEval = eval.clone(true, true, false, false);
        oldEval.Status__c = 'Complete';
        oldEval.EvaluationDate__c = Date.today().addDays(-1);
        
        eval.EvaluationDate__c = Date.today().addDays(-1);

        Map<Id, Evaluation__c> oldMap = new Map<Id, Evaluation__c>{ eval.Id => oldEval };

        Test.startTest();
        EvaluationTriggerHelper.updateEvaluationDateBasedOnStatus(
            new List<Evaluation__c>{ eval },
            oldMap
        );
        Test.stopTest();

        System.assertEquals(Date.today().addDays(-1), eval.EvaluationDate__c);
    }

}