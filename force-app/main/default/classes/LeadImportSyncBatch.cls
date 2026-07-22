/**
 * Batch class to process Lead_Import__c records in chunks.
 * Each execute() gets its own governor limits, avoiding SOQL limit errors.
 * 
 * Usage (Anonymous Apex):
 *   Database.executeBatch(new LeadImportSyncBatch(), 1);
 */
public class LeadImportSyncBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Lead_Import__c
            WHERE Status__c = 'Pending'
            ORDER BY CreatedDate ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lead_Import__c> scope) {
        // Each execute() call gets fresh governor limits (100 SOQL queries).
        // processPendingImports() picks up the next batch of pending records.
        LeadImportSyncService.SyncBatchResult r = LeadImportSyncService.processPendingImports();
        System.debug('Batch chunk — Processed: ' + r.totalProcessed + ' | Synced: ' + r.synced + ' | Failed: ' + r.failed);
    }

    public void finish(Database.BatchableContext bc) {
        Integer remaining = [SELECT COUNT() FROM Lead_Import__c WHERE Status__c = 'Pending'];
        System.debug('LeadImportSyncBatch finished. Remaining pending: ' + remaining);
    }
}