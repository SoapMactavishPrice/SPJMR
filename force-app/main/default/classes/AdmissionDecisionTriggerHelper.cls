public class AdmissionDecisionTriggerHelper {
    
    public static void updateApplicationStateMgmtonUpdate(
        List<Admission_Decision__c> newList,
        Map<Id, Admission_Decision__c> oldMap
    ) {
        if (newList.isEmpty() || oldMap.isEmpty()) {
            return;
        }

        List<Admission_Decision__c> decisionsWithChangedResult =
            new List<Admission_Decision__c>();

        for (Admission_Decision__c decision : newList) {
            Admission_Decision__c oldDecision = oldMap.get(decision.Id);
            if (oldDecision != null && decision.Result__c != oldDecision.Result__c) {
                decisionsWithChangedResult.add(decision);
            }
        }

        updateRelatedApplicationStates(decisionsWithChangedResult);
    }
    
    public static void preventAdditionalRecordCreation(List<Admission_Decision__c> listNewAdmissions){
        if(listNewAdmissions.isEmpty()){
            return;
        }

        Set<Id> applicationIds = new Set<Id>();
        Map<Id, Integer> rowsPerApplication = new Map<Id, Integer>();

        for(Admission_Decision__c admission : listNewAdmissions){
            if(admission.Application__c == null){
                continue;
            }
            applicationIds.add(admission.Application__c);
            Integer rowCount = rowsPerApplication.containsKey(admission.Application__c)
                ? rowsPerApplication.get(admission.Application__c)
                : 0;
            rowsPerApplication.put(admission.Application__c, rowCount + 1);
        }

        Map<Id, Integer> persistedCountByApplication = new Map<Id, Integer>();
        for(AggregateResult result : [
            SELECT Application__c applicationId, COUNT(Id) decisionCount
            FROM Admission_Decision__c
            WHERE Application__c IN :applicationIds
            GROUP BY Application__c
        ]){
            persistedCountByApplication.put(
                (Id)result.get('applicationId'),
                (Integer)result.get('decisionCount')
            );
        }

        for(Admission_Decision__c admission : listNewAdmissions){
            if(
                admission.Application__c != null &&
                (
                    rowsPerApplication.get(admission.Application__c) > 1 ||
                    persistedCountByApplication.get(admission.Application__c) > 1
                )
            ){
                admission.addError('Only one Admission Decision record is allowed per Application.');
            }
        }
    }
    
    public static void updateApplicationStateMgmtonInsert(
        List<Admission_Decision__c> listNewAdmissions
    ) {
        updateRelatedApplicationStates(listNewAdmissions);
    }

    private static void updateRelatedApplicationStates(
        List<Admission_Decision__c> decisions
    ) {
        if (decisions == null || decisions.isEmpty()) {
            return;
        }

        Map<Id, String> resultByApplicationId = new Map<Id, String>();
        for (Admission_Decision__c decision : decisions) {
            if (decision.Application__c != null) {
                resultByApplicationId.put(decision.Application__c, decision.Result__c);
            }
        }

        if (resultByApplicationId.isEmpty()) {
            return;
        }

        List<Application__c> applicationsToUpdate = new List<Application__c>();
        for (Application__c application : [
            SELECT Id, Applicant_State_Management__c
            FROM Application__c
            WHERE Id IN :resultByApplicationId.keySet()
        ]) {
            String newState = resolveApplicationState(
                resultByApplicationId.get(application.Id),
                application.Applicant_State_Management__c
            );

            if (
                newState != null &&
                newState != application.Applicant_State_Management__c
            ) {
                applicationsToUpdate.add(new Application__c(
                    Id = application.Id,
                    Applicant_State_Management__c = newState
                ));
            }
        }

        if (!applicationsToUpdate.isEmpty()) {
            update applicationsToUpdate;
        }
    }

    private static String resolveApplicationState(
        String admissionResult,
        String currentApplicationState
    ) {
        if (admissionResult == 'Eligible for Admission') {
            return 'Offer Issued';
        }
        if (admissionResult == 'Waitlisted') {
            return 'Waitlisted';
        }
        if (admissionResult == 'Not Eligible') {
            if (currentApplicationState == 'Interview Round 1') {
                return 'Reject Round 1';
            }
            if (currentApplicationState == 'Interview Round 2') {
                return 'Reject Round 2';
            }
            return 'Disqualified';
        }

        return null;
    }

    public static void setApplicantEmail(List<Admission_Decision__c> newList) {
        Map<Id,List<Admission_Decision__c>> appAdmissionsDescMap = new Map<Id,List<Admission_Decision__c>>();
        for(Admission_Decision__c eachAdmissionsDesc : newList) {
            if(eachAdmissionsDesc?.Application__c == null){
                continue;
            }
            if(appAdmissionsDescMap.containsKey(eachAdmissionsDesc.Application__c)){
                appAdmissionsDescMap.get(eachAdmissionsDesc.Application__c).add(eachAdmissionsDesc);
            } else {
                appAdmissionsDescMap.put(eachAdmissionsDesc.Application__c,new List<Admission_Decision__c> {eachAdmissionsDesc});
            }
        }

        for(Application__c app : [SELECT Id, Applicant__r.PersonEmail FROM Application__c WHERE Id IN :appAdmissionsDescMap.keySet()]) {
            String email = app.Applicant__r?.PersonEmail;
            if (String.isBlank(email)) {
                continue;
            }
            for(Admission_Decision__c eachAdmissionsDesc : appAdmissionsDescMap.get(app.Id)) {
                eachAdmissionsDesc.ApplicantEmail__c = email;
            }
        }
    }

    @InvocableMethod(
        label='Build Admission Decision Email Wrappers'
        description='Builds one email wrapper per Admission Decision from a bulk collection of Admission Decision IDs.'
    )
    public static List<AdmissionDecisionEmailWrapperResponse> buildAdmissionDecisionEmailWrappers(
        List<AdmissionDecisionEmailWrapperRequest> requests
    ) {
        List<AdmissionDecisionEmailWrapperResponse> responses =
            new List<AdmissionDecisionEmailWrapperResponse>();
        if (requests == null || requests.isEmpty()) {
            return responses;
        }

        Set<Id> admissionDecisionIds = new Set<Id>();

        for (AdmissionDecisionEmailWrapperRequest request : requests) {
            if (request == null || request.admissionDecisionIds == null) {
                continue;
            }
            for (String admissionDecisionIdValue : request.admissionDecisionIds) {
                Id admissionDecisionId = toAdmissionDecisionId(
                    admissionDecisionIdValue
                );
                if (admissionDecisionId != null) {
                    admissionDecisionIds.add(admissionDecisionId);
                }
            }
        }

        Map<Id, Admission_Decision__c> decisionsById =
            new Map<Id, Admission_Decision__c>();
        if (!admissionDecisionIds.isEmpty()) {
            decisionsById = new Map<Id, Admission_Decision__c>([
                SELECT Id,
                       ApplicantEmail__c,
                       Application__r.Applicant__r.PersonContactId
                FROM Admission_Decision__c
                WHERE Id IN :admissionDecisionIds
            ]);
        }

        Map<Id, ContentDocumentLink> latestLinkByDecisionId =
            new Map<Id, ContentDocumentLink>();
        if (!admissionDecisionIds.isEmpty()) {
            for (ContentDocumentLink documentLink : [
                SELECT LinkedEntityId,
                       ContentDocumentId,
                       ContentDocument.CreatedDate,
                       ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :admissionDecisionIds
            ]) {
                ContentDocumentLink current = latestLinkByDecisionId.get(
                    documentLink.LinkedEntityId
                );
                if (
                    current == null ||
                    documentLink.ContentDocument.CreatedDate >
                        current.ContentDocument.CreatedDate
                ) {
                    latestLinkByDecisionId.put(
                        documentLink.LinkedEntityId,
                        documentLink
                    );
                }
            }
        }

        for (AdmissionDecisionEmailWrapperRequest request : requests) {
            AdmissionDecisionEmailWrapperResponse response =
                new AdmissionDecisionEmailWrapperResponse();
            response.emailWrappers = new List<AdmissionDecisionEmailFlowWrapper>();

            if (request == null || request.admissionDecisionIds == null) {
                responses.add(response);
                continue;
            }

            for (String admissionDecisionIdValue : request.admissionDecisionIds) {
                Id admissionDecisionId = toAdmissionDecisionId(
                    admissionDecisionIdValue
                );
                if (admissionDecisionId == null) {
                    continue;
                }

                Admission_Decision__c decision = decisionsById.get(
                    admissionDecisionId
                );
                if (decision == null) {
                    continue;
                }

                ContentDocumentLink documentLink = latestLinkByDecisionId.get(
                    decision.Id
                );
                AdmissionDecisionEmailFlowWrapper emailWrapper =
                    new AdmissionDecisionEmailFlowWrapper();
                emailWrapper.admissionDecisionRecordId = decision.Id;
                emailWrapper.admissionDecisionEmailId =
                    decision.ApplicantEmail__c;
                emailWrapper.recipientId =
                    decision.Application__r?.Applicant__r.PersonContactId;

                if (documentLink != null) {
                    emailWrapper.contentDocumentId =
                        documentLink.ContentDocumentId;
                    emailWrapper.attachmentVersionId =
                        documentLink.ContentDocument.LatestPublishedVersionId;
                }

                response.emailWrappers.add(emailWrapper);
            }

            responses.add(response);
        }

        return responses;
    }

    private static Id toAdmissionDecisionId(String admissionDecisionIdValue) {
        if (String.isBlank(admissionDecisionIdValue)) {
            return null;
        }
        try {
            Id admissionDecisionId = (Id) admissionDecisionIdValue.trim();
            return admissionDecisionId.getSObjectType() ==
                Admission_Decision__c.SObjectType
                ? admissionDecisionId
                : null;
        } catch (Exception ignored) {
            return null;
        }
    }

    public class AdmissionDecisionEmailWrapperRequest {
        @InvocableVariable(required=true)
        public List<String> admissionDecisionIds;
    }

    public class AdmissionDecisionEmailWrapperResponse {
        @InvocableVariable
        public List<AdmissionDecisionEmailFlowWrapper> emailWrappers;
    }

    public static void communicateTheDecision(List<Admission_Decision__c> newList, CommunicationsController.CommunicationScenario scenario) {
        if (newList.isEmpty()) {
            return;
        }
 
        Set<Id> applicationIds = new Set<Id>();
 
        for (Admission_Decision__c decision : newList) {
            if (decision.Application__c != null) {
                applicationIds.add(decision.Application__c);
            }
        }
 
        Map<Id, Application__c> applicationMap = new Map<Id, Application__c>([
            SELECT Id, Program__c
            FROM Application__c
            WHERE Id IN :applicationIds
        ]);
 
        Map<Id, CommunicationsController.CommunicationRequest> requestsByProgram = new Map<Id, CommunicationsController.CommunicationRequest>();
 
        for (Admission_Decision__c decision : newList) {
 
            Application__c application = applicationMap.get(decision.Application__c);
 
            if (application == null || application.Program__c == null) {
                continue;
            }
 
            if (!requestsByProgram.containsKey(application.Program__c)) {
 
                CommunicationsController.CommunicationRequest request = new CommunicationsController.CommunicationRequest();
                request.scenario = scenario;
                request.programId = application.Program__c;
                request.applicationIdToReferenceRecordId = new Map<Id, Id>();
 
                requestsByProgram.put(application.Program__c, request);
            }
 
            requestsByProgram.get(application.Program__c)
                .applicationIdToReferenceRecordId
                .put(
                    decision.Application__c,
                    decision.Id
                );
        }
 
        for (CommunicationsController.CommunicationRequest request : requestsByProgram.values()) {
            CommunicationService.communicate(request);
        }
    }

    public static void enforceOfferCheckboxExclusivity(List<Admission_Decision__c> newList, Map<Id, Admission_Decision__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }

        for (Admission_Decision__c decision : newList) {
            Admission_Decision__c oldDecision = oldMap != null ? oldMap.get(decision.Id) : null;

            Boolean offerWithdrawnJustSetTrue = transitionedToTrue(decision.OfferWithdrawn__c, oldDecision?.OfferWithdrawn__c);
            Boolean offerDeclinedJustSetTrue = transitionedToTrue(decision.Offer_Declined__c, oldDecision?.Offer_Declined__c);
            Boolean offerAcceptedJustSetTrue = transitionedToTrue(decision.Offer_Accepted__c, oldDecision?.Offer_Accepted__c);
            Boolean finalOfferAcceptedJustSetTrue = transitionedToTrue(decision.FinalOfferAccepted__c, oldDecision?.FinalOfferAccepted__c);

            if (offerWithdrawnJustSetTrue) {
                decision.Offer_Declined__c = false;
            } else if (offerDeclinedJustSetTrue) {
                decision.Offer_Accepted__c = false;
                decision.FinalOfferAccepted__c = false;
                decision.OfferWithdrawn__c = false;
            } else if (offerAcceptedJustSetTrue || finalOfferAcceptedJustSetTrue) {
                decision.OfferWithdrawn__c = false;
                decision.Offer_Declined__c = false;
            }
        }
    }

    private static Boolean transitionedToTrue(Boolean newValue, Boolean oldValue) {
        return newValue == true && oldValue != true;
    }

}