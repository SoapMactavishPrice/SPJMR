@IsTest
private class ApplicationTriggerHandlerTest {

    private static Application__c createApplication() {
        Application__c app = new Application__c(
            Name = 'Test Application'
        );
        insert app;
        return app;
    }

    private static Opportunity createOpportunity(Id applicationId) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Application__c = applicationId
        );
        insert opp;
        return opp;
    }

    @IsTest
    static void testInitiatedStatusUpdatesOpportunity() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Status__c = 'Initiated';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName, Stage_Initiated_Date__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Initiated', updatedOpp.StageName);
        System.assertNotEquals(null, updatedOpp.Stage_Initiated_Date__c);
    }

    @IsTest
    static void testPaidStatusUpdatesOpportunity() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Status__c = 'Paid';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Paid', updatedOpp.StageName);
    }

    @IsTest
    static void testApplicationStageMapping() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'Academic Details';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Academic Details', updatedOpp.StageName);
    }

    @IsTest
    static void testApiValueMapping() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'Program_Detail__c';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Programme Details', updatedOpp.StageName);
    }

    @IsTest
    static void testCaseInsensitiveMapping() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'program details';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Programme Details', updatedOpp.StageName);
    }

    @IsTest
    static void testNoRelevantChange() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Prospecting', updatedOpp.StageName);
    }

    @IsTest
    static void testUnknownApplicationStageDoesNothing() {

        Application__c app = createApplication();
        Opportunity opp = createOpportunity(app.Id);

        Application__c oldApp = app.clone(false, true, false, false);

        app.Application_Stage__c = 'Unknown Stage';

        Test.startTest();
        ApplicationTriggerHandler.handleAfterUpdate(
            new List<Application__c>{app},
            new Map<Id, Application__c>{app.Id => oldApp}
        );
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals('Prospecting', updatedOpp.StageName);
    }
}