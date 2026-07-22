/**
 * B2C helpers for Education Cloud program hierarchy ({@code Program.ParentProgramId}): when a lead has
 * more than one program row under the same parent, one opportunity/application uses the parent program;
 * a single child program keeps the child on opportunity/application. Also finds reusable applications
 * from open, non-won opportunities in the same program family.
 */
public without sharing class B2CProgramParentHelper {
    /**
     * Returns the Id used to decide "same parent program family": children of the same parent share that
     * parent's Id; a root program (no parent) is its own family.
     *
     * @param program Program row (may be null).
     * @return Parent Id when {@code ParentProgramId} is set, otherwise the program Id; null if program is null.
     */
    public static Id familyGroupKey(Program program) {
        Id result = null;
        if (program != null) {
            result = program.ParentProgramId != null ? program.ParentProgramId : program.Id;
        }
        return result;
    }

    /**
     * Returns whether opportunity/application {@code Program__c} should be the parent program.
     * Roll-up happens only when there are multiple lead programs in the same family and that family is
     * under a parent ({@code ParentProgramId} is set). A single child program does not roll up.
     *
     * @param members Programs in the same family group (same {@link #familyGroupKey}).
     * @return True when there is more than one member and the first member has a parent (shared parent group).
     */
    public static Boolean shouldConsolidateOpportunityToParent(List<Program> members) {
        Boolean result = false;
        if (members != null && members.size() > 1 && members[0].ParentProgramId != null) {
            result = true;
        }
        return result;
    }

    /**
     * Resolves which {@code Program__c} to set on Opportunity and Application records for this group.
     *
     * @param members Programs in one family group (non-empty).
     * @return Parent program Id only when multiple siblings share that parent; otherwise the program Id
     *         of the sole member (or first member when not rolling up, e.g. duplicate root selection).
     */
    public static Id opportunityAndApplicationProgramId(List<Program> members) {
        Id result = null;
        if (members != null && !members.isEmpty()) {
            if (shouldConsolidateOpportunityToParent(members)) {
                result = members[0].ParentProgramId;
            } else {
                result = members[0].Id;
            }
        }
        return result;
    }

    /**
     * Groups selected programs by {@link #familyGroupKey} while preserving selection order within each group.
     *
     * @param selectedProgramIds Ordered program Ids from the UI or lead junction rows.
     * @param programById Map of Program by Id (must include every selected Id).
     * @return Map from family key to programs in that family.
     */
    public static Map<Id, List<Program>> groupSelectedProgramsByFamily(
        List<String> selectedProgramIds,
        Map<Id, Program> programById
    ) {
        Map<Id, List<Program>> groups = new Map<Id, List<Program>>();
        if (selectedProgramIds == null || programById == null) {
            return groups;
        }
        for (String pid : selectedProgramIds) {
            Id programId = SPJIMRUtility.parseSalesforceId(pid);
            if (programId == null) {
                continue;
            }
            Program p = programById.get(programId);
            if (p == null) {
                continue;
            }
            Id key = familyGroupKey(p);
            if (!groups.containsKey(key)) {
                groups.put(key, new List<Program>());
            }
            groups.get(key).add(p);
        }
        return groups;
    }

    /**
     * Finds an application to attach to a new opportunity when an open ({@code IsClosed = false}),
     * non-won opportunity already exists on the account for the same program family as {@code programId}.
     *
     * @param accountId Applicant (Person) account.
     * @param programId Any program in the intake (child or parent).
     * @return Application Id to link to a new opportunity, or null if none qualifies.
     */
    public static Id findReusableApplicationForParentFamily(Id accountId, Id programId) {
        Id result = null;
        if (accountId == null || programId == null) {
            return result;
        }

        List<Program> targetRows = [
            SELECT Id, ParentProgramId
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];
        if (targetRows.isEmpty()) {
            return result;
        }
        Id targetFamily = familyGroupKey(targetRows[0]);

        List<Opportunity> candidates = [
            SELECT Id, Application__c, Program__c, Program__r.ParentProgramId
            FROM Opportunity
            WHERE AccountId = :accountId
            AND IsWon = false
            AND IsClosed = false
            AND Application__c != null
            ORDER BY CreatedDate DESC
        ];

        for (Opportunity o : candidates) {
            if (o.Program__c == null || o.Application__c == null) {
                continue;
            }
            Id oppFamily = familyGroupKey(o.Program__r);
            if (oppFamily == targetFamily) {
                result = o.Application__c;
                break;
            }
        }
        return result;
    }
}