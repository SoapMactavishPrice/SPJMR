/**
 * Supplies Division New Aura UI with specialisation options scoped to the academic term's batch (Program Cohort).
 *
 * @see BatchCourseAssignmentController#getBatchSpecialisations
 */
public with sharing class DivisionSpecialisationController {

    /**
     * Reads Program Cohort Id from the term's Batch_Name__c lookup.
     *
     * @param termId Academic term Id (Division__c.Term__c).
     * @return ProgramCohort Id or null when missing or term not found.
     */
    private static Id resolveBatchIdFromTerm(Id termId) {
        Id batchId = null;
        if (termId != null) {
            List<AcademicTerm> rows = [
                SELECT Batch_Name__c
                FROM AcademicTerm
                WHERE Id = :termId
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                batchId = rows[0].Batch_Name__c;
            }
        }
        return batchId;
    }

    /**
     * Active specialisations for the batch linked to the given term (Term → Batch_Name__c → ProgramCohort).
     *
     * @param termId Division Term__c (AcademicTerm Id).
     * @return Rows for lightning:select; empty when term or batch is unknown.
     */
    @AuraEnabled
    public static List<SpecialisationOption> loadSpecialisationsForTerm(Id termId) {
        List<SpecialisationOption> result = new List<SpecialisationOption>();
        Id batchId = resolveBatchIdFromTerm(termId);
        for (BatchCourseAssignmentController.SpecialisationWrapper row :
                BatchCourseAssignmentController.getBatchSpecialisations(batchId)) {
            SpecialisationOption opt = new SpecialisationOption();
            opt.specialisationId = row.specialisationId;
            opt.specialisationName = row.specialisationName;
            result.add(opt);
        }
        return result;
    }

    /**
     * Picklist row for Aura (matches SpecialisationWrapper field names).
     */
    public class SpecialisationOption {
        @AuraEnabled
        public Id specialisationId { get; set; }
        @AuraEnabled
        public String specialisationName { get; set; }
    }
}