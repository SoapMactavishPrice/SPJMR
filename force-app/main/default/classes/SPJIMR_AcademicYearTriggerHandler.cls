public with sharing class SPJIMR_AcademicYearTriggerHandler {
    
    /**
     * Main entry point for the trigger handler
     * @param newList List of new AcademicYear records
     * @param oldMap Map of old AcademicYear records (keyed by Id)
     */
    public static void handleTrigger(List<AcademicYear> newList, Map<Id, AcademicYear> oldMap) {
        if (Trigger.isAfter && Trigger.isUpdate) {
            handleAfterUpdate(newList, oldMap);
        }
    }

    /**
     * Delegates to SPJIMR_ProgramCodeCopyHandler.syncAcademicYear.
     * Called from BatchGroupTrigger before insert / before update. oldMap is null on insert.
     */
    public static void syncProgramCodeFromProgram(
        List<AcademicYear> newList,
        Map<Id, AcademicYear> oldMap
    ) {
        SPJIMR_ProgramCodeCopyHandler.syncAcademicYear(newList, oldMap);
    }
    
    /**
     * Handles after update logic for AcademicYear records
     * Checks if Batch_Group_Code__c has changed and updates division codes accordingly
     * @param newList List of updated AcademicYear records
     * @param oldMap Map of old AcademicYear records (keyed by Id)
     */
    private static void handleAfterUpdate(List<AcademicYear> newList, Map<Id, AcademicYear> oldMap) {
        // Check if Batch_Group_Code__c has changed
        List<AcademicYear> academicYearsToProcess = new List<AcademicYear>();
        for (AcademicYear ay : newList) {
            AcademicYear oldAY = oldMap.get(ay.Id);
            if (oldAY != null && ay.Batch_Group_Code__c != oldAY.Batch_Group_Code__c) {
                academicYearsToProcess.add(ay);
            }
        }
        
        if (!academicYearsToProcess.isEmpty()) {
            SPJIMRDivisionCodeHandler.updateDivisionCodesForAcademicYears(academicYearsToProcess);
            
            // Also update division codes for all terms under these academic years
            Set<Id> academicYearIds = new Set<Id>();
            for (AcademicYear ay : academicYearsToProcess) {
                academicYearIds.add(ay.Id);
            }
            
            List<AcademicTerm> termsToProcess = [
                SELECT Id
                FROM AcademicTerm
                WHERE AcademicYearId IN :academicYearIds
            ];
            
            if (!termsToProcess.isEmpty()) {
                SPJIMRDivisionCodeHandler.updateDivisionCodesForTerms(termsToProcess);
            }
        }
    }
}