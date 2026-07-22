public class LeadProgramMappingHandler {

    public static void syncProgramFields(List<Lead> newLeads) {

        Set<String> programNames = new Set<String>();
        Set<Id> programIds = new Set<Id>();

        //  Collect values
        for (Lead l : newLeads) {

            if (!String.isBlank(l.Program_Picklist__c)) {
                programNames.add(l.Program_Picklist__c.trim());
            }

            if (l.Program_Master__c != null) {
                programIds.add(l.Program_Master__c);
            }
        }

        //  Query Programs
        Map<String, Program> programByName = new Map<String, Program>();
        Map<Id, Program> programById = new Map<Id, Program>();

        if (!programNames.isEmpty() || !programIds.isEmpty()) {
            for (Program p : [
                SELECT Id, Name
                FROM Program
                WHERE Name IN :programNames
                   OR Id IN :programIds
            ]) {
                programByName.put(p.Name, p);
                programById.put(p.Id, p);
            }
        }

        //  Sync Logic
        for (Lead l : newLeads) {

            //  Priority 1: Picklist → Lookup
            if (!String.isBlank(l.Program_Picklist__c)) {

                String programName = l.Program_Picklist__c.trim();

                if (programByName.containsKey(programName)) {
                    l.Program_Master__c = programByName.get(programName).Id;
                }

            }
            //  Reverse: Lookup → Picklist
            else if (l.Program_Master__c != null) {

                Program p = programById.get(l.Program_Master__c);

                if (p != null) {
                    l.Program_Picklist__c = p.Name;
                }
            }
        }
    }
}