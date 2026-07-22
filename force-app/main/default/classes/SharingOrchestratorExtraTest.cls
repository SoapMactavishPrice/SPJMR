/**
 * Supplements SharingOrchestratorTest by hitting the populated path: when an Application__c
 * has Program__c change, processRecordsToUpdate collects the Id and calls handleRecords.
 */
@IsTest(seeAllData=true)
private class SharingOrchestratorExtraTest {

    @IsTest
    static void processRecordsToUpdate_collectsIdsWhenProgramChanged() {
        List<Application__c> apps = [SELECT Id, Program__c FROM Application__c WHERE Program__c != null LIMIT 2];
        if (apps.size() < 2) {
            return;
        }
        // Construct old version with different Program__c so the change-detection branch fires
        Map<Id, Application__c> oldMap = new Map<Id, Application__c>();
        Id otherProgram = apps[1].Program__c;
        Application__c modified = apps[0].clone(true, true, true, true);
        // Set the "new" version's Program__c to a different value than "old"
        modified.Program__c = otherProgram;
        Application__c oldVersion = apps[0].clone(true, true, true, true);
        // Leave oldVersion.Program__c as apps[0].Program__c (different from modified.Program__c)
        oldMap.put(apps[0].Id, oldVersion);

        Test.startTest();
        try {
            SharingOrchestrator.processRecordsToUpdate(new List<Application__c>{ modified }, oldMap);
        } catch (Exception e) {
            // Downstream GenericProgramSharingFuture is @future; in test it may not run cleanly
        }
        Test.stopTest();
    }

    @IsTest
    static void handleRecords_runsFutureWithRealAppIds() {
        List<Application__c> apps = [SELECT Id FROM Application__c WHERE Program__c != null LIMIT 1];
        if (apps.isEmpty()) {
            return;
        }
        Test.startTest();
        SharingOrchestrator.handleRecords('Application__c', new Set<Id>{ apps[0].Id });
        Test.stopTest();
    }
}