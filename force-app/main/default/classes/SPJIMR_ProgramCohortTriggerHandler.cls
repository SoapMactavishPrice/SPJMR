public with sharing class SPJIMR_ProgramCohortTriggerHandler {
    
    /**
* Main entry point for the trigger handler
* @param newList List of new ProgramCohort records
* @param oldMap Map of old ProgramCohort records (keyed by Id)
*/
    public static void handleTrigger(List<ProgramCohort> newList, Map<Id, ProgramCohort> oldMap) {
        if (Trigger.isBefore && Trigger.isInsert) {
            validateUniqueShortBatchCode(newList, null);/*956 added method*/
            validateUniqueBatchCode(newList, null);
            populateFieldsFromProgram(newList, null, true);
        }
        
        if (Trigger.isBefore && Trigger.isUpdate) {
            validateShortBatchCodeModification(newList, oldMap);/*975 added method*/
            validateUniqueShortBatchCode(newList, oldMap);/*956 added method*/
            validateUniqueBatchCode(newList, oldMap);
            populateFieldsFromProgram(newList, oldMap, false);
        }
        
        if (Trigger.isAfter && Trigger.isUpdate) {
            handleAfterUpdate(newList, oldMap);
            // Photo-upload window notification: fires when Profile_Window_Start_Time__c or Profile_Window_End_Time__c changes
            sendNotificationOnWindowChange((Map<Id, ProgramCohort>) Trigger.newMap, oldMap);
            // sendProfileWindowNotifications((Map<Id, ProgramCohort>) Trigger.newMap, oldMap); // commented out: replaced by sendNotificationOnWindowChange
        }
        
        if (Trigger.isAfter && Trigger.isInsert) {
            // sendProfileWindowNotifications((Map<Id, ProgramCohort>) Trigger.newMap, null); // commented out: replaced by sendNotificationOnWindowChange (update-only)
        }
    }
    
    /**
* Handles after update logic for ProgramCohort records
* Checks if Short_Batch_Code__c has changed and updates division codes accordingly
* @param newList List of updated ProgramCohort records
* @param oldMap Map of old ProgramCohort records (keyed by Id)
*/
    private static void handleAfterUpdate(List<ProgramCohort> newList, Map<Id, ProgramCohort> oldMap) {
        // Check if Short_Batch_Code__c has changed
        List<ProgramCohort> batchesToProcess = new List<ProgramCohort>();
        for (ProgramCohort batch : newList) {
            ProgramCohort oldBatch = oldMap.get(batch.Id);
            if (batch.Short_Batch_Code__c != oldBatch.Short_Batch_Code__c) {
                batchesToProcess.add(batch);
            }
        }
        
        if (!batchesToProcess.isEmpty()) {
            SPJIMRDivisionCodeHandler.updateDivisionCodesForBatches(batchesToProcess);
        }
    }
    
    /**
* Populates ProgramCohort fields from related Program record
* - Batch_Credit_Hours__c from Programme_Credit_Hours__c (if empty) - on insert and update
* - Specialisation fields (only on insert)
* @param programCohorts List of ProgramCohort records to process
* @param oldMap Map of old ProgramCohort records (null for insert, populated for update)
* @param isInsert Boolean flag indicating if this is an insert operation
*/
    private static void populateFieldsFromProgram(List<ProgramCohort> programCohorts, Map<Id, ProgramCohort> oldMap, Boolean isInsert) {
        Set<Id> programIds = collectProgramIds(programCohorts, isInsert);
        
        if (!programIds.isEmpty()) {
            Map<Id, Program> programMap = queryPrograms(programIds);
            
            for (ProgramCohort cohort : programCohorts) {
                if (cohort.ProgramId != null && programMap.containsKey(cohort.ProgramId)) {
                    Program relatedProgram = programMap.get(cohort.ProgramId);
                    populateBatchCreditHours(cohort, relatedProgram, oldMap);
                    
                    if (isInsert) {
                        populateSpecialisationFields(cohort, relatedProgram);
                        populateBatchCurrencyFields(cohort, relatedProgram);
                    }
                }
            }
        }
    }
    
    /**
* Collects Program IDs that need to be queried
* @param programCohorts List of ProgramCohort records
* @param isInsert Boolean flag indicating if this is an insert operation
* @return Set of Program IDs
*/
    private static Set<Id> collectProgramIds(List<ProgramCohort> programCohorts, Boolean isInsert) {
        Set<Id> programIds = new Set<Id>();
        
        for (ProgramCohort cohort : programCohorts) {
            if (isInsert) {
                programIds.add(cohort.ProgramId);
            } else if (cohort.Batch_Credit_Hours__c == null) {
                programIds.add(cohort.ProgramId);
            }
            
        }
        
        return programIds;
    }
    
    /**
* Queries Program records with all needed fields
* @param programIds Set of Program IDs to query
* @return Map of Program records keyed by Id
*/
    private static Map<Id, Program> queryPrograms(Set<Id> programIds) {
        return new Map<Id, Program>([
            SELECT Id, 
            Programme_Credit_Hours__c,
            SPJIMR_Is_Specialisation_Program__c,
            SPJIMR_Is_Major_Specialisation__c,
            SPJIMR_Is_Minor_Specialisation__c,
            Programme_Base_Currency__c
            FROM Program
            WHERE Id IN :programIds
        ]);
    }
    
    /**
* Populates Batch_Credit_Hours__c from Programme_Credit_Hours__c if empty
* @param cohort ProgramCohort record to populate
* @param relatedProgram Related Program record
* @param oldMap Map of old ProgramCohort records (null for insert)
*/
    private static void populateBatchCreditHours(ProgramCohort cohort, Program relatedProgram, Map<Id, ProgramCohort> oldMap) {
        if (cohort.Batch_Credit_Hours__c == null && relatedProgram.Programme_Credit_Hours__c != null) {
            Boolean shouldPopulate = oldMap == null ? true : shouldPopulateFromOldRecord(oldMap, cohort.Id);
            
            if (shouldPopulate) {
                cohort.Batch_Credit_Hours__c = relatedProgram.Programme_Credit_Hours__c;
            }
        }
    }
    
    /**
* Determines if Batch_Credit_Hours__c should be populated based on old record
* @param oldMap Map of old ProgramCohort records
* @param cohortId Id of the ProgramCohort record
* @return Boolean indicating if field should be populated
*/
    private static Boolean shouldPopulateFromOldRecord(Map<Id, ProgramCohort> oldMap, Id cohortId) {
        ProgramCohort oldCohort = oldMap.get(cohortId);
        return oldCohort == null || oldCohort.Batch_Credit_Hours__c == null;
    }
    
    /**
* Populates specialisation fields from Program record
* @param cohort ProgramCohort record to populate
* @param relatedProgram Related Program record
*/
    private static void populateSpecialisationFields(ProgramCohort cohort, Program relatedProgram) {
        
        cohort.SPJIMR_Is_Specialisation_Program__c = relatedProgram.SPJIMR_Is_Specialisation_Program__c;
        
        
        
        cohort.SPJIMR_Is_Major_Specialisation__c = relatedProgram.SPJIMR_Is_Major_Specialisation__c;
        
        
        
        cohort.SPJIMR_Is_Minor_Specialisation__c = relatedProgram.SPJIMR_Is_Minor_Specialisation__c;
        
    }
    
    private static void populateBatchCurrencyFields(ProgramCohort cohort,Program relatedProgram) {

    if (relatedProgram.Programme_Base_Currency__c != null) {

        cohort.Batch_Base_Currency__c = relatedProgram.Programme_Base_Currency__c;

        cohort.Batch_Base_Currency__c =relatedProgram.Programme_Base_Currency__c;
    }
}
    
    
    
    
    
    // private static void sendNotificationOnWindowChange(
    //     Map<Id, ProgramCohort> newMap,
    //     Map<Id, ProgramCohort> oldMap
    // ) {
    //     if (oldMap == null) return; // insert context — not applicable
    
    //     // Step 1: Collect cohorts where start or end date changed
    //     Set<Id> changedCohortIds = new Set<Id>();
    //     for (Id cohortId : newMap.keySet()) {
    //         ProgramCohort n = newMap.get(cohortId);
    //         ProgramCohort o = oldMap.get(cohortId);
    
    //         Boolean startChanged = n.Profile_Window_Start_Time__c != o.Profile_Window_Start_Time__c;
    //         Boolean endChanged   = n.Profile_Window_End_Time__c   != o.Profile_Window_End_Time__c;
    
    //         if ((startChanged || endChanged) && n.Profile_Window_End_Time__c != null) {
    //             changedCohortIds.add(cohortId);
    //         }
    //     }
    //     System.debug('sendNotificationOnWindowChange — changedCohortIds: ' + changedCohortIds.size());
    //     if (changedCohortIds.isEmpty()) return;
    
    //     // Step 2: Fetch ProgramCohortMembers with related ProgramEnrollment.AccountId in one query
    //     List<ProgramCohortMember> members = [
    //         SELECT Id, ProgramCohortId, ProgramEnrollment.AccountId
    //         FROM ProgramCohortMember
    //         WHERE ProgramCohortId IN :changedCohortIds
    //         AND   ProgramEnrollmentId != null
    //     ];
    //     System.debug('sendNotificationOnWindowChange — members found: ' + members.size());
    //     if (members.isEmpty()) return;
    
    //     // Step 3: Build cohortToAccountIds and allAccountIds directly from ProgramEnrollment.AccountId
    //     Set<Id> allAccountIds = new Set<Id>();
    //     Map<Id, Set<Id>> cohortToAccountIds = new Map<Id, Set<Id>>();
    //     for (ProgramCohortMember member : members) {
    //         if (member.ProgramEnrollment == null || member.ProgramEnrollment.AccountId == null) continue;
    //         Id accountId = member.ProgramEnrollment.AccountId;
    //         allAccountIds.add(accountId);
    //         if (!cohortToAccountIds.containsKey(member.ProgramCohortId)) {
    //             cohortToAccountIds.put(member.ProgramCohortId, new Set<Id>());
    //         }
    //         cohortToAccountIds.get(member.ProgramCohortId).add(accountId);
    //     }
    //     System.debug('sendNotificationOnWindowChange — allAccountIds: ' + allAccountIds.size());
    //     if (allAccountIds.isEmpty()) return;
    
    //     // Step 4: Resolve Account IDs → User IDs
    //     // Messaging.CustomNotification.send() requires User IDs, not Account IDs.
    //     Map<Id, Id> accountToUserId = new Map<Id, Id>();
    //     for (User u : [
    //         SELECT Id, AccountId
    //         FROM User
    //         WHERE AccountId IN :allAccountIds
    //         AND   IsActive = true
    //     ]) {
    //         accountToUserId.put(u.AccountId, u.Id);
    //     }
    //     System.debug('sendNotificationOnWindowChange — portal users resolved: ' + accountToUserId.size());
    
    //     // Step 5: Fetch the Custom Notification Type
    //     CustomNotificationType notifType;
    //     try {
    //         notifType = [
    //             SELECT Id
    //             FROM CustomNotificationType
    //             WHERE DeveloperName = 'Portal_User_Notification'
    //             LIMIT 1
    //         ];
    //     } catch (QueryException e) {
    //         System.debug('SPJIMR_ProgramCohortTriggerHandler: Custom Notification Type not found — ' + e.getMessage());
    //         return;
    //     }
    
    //     // Step 6: Send notification per cohort and build Portal_Notification__c records
    //     List<Portal_Notification__c> portalNotifs = new List<Portal_Notification__c>();
    
    //     for (Id cohortId : changedCohortIds) {
    //         Set<Id> accountIds = cohortToAccountIds.get(cohortId);
    //         if (accountIds == null || accountIds.isEmpty()) continue;
    
    //         ProgramCohort cohort    = newMap.get(cohortId);
    //         String endTimeFormatted = cohort.Profile_Window_End_Time__c.format('MMM d, yyyy h:mm a');
    //         String notifTitle       = 'Photo Upload Window Updated';
    //         String notifBody        = 'You can upload your photo until ' + endTimeFormatted;
    
    //         Messaging.CustomNotification notification = new Messaging.CustomNotification();
    //         notification.setNotificationTypeId(notifType.Id);
    //         notification.setTitle(notifTitle);
    //         notification.setBody(notifBody);
    //         notification.setTargetPageRef(
    //             '{"type":"standard__namedPage","attributes":{"pageName":"home"}}'
    //         );
    
    //         Set<String> recipientUserIds = new Set<String>();
    //         for (Id accountId : accountIds) {
    //             // Portal_Notification__c uses Account ID — matches PortalNotificationController query
    //             portalNotifs.add(new Portal_Notification__c(
    //                 Title__c             = notifTitle,
    //                 Body__c              = notifBody,
    //                 Recipient_Account__c = accountId,
    //                 Is_Read__c           = false
    //             ));
    //             // Messaging.CustomNotification needs User ID
    //             Id userId = accountToUserId.get(accountId);
    //             if (userId != null) {
    //                 recipientUserIds.add(String.valueOf(userId));
    //             }
    //         }
    
    //         if (!recipientUserIds.isEmpty()) {
    //             try {
    //                 notification.send(recipientUserIds);
    //                 System.debug('sendNotificationOnWindowChange — notification sent for cohort: ' + cohortId);
    //             } catch (Exception e) {
    //                 System.debug('SPJIMR_ProgramCohortTriggerHandler: send failed for cohort ' + cohortId + ' — ' + e.getMessage());
    //             }
    //         }
    //     }
    
    //     // Step 7: Bulk-insert Portal_Notification__c records for the portal header bell LWC
    //     if (!portalNotifs.isEmpty()) {
    //         try {
    //             insert portalNotifs;
    //             System.debug('sendNotificationOnWindowChange — inserted ' + portalNotifs.size() + ' Portal_Notification__c records');
    //         } catch (Exception e) {
    //             System.debug('SPJIMR_ProgramCohortTriggerHandler: Portal_Notification__c insert failed — ' + e.getMessage());
    //         }
    //     }
    // }
    
    private static void sendNotificationOnWindowChange(
        Map<Id, ProgramCohort> newMap,
        Map<Id, ProgramCohort> oldMap
    ) {
        if (oldMap == null) return;
        
        Set<Id> changedCohortIds = new Set<Id>();
        
        for (Id cohortId : newMap.keySet()) {
            ProgramCohort n = newMap.get(cohortId);
            ProgramCohort o = oldMap.get(cohortId);
            
            Boolean startChanged = n.Profile_Window_Start_Time__c != o.Profile_Window_Start_Time__c;
            Boolean endChanged   = n.Profile_Window_End_Time__c   != o.Profile_Window_End_Time__c;
            
            if ((startChanged || endChanged) && n.Profile_Window_End_Time__c != null) {
                changedCohortIds.add(cohortId);
            }
        }
        
        if (changedCohortIds.isEmpty()) return;
        
        List<ProgramCohortMember> members = [
            SELECT ProgramCohortId, ProgramEnrollment.AccountId
            FROM ProgramCohortMember
            WHERE ProgramCohortId IN :changedCohortIds
            AND ProgramEnrollmentId != null
        ];
        
        if (members.isEmpty()) return;
        
        Map<Id, Set<Id>> cohortToAccountIds = new Map<Id, Set<Id>>();
        
        for (ProgramCohortMember m : members) {
            if (m.ProgramEnrollment == null || m.ProgramEnrollment.AccountId == null) continue;
            
            if (!cohortToAccountIds.containsKey(m.ProgramCohortId)) {
                cohortToAccountIds.put(m.ProgramCohortId, new Set<Id>());
            }
            
            cohortToAccountIds.get(m.ProgramCohortId).add(m.ProgramEnrollment.AccountId);
        }
        
        List<Portal_Notification__c> portalNotifs = new List<Portal_Notification__c>();
        
        for (Id cohortId : changedCohortIds) {
            ProgramCohort cohort = newMap.get(cohortId);
            Set<Id> accountIds = cohortToAccountIds.get(cohortId);
            
            if (accountIds == null) continue;
            
            String endTimeFormatted = cohort.Profile_Window_End_Time__c.format('MMM d, yyyy h:mm a');
            
            for (Id accountId : accountIds) {
                portalNotifs.add(new Portal_Notification__c(
                    Title__c             = 'Photo Upload Window Updated',
                    Body__c              = 'You can upload your photo until ' + endTimeFormatted,
                    Recipient_Account__c = accountId,
                    Is_Read__c           = false
                ));
            }
        }
        
        if (!portalNotifs.isEmpty()) {
            insert portalNotifs;
        }
    }

    /*956 start*/
    /**
     * @description Validates that Short_Batch_Code__c is unique within the same Program,
     *              both within the current transaction and against existing database records.
     * @param newList List of ProgramCohort records being inserted or updated
     * @param oldMap Map of old ProgramCohort records (null for insert)
     */
    private static void validateUniqueShortBatchCode(
        List<ProgramCohort> newList,
        Map<Id, ProgramCohort> oldMap
    ) {
        Set<Id> programIds = new Set<Id>();
        Set<String> transactionKeys = new Set<String>();

        for (ProgramCohort cohort : newList) {
            if (cohort.ProgramId == null || String.isBlank(cohort.Short_Batch_Code__c)) {
                continue;
            }

            String key = buildProgramBatchCodeKey(cohort.ProgramId, cohort.Short_Batch_Code__c);

            // Duplicate within same transaction
            if (transactionKeys.contains(key)) {
                cohort.Short_Batch_Code__c.addError('Short Batch Code must be unique within the program.');
            } else {
                transactionKeys.add(key);
            }

            // Skip unchanged values during update
            if (isShortCodeUnchanged(cohort, oldMap)) {
                continue;
            }

            programIds.add(cohort.ProgramId);
        }

        if (programIds.isEmpty()) {
            return;
        }

        // Query existing records and apply validation
        Map<String, Id> existingMap = queryExistingShortBatchCodes(programIds);
        applyShortBatchCodeErrors(newList, existingMap);
    }

    /**
     * @description Returns true if Short_Batch_Code__c and ProgramId are both unchanged during update.
     * @param cohort The new ProgramCohort record
     * @param oldMap Map of old ProgramCohort records (null for insert)
     * @return Boolean true if neither field changed
     */
    private static Boolean isShortCodeUnchanged(ProgramCohort cohort, Map<Id, ProgramCohort> oldMap) {
        if (oldMap == null || !oldMap.containsKey(cohort.Id)) {
            return false;
        }
        ProgramCohort oldRec = oldMap.get(cohort.Id);
        return oldRec.Short_Batch_Code__c == cohort.Short_Batch_Code__c
            && oldRec.ProgramId == cohort.ProgramId;
    }

    /**
     * @description Queries existing ProgramCohort records to detect Short_Batch_Code__c conflicts.
     * @param programIds Set of Program Ids to check within
     * @return Map of composite key to existing record Id
     */
    private static Map<String, Id> queryExistingShortBatchCodes(Set<Id> programIds) {
        Map<String, Id> existingMap = new Map<String, Id>();
        for (ProgramCohort existing : [
            SELECT Id, ProgramId, Short_Batch_Code__c
            FROM ProgramCohort
            WHERE ProgramId IN :programIds
            AND Short_Batch_Code__c != NULL
            WITH USER_MODE
        ]) {
            existingMap.put(
                buildProgramBatchCodeKey(existing.ProgramId, existing.Short_Batch_Code__c),
                existing.Id
            );
        }
        return existingMap;
    }

    /**
     * @description Applies field errors for any cohort whose Short_Batch_Code__c
     *              conflicts with an existing database record.
     * @param newList List of ProgramCohort records being processed
     * @param existingMap Map of composite key to existing record Id
     */
    private static void applyShortBatchCodeErrors(List<ProgramCohort> newList, Map<String, Id> existingMap) {
        for (ProgramCohort cohort : newList) {
            if (cohort.ProgramId == null || String.isBlank(cohort.Short_Batch_Code__c)) {
                continue;
            }
            String key = buildProgramBatchCodeKey(cohort.ProgramId, cohort.Short_Batch_Code__c);
            // Ignore same record during update
            if (existingMap.containsKey(key) && existingMap.get(key) != cohort.Id) {
                cohort.Short_Batch_Code__c.addError('Short Batch Code must be unique within the Program.');
            }
        }
    }
    /*956 end*/

    private static void validateUniqueBatchCode(
        List<ProgramCohort> newList,
        Map<Id, ProgramCohort> oldMap
    ) {
        
        Set<Id> programIds = new Set<Id>();
        Set<String> transactionKeys = new Set<String>();
        
        for (ProgramCohort cohort : newList) {
            
            if (cohort.ProgramId == null ||
                String.isBlank(cohort.Batch_Code__c)) {
                    continue;
                }
            
            String key =
                String.valueOf(cohort.ProgramId) +
                '-' +
                cohort.Batch_Code__c.trim().toLowerCase();
            
            if (transactionKeys.contains(key)) {
                
                cohort.Batch_Code__c.addError(
                    'Batch Code must be unique within the Program.'
                );
                
            } else {
                transactionKeys.add(key);
            }
            
            if (oldMap != null &&
                oldMap.containsKey(cohort.Id)) {
                    
                    ProgramCohort oldRec = oldMap.get(cohort.Id);
                    
                    Boolean codeChanged =
                        oldRec.Batch_Code__c != cohort.Batch_Code__c;
                    
                    Boolean programChanged =
                        oldRec.ProgramId != cohort.ProgramId;
                    
                    if (!codeChanged && !programChanged) {
                        continue;
                    }
                }
            
            programIds.add(cohort.ProgramId);
        }
        
        if (programIds.isEmpty()) {
            return;
        }
        
        Map<String, Id> existingMap = new Map<String, Id>();
        
        for (ProgramCohort existing : [
            SELECT Id,
            ProgramId,
            Batch_Code__c
            FROM ProgramCohort
            WHERE ProgramId IN :programIds
            AND Batch_Code__c != NULL
        ]) {
            
            String key =
                String.valueOf(existing.ProgramId) +
                '-' +
                existing.Batch_Code__c.trim().toLowerCase();
            
            existingMap.put(key, existing.Id);
        }
        
        for (ProgramCohort cohort : newList) {
            
            if (cohort.ProgramId == null ||
                String.isBlank(cohort.Batch_Code__c)) {
                    continue;
                }
            
            String key =
                String.valueOf(cohort.ProgramId) +
                '-' +
                cohort.Batch_Code__c.trim().toLowerCase();
            
            if (existingMap.containsKey(key)) {
                
                if (cohort.Id != null &&
                    existingMap.get(key) == cohort.Id) {
                        continue;
                    }
                
                cohort.Batch_Code__c.addError(
                    'Batch Code must be unique within the Program.'
                );
            }
        }
    }
    
    private static String buildProgramBatchCodeKey(
        Id programId,
        String shortCode
    ) {
        
        return String.valueOf(programId) +
            '-' +
            shortCode.trim().toLowerCase();
    }
    
    /*975 Start*/
    /**
     * @description Prevents modification of Short_Batch_Code__c once students have been
     *              enrolled and roll numbers have been generated.
     * @param newList List of ProgramCohort records being updated
     * @param oldMap Map of old ProgramCohort records
     */
    private static void validateShortBatchCodeModification(
        List<ProgramCohort> newList,
        Map<Id, ProgramCohort> oldMap
    ) {
        Set<Id> cohortIds = new Set<Id>();
        
        // Identify records where Short_Batch_Code__c changed
        for (ProgramCohort newRec : newList) {
            ProgramCohort oldRec = oldMap.get(newRec.Id);
            if (newRec.Short_Batch_Code__c != oldRec.Short_Batch_Code__c) {
                cohortIds.add(newRec.Id);
            }
        }
        
        if (cohortIds.isEmpty()) {
            return;
        }
        
        // Find cohorts having members with roll numbers
        Set<Id> restrictedCohortIds = new Set<Id>();
        
        for (ProgramCohortMember pcm : [
            SELECT Id, ProgramCohortId, Roll_Number__c
            FROM ProgramCohortMember
            WHERE ProgramCohortId IN :cohortIds
            AND Roll_Number__c != NULL
            WITH USER_MODE
        ]) {
            restrictedCohortIds.add(pcm.ProgramCohortId);
        }
        
        // Prevent update
        for (ProgramCohort newRec : newList) {
            if (!restrictedCohortIds.contains(newRec.Id)) {
                continue;
            }
            ProgramCohort oldRec = oldMap.get(newRec.Id);
            if (newRec.Short_Batch_Code__c != oldRec.Short_Batch_Code__c) {
                newRec.Short_Batch_Code__c.addError(
                    'Batch Short Code cannot be modified after student enrollment and roll number generation.'
                );
            }
        }
    }
    /*975 End*/
    
}