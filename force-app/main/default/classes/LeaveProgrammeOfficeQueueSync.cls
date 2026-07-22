/**
 * Keeps the "Leave Programme Office" queue membership in sync with the set of users
 * whose Program_Team_Members__c.Role__c = 'Programme Office'.
 *
 * The Leave Application Approval process assigns Step 1 (Programme Office Verification)
 * to this queue, so any change to Programme Office team members must be reflected in the
 * queue for the approver list to stay dynamic.
 *
 * GroupMember is a setup object, so the reconcile runs asynchronously (@future) to avoid
 * MIXED_DML_OPERATION with the triggering Program_Team_Members__c DML.
 */
public without sharing class LeaveProgrammeOfficeQueueSync {

    @TestVisible private static final String PO_ROLE = 'Programme Office';
    @TestVisible private static final String QUEUE_DEV_NAME = 'Leave_Programme_Office';
    private static final String USER_KEY_PREFIX = '005'; // Id key prefix for User

    /**
     * Entry point from ProgramTeamMemberTrigger (after insert/update/delete/undelete).
     * Only triggers a resync when a Programme Office membership may have changed.
     */
    public static void handle(List<Program_Team_Members__c> newList,
                              List<Program_Team_Members__c> oldList) {

        Boolean relevant = false;

        if (newList != null) {
            for (Program_Team_Members__c r : newList) {
                if (r.Role__c == PO_ROLE) { relevant = true; break; }
            }
        }
        if (!relevant && oldList != null) {
            for (Program_Team_Members__c r : oldList) {
                if (r.Role__c == PO_ROLE) { relevant = true; break; }
            }
        }

        // A @future can't be enqueued from an existing future/batch context.
        if (relevant && !System.isFuture() && !System.isBatch()) {
            syncQueueAsync();
        }
    }

    /**
     * Full reconcile of the queue's USER members against the current Programme Office users.
     * Idempotent and bulk-safe: recomputes the desired set from scratch each run.
     */
    @future
    public static void syncQueueAsync() {

        List<Group> queues = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :QUEUE_DEV_NAME
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            System.debug('Leave Programme Office queue not found; skipping sync.');
            return;
        }
        Id queueId = queues[0].Id;

        // Desired members = all users currently holding the Programme Office role.
        Set<Id> desired = new Set<Id>();
        for (Program_Team_Members__c po : [
            SELECT User__c FROM Program_Team_Members__c
            WHERE Role__c = :PO_ROLE AND User__c != null
        ]) {
            desired.add(po.User__c);
        }

        // Existing USER members of the queue (ignore any group/role members).
        Map<Id, GroupMember> currentUserMembers = new Map<Id, GroupMember>();
        for (GroupMember gm : [
            SELECT Id, UserOrGroupId FROM GroupMember WHERE GroupId = :queueId
        ]) {
            if (String.valueOf(gm.UserOrGroupId).startsWith(USER_KEY_PREFIX)) {
                currentUserMembers.put(gm.UserOrGroupId, gm);
            }
        }

        // Add Programme Office users that aren't members yet.
        List<GroupMember> toAdd = new List<GroupMember>();
        for (Id uid : desired) {
            if (!currentUserMembers.containsKey(uid)) {
                toAdd.add(new GroupMember(GroupId = queueId, UserOrGroupId = uid));
            }
        }

        // Remove user members who are no longer Programme Office users.
        List<GroupMember> toRemove = new List<GroupMember>();
        for (Id existingUid : currentUserMembers.keySet()) {
            if (!desired.contains(existingUid)) {
                toRemove.add(currentUserMembers.get(existingUid));
            }
        }

        if (!toAdd.isEmpty()) {
            insert toAdd;
        }
        if (!toRemove.isEmpty()) {
            delete toRemove;
        }
    }
}