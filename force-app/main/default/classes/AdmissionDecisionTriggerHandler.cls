public class AdmissionDecisionTriggerHandler {
    public void beforeInsert(List<Admission_Decision__c> newList) {
        AdmissionDecisionTriggerHelper.setApplicantEmail(newList);
    }

    public void beforeUpdate(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap,
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        AdmissionDecisionTriggerHelper.setApplicantEmail(newList);
    }

    public void afterInsert(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap
    ) {
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(newList);
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(newList);

        if (!AdmissionDecisionImportBatch.isCsvImportInProgress()) {
            SharingOrchestrator.handleRecords('Admission_Decision__c', newMap.keySet());
            AdmissionDecisionTriggerHelper.communicateTheDecision(newList);
        }
    }

    public void afterUpdate(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap,
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonUpdate(newList, oldMap);
    }

    public void beforeDelete(
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {}

    public void afterDelete(
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {}

    public void afterUndelete(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap
    ) {}
}