public class AdmissionDecisionTriggerHandler {
    public void beforeInsert(List<Admission_Decision__c> newList) {
        clearInapplicableFields(newList);
        AdmissionDecisionTriggerHelper.setApplicantEmail(newList);
    }

    public void beforeUpdate(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap,
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        clearInapplicableFields(newList);
        AdmissionDecisionTriggerHelper.setApplicantEmail(newList);
    }

    public void afterInsert(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap
    ) {
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(newList);
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(newList);

        //SharingOrchestrator.handleRecords('Admission_Decision__c', newMap.keySet());
        AdmissionDecisionTriggerHelper.communicateTheDecision(newList);
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

    private static void clearInapplicableFields(List<Admission_Decision__c> decisions) {
        for (Admission_Decision__c decision : decisions) {
            if (decision.Result__c != 'Waitlisted') {
                decision.WaitlistNumber__c = null;
            }

            if (
                decision.Result__c == 'Waitlisted' ||
                decision.Result__c == 'Not Eligible'
            ) {
                decision.Offer_Letter_Date__c = null;
                decision.LastDateOfAcceptance__c = null;
                decision.SignedLetterOfAcceptanceEta__c = null;
                decision.PaymentOfTheAcceptanceFeeEta__c = null;
                decision.PaymentOfTheFirstInstallmentEta__c = null;
            }
        }
    }
}