public class ProgramTriggerHandler {
    
    public static void preventDuplicateShortProgrammeCode(List<Program> newRecords, Map<Id, Program> oldMap) {
        
        // Collect Short Programme Codes & Programme Codes from incoming records
        Set<String> incomingShortCodes = new Set<String>();
        Set<String> incomingProgrammeCodes = new Set<String>();
        
        for (Program prog : newRecords) {
            if (String.isNotBlank(prog.Short_Programme_Code__c)) {
                incomingShortCodes.add(prog.Short_Programme_Code__c.trim().toLowerCase());
            }
            if (String.isNotBlank(prog.Program_Code__c)) {
                incomingProgrammeCodes.add(prog.Program_Code__c.trim().toLowerCase());
            }
        }
        
        // Exclude current records on update
        Set<Id> currentIds = (oldMap != null) ? oldMap.keySet() : new Set<Id>();
        
        // ── Query for Short Programme Code duplicates ──
        Set<String> usedShortCodes = new Set<String>();
        if (!incomingShortCodes.isEmpty()) {
            List<Program> existingShortCodes = [
                SELECT Id, Short_Programme_Code__c 
                FROM Program
                WHERE Short_Programme_Code__c IN :incomingShortCodes
                AND Id NOT IN :currentIds
            ];
            for (Program existing : existingShortCodes) {
                if (String.isNotBlank(existing.Short_Programme_Code__c)) {
                    usedShortCodes.add(existing.Short_Programme_Code__c.trim().toLowerCase());
                }
            }
        }
        
        // ── Query for Programme Code duplicates ──
        Set<String> usedProgrammeCodes = new Set<String>();
        if (!incomingProgrammeCodes.isEmpty()) {
            List<Program> existingProgrammeCodes = [
                SELECT Id, Program_Code__c 
                FROM Program
                WHERE Program_Code__c IN :incomingProgrammeCodes
                AND Id NOT IN :currentIds
            ];
            for (Program existing : existingProgrammeCodes) {
                if (String.isNotBlank(existing.Program_Code__c)) {
                    usedProgrammeCodes.add(existing.Program_Code__c.trim().toLowerCase());
                }
            }
        }
        
        // ── Throw errors on duplicates ──
        for (Program prog : newRecords) {
            
            // Check Short Programme Code
            if (String.isNotBlank(prog.Short_Programme_Code__c)) {
                if (usedShortCodes.contains(prog.Short_Programme_Code__c.trim().toLowerCase())) {
                    prog.addError(
                        'Short Programme Code "' + prog.Short_Programme_Code__c + '" already exists. Please enter a unique value.'
                    );
                }
            }
            
            // Check Programme Code
            if (String.isNotBlank(prog.Program_Code__c)) {
                if (usedProgrammeCodes.contains(prog.Program_Code__c.trim().toLowerCase())) {
                    prog.addError(
                        'Programme Code "' + prog.Program_Code__c + '" already exists. Please enter a unique value.'
                    );
                }
            }
        }
    }
    
    /*975 Start*/
    public static void validateShortProgrammeCodeModification(List<Program> newRecords,Map<Id, Program> oldMap) {
        // oldMap is null on insert; this method only makes sense on update.
        if (oldMap == null) return;

        Set<Id> changedProgramIds = new Set<Id>();

        // Identify Programs where Short Programme Code changed
        for (Program newProg : newRecords) {

            Program oldProg = oldMap.get(newProg.Id);
            
            if (newProg.Short_Programme_Code__c !=
                oldProg.Short_Programme_Code__c) {
                    
                    changedProgramIds.add(newProg.Id);
                }
        }
        
        if (changedProgramIds.isEmpty()) {
            return;
        }
        
        // Get related Program Cohorts
        Map<Id, Id> cohortToProgramMap = new Map<Id, Id>();
        
        for (ProgramCohort cohort : [
            SELECT Id, ProgramId
            FROM ProgramCohort
            WHERE ProgramId IN :changedProgramIds
        ]) {
            
            cohortToProgramMap.put(
                cohort.Id,
                cohort.ProgramId
            );
        }
        
        if (cohortToProgramMap.isEmpty()) {
            return;
        }
        
        // Check if related cohort members exist with enrollments / roll numbers
        Set<Id> restrictedProgramIds = new Set<Id>();
        
        for (ProgramCohortMember pcm : [
            
            SELECT Id,
            ProgramCohortId,
            Roll_Number__c,
            ProgramEnrollmentId
            
            FROM ProgramCohortMember
            
            WHERE ProgramCohortId IN :cohortToProgramMap.keySet()
            
            AND (
                Roll_Number__c != NULL
                OR ProgramEnrollmentId != NULL
            )
        ]) {
            
            restrictedProgramIds.add(
                cohortToProgramMap.get(pcm.ProgramCohortId)
            );
        }
        
        // Prevent modification
        for (Program newProg : newRecords) {
            
            if (restrictedProgramIds.contains(newProg.Id)) {
                
                Program oldProg = oldMap.get(newProg.Id);
                
                if (newProg.Short_Programme_Code__c !=
                    oldProg.Short_Programme_Code__c) {
                        
                        newProg.Short_Programme_Code__c.addError(
                            'Short Programme Code cannot be modified after student enrollment and roll number generation.'
                        );
                    }
            }
        }
    }
    /*975 End*/
}