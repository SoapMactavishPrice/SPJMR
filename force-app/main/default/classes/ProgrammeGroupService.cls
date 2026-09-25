public without sharing class ProgrammeGroupService {

    /**
     * Creates one Public Group per unique Program Code.
     *
     * The method is idempotent:
     * If the group already exists, it will not create another one.
     */
    public static void createGroupsForPrograms(
        List<Program> programs
    ) {

        if (programs == null || programs.isEmpty()) {
            return;
        }

        Set<String> programCodes = new Set<String>();

        for (Program programRecord : programs) {

            if (String.isNotBlank(programRecord.Program_Code__c)) {

                programCodes.add(
                    programRecord.Program_Code__c.trim()
                );
            }
        }

        if (programCodes.isEmpty()) {
            return;
        }

        /*
         * Map:
         * DeveloperName -> Group
         */
        Map<String, Group> existingGroups =
            getExistingGroups(programCodes);

        List<Group> groupsToInsert = new List<Group>();

        for (String programCode : programCodes) {

            String developerName =
                buildDeveloperName(programCode);

            if (!existingGroups.containsKey(developerName)) {

                groupsToInsert.add(
                    new Group(
                        Name = buildGroupName(programCode),
                        DeveloperName = developerName,
                        Type = 'Regular'
                    )
                );
            }
        }

        if (groupsToInsert.isEmpty()) {
            return;
        }

        /*
         * Use partial success.
         *
         * This protects us from concurrent Queueable jobs where
         * another transaction may create the same group first.
         */
        Database.SaveResult[] results =
            Database.insert(groupsToInsert, false);

        Set<String> duplicateDeveloperNames =
            new Set<String>();

        for (Integer i = 0; i < results.size(); i++) {

            if (!results[i].isSuccess()) {

                for (Database.Error error : results[i].getErrors()) {

                    if (error.getStatusCode() ==
                        StatusCode.DUPLICATE_VALUE) {

                        duplicateDeveloperNames.add(
                            groupsToInsert[i].DeveloperName
                        );
                    }
                }
            }
        }

        /*
         * Duplicate groups are expected in a race condition.
         * We intentionally do not throw an exception.
         */
        if (!duplicateDeveloperNames.isEmpty()) {

            List<Group> groupsCreatedByOtherTransactions = [
                SELECT Id, Name, DeveloperName
                FROM Group
                WHERE DeveloperName IN :duplicateDeveloperNames
            ];
        }
    }
    
    /**
     * Returns existing Programme groups.
     *
     * This public wrapper is used by the
     * ProgrammeSharingService.
     */
    public static Map<String, Group> getProgrammeGroups(
        Set<String> programCodes
    ) {
        return getExistingGroups(programCodes);
    }/**se-1390*/


    /**
     * Returns existing Programme groups.
     */
    private static Map<String, Group> getExistingGroups(
        Set<String> programCodes
    ) {

        Set<String> developerNames = new Set<String>();

        for (String programCode : programCodes) {
            developerNames.add(
                buildDeveloperName(programCode)
            );
        }

        Map<String, Group> result =
            new Map<String, Group>();

        for (Group groupRecord : [
            SELECT Id, Name, DeveloperName, Type
            FROM Group
            WHERE DeveloperName IN :developerNames
        ]) {

            result.put(
                groupRecord.DeveloperName,
                groupRecord
            );
        }

        return result;
    }


    /**
     * Builds Public Group Name.
     *
     * Example:
     * GMP -> Programme_GMP
     */
    public static String buildGroupName(String programCode) {

        return 'Programme_' + programCode;
    }


    /**
     * Builds a valid Group DeveloperName.
     *
     * Rules:
     * - Alphanumeric / underscore
     * - Starts with a letter
     * - Maximum 80 characters
     */
    public static String buildDeveloperName(String programCode) {

        String sanitizedCode = programCode == null
            ? ''
            : programCode.trim();

        /*
         * Replace anything other than:
         * A-Z
         * a-z
         * 0-9
         * _
         */
        sanitizedCode =
            sanitizedCode.replaceAll('[^a-zA-Z0-9_]', '_');

        String developerName =
            'Programme_' + sanitizedCode;

        /*
         * Programme_ already guarantees that the
         * DeveloperName starts with a letter.
         */

        if (developerName.length() > 80) {
            developerName =
                developerName.substring(0, 80);
        }

        return developerName;
    }
public static void addTeamMembersToGroups(
    List<Program_Team_Members__c> members
) {

    if (members == null || members.isEmpty()) {
        return;
    }

    /*
     * Programme Code -> User Ids
     */
    Map<String, Set<Id>> usersByProgramCode =
        new Map<String, Set<Id>>();

    Set<String> programCodes = new Set<String>();

    Set<Id> userIds = new Set<Id>();

    for (Program_Team_Members__c member : members) {

        String programCode =
            member.Program_Team__r
                .Program__r
                .Program_Code__c;

        Id userId = member.User__c;

        if (String.isBlank(programCode) || userId == null) {
            continue;
        }

        programCode = programCode.trim();

        programCodes.add(programCode);
        userIds.add(userId);

        if (!usersByProgramCode.containsKey(programCode)) {
            usersByProgramCode.put(
                programCode,
                new Set<Id>()
            );
        }

        usersByProgramCode
            .get(programCode)
            .add(userId);
    }

    if (programCodes.isEmpty() || userIds.isEmpty()) {
        return;
    }


    /*
     * Find Programme Groups.
     */
    Map<String, Group> groupsByDeveloperName =
        getExistingGroups(programCodes);


    /*
     * If group doesn't exist, don't fail the transaction.
     *
     * The retry strategy can be added separately.
     */
    List<GroupMember> membershipsToInsert =
        new List<GroupMember>();


    /*
     * First collect Group Ids.
     */
    Set<Id> groupIds = new Set<Id>();

    for (String programCode : programCodes) {

        String developerName =
            buildDeveloperName(programCode);

        if (groupsByDeveloperName.containsKey(developerName)) {

            groupIds.add(
                groupsByDeveloperName
                    .get(developerName)
                    .Id
            );
        }
    }

    if (groupIds.isEmpty()) {
        return;
    }


    /*
     * Find existing memberships.
     */
    Map<String, GroupMember> existingMemberships =
        new Map<String, GroupMember>();

    for (GroupMember existingMember : [
        SELECT Id, GroupId, UserOrGroupId
        FROM GroupMember
        WHERE GroupId IN :groupIds
        AND UserOrGroupId IN :userIds
    ]) {

        String key =
            String.valueOf(existingMember.GroupId)
            + ':'
            + String.valueOf(existingMember.UserOrGroupId);

        existingMemberships.put(
            key,
            existingMember
        );
    }


    /*
     * Build new memberships only.
     */
    for (String programCode : usersByProgramCode.keySet()) {

        String developerName =
            buildDeveloperName(programCode);

        Group targetGroup =
            groupsByDeveloperName.get(developerName);

        if (targetGroup == null) {
            continue;
        }

        for (Id userId :
            usersByProgramCode.get(programCode)) {

            String key =
                String.valueOf(targetGroup.Id)
                + ':'
                + String.valueOf(userId);

            if (!existingMemberships.containsKey(key)) {

                membershipsToInsert.add(
                    new GroupMember(
                        GroupId = targetGroup.Id,
                        UserOrGroupId = userId
                    )
                );
            }
        }
    }


    /*
     * Insert memberships.
     *
     * allOrNone=false prevents one duplicate from
     * causing the entire bulk operation to fail.
     */
    if (!membershipsToInsert.isEmpty()) {

        Database.SaveResult[] results =
            Database.insert(
                membershipsToInsert,
                false
            );

        /*
         * DUPLICATE_VALUE can still theoretically happen
         * if another async transaction adds the same user
         * at the same time.
         *
         * We intentionally don't throw the exception.
         */
        for (Database.SaveResult result : results) {

            if (!result.isSuccess()) {

                for (Database.Error error :
                    result.getErrors()) {

                    if (error.getStatusCode() ==
                        StatusCode.DUPLICATE_VALUE) {

                        // Expected idempotency/race-condition case.
                        continue;
                    }

                    // For a production implementation,
                    // log unexpected errors here.
                }
            }
        }
    }
}
}