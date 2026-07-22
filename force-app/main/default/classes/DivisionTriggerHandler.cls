public class DivisionTriggerHandler {
    
    public static void validateSpecialisationType(List<Division__c> newDivisions) {
        
        Set<Id> specialisationIds = new Set<Id>();
        Set<Id> divisionGroupIds  = new Set<Id>();
        
        for (Division__c div : newDivisions) {
            if (div.SPJIMR_Specialisation__c != null) {
                specialisationIds.add(div.SPJIMR_Specialisation__c);
            }
            if (div.Division_Group__c != null) {
                divisionGroupIds.add(div.Division_Group__c);
            }
        }
        
        if (specialisationIds.isEmpty() || divisionGroupIds.isEmpty()) return;
        
        // Query Specialisation Name (lookup to Specialisation Master)
        Map<Id, Specialisation__c> specialisationMap = new Map<Id, Specialisation__c>([
            SELECT Id, Specialisation_Name__c, Specialisation_Name__r.Name
            FROM Specialisation__c
            WHERE Id IN :specialisationIds
        ]);
        
        // Query Division Group Name
        Map<Id, Division_Group__c> divisionGroupMap = new Map<Id, Division_Group__c>([
            SELECT Id, Name
            FROM Division_Group__c
            WHERE Id IN :divisionGroupIds
        ]);
        
        for (Division__c div : newDivisions) {
            
            if (div.SPJIMR_Specialisation__c == null || div.Division_Group__c == null) continue;
            
            Specialisation__c spec = specialisationMap.get(div.SPJIMR_Specialisation__c);
            Division_Group__c dg   = divisionGroupMap.get(div.Division_Group__c);
            
            if (spec == null || dg == null) continue;
            
            String dgName   = (dg.Name != null) ? dg.Name.toLowerCase() : '';
            String specName = (spec.Specialisation_Name__r != null && spec.Specialisation_Name__r.Name != null)
                ? spec.Specialisation_Name__r.Name.toLowerCase() : '';
            
            Boolean dgIsMajor   = dgName.contains('major');
            Boolean dgIsMinor   = dgName.contains('minor');
            Boolean specIsMajor = specName.contains('major');
            Boolean specIsMinor = specName.contains('minor');
            
            // Major Division Group → only Major Specialisation allowed
            if (dgIsMajor && specIsMinor) {
                div.addError(
                    'Mismatch: A Major Specialisation Division Group cannot be assigned a Minor Specialisation. ' +
                    'Only Major Specialisation courses are allowed.'
                );
            }
            
            // Minor Division Group → only Minor Specialisation allowed
            if (dgIsMinor && specIsMajor) {
                div.addError(
                    'Mismatch: A Minor Specialisation Division Group cannot be assigned a Major Specialisation. ' +
                    'Only Minor Specialisation courses are allowed.'
                );
            }
        }
    }
  }