public without sharing class ProgrammeSharingService {

    private static final String ACCESS_LEVEL = 'Read';

    public static void sharePrograms(
        List<Program> programs
    ) {

        if (programs == null || programs.isEmpty()) {
            return;
        }

        /*
         * Program Id -> Programme Code
         */
        Map<Id, String> programCodeById =
            new Map<Id, String>();

        Set<String> programCodes =
            new Set<String>();

        for (Program programRecord : programs) {

            if (programRecord.Id == null ||
                String.isBlank(programRecord.Program_Code__c)) {
                continue;
            }

            String programCode =
                programRecord.Program_Code__c.trim();

            programCodeById.put(
                programRecord.Id,
                programCode
            );

            programCodes.add(programCode);
        }

        if (programCodeById.isEmpty()) {
            return;
        }

        /*
         * Find existing Programme Public Groups.
         */
        Map<String, Group> groupsByDeveloperName =
            ProgrammeGroupService.getProgrammeGroups(
                programCodes
            );

        if (groupsByDeveloperName.isEmpty()) {
            return;
        }

        /*
         * Collect relevant Group Ids.
         */
        Set<Id> groupIds = new Set<Id>();

        for (String programCode : programCodes) {

            String developerName =
                ProgrammeGroupService.buildDeveloperName(
                    programCode
                );

            Group programmeGroup =
                groupsByDeveloperName.get(developerName);

            if (programmeGroup != null) {
                groupIds.add(programmeGroup.Id);
            }
        }

        if (groupIds.isEmpty()) {
            return;
        }

        /*
         * Check existing shares.
         */
        Map<String, ProgramShare> existingShares =
            new Map<String, ProgramShare>();

        for (ProgramShare existingShare : [
            SELECT Id,
                   ParentId,
                   UserOrGroupId,
                   AccessLevel,
                   RowCause
            FROM ProgramShare
            WHERE ParentId IN :programCodeById.keySet()
            AND UserOrGroupId IN :groupIds
        ]) {

            String key =
                String.valueOf(existingShare.ParentId)
                + ':'
                + String.valueOf(
                    existingShare.UserOrGroupId
                );

            existingShares.put(key, existingShare);
        }

        /*
         * Create missing shares.
         */
        List<ProgramShare> sharesToInsert =
            new List<ProgramShare>();

        for (Id programId : programCodeById.keySet()) {

            String programCode =
                programCodeById.get(programId);

            String developerName =
                ProgrammeGroupService.buildDeveloperName(
                    programCode
                );

            Group programmeGroup =
                groupsByDeveloperName.get(developerName);

            if (programmeGroup == null) {
                continue;
            }

            String key =
                String.valueOf(programId)
                + ':'
                + String.valueOf(programmeGroup.Id);

            if (existingShares.containsKey(key)) {
                continue;
            }

            ProgramShare programShare =
                new ProgramShare();

            programShare.ParentId = programId;
            programShare.UserOrGroupId =
                programmeGroup.Id;
            programShare.AccessLevel =
                ACCESS_LEVEL;

            /*
             * TEMPORARY:
             * Replace Manual with the agreed
             * Apex Sharing Reason.
             */
            programShare.RowCause = 'Manual';

            sharesToInsert.add(programShare);
        }

        if (!sharesToInsert.isEmpty()) {

            Database.insert(
                sharesToInsert,
                false
            );
        }
    }
}