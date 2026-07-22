public class RoundMasterTriggerHelper {
    
    private static Boolean containsNumber(String value) {
        return Pattern.compile('.*\\d.*')
            .matcher(value)
            .matches();
    }
    
    
    //Validates if name has any Numerics and throws error, checks if only round number exists for a program
    public static void checkForSameSequence(List<RoundMaster__c> listNewRounds){
        if(!listNewRounds.isEmpty()){
            Map<String,RoundMaster__c> map_SequnceToRound = new Map<String,RoundMaster__c>();
            Set<Id> programId_set = new Set<Id>();
            for(RoundMaster__c round:listNewRounds){
                if(round.Name != null && containsNumber(round.Name)){
                    round.addError('Round Name cannot have numerical values');
                }
                programId_set.add(round.Program__c);
                map_SequnceToRound.put(round.Program__c+String.valueOf(round.RoundNumber__c),round);
            }
            Set<Id> newRoundIds = new Set<Id>();
            for (RoundMaster__c r : listNewRounds) {
                if (r.Id != null) {
                    newRoundIds.add(r.Id);
                }
            }
            List<RoundMaster__c> existingRounds = [SELECT Id,RoundNumber__c,Program__c FROM RoundMaster__c WHERE Program__c IN:programId_set AND Id NOT IN :newRoundIds];
            Set<Decimal> sequenceSet = new Set<Decimal>();
            for(RoundMaster__c existingRound :existingRounds){
                if(map_SequnceToRound.containsKey(existingRound.Program__c + String.valueOf(existingRound.RoundNumber__c))){
                    map_SequnceToRound.get(existingRound.Program__c+String.valueOf(existingRound.RoundNumber__c)).addError('This round already exists for this Programme');
                }
                
            }
        }
    }
}