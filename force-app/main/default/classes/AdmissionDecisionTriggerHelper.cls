public class AdmissionDecisionTriggerHelper {
    
    public static void updateApplicationStateMgmtonUpdate(List<Admission_Decision__c> newList,  Map<Id,Admission_Decision__c> oldMap){
        if(newList.isEmpty() || oldMap.isEmpty()){
            return;
        }
        Map<Id,String> mapApplicationToStatus = new Map<Id,String>();
        for(Admission_Decision__c adm: newList){
            if(adm.Result__c != oldMap.get(adm.Id).Result__c){
                String result = adm.Result__c;
                switch on result{
                    when 'Eligible for Admission'{
                        mapApplicationToStatus.put(adm.Application__c, 'Offer Issued');
                    }
                    when 'Not Eligible'{
                        mapApplicationToStatus.put(adm.Application__c, 'Disqualified');
                    }
                    when 'Waitlisted'{
                        mapApplicationToStatus.put(adm.Application__c, 'Waitlisted');
                    }
                }
            }
        }
        if(mapApplicationToStatus.isEmpty()){
            return;
        }
        List<Application__c> listApplications = [SELECT Id FROM Application__c WHERE Id IN:mapApplicationToStatus.keySet()];
        List<Application__c> updateApplications = new List<Application__c>();
        if(listApplications.isEmpty()){
            return;
        }
        for(Application__c application:listApplications){
            if(mapApplicationToStatus.containsKey(application.Id)){
                Application__c app = new Application__c(Id = application.Id, Applicant_State_Management__c =mapApplicationToStatus.get(application.Id) );
                updateApplications.add(app);
            }
        }
        if(!updateApplications.isEmpty()){
            try{
                update updateApplications;
            }
            catch(DMLException e){
                system.debug('Could not Update Applications Records from Admission Decision Before Update Trigger '+e.getMessage());
            }
        }
    }
    
    public static void preventAdditionalRecordCreation(List<Admission_Decision__c> listNewAdmissions){
        if(listNewAdmissions.isEmpty()){
            return;
        }
        Map<Id,Id> mapApplicationToAdmission = new Map<Id,Id>();
        Map<Id,Integer> mapAdmissionCount = new Map<Id,Integer>();
        for(Admission_Decision__c admission:listNewAdmissions){
            if(mapApplicationToAdmission.containsKey(admission.Application__c)){
                admission.addError('Admission Decision Record Already present');
                break;
            }
            mapApplicationToAdmission.put(admission.Application__c,admission.Id);
            
            mapAdmissionCount.put(admission.Application__c,0);
        }
        
        List<Admission_Decision__c> listExistingDecisions = [SELECT Id,Application__c FROM Admission_Decision__c WHERE Id IN :mapApplicationToAdmission.values()];
        if(listExistingDecisions.isEmpty()){
            return;
        }
        for(Admission_Decision__c adm:listExistingDecisions){
            if(mapAdmissionCount.containsKey(adm.Application__c)){
                mapAdmissionCount.put(adm.Application__c,mapAdmissionCount.get(adm.Application__c)+1);
            }
        }
        
        for(Admission_Decision__c adm:listNewAdmissions){
            if(mapAdmissionCount.containsKey(adm.Application__c) && mapAdmissionCount.get(adm.Application__c)>1 ){
                adm.addError('Admission Decision Record Already Present');
            }
        }
    }
    
    public static void updateApplicationStateMgmtonInsert(List<Admission_Decision__c> listNewAdmissions){
        Map<String,String> mapAdmissionResultToAppState = new Map<String,String>{'Waitlisted'=>'Waitlisted','Not Eligible'=>'Disqualified','Eligible for Admission'=>'Offer Issued'};
         
        if(listNewAdmissions.isEmpty()){
            return;
        }
      	Map<Id,String> mapApplicationToNewState = new Map<Id,String>();  
        for(Admission_Decision__c admDecision:listNewAdmissions){
            
            mapApplicationToNewState.put(admDecision.Application__c,mapAdmissionResultToAppState.get(admDecision.Result__c));
        }
        List<Application__c> listApplication = [SELECT Id FROM Application__c WHERE Id IN :mapApplicationToNewState.keySet()];
        if(listApplication.isEmpty()){
            return;
        }
       List<Application__c> updateApplicationList = new List<Application__c>();
        for(Application__c app:listApplication){
            if(mapApplicationToNewState.containsKey(app.Id)){
                app.Applicant_State_Management__c = mapApplicationToNewState.get(app.Id);
                updateApplicationList.add(app);
            }
            
        }
        if(updateApplicationList.isEmpty()){
            return;
        }
        try{
            update updateApplicationList;
        }
        catch(DMLException e){
            system.debug('Could not Update Applicant State From Admission Decision '+e.getMessage());
        }
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