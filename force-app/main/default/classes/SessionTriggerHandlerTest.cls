@IsTest
private class SessionTriggerHandlerTest {
    @IsTest
    static void emptyMapsEarlyReturn() {
        SessionTriggerHandler.handleScheduleTypePublished(
            new Map<Id, Session__c>(), new Map<Id, Session__c>()
        );
    }
    @IsTest
    static void noStatusChangeNoActions() {
        Id fake = Schema.SObjectType.Session__c.getKeyPrefix() + '000000000001';
        Session__c older = (Session__c) JSON.deserialize(
            '{"attributes":{"type":"Session__c"},"Id":"' + fake + '","Schedule_Type__c":"Draft"}',
            Session__c.class
        );
        Session__c newer = (Session__c) JSON.deserialize(
            '{"attributes":{"type":"Session__c"},"Id":"' + fake + '","Schedule_Type__c":"Draft"}',
            Session__c.class
        );
        SessionTriggerHandler.handleScheduleTypePublished(
            new Map<Id, Session__c>{ fake => newer },
            new Map<Id, Session__c>{ fake => older }
        );
    }
}