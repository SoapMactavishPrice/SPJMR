public without sharing class ProgrammeSharingService {

    private static final String ACCESS_LEVEL = 'Read';

    /*
     * Generic sharing method.
     *
     * objectApiName:
     * Program
     * Session__c
     * Campus__c
     * AcademicTerm
     * Program_Courses__c
     * Leave_Application__c
     * Withdrawal_Request__c
     * Deferment_Request__c
     * Account
     *
     * recordIdToProgrammeCode:
     * Record Id -> Programme Code
     */
    public static void shareRecords(
        String objectApiName,
        Map<Id, String> recordIdToProgrammeCode
    ) {

        if (
            String.isBlank(objectApiName) ||
            recordIdToProgrammeCode == null ||
            recordIdToProgrammeCode.isEmpty()
        ) {
            return;
        }

        /*
         * Clean Programme Codes and remove invalid records.
         */
        Map<Id, String> validRecordCodes =
            new Map<Id, String>();

        Set<String> programmeCodes =
            new Set<String>();

        for (Id recordId : recordIdToProgrammeCode.keySet()) {

            String programmeCode =
                recordIdToProgrammeCode.get(recordId);

            if (
                recordId == null ||
                String.isBlank(programmeCode)
            ) {
                continue;
            }

            programmeCode = programmeCode.trim();

            validRecordCodes.put(
                recordId,
                programmeCode
            );

            programmeCodes.add(
                programmeCode
            );
        }

        if (validRecordCodes.isEmpty()) {
            return;
        }

        /*
         * Find existing Programme Public Groups.
         */
        Map<String, Group> groupsByDeveloperName =
            ProgrammeGroupService.getProgrammeGroups(
                programmeCodes
            );

        if (groupsByDeveloperName.isEmpty()) {
            return;
        }

        /*
         * Record Id -> Programme Group Id
         */
        Map<Id, Id> groupIdByRecordId =
            new Map<Id, Id>();

        Set<Id> groupIds =
            new Set<Id>();

        for (Id recordId : validRecordCodes.keySet()) {

            String programmeCode =
                validRecordCodes.get(recordId);

            String developerName =
                ProgrammeGroupService.buildDeveloperName(
                    programmeCode
                );

            Group programmeGroup =
                groupsByDeveloperName.get(
                    developerName
                );

            if (programmeGroup == null) {
                continue;
            }

            groupIdByRecordId.put(
                recordId,
                programmeGroup.Id
            );

            groupIds.add(
                programmeGroup.Id
            );
        }

        if (groupIdByRecordId.isEmpty()) {
            return;
        }

        /*
         * Get the appropriate Share object dynamically.
         *
         * Example:
         * Program       -> ProgramShare
         * Session__c    -> Session__Share
         * Campus__c     -> Campus__Share
         * Account       -> AccountShare
         */
        String shareObjectApiName =
            objectApiName + 'Share';

        Schema.SObjectType shareObjectType =
            Schema.getGlobalDescribe().get(
                shareObjectApiName
            );

        if (shareObjectType == null) {
            return;
        }

        /*
         * Record Ids used for existing-share query.
         */
        Set<Id> recordIds =
            validRecordCodes.keySet();

        /*
         * Check existing shares to prevent duplicates.
         */
        String query =
            'SELECT Id, ParentId, UserOrGroupId, ' +
            'AccessLevel, RowCause ' +
            'FROM ' + shareObjectApiName +
            ' WHERE ParentId IN :recordIds ' +
            ' AND UserOrGroupId IN :groupIds';

        Map<String, Object> bindVariables =
            new Map<String, Object>{
                'recordIds' => recordIds,
                'groupIds' => groupIds
            };

        List<SObject> existingShares =
            Database.queryWithBinds(
                query,
                bindVariables,
                AccessLevel.SYSTEM_MODE
            );

        Set<String> existingShareKeys =
            new Set<String>();

        for (SObject existingShare : existingShares) {

            Id parentId =
                (Id) existingShare.get(
                    'ParentId'
                );

            Id userOrGroupId =
                (Id) existingShare.get(
                    'UserOrGroupId'
                );

            String key =
                String.valueOf(parentId) +
                ':' +
                String.valueOf(userOrGroupId);

            existingShareKeys.add(key);
        }

        /*
         * Create missing shares.
         */
        List<SObject> sharesToInsert =
            new List<SObject>();

        for (Id recordId : groupIdByRecordId.keySet()) {

            Id groupId =
                groupIdByRecordId.get(
                    recordId
                );

            String key =
                String.valueOf(recordId) +
                ':' +
                String.valueOf(groupId);

            if (existingShareKeys.contains(key)) {
                continue;
            }

            SObject shareRecord =
                shareObjectType.newSObject();

            shareRecord.put(
                'ParentId',
                recordId
            );

            shareRecord.put(
                'UserOrGroupId',
                groupId
            );

            shareRecord.put(
                'AccessLevel',
                ACCESS_LEVEL
            );

            /*
             * TEMPORARY:
             * Replace Manual with the agreed
             * Apex Sharing Reason.
             */
            shareRecord.put(
                'RowCause',
                'Manual'
            );

            sharesToInsert.add(
                shareRecord
            );
        }

        /*
         * Insert all shares in bulk.
         */
        if (!sharesToInsert.isEmpty()) {

            Database.insert(
                sharesToInsert,
                false
            );
        }
    }
}