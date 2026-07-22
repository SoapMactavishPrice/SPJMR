public with sharing class LeadImportCleanupBatch implements Database.Batchable<SObject>, Database.Stateful {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Lead_Import__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lead_Import__c> scope) {
        if (!scope.isEmpty()) {
            Database.delete(scope, false); // partial success allowed
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Lead_Import__c cleanup completed');
    }
}