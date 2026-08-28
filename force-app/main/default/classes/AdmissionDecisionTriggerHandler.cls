public class AdmissionDecisionTriggerHandler {
    public void beforeInsert(List<Admission_Decision__c> newList) {
        clearInapplicableFieldsOnInsert(newList);
        AdmissionDecisionTriggerHelper.setApplicantEmail(newList);
    }

    public void beforeUpdate(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap,
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        clearFieldsForResultTransitions(newList, oldMap);
        AdmissionDecisionTriggerHelper.setApplicantEmail(newList);
        AdmissionDecisionTriggerHelper.enforceOfferCheckboxExclusivity(newList, oldMap);
    }

    public void afterInsert(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap
    ) {
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonInsert(newList);
        AdmissionDecisionTriggerHelper.preventAdditionalRecordCreation(newList);

        //SharingOrchestrator.handleRecords('Admission_Decision__c', newMap.keySet());
        enqueueOfferLetterGeneration(newList, null);
    }

    public void afterUpdate(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> newMap,
        List<Admission_Decision__c> oldList,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        AdmissionDecisionTriggerHelper.updateApplicationStateMgmtonUpdate(newList, oldMap);
        enqueueOfferLetterGeneration(newList, oldMap);
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

    private static void clearInapplicableFieldsOnInsert(
        List<Admission_Decision__c> decisions
    ) {
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
                decision.BalanceFeePaymentETA__c = null;
            }
        }
    }

    private static void clearFieldsForResultTransitions(
        List<Admission_Decision__c> decisions,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        for (Admission_Decision__c decision : decisions) {
            Admission_Decision__c oldDecision = oldMap.get(decision.Id);
            if (
                oldDecision == null ||
                decision.Result__c == oldDecision.Result__c
            ) {
                continue;
            }

            if (
                oldDecision.Result__c == 'Eligible for Admission' &&
                decision.Result__c != 'Eligible for Admission'
            ) {
                decision.Offer_Letter_Date__c = null;
                decision.LastDateOfAcceptance__c = null;
                decision.SignedLetterOfAcceptanceEta__c = null;
                decision.PaymentOfTheAcceptanceFeeEta__c = null;
                decision.PaymentOfTheFirstInstallmentEta__c = null;
                decision.BalanceFeePaymentETA__c = null;
            }

            if (oldDecision.Result__c == 'Waitlisted') {
                decision.WaitlistNumber__c = null;
            }
        }
    }

    private static void enqueueOfferLetterGeneration(
        List<Admission_Decision__c> decisions,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        List<Id> eligibleDecisionIds = new List<Id>();
        List<Admission_Decision__c> decisionsToCommunicate =
            new List<Admission_Decision__c>();

        for (Admission_Decision__c decision : decisions) {
            Admission_Decision__c oldDecision = oldMap == null
                ? null
                : oldMap.get(decision.Id);
            Boolean resultChanged = oldDecision == null ||
                decision.Result__c != oldDecision.Result__c;
            Boolean offerDataChanged = oldDecision == null ||
                resultChanged ||
                decision.Offer_Letter_Date__c != oldDecision.Offer_Letter_Date__c ||
                decision.LastDateOfAcceptance__c != oldDecision.LastDateOfAcceptance__c ||
                decision.SignedLetterOfAcceptanceEta__c != oldDecision.SignedLetterOfAcceptanceEta__c ||
                decision.PaymentOfTheAcceptanceFeeEta__c != oldDecision.PaymentOfTheAcceptanceFeeEta__c ||
                decision.PaymentOfTheFirstInstallmentEta__c != oldDecision.PaymentOfTheFirstInstallmentEta__c ||
                decision.BalanceFeePaymentETA__c != oldDecision.BalanceFeePaymentETA__c;
            Boolean becameEligible =
                decision.Result__c == 'Eligible for Admission' && offerDataChanged;

            if (becameEligible && decision.Id != null) {
                eligibleDecisionIds.add(decision.Id);
            }

            if (
                resultChanged &&
                decision.Id != null &&
                decision.Application__c != null &&
                (
                    decision.Result__c == 'Waitlisted' ||
                    decision.Result__c == 'Not Eligible'
                )
            ) {
                decisionsToCommunicate.add(decision);
            }
        }

        if (!eligibleDecisionIds.isEmpty()) {
            OfferLetterGenerationDispatcher.requestGeneration(
                eligibleDecisionIds
            );
        }

        communicateDecisionOutcomes(decisionsToCommunicate);
    }

    private static void communicateDecisionOutcomes(
        List<Admission_Decision__c> decisions
    ) {
        if (decisions.isEmpty()) {
            return;
        }

        Set<Id> applicationIds = new Set<Id>();
        for (Admission_Decision__c decision : decisions) {
            applicationIds.add(decision.Application__c);
        }

        Map<Id, Application__c> applicationsById =
            new Map<Id, Application__c>([
                SELECT Id, Program__c
                FROM Application__c
                WHERE Id IN :applicationIds
            ]);

        Map<CommunicationsController.CommunicationScenario,
            Map<Id, CommunicationsController.CommunicationRequest>>
            requestsByScenarioAndProgram =
                new Map<CommunicationsController.CommunicationScenario,
                    Map<Id, CommunicationsController.CommunicationRequest>>();

        for (Admission_Decision__c decision : decisions) {
            Application__c application = applicationsById.get(
                decision.Application__c
            );
            if (application == null || application.Program__c == null) {
                continue;
            }

            CommunicationsController.CommunicationScenario scenario =
                decision.Result__c == 'Waitlisted'
                    ? CommunicationsController.CommunicationScenario.OFFER_WAITLISTED
                    : CommunicationsController.CommunicationScenario.OFFER_NOT_ELIGIBLE;

            if (!requestsByScenarioAndProgram.containsKey(scenario)) {
                requestsByScenarioAndProgram.put(
                    scenario,
                    new Map<Id, CommunicationsController.CommunicationRequest>()
                );
            }

            Map<Id, CommunicationsController.CommunicationRequest>
                requestsByProgram = requestsByScenarioAndProgram.get(scenario);

            if (!requestsByProgram.containsKey(application.Program__c)) {
                CommunicationsController.CommunicationRequest request =
                    new CommunicationsController.CommunicationRequest();
                request.scenario = scenario;
                request.programId = application.Program__c;
                request.applicationIdToReferenceRecordId = new Map<Id, Id>();
                requestsByProgram.put(application.Program__c, request);
            }

            requestsByProgram.get(application.Program__c)
                .applicationIdToReferenceRecordId.put(
                    decision.Application__c,
                    decision.Id
                );
        }

        for (
            Map<Id, CommunicationsController.CommunicationRequest>
                requestsByProgram : requestsByScenarioAndProgram.values()
        ) {
            for (
                CommunicationsController.CommunicationRequest request :
                    requestsByProgram.values()
            ) {
                System.debug('Count');
                CommunicationService.communicateInline(request);
            }
        }
    }
}