public with sharing class ProgramEnrollmentTriggerHandler {
    
    public  void beforeInsert(List<ProgramEnrollment> newList, Map<Id, ProgramEnrollment> newMap) {

        Set<Id> programIds = new Set<Id>();
        Set<Id> batchIds = new Set<Id>();
    
        for (ProgramEnrollment pe : newList) {
            if (pe.ProgramId != null) programIds.add(pe.ProgramId);
            if (pe.Batch__c != null) batchIds.add(pe.Batch__c);
        }
    
        if (programIds.isEmpty() || batchIds.isEmpty()) {
            return; // Nothing to process
        }
    
       
        Map<Id, Program> programMap = new Map<Id, Program>(
            [SELECT Id, Short_Programme_Code__c FROM Program WHERE Id IN :programIds]
        );
    
        Map<Id, ProgramCohort> batchMap = new Map<Id, ProgramCohort>(
            [SELECT Id, Batch_Code__c FROM ProgramCohort WHERE Id IN :batchIds]
        );
    
       
        List<ProgramEnrollment> existingList = [
            SELECT ProgramId, Batch__c, Serial_Number__c FROM ProgramEnrollment
            WHERE ProgramId IN :programIds AND Batch__c IN :batchIds ORDER BY Serial_Number__c DESC];
    
       system.debug(existingList);
        Map<String, Integer> maxSerialMap = new Map<String, Integer>();
    
        for (ProgramEnrollment e : existingList) {
            String key = e.ProgramId + '-' + e.Batch__c;
    
            // Store only the first (highest) serial due to DESC order
            if (!maxSerialMap.containsKey(key) && e.Serial_Number__c != null) {
                maxSerialMap.put(key, Integer.valueOf(e.Serial_Number__c));
            }else if(e.Serial_Number__c == null){
                maxSerialMap.put(key, 0);
            }
        }
    
        system.debug(maxSerialMap);
        for (ProgramEnrollment pe : newList) {
            if (pe.ProgramId == null || pe.Batch__c == null) continue;
    
            String key = pe.ProgramId + '-' + pe.Batch__c;
    
            // Next serial number
            Integer nextSerial = maxSerialMap.containsKey(key) ? maxSerialMap.get(key) + 1 : 1;

            // Convert to Decimal so format() doesn't fail
            String serialStr = String.valueOf(nextSerial);
            if (serialStr.length() == 1) serialStr = '00' + serialStr;
            else if (serialStr.length() == 2) serialStr = '0' + serialStr;

            pe.Serial_Number__c = nextSerial; 

            System.debug('RollNo -> ' + pe.Roll_Number__c);


            // pe.Serial_Number__c = nextSerial;
    
            // Fetch codes
            String programCode = programMap.get(pe.ProgramId).Short_Programme_Code__c;
            String batchCode   = batchMap.get(pe.Batch__c).Batch_Code__c;
    
            // Generate Roll Number
            pe.Roll_Number__c = programCode +'-' + batchCode+'-' + serialStr;
            system.debug('RollNo-> '+pe.Roll_Number__c);
            
            // Update map so next new record increments correctly
            maxSerialMap.put(key, nextSerial);
        }
    }
    
}