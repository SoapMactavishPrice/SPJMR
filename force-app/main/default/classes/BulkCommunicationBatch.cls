public with sharing class BulkCommunicationBatch
    implements Database.Batchable<SObject> {

    private CommunicationsController.CommunicationRequest requestTemplate;

    public BulkCommunicationBatch(
        CommunicationsController.CommunicationRequest requestTemplate
    ) {
        this.requestTemplate = requestTemplate;
    }

    public Database.QueryLocator start(
        Database.BatchableContext batchContext
    ) {
        Set<Id> applicationIds = new Set<Id>();

        if (requestTemplate != null && requestTemplate.applicationIds != null) {
            applicationIds.addAll(requestTemplate.applicationIds);
        }

        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Application__c
                WHERE Id IN :applicationIds
            ]
        );
    }

    public void execute(
        Database.BatchableContext batchContext,
        List<SObject> scope
    ) {
        List<Id> scopeApplicationIds = new List<Id>();

        for (SObject scopeRecord : scope) {
            scopeApplicationIds.add((Id) scopeRecord.get('Id'));
        }

        CommunicationService.processAsyncScope(
            requestTemplate,
            scopeApplicationIds
        );
    }

    public void finish(Database.BatchableContext batchContext) {
    }
}