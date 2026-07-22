public class UserTriggerHandler {
    
    public void handleAfterInsert(List<User> newUserList,List<User>oldUserList,
                                        Map<Id,User> mapNewUser,
                                         Map<Id,User> mapOldUser){
                                              /* Description: Send Welcome Email to Applicants*/
                                            // UserTriggerHelper.sendApplicantWelcomeEmail(newUserList);
                                         }
    
    public void handlerBeforeInsert(List<User> newUserList){
      //  UserTriggerHelper.populateProgrammeNamesFromOpportunity(newUserList);
    }

    private static final String TARGET_PROFILE_NAME = 'SPJIMR Student Portal User';
    private static final String TARGET_PERMSET_NAME  = 'Perm_SPJIMR_Student';
	
    public static void assignPermissionSetOnInsert(List<User> newUsers) {

        // 1. Fetch target Profile Id
        List<Profile> profiles = [
            SELECT Id FROM Profile
            WHERE Name = :TARGET_PROFILE_NAME
            LIMIT 1
        ];
        if (profiles.isEmpty()) {
            System.debug('Profile not found: ' + TARGET_PROFILE_NAME);
            return;
        }
        Id targetProfileId = profiles[0].Id;

        // 2. Filter eligible users
        List<Id> eligibleUserIds = new List<Id>();
        for (User u : newUsers) {
            if (u.ProfileId == targetProfileId && u.Id != null && u.IsActive) {
                eligibleUserIds.add(u.Id);
            }
        }

        if (eligibleUserIds.isEmpty()) return;

        // 3. ✅ Enqueue async — runs AFTER transaction commits
        //    Safe for both single creation and bulk import of 100+ users
        System.enqueueJob(
            new PermSetAssignmentQueueable(eligibleUserIds, TARGET_PERMSET_NAME)
        );
    }


    // ── Queueable Inner Class ──────────────────────────────────────────
    public class PermSetAssignmentQueueable implements Queueable {

        private List<Id> userIds;
        private String   permSetName;

        public PermSetAssignmentQueueable(List<Id> userIds, String permSetName) {
            this.userIds     = userIds;
            this.permSetName = permSetName;
        }

        public void execute(QueueableContext ctx) {

            // 4. Fetch Permission Set
            List<PermissionSet> permSets = [
                SELECT Id FROM PermissionSet
                WHERE Name = :permSetName
                LIMIT 1
            ];
            if (permSets.isEmpty()) {
                System.debug('Permission Set not found: ' + permSetName);
                return;
            }
            Id permSetId = permSets[0].Id;

            // 5. Re-query users — confirms all 100 are fully saved
            List<User> users = [
                SELECT Id FROM User
                WHERE Id IN :userIds
                AND IsActive = true
            ];

            // 6. Skip already assigned users
            Set<Id> alreadyAssigned = new Set<Id>();
            for (PermissionSetAssignment psa : [
                SELECT AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSetId = :permSetId
                AND AssigneeId IN :userIds
            ]) {
                alreadyAssigned.add(psa.AssigneeId);
            }

            // 7. Build assignments
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (User u : users) {
                if (!alreadyAssigned.contains(u.Id)) {
                    assignments.add(new PermissionSetAssignment(
                        AssigneeId      = u.Id,
                        PermissionSetId = permSetId
                    ));
                }
            }

            // 8. ✅ Insert in chunks of 200 — handles 100, 500, 1000+ users
            if (!assignments.isEmpty()) {
                List<PermissionSetAssignment> chunk = new List<PermissionSetAssignment>();
                for (Integer i = 0; i < assignments.size(); i++) {
                    chunk.add(assignments[i]);
                    if (chunk.size() == 200 || i == assignments.size() - 1) {
                        Database.SaveResult[] results = Database.insert(chunk, false);
                        for (Integer j = 0; j < results.size(); j++) {
                            if (!results[j].isSuccess()) {
                                System.debug('❌ Failed: ' + chunk[j].AssigneeId
                                    + ' | ' + results[j].getErrors()[0].getMessage());
                            } else {
                                System.debug('✅ Assigned: ' + chunk[j].AssigneeId);
                            }
                        }
                        chunk.clear();
                    }
                }
            }
        }
    }
}