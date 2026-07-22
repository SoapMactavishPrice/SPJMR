/**
 * Maintains a per-Program <strong>public group</strong> and <strong>GroupMember</strong> rows when users are granted or
 * revoked from the Manage Program Hierarchy Access screen. Record access then comes from <strong>org sharing rules</strong>
 * (owner-based or criteria-based) that administrators configure in Setup to share appropriate rows <em>with</em> that
 * public group — Apex cannot create or edit sharing rule metadata at click time.
 *
 * <p><strong>Admin checklist (one-time per object / owner pattern):</strong> (1) Ensure private OWD where sharing rules
 * apply. (2) Create owner-based or criteria-based sharing rules on Academic Year, Program, Term, etc., that grant
 * Read/Read-Write to the same public group linked on the Program (this field). (3) Typical owner-based pattern: share
 * records owned by a programme operations queue or role with the program’s access group. Criteria-based pattern: use
 * lookups such as {@code Program_Master__c} or {@code Batch__r.ProgramId} when those fields exist.</p>
 *
 * <p>Runs <strong>without sharing</strong> so Group, GroupMember, and Program updates succeed for the running user
 * when the class is granted.</p>
 *
 * @see ProgramHierarchyAccessController
 * @see ProgramHierarchyAccessService
 */
public without sharing class ProgramAccessPublicGroupService {

    private static final String ACCESS_GROUP_FIELD = 'SPJIMR_Program_Access_Group__c';
    private static final String GROUP_TYPE_REGULAR = 'Regular';

    /**
     * Applies public-group membership changes for a Program (creates the group on first use, then adds or removes
     * users in bulk).
     *
     * @param programId Program whose {@code SPJIMR_Program_Access_Group__c} is used (created if blank).
     * @param grantUserIds Active user Ids to add to the group (may be empty, not null).
     * @param revokeUserIds Active user Ids to remove from the group (may be empty, not null).
     */
    public static void applyMembershipChanges(Id programId, List<Id> grantUserIds, List<Id> revokeUserIds) {
        if (programId == null) {
            throw new AuraHandledException('Program Id is required.');
        }
        if (!isAccessGroupFieldAvailable()) {
            System.debug(
                LoggingLevel.WARN,
                'ProgramAccessPublicGroupService skipped: ' + ACCESS_GROUP_FIELD + ' not on Program in this org.'
            );
            return;
        }
        Id groupId = resolveOrCreateAccessGroup(programId);
        if (groupId == null) {
            throw new AuraHandledException(
                'Could not create the program access public group. Ensure the running user can create public groups '
                    + '(Manage Public Groups or equivalent admin permission).'
            );
        }
        Set<Id> toGrant = filterUserIds(grantUserIds);
        Set<Id> toRevoke = filterUserIds(revokeUserIds);
        if (!toGrant.isEmpty()) {
            insertGroupMembersIfMissing(groupId, toGrant);
        }
        if (!toRevoke.isEmpty()) {
            deleteGroupMembers(groupId, toRevoke);
        }
    }

    /**
     * Adds the given active users to a public group (skips duplicates and non-user Ids). Intended for tests and reuse.
     *
     * @param publicGroupId Public {@link Group} Id ({@code Type} regular).
     * @param userIds User Ids to add.
     */
    public static void addMembersToPublicGroup(Id publicGroupId, List<Id> userIds) {
        if (publicGroupId == null || userIds == null || userIds.isEmpty()) {
            return;
        }
        insertGroupMembersIfMissing(publicGroupId, filterUserIds(userIds));
    }

    /**
     * Removes the given users from a public group.
     *
     * @param publicGroupId Public {@link Group} Id.
     * @param userIds User Ids to remove.
     */
    public static void removeMembersFromPublicGroup(Id publicGroupId, List<Id> userIds) {
        if (publicGroupId == null || userIds == null || userIds.isEmpty()) {
            return;
        }
        deleteGroupMembers(publicGroupId, filterUserIds(userIds));
    }

    /**
     * Loads the access public group Id for a Program, or null when unset / field missing.
     *
     * @param programId Program Id.
     * @return Group Id or null.
     */
    public static Id getAccessGroupIdForProgram(Id programId) {
        if (programId == null || !programHasAccessGroupField()) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT Id, ' + ACCESS_GROUP_FIELD + ' FROM Program WHERE Id = :programId LIMIT 1'
        );
        if (rows.isEmpty()) {
            return null;
        }
        return (Id) rows[0].get(ACCESS_GROUP_FIELD);
    }

    /**
     * Returns user Ids that are direct members of the Program’s access public group.
     *
     * @param groupId Public group Id.
     * @return User Ids (empty when {@code groupId} is null).
     */
    public static Set<Id> loadUserIdsInAccessGroup(Id groupId) {
        Set<Id> result = new Set<Id>();
        if (groupId == null) {
            return result;
        }
        Set<Id> candidates = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId = :groupId
        ]) {
            if (gm.UserOrGroupId != null && gm.UserOrGroupId.getSobjectType() == User.SObjectType) {
                candidates.add(gm.UserOrGroupId);
            }
        }
        if (candidates.isEmpty()) {
            return result;
        }
        for (User u : [SELECT Id FROM User WHERE Id IN :candidates AND IsActive = true]) {
            result.add(u.Id);
        }
        return result;
    }

    /**
     * Builds a unique public group API label (stored in {@link Group#Name}) for a Program, max 40 characters.
     *
     * @param programId Program Id.
     * @return Name string suitable for {@link Group#Name}.
     */
    public static String buildAccessGroupName(Id programId) {
        String suffix = String.valueOf(programId).replace('-', '');
        String base = 'SPJP-' + suffix;
        if (base.length() > 40) {
            base = base.substring(0, 40);
        }
        return base;
    }

    /**
     * Whether {@link #ACCESS_GROUP_FIELD} exists on Program in this org (deploy field metadata before relying on groups).
     *
     * @return True when the lookup field is available.
     */
    public static Boolean isAccessGroupFieldAvailable() {
        return programHasAccessGroupField();
    }

    private static Boolean programHasAccessGroupField() {
        return Schema.SObjectType.Program.fields.getMap().containsKey(ACCESS_GROUP_FIELD);
    }

    private static Id resolveOrCreateAccessGroup(Id programId) {
        if (!programHasAccessGroupField()) {
            return null;
        }
        List<SObject> rows = Database.query(
            'SELECT Id, ' + ACCESS_GROUP_FIELD + ' FROM Program WHERE Id = :programId FOR UPDATE'
        );
        if (rows.isEmpty()) {
            return null;
        }
        SObject pr = rows[0];
        Id existing = (Id) pr.get(ACCESS_GROUP_FIELD);
        if (existing != null) {
            return existing;
        }
        Group g = new Group();
        g.Name = buildAccessGroupName(programId);
        g.Type = GROUP_TYPE_REGULAR;
        insert g;
        pr.put(ACCESS_GROUP_FIELD, g.Id);
        update pr;
        return g.Id;
    }

    private static Set<Id> filterUserIds(List<Id> raw) {
        Set<Id> out = new Set<Id>();
        if (raw == null) {
            return out;
        }
        for (Id uid : raw) {
            if (uid != null) {
                out.add(uid);
            }
        }
        return out;
    }

    private static void insertGroupMembersIfMissing(Id groupId, Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        Set<Id> already = new Set<Id>();
        for (GroupMember gm : [
            SELECT UserOrGroupId
            FROM GroupMember
            WHERE GroupId = :groupId
            AND UserOrGroupId IN :userIds
        ]) {
            already.add(gm.UserOrGroupId);
        }
        Set<Id> activeUsers = new Map<Id, User>([
            SELECT Id
            FROM User
            WHERE Id IN :userIds
            AND IsActive = true
        ])
            .keySet();
        List<GroupMember> toInsert = new List<GroupMember>();
        for (Id uid : userIds) {
            if (!already.contains(uid) && activeUsers.contains(uid)) {
                GroupMember m = new GroupMember();
                m.GroupId = groupId;
                m.UserOrGroupId = uid;
                toInsert.add(m);
            }
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static void deleteGroupMembers(Id groupId, Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        List<GroupMember> rows = [
            SELECT Id
            FROM GroupMember
            WHERE GroupId = :groupId
            AND UserOrGroupId IN :userIds
        ];
        if (!rows.isEmpty()) {
            delete rows;
        }
    }
}