/**
 * LWC entry for managing Program access: Manual Edit shares on the full hierarchy plus per-program public group
 * membership ({@code SPJIMR_Program_Access_Group__c}).
 */
public with sharing class ProgramHierarchyAccessController {

    /**
     * Lightweight health check for the LWC and debug logging (search logs for {@code PHAS PING}).
     *
     * @return Confirmation text with timestamp.
     */
    @AuraEnabled
    public static String ping() {
        Datetime now = System.now();
        System.debug(LoggingLevel.WARN, 'PHAS PING userId=' + UserInfo.getUserId() + ' at=' + now);
        return 'Ping OK at ' + now.formatGmt('yyyy-MM-dd HH:mm:ss') + 'Z';
    }

    /**
     * Loads users (program team, members of the program access public group, and legacy Manual Program share users).
     *
     * @param programId Program record Id from the host record page.
     * @return Rows for the UI; empty when {@code programId} is null.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProgramHierarchyAccessService.ProgramAccessUserRow> getAccessRows(Id programId) {
        if (programId == null) {
            return new List<ProgramHierarchyAccessService.ProgramAccessUserRow>();
        }
        return ProgramHierarchyAccessService.buildAccessRows(programId);
    }

    /**
     * Applies grant and revoke: public group membership plus Manual Edit shares on the full Program hierarchy
     * (batches, batch groups, terms, divisions, enrollments, cohort members, sessions, courses, and related records).
     *
     * @param programId Program record Id.
     * @param grantUserIds Users to grant (may be empty, not null).
     * @param revokeUserIds Users to revoke (may be empty, not null).
     */
    @AuraEnabled
    public static String applyChanges(Id programId, List<Id> grantUserIds, List<Id> revokeUserIds) {
        Integer grantCt = grantUserIds == null ? 0 : grantUserIds.size();
        Integer revokeCt = revokeUserIds == null ? 0 : revokeUserIds.size();
        System.debug(
            LoggingLevel.WARN,
            'PHAS Controller.applyChanges programId=' + programId + ' grantUserIds=' + grantCt + ' revokeUserIds=' + revokeCt
        );
        if (programId == null) {
            throw new AuraHandledException('Program Id is required.');
        }
        if (revokeUserIds != null && !revokeUserIds.isEmpty()) {
            ProgramHierarchyAccessService.revokeHierarchyAccessForUsers(programId, revokeUserIds);
        }
        ProgramAccessPublicGroupService.applyMembershipChanges(programId, grantUserIds, revokeUserIds);
        if (grantUserIds != null && !grantUserIds.isEmpty()) {
            ProgramHierarchyAccessService.grantHierarchyAccessForUsers(programId, grantUserIds);
        }
        return 'Apex completed: granted=' + grantCt + ', revoked=' + revokeCt + ', programId=' + programId;
    }
}