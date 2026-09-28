public without sharing class ProgrammeSharingService {

    private static final String ACCESS_LEVEL = 'Read';

    /*
     * TEMPORARY:
     * Replace this with the agreed Apex Sharing Reason
     * once the Sharing Reason is created for each object.
     */
    private static final String ROW_CAUSE = 'Manual';


    public static void shareRecords(
        String objectApiName,
        Map<Id, String> newRecordCodes,
        Map<Id, String> oldRecordCodes
    ) {

        if (
            String.isBlank(objectApiName) ||
            newRecordCodes == null ||
            newRecordCodes.isEmpty()
        ) {
            return;
        }


        /*
         * ---------------------------------------------------------
         * GET SHARE OBJECT
         * ---------------------------------------------------------
         *
         * Program       -> ProgramShare
         * Session__c    -> Session__Share
         * Campus__c     -> Campus__Share
         * Account       -> AccountShare
         */
        String shareObjectApiName;

        if (objectApiName.endsWith('__c')) {

            shareObjectApiName =
                objectApiName.replace(
                    '__c',
                    '__Share'
                );

        } else {

            shareObjectApiName =
                objectApiName + 'Share';
        }

        System.debug(
            'SHARE OBJECT = ' +
            shareObjectApiName
        );


        Schema.SObjectType shareObjectType =
            Schema.getGlobalDescribe().get(
                shareObjectApiName
            );

        if (shareObjectType == null) {
            return;
        }


        /*
         * ---------------------------------------------------------
         * ACCOUNT HAS DIFFERENT SHARE FIELD NAMES
         * ---------------------------------------------------------
         *
         * AccountShare:
         *     AccountId
         *     AccountAccessLevel
         *
         * Other Share objects:
         *     ParentId
         *     AccessLevel
         */
        String parentFieldName =
            objectApiName == 'Account'
                ? 'AccountId'
                : 'ParentId';

        String accessLevelFieldName =
            objectApiName == 'Account'
                ? 'AccountAccessLevel'
                : 'AccessLevel';


        /*
         * ---------------------------------------------------------
         * CLEAN NEW PROGRAMME CODES
         * ---------------------------------------------------------
         */
        Map<Id, String> validNewCodes =
            new Map<Id, String>();

        Set<String> newProgrammeCodes =
            new Set<String>();

        for (
            Id recordId :
            newRecordCodes.keySet()
        ) {

            if (recordId == null) {
                continue;
            }

            String newCode =
                newRecordCodes.get(
                    recordId
                );

            if (String.isNotBlank(newCode)) {

                newCode =
                    newCode.trim();

                validNewCodes.put(
                    recordId,
                    newCode
                );

                newProgrammeCodes.add(
                    newCode
                );
            }
        }


        /*
         * ---------------------------------------------------------
         * FIND PROGRAMME CODE CHANGES
         * ---------------------------------------------------------
         *
         * Example:
         *
         * Old = SDT
         * New = PGDM
         *
         * Then:
         *     remove SDT share
         *     create PGDM share
         */
        Map<Id, String> changedOldCodes =
            new Map<Id, String>();

        Set<String> oldProgrammeCodes =
            new Set<String>();

        if (
            oldRecordCodes != null &&
            !oldRecordCodes.isEmpty()
        ) {

            for (
                Id recordId :
                oldRecordCodes.keySet()
            ) {

                String oldCode =
                    oldRecordCodes.get(
                        recordId
                    );

                String newCode =
                    newRecordCodes.get(
                        recordId
                    );


                String normalizedOldCode =
                    String.isBlank(oldCode)
                        ? null
                        : oldCode.trim();

                String normalizedNewCode =
                    String.isBlank(newCode)
                        ? null
                        : newCode.trim();


                /*
                 * Only process when Programme Code changed.
                 */
                if (
                    normalizedOldCode !=
                    normalizedNewCode
                ) {

                    if (
                        normalizedOldCode != null
                    ) {

                        changedOldCodes.put(
                            recordId,
                            normalizedOldCode
                        );

                        oldProgrammeCodes.add(
                            normalizedOldCode
                        );
                    }
                }
            }
        }


        /*
         * ---------------------------------------------------------
         * REMOVE STALE SHARES
         * ---------------------------------------------------------
         *
         * This handles:
         *
         * SDT -> PGDM
         * SDT -> blank
         *
         * The old Programme Group share is removed.
         */
        if (
            !changedOldCodes.isEmpty() &&
            !oldProgrammeCodes.isEmpty()
        ) {

            Map<String, Group> oldGroups =
                ProgrammeGroupService.getProgrammeGroups(
                    oldProgrammeCodes
                );

            if (
                oldGroups != null &&
                !oldGroups.isEmpty()
            ) {

                /*
                 * Record Id -> Old Programme Group Id
                 */
                Map<Id, Id> oldGroupByRecord =
                    new Map<Id, Id>();

                Set<Id> oldGroupIds =
                    new Set<Id>();


                for (
                    Id recordId :
                    changedOldCodes.keySet()
                ) {

                    String oldCode =
                        changedOldCodes.get(
                            recordId
                        );

                    String developerName = ProgrammeGroupService.buildDeveloperName(oldCode);

                    Group oldGroup =
                        oldGroups.get(
                            developerName
                        );

                    if (oldGroup == null) {
                        continue;
                    }

                    oldGroupByRecord.put(
                        recordId,
                        oldGroup.Id
                    );

                    oldGroupIds.add(
                        oldGroup.Id
                    );
                }


                if (
                    !oldGroupByRecord.isEmpty()
                ) {

                    Set<Id> changedRecordIds =
                        oldGroupByRecord.keySet();


                    /*
                     * Find existing shares for the
                     * old Programme Groups.
                     */
                    String oldShareQuery =
                        'SELECT Id, ' +
                        parentFieldName +
                        ', UserOrGroupId, ' +
                        'RowCause ' +
                        'FROM ' +
                        shareObjectApiName +
                        ' WHERE ' +
                        parentFieldName +
                        ' IN :changedRecordIds ' +
                        ' AND UserOrGroupId IN :oldGroupIds';


                    Map<String, Object> oldBindVariables =
                        new Map<String, Object>{
                            'changedRecordIds' =>
                                changedRecordIds,
                            'oldGroupIds' =>
                                oldGroupIds
                        };


                    List<SObject> oldShares =
                        Database.queryWithBinds(
                            oldShareQuery,
                            oldBindVariables,
                            AccessLevel.SYSTEM_MODE
                        );


                    List<SObject> sharesToDelete =
                        new List<SObject>();


                    for (
                        SObject oldShare :
                        oldShares
                    ) {

                        Id parentId =
                            (Id) oldShare.get(
                                parentFieldName
                            );

                        Id groupId =
                            (Id) oldShare.get(
                                'UserOrGroupId'
                            );

                        String rowCause =
                            String.valueOf(
                                oldShare.get(
                                    'RowCause'
                                )
                            );


                        /*
                         * Delete only the share belonging
                         * to the old Programme Group.
                         */
                        if (
                            oldGroupByRecord.containsKey(
                                parentId
                            ) &&
                            oldGroupByRecord.get(
                                parentId
                            ) == groupId &&
                            rowCause == ROW_CAUSE
                        ) {

                            sharesToDelete.add(
                                oldShare
                            );
                        }
                    }


                    /*
                     * Delete stale shares in bulk.
                     */
                    if (
                        !sharesToDelete.isEmpty()
                    ) {

                        Database.DeleteResult[] deleteResults =
                            Database.delete(
                                sharesToDelete,
                                false
                            );


                        for (
                            Database.DeleteResult result :
                            deleteResults
                        ) {

                            if (
                                !result.isSuccess()
                            ) {

                                for (
                                    Database.Error error :
                                    result.getErrors()
                                ) {

                                    System.debug(
                                        'SHARE DELETE ERROR: ' +
                                        error.getStatusCode() +
                                        ' - ' +
                                        error.getMessage()
                                    );
                                }

                            } else {

                                System.debug(
                                    'STALE SHARE DELETED: ' +
                                    result.getId()
                                );
                            }
                        }
                    }
                }
            }
        }


        /*
         * ---------------------------------------------------------
         * IF THERE ARE NO NEW PROGRAMME CODES
         * ---------------------------------------------------------
         *
         * This happens when:
         *
         * SDT -> blank
         *
         * Old share has already been removed above.
         * Nothing else needs to be created.
         */
        if (validNewCodes.isEmpty()) {
            return;
        }


        /*
         * ---------------------------------------------------------
         * FIND NEW PROGRAMME GROUPS
         * ---------------------------------------------------------
         */
        Map<String, Group> groupsByDeveloperName =
            ProgrammeGroupService.getProgrammeGroups(
                newProgrammeCodes
            );


        System.debug(
            'NEW PROGRAMME CODES = ' +
            newProgrammeCodes
        );

        System.debug(
            'NEW GROUPS FOUND = ' +
            groupsByDeveloperName
        );


        if (
            groupsByDeveloperName == null ||
            groupsByDeveloperName.isEmpty()
        ) {
            return;
        }


        /*
         * ---------------------------------------------------------
         * RECORD ID -> NEW PROGRAMME GROUP ID
         * ---------------------------------------------------------
         */
        Map<Id, Id> groupIdByRecordId =
            new Map<Id, Id>();

        Set<Id> groupIds =
            new Set<Id>();


        for (
            Id recordId :
            validNewCodes.keySet()
        ) {

            String programmeCode =
                validNewCodes.get(
                    recordId
                );


            String developerName =ProgrammeGroupService.buildDeveloperName(programmeCode);


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


        System.debug(
            'GROUP ID BY RECORD = ' +
            groupIdByRecordId
        );

        System.debug(
            'GROUP IDS = ' +
            groupIds
        );


        if (
            groupIdByRecordId.isEmpty()
        ) {
            return;
        }


        /*
         * ---------------------------------------------------------
         * GET EXISTING NEW SHARES
         * ---------------------------------------------------------
         *
         * This prevents duplicate shares.
         */
        Set<Id> recordIds =
            validNewCodes.keySet();


        String query =
            'SELECT Id, ' +
            parentFieldName +
            ', UserOrGroupId, ' +
            accessLevelFieldName +
            ', RowCause ' +
            'FROM ' +
            shareObjectApiName +
            ' WHERE ' +
            parentFieldName +
            ' IN :recordIds ' +
            ' AND UserOrGroupId IN :groupIds';


        Map<String, Object> bindVariables =
            new Map<String, Object>{
                'recordIds' =>
                    recordIds,
                'groupIds' =>
                    groupIds
            };


        List<SObject> existingShares =
            Database.queryWithBinds(
                query,
                bindVariables,
                AccessLevel.SYSTEM_MODE
            );


        Set<String> existingShareKeys =
            new Set<String>();


        for (
            SObject existingShare :
            existingShares
        ) {

            Id parentId =
                (Id) existingShare.get(
                    parentFieldName
                );


            Id userOrGroupId =
                (Id) existingShare.get(
                    'UserOrGroupId'
                );


            String rowCause =
                String.valueOf(
                    existingShare.get(
                        'RowCause'
                    )
                );


            /*
             * Only consider shares created by
             * ProgrammeSharingService.
             */
            if (
                rowCause == ROW_CAUSE
            ) {

                String key =
                    String.valueOf(
                        parentId
                    ) +
                    ':' +
                    String.valueOf(
                        userOrGroupId
                    );


                existingShareKeys.add(
                    key
                );
            }
        }


        /*
         * ---------------------------------------------------------
         * CREATE NEW SHARES
         * ---------------------------------------------------------
         */
        List<SObject> sharesToInsert =
            new List<SObject>();


        for (
            Id recordId :
            groupIdByRecordId.keySet()
        ) {

            Id groupId =
                groupIdByRecordId.get(
                    recordId
                );


            String key =
                String.valueOf(
                    recordId
                ) +
                ':' +
                String.valueOf(
                    groupId
                );


            /*
             * Prevent duplicate shares.
             */
            if (
                existingShareKeys.contains(
                    key
                )
            ) {
                continue;
            }


            SObject shareRecord =
                shareObjectType.newSObject();


            /*
             * ParentId for normal Share objects.
             * AccountId for AccountShare.
             */
            shareRecord.put(
                parentFieldName,
                recordId
            );


            shareRecord.put(
                'UserOrGroupId',
                groupId
            );


            /*
             * AccessLevel for normal Share objects.
             * AccountAccessLevel for AccountShare.
             */
            shareRecord.put(
                accessLevelFieldName,
                ACCESS_LEVEL
            );


            /*
             * TEMPORARY:
             * Replace Manual with the agreed
             * Apex Sharing Reason.
             */
            shareRecord.put(
                'RowCause',
                ROW_CAUSE
            );


            sharesToInsert.add(
                shareRecord
            );
        }


        System.debug(
            'SHARES TO INSERT = ' +
            sharesToInsert
        );


        /*
         * ---------------------------------------------------------
         * INSERT NEW SHARES IN BULK
         * ---------------------------------------------------------
         */
        if (
            !sharesToInsert.isEmpty()
        ) {

            Database.SaveResult[] results =
                Database.insert(
                    sharesToInsert,
                    false
                );


            for (
                Database.SaveResult result :
                results
            ) {

                if (
                    !result.isSuccess()
                ) {

                    for (
                        Database.Error error :
                        result.getErrors()
                    ) {

                        System.debug(
                            'SHARE INSERT ERROR: ' +
                            error.getStatusCode() +
                            ' - ' +
                            error.getMessage()
                        );
                    }

                } else {

                    System.debug(
                        'SHARE INSERT SUCCESS: ' +
                        result.getId()
                    );
                }
            }
        }
    }
}