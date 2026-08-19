/**
 * @description Resolves (a) the programme a leave application belongs to and (b) the approver
 * users mapped to that programme, so leave routing stays inside the student's own programme.
 *
 * The programme is derived on the fly from the leave's enrollment links — nothing is stored on
 * Leave_Application__c:
 *   Batch_Enrollment__c -> ProgramCohort.ProgramId          (preferred)
 *   Term_Enrollment__c  -> AcademicTerm.Program_Name__c     (fallback)
 * Callers must therefore select Batch_Enrollment__c and Term_Enrollment__c on any leave record
 * they pass in.
 *
 * Approver mapping is configured entirely in existing metadata:
 *   Program_Team_Members__c.Role__c  -> 'Programme Office' / 'Manager' / 'Deputy Chairperson'
 *   Program_Team_Members__c.Program_Team__c -> Program_Team__c.Program__c -> Program
 *
 * A programme may have more than one Program_Team__c; members of every team under the programme
 * are returned, de-duplicated and ordered by creation date so the "first" approver is stable.
 *
 * Runs without sharing: routing is a system decision. A student submitting a leave must be able
 * to resolve their Programme Office approvers without having record access to the programme team
 * configuration.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
// Justification: system-context routing lookup. Approver resolution must not depend on the running
// user's access to Program_Team_Members__c / ProgramCohortMember / AcademicTermEnrollment setup data.
public without sharing class LeaveApproverResolver {

    /**
     * @description Programme of a single leave application.
     * @param leave Leave with Batch_Enrollment__c and Term_Enrollment__c selected.
     * @return Program Id, or null when the programme cannot be derived.
     */
    public static Id resolveProgramId(Leave_Application__c leave) {
        if (leave == null) {
            return null;
        }
        return resolveProgramIds(new List<Leave_Application__c>{ leave })[0];
    }

    /**
     * @description Programmes of several leave applications, in one pair of queries. Safe to call
     * from a before-insert trigger: the records need no Ids, only their enrollment lookups.
     * @param leaves Leaves with Batch_Enrollment__c and Term_Enrollment__c selected.
     * @return Program Ids positionally aligned with the input list; null where underivable.
     */
    public static List<Id> resolveProgramIds(List<Leave_Application__c> leaves) {
        List<Id> programIds = new List<Id>();
        if (leaves == null || leaves.isEmpty()) {
            return programIds;
        }

        Map<Id, Id> programByBatch = programByBatchEnrollment(collectBatchEnrollmentIds(leaves));
        Map<Id, Id> programByTerm = programByTermEnrollment(collectTermEnrollmentIds(leaves));

        for (Leave_Application__c rec : leaves) {
            Id programId = programByBatch.get(rec.Batch_Enrollment__c);
            if (programId == null) {
                programId = programByTerm.get(rec.Term_Enrollment__c);
            }
            programIds.add(programId);
        }
        return programIds;
    }

    /**
     * @description Approver user Ids holding the given role on any programme team of one programme.
     * @param programId Programme to resolve approvers for.
     * @param role Program_Team_Members__c.Role__c value to match.
     * @return Distinct approver user Ids, oldest membership first; empty when none are mapped.
     */
    public static List<Id> getApprovers(Id programId, String role) {
        if (programId == null) {
            return new List<Id>();
        }
        List<Id> approvers = getApproversByProgram(new Set<Id>{ programId }, role).get(programId);
        return approvers == null ? new List<Id>() : approvers;
    }

    /**
     * @description Bulk variant of {@link #getApprovers} for several programmes in one query.
     * @param programIds Programmes to resolve approvers for.
     * @param role Program_Team_Members__c.Role__c value to match.
     * @return Programme Id to distinct approver user Ids; programmes with no mapping are absent.
     */
    public static Map<Id, List<Id>> getApproversByProgram(Set<Id> programIds, String role) {
        Map<Id, List<Id>> approversByProgram = new Map<Id, List<Id>>();
        if (programIds == null || programIds.isEmpty() || String.isBlank(role)) {
            return approversByProgram;
        }

        Map<Id, Set<Id>> seenByProgram = new Map<Id, Set<Id>>();
        for (Program_Team_Members__c ptm : [
            SELECT User__c, Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Role__c = :role
            AND User__c != NULL
            AND Program_Team__r.Program__c IN :programIds
            ORDER BY CreatedDate ASC
        ]) {
            addApprover(approversByProgram, seenByProgram, ptm.Program_Team__r.Program__c, ptm.User__c);
        }
        return approversByProgram;
    }

    /**
     * @description Adds one approver to the per-programme accumulator, skipping duplicates.
     * @param approversByProgram Ordered approver list per programme; mutated.
     * @param seenByProgram De-duplication set per programme; mutated.
     * @param programId Programme the approver belongs to.
     * @param userId Approver user Id.
     */
    private static void addApprover(
        Map<Id, List<Id>> approversByProgram,
        Map<Id, Set<Id>> seenByProgram,
        Id programId,
        Id userId
    ) {
        if (programId == null || userId == null) {
            return;
        }
        if (!seenByProgram.containsKey(programId)) {
            seenByProgram.put(programId, new Set<Id>());
            approversByProgram.put(programId, new List<Id>());
        }
        if (seenByProgram.get(programId).add(userId)) {
            approversByProgram.get(programId).add(userId);
        }
    }

    /**
     * @description Batch enrollment Ids referenced by the given leaves.
     * @param leaves Leave applications to scan.
     * @return Referenced ProgramCohortMember Ids.
     */
    private static Set<Id> collectBatchEnrollmentIds(List<Leave_Application__c> leaves) {
        Set<Id> ids = new Set<Id>();
        for (Leave_Application__c rec : leaves) {
            if (rec.Batch_Enrollment__c != null) {
                ids.add(rec.Batch_Enrollment__c);
            }
        }
        return ids;
    }

    /**
     * @description Term enrollment Ids referenced by the given leaves.
     * @param leaves Leave applications to scan.
     * @return Referenced AcademicTermEnrollment Ids.
     */
    private static Set<Id> collectTermEnrollmentIds(List<Leave_Application__c> leaves) {
        Set<Id> ids = new Set<Id>();
        for (Leave_Application__c rec : leaves) {
            if (rec.Term_Enrollment__c != null) {
                ids.add(rec.Term_Enrollment__c);
            }
        }
        return ids;
    }

    /**
     * @description Maps batch enrollments to their programme via the cohort.
     * @param batchEnrollmentIds ProgramCohortMember Ids to resolve.
     * @return ProgramCohortMember Id to Program Id.
     */
    private static Map<Id, Id> programByBatchEnrollment(Set<Id> batchEnrollmentIds) {
        Map<Id, Id> programByEnrollment = new Map<Id, Id>();
        if (batchEnrollmentIds.isEmpty()) {
            return programByEnrollment;
        }
        for (ProgramCohortMember pcm : [
            SELECT Id, ProgramCohort.ProgramId
            FROM ProgramCohortMember
            WHERE Id IN :batchEnrollmentIds
        ]) {
            if (pcm.ProgramCohort.ProgramId != null) {
                programByEnrollment.put(pcm.Id, pcm.ProgramCohort.ProgramId);
            }
        }
        return programByEnrollment;
    }

    /**
     * @description Maps term enrollments to their programme via the academic term.
     * @param termEnrollmentIds AcademicTermEnrollment Ids to resolve.
     * @return AcademicTermEnrollment Id to Program Id.
     */
    private static Map<Id, Id> programByTermEnrollment(Set<Id> termEnrollmentIds) {
        Map<Id, Id> programByEnrollment = new Map<Id, Id>();
        if (termEnrollmentIds.isEmpty()) {
            return programByEnrollment;
        }
        for (AcademicTermEnrollment ate : [
            SELECT Id, AcademicTerm.Program_Name__c
            FROM AcademicTermEnrollment
            WHERE Id IN :termEnrollmentIds
        ]) {
            if (ate.AcademicTerm.Program_Name__c != null) {
                programByEnrollment.put(ate.Id, ate.AcademicTerm.Program_Name__c);
            }
        }
        return programByEnrollment;
    }
}