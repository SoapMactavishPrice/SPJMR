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

    public static void communicateTheDecision(List<Admission_Decision__c> newList) {
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
                request.scenario = CommunicationsController.CommunicationScenario.OFFER_AVAILABLE;
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

}