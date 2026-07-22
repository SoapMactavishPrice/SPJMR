public class RoundResultTriggerHelper {
    
    public static void updateApplicationScore(List<Round_Result__c> listNewRounds){
        if(listNewRounds.isEmpty()){
            return;
        }
        
        Map<Id,Decimal> mapAppSlotToScore = new Map<Id,Decimal>();
        Set<Id> applicationIds = new Set<Id>();
        Map<Id,Id> mapAppToAppSlot = new Map<Id,Id>();
        for(Round_Result__c roundRes:listNewRounds){
            mapAppSlotToScore.put(roundRes.ApplicationSlotBooking__c,roundRes.Net_Score__c);
        }
        
        List<ApplicationSlotBooking__c> listAppSlots = [SELECT Application__c FROM ApplicationSlotBooking__c 
                                                        WHERE Id IN :mapAppSlotToScore.keySet()];
        
        for(ApplicationSlotBooking__c appSlot: listAppSlots){
            mapAppToAppSlot.put(appSlot.Application__c,appSlot.Id);
            applicationIds.add(appSlot.Application__c);
        }
        List<Application__c> applicationList = [SELECT Id,Evaluation_Score__c FROM Application__c WHERE Id IN :applicationIds];
        List<Application__c> updateApplicationList = new List<Application__c>();
        for(Application__c app:applicationList){
            if( app.Evaluation_Score__c == null){
                app.Evaluation_Score__c= mapAppSlotToScore.get(mapAppToAppSlot.get(app.Id));
                continue;
            }
            app.Evaluation_Score__c+=mapAppSlotToScore.get(mapAppToAppSlot.get(app.Id));
            updateApplicationList.add(app);
        }
        if(updateApplicationList.size()>0){
            try{
                update updateApplicationList;
            }
            catch(DMLException e){
                system.debug('Could not update score on Application '+e.getMessage());
            }
        }
    }

}