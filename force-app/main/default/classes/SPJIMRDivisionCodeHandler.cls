public class SPJIMRDivisionCodeHandler {

    /**
     * Updates division codes for the provided divisions.
     * This method is called from Division trigger and always recalculates the code.
     */
    public static void updateDivisionCodes(List<Division__c> divisions) {
        Set<Id> termIds = new Set<Id>();

        // Collect Term IDs from divisions
        for (Division__c div : divisions) {
            if (div.Term__c != null) {
                termIds.add(div.Term__c);
            }
        }

        if (termIds.isEmpty()) {
            return;
        }

        // Query Term with parent Batch Group and Batch
        Map<Id, AcademicTerm> termMap = new Map<Id, AcademicTerm>(
            [SELECT Id,
                    Term_Code__c,
                    AcademicYear.Batch_Group_Code__c,
                    AcademicYear.Batch__r.Short_Batch_Code__c
             FROM AcademicTerm
             WHERE Id IN :termIds]
        );

        // Build Division Code - Always recalculate
        for (Division__c div : divisions) {
            if (div.Term__c != null && termMap.containsKey(div.Term__c)) {
                AcademicTerm term = termMap.get(div.Term__c);

                String shortBatchCode = term.AcademicYear.Batch__r.Short_Batch_Code__c;
                String batchGroupCode = term.AcademicYear.Batch_Group_Code__c;
                String termCode       = term.Term_Code__c;
                String divisionName   = div.Division_Name__c;

                // Always recalculate division code when any component changes
                if (String.isNotBlank(shortBatchCode) && 
                    String.isNotBlank(batchGroupCode) && 
                    String.isNotBlank(termCode) && 
                    String.isNotBlank(divisionName)) {
                    div.SPJIMR_Division_Code__c =
                        shortBatchCode + '-' +
                        batchGroupCode + '-' +
                        termCode + '-' +
                        divisionName;
                }
            }
        }
    }

    /**
     * Updates division codes for all divisions related to the provided AcademicTerms.
     * Called when Term_Code__c changes on AcademicTerm.
     */
    public static void updateDivisionCodesForTerms(List<AcademicTerm> terms) {
        // Query all divisions for these terms
        List<Division__c> divisionsToUpdate = [
            SELECT Id, Term__c, Division_Name__c
            FROM Division__c
            WHERE Term__c IN :terms
        ];

        if (!divisionsToUpdate.isEmpty()) {
            updateDivisionCodes(divisionsToUpdate);
            update divisionsToUpdate;
        }
    }

    /**
     * Updates division codes for all divisions related to AcademicTerms under the provided AcademicYears.
     * Called when Batch_Group_Code__c changes on AcademicYear.
     */
    public static void updateDivisionCodesForAcademicYears(List<AcademicYear> academicYears) {

        // Query all divisions for these terms
        List<Division__c> divisionsToUpdate = [
            SELECT Id, Term__c,Term__r.Batch_Name__c , SPJIMR_Division_Code__c, Term__r.AcademicYearId,   Division_Name__c FROM Division__C WHERE Term__r.AcademicYearId IN :academicYears
        ];

        if (!divisionsToUpdate.isEmpty()) {
            updateDivisionCodes(divisionsToUpdate);
            update divisionsToUpdate;
        }
    }

    /**
     * Updates division codes for all divisions related to AcademicTerms under AcademicYears 
     * that reference the provided Batches (ProgramCohorts).
     * Called when Short_Batch_Code__c changes on ProgramCohort.
     */
    public static void updateDivisionCodesForBatches(List<ProgramCohort> batches) {
        // Query all divisions for these terms
        List<Division__c> divisionsToUpdate = [
            SELECT Id, Term__c,Term__r.Batch_Name__c , SPJIMR_Division_Code__c,  Division_Name__c FROM Division__C WHERE Term__r.Batch_Name__c IN :batches
        ];

        if (!divisionsToUpdate.isEmpty()) {
            
            updateDivisionCodes(divisionsToUpdate);
            
            update divisionsToUpdate;
        }
    }
}