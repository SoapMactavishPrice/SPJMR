public class EvaluationTriggerHelper {
    
    public static void updateApplicationStatus(List<Evaluation__c> listNewEval){
        if(!listNewEval.isEmpty()){
            Map<Id,Id> mapEvalToAppSlot = new Map<Id,Id>();
            Map<Id,Integer> mapEvalIdToCount = new Map<Id,Integer>();
            Map<Id,Id> mapAppSlotToProgramTeam = new Map<Id,Id>();
            Map<Id,Id> mapProgramTeamMemberToTeam = new Map<Id,Id>();
            Map<Id,Integer> mapPTeamCount = new Map<Id,Integer>();
            for(Evaluation__c eval:listNewEval){
                mapEvalToAppSlot.put(eval.Application_Slot_Booking__c,eval.Id);
                mapEvalIdToCount.put(eval.Application_Slot_Booking__c,0);
            }
            
            List<Evaluation__c> listOldEval = [SELECT Id,Application_Slot_Booking__c FROM Evaluation__c WHERE Application_Slot_Booking__c IN :mapEvalToAppSlot.keySet()];
            for(Evaluation__c eval:listOldEval){
                if(mapEvalToAppSlot.containsKey(eval.Application_Slot_Booking__c)){
                    mapEvalIdToCount.put(eval.Application_Slot_Booking__c,mapEvalIdToCount.get(eval.Application_Slot_Booking__c)+1);
                }
            }
            List<ApplicationSlotBooking__c> listAppSlotBookings = [SELECT Id,Application__c,Panel_Master__r.ProgramTeam__c FROM ApplicationSlotBooking__c WHERE Id IN :mapEvalToAppSlot.values()];
            if(listAppSlotBookings.size()>0){
                for(ApplicationSlotBooking__c appSlot:listAppSlotBookings){
                mapAppSlotToProgramTeam.put(appSlot?.Panel_Master__r?.ProgramTeam__c,appSlot.Id);
              
            	}
                if(mapAppSlotToProgramTeam.size()>0){
                 List<Program_Team_Members__c> listProgramTeamMembers =   [SELECT Id,Program_Team__c FROM Program_Team_Members__c WHERE Program_Team__c IN :mapAppSlotToProgramTeam.keySet()];
                    if(listProgramTeamMembers.size()>0){
                        for(Program_Team_Members__c pteam:listProgramTeamMembers){
                            mapProgramTeamMemberToTeam.put(pteam.Id,pteam.Program_Team__c);
                            if(!mapPTeamCount.containsKey(pteam.Program_Team__c)){
                                mapPTeamCount.put(pteam.Program_Team__c,0);
                            }
                            else{
                                mapPTeamCount.put(pteam.Program_Team__c,mapPTeamCount.get(pteam.Program_Team__c)+1);
                            }
                        }
                        
                        for(Evaluation__c eval:listOldEval){
                           
                        }
                        
                     
                    }
                }
            }
            
            
        }
    }

    public static void updateEvaluationDateBasedOnStatus(List<Evaluation__c> newList, Map<Id, Evaluation__c> oldMap) {
        for (Evaluation__c newEval : newList) {
            Evaluation__c oldEval = oldMap.get(newEval.Id);
            if (newEval.Status__c == 'Complete' && (oldEval == null || oldEval.Status__c != 'Complete')) {
                newEval.EvaluationDate__c = Date.today();
            }
        }
    }

}