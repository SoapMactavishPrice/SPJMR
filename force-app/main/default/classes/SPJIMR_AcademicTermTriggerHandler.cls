public with sharing class SPJIMR_AcademicTermTriggerHandler {
    
    /**
     * Main entry point for the trigger handler
     * @param newList List of new AcademicTerm records
     * @param oldMap Map of old AcademicTerm records (keyed by Id)
     */
    public static void handleTrigger(List<AcademicTerm> newList, Map<Id, AcademicTerm> oldMap) {
        if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
            syncProgramCodeFromProgram(newList, oldMap);
        }
        if (Trigger.isAfter && Trigger.isUpdate) {
            handleAfterUpdate(newList, oldMap);
        }
    }

    /**
     * Delegates to SPJIMR_ProgramCodeCopyHandler.syncAcademicTerm.
     *
     * @param newList Terms in the trigger context.
     * @param oldMap Prior values on update; null on insert.
     */
    public static void syncProgramCodeFromProgram(
        List<AcademicTerm> newList,
        Map<Id, AcademicTerm> oldMap
    ) {
        SPJIMR_ProgramCodeCopyHandler.syncAcademicTerm(newList, oldMap);
    }
    
    /**
     * Handles after update logic for AcademicTerm records
     * Checks if Term_Code__c has changed and updates division codes accordingly
     * @param newList List of updated AcademicTerm records
     * @param oldMap Map of old AcademicTerm records (keyed by Id)
     */
    private static void handleAfterUpdate(List<AcademicTerm> newList, Map<Id, AcademicTerm> oldMap) {
        // Check if Term_Code__c has changed
        List<AcademicTerm> termsToProcess = new List<AcademicTerm>();
        for (AcademicTerm term : newList) {
            AcademicTerm oldTerm = oldMap.get(term.Id);
            if (term.Term_Code__c != oldTerm.Term_Code__c) {
                termsToProcess.add(term);
            }
        }
        
        if (!termsToProcess.isEmpty()) {
            SPJIMRDivisionCodeHandler.updateDivisionCodesForTerms(termsToProcess);
        }
    }
}