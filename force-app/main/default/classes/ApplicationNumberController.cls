public without sharing class ApplicationNumberController {
    public static final Set<String> hierarchyProgramCodes = new Set<String>{'PGDM','PGDM-BM','PGDM&PGDM-BM'};
    public static final Set<String> paidStatuses = new Set<String>{'Paid','Paid For PGDM','Paid For PGDM-BM'};
    
        public static void updateNonPaidOpportunities(List<ProgramCohort> newList, Map<Id,ProgramCohort> oldMap){
            Set<Id> applicationClosedBatchesId = new Set<Id>();
            List<Opportunity> updateOpportunityList = new List<Opportunity>();
            for(ProgramCohort p: newList){
                if(!p.IsAcceptingApplications__c && 
                   oldMap.get(p.Id).IsAcceptingApplications__c
                  ){
                       applicationClosedBatchesId.add(p.Id);
                   }
            }
            Set<Id> applicationIds = new Set<Id>();
            for(ProgramCohort p: [SELECT Id, 
                                  (SELECT Id FROM Applications__r)
                                  FROM ProgramCohort WHERE Id IN:applicationClosedBatchesId]){
                                      for(Application__c app: p.Applications__r){
                                          applicationIds.add(app.Id);
                                          
                                      }
                                  } 
            
            
            for(Opportunity opp: [SELECT Id,StageName FROM Opportunity 
                                  WHERE Application__c IN :applicationIds]){
                                              if(opp.StageName != 'Paid'){
                                                  updateOpportunityList.add(
                                                  	new Opportunity(Id=opp.Id,StageName='Closed Lost')
                                                  );
                                              }
                                          }
            
            if(!updateOpportunityList.isEmpty()){
                try{
                    update updateOpportunityList;
                }
                catch(DMLException e){
                    system.debug('Could not Update Opportunities: '+e.getMessage());
                }
            }
        }
        
        private static String generateApplicationName(
            String applicationNumber,
            String batchCode
        ) {
            if (
                String.isBlank(applicationNumber) ||
                String.isBlank(batchCode) ||
                applicationNumber.contains('-')
            ) {
                return null;
            }
        
            return applicationNumber + '-' + batchCode;
        }
        
    public static void updateApplicationNames(List<Application__c> newList, Map<Id, Application__c> oldMap){
        Map<Id,Application__c> paidApplicationMap = new Map<Id,Application__c>();
        Set<Id> batchIds = new Set<Id>();
        Map<Id,ProgramCohort> batchMap = new Map<Id,ProgramCohort>();
        Set<Id> programIds = new Set<Id>();
        Map<Id,Program> programMap = new Map<Id,Program>();
        List<Application__c> updateApplications = new List<Application__c>();
        for(Application__c app:newList){
            if(paidStatuses.contains(app.Application_Status__c) && 
               app.Application_Status__c!=oldMap.get(app.Id).Application_Status__c){
                   paidApplicationMap.put(app.Id,app);
                   batchIds.add(app.Batch__c);
                   programIds.add(app.Program__c);
               }
        }
        if(paidApplicationMap.values().isEmpty()){
            return;
        }
        for(ProgramCohort b:[SELECT Id,Application_Code__c,Short_Batch_Code__c 
                             FROM ProgramCohort WHERE Id IN:batchIds]){
            batchMap.put(b.Id,b);
        }
        for(Program p:[SELECT Id,Program_Code__c
                             FROM Program WHERE Id IN:programIds]){
            programMap.put(p.Id,p);
        }
        
        for(Application__c app:paidApplicationMap.values()){
            
            if(batchMap.containsKey(app.Batch__c)){
                Program p = programMap.get(app.Program__c);
                Boolean isHierarchyProgram = hierarchyProgramCodes.contains(p.Program_Code__c);
                String appNumber = isHierarchyProgram? generateApplicationName(app.Name,batchMap.get(app.Batch__c).Application_Code__c)
                    :generateApplicationName(app.Name,batchMap.get(app.Batch__c).Short_Batch_Code__c);
                if(appNumber==null) continue;
                Application__c updateApp = new Application__c(Id=app.Id,Name=appNumber);
                updateApplications.add(updateApp);
            }
        }
        
        if(!updateApplications.isEmpty()){
            try{
                update updateApplications;
            }
            catch(DMLException e){
                system.debug('Error Updating/Appending batch code to Application Number: '+ e.getMessage());
            }
        }
    }
    
    
}