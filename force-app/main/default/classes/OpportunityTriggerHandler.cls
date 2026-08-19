/**
    * Opportunity automation: B2C owner assignment on insert (prefers related Lead owner, else program queue from metadata),
    * B2B Closed Won Draft contract creation from Synced or Accepted quotes, and legacy non-B2B close-won contract sync.
    *
    * <p>Note: B2B contract DML runs in after update. Row-level addError on the Opportunity is not available there;
    * failures throw DmlException or IllegalArgumentException, which roll back the entire save (including the stage change).</p>
    *
    * @see ProgramQueueRoutingService
    */
    public without sharing class OpportunityTriggerHandler {
        private static Boolean isB2BClosedWonContractAutomationRunning = false;
        
        private static final String STAGE_CLOSED_WON = 'Closed Won';
        private static final String QUOTE_STATUS_ACCEPTED = 'Accepted';
        private static final String B2B_AUTO_CONTRACT_DESCRIPTION =
            'Automatically generated from Closed Won Opportunity via Synced/Accepted Quote.';
        /**
        * For B2C opportunities with {@code Program__c}: sets {@code OwnerId} to the matching Lead&apos;s owner when resolvable
        * (converted Lead on the Account, or open Lead with {@code Lead_Program__c} for the same program and Person Account email);
        * otherwise assigns the queue from {@code Program_Queue_Routing__mdt} when configured.
        *
        * @param newList {@code Trigger.new} on insert.
        */
        public static void handleBeforeInsert(List<Opportunity> newList) {
            if (newList == null || newList.isEmpty()) {
                return;
            }

            Schema.RecordTypeInfo b2cOppRti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get('B2C_Opportunity');
            if (b2cOppRti == null) {
                return;
            }
            Id b2cRecordTypeId = b2cOppRti.getRecordTypeId();
            
            List<Opportunity> b2cWithProgram = new List<Opportunity>();
            Set<Id> programIds = new Set<Id>();
            Set<Id> accountIds = new Set<Id>();
            for (Opportunity opp : newList) {
                if (opp.RecordTypeId == b2cRecordTypeId && opp.Program__c != null) {
                    b2cWithProgram.add(opp);
                    programIds.add(opp.Program__c);
                    if (opp.AccountId != null) {
                        accountIds.add(opp.AccountId);
                    }
                }
            }
            if (b2cWithProgram.isEmpty() || programIds.isEmpty()) {
                return;
            }
            
            Map<Id, Id> accountIdToConvertedLeadId = resolveConvertedLeadIdByAccount(accountIds);
            Map<Id, String> accountIdToPersonEmail = loadPersonEmailByAccountId(accountIds);
            
            Map<String, Id> accountProgramKeyToLeadProgramOwnerId = resolveLeadProgramOwnerIdByConvertedLead(
                accountIdToConvertedLeadId,
            programIds
                );
            Map<String, Id> emailProgramKeyToLeadOwnerId = resolveLeadOwnerIdByOpenLeadProgram(
                accountIdToPersonEmail,
            programIds,
            accountIdToConvertedLeadId.keySet()
                );
            //Map<Id, Id> programIdToQueueId = ProgramQueueRoutingService.resolveProgramIdToValidatedQueueIdMap(programIds);
            
            for (Opportunity opp : b2cWithProgram) {
                Id leadOwnerId = null;
                if (opp.AccountId != null) {
                    leadOwnerId = accountProgramKeyToLeadProgramOwnerId.get(accountProgramKey(opp.AccountId, opp.Program__c));
                    if (leadOwnerId == null) {
                        String personEmail = accountIdToPersonEmail.get(opp.AccountId);
                        if (String.isNotBlank(personEmail)) {
                            String key = emailProgramKey(personEmail, opp.Program__c);
                            leadOwnerId = emailProgramKeyToLeadOwnerId.get(key);
                        }
                    }
                }
                if (leadOwnerId != null) {
                    opp.OwnerId = leadOwnerId;
                } else {
                    Id defOwnerId = LeadProgramRoutingService.resolveLeadProgramOwnerId();
                    //Id queueId = programIdToQueueId.get(opp.Program__c);
                    if (defOwnerId != null) {
                        opp.OwnerId = defOwnerId;
                    }
                }
            }
        }
        
        
        /**
        * Most recently converted Lead Id per Account (by ConvertedDate).
        */
        private static Map<Id, Id> resolveConvertedLeadIdByAccount(Set<Id> accountIds) {
            Map<Id, Id> result = new Map<Id, Id>();
            if (accountIds == null || accountIds.isEmpty()) {
                return result;
            }
            for (Lead row : [
            SELECT Id, ConvertedAccountId, ConvertedDate
            FROM Lead
            WHERE IsConverted = TRUE AND ConvertedAccountId IN :accountIds
            ORDER BY ConvertedDate DESC NULLS LAST
        ]) {
                if (!result.containsKey(row.ConvertedAccountId)) {
                    result.put(row.ConvertedAccountId, row.Id);
                }
            }
            return result;
        }
        
        /**
        * Lead_Program__c.OwnerId for the converted Lead + Program combination, keyed by Account + Program
        * so it can be matched directly against the new Opportunity.
        */
        private static Map<String, Id> resolveLeadProgramOwnerIdByConvertedLead(
        Map<Id, Id> accountIdToConvertedLeadId,
        Set<Id> programIds
    ) {
        Map<String, Id> result = new Map<String, Id>();

        if (accountIdToConvertedLeadId == null ||
            accountIdToConvertedLeadId.isEmpty() ||
            programIds == null ||
            programIds.isEmpty()) {
            return result;
        }

        // Lead -> Account
        Map<Id, Id> leadIdToAccountId = new Map<Id, Id>();
        for (Id accId : accountIdToConvertedLeadId.keySet()) {
            leadIdToAccountId.put(accountIdToConvertedLeadId.get(accId), accId);
        }

        // Query all programs once
        Map<Id, Program> allPrograms = new Map<Id, Program>([
            SELECT Id, ParentProgramId
            FROM Program
        ]);

        // Parent -> Children
        Map<Id, Set<Id>> parentToChildren = new Map<Id, Set<Id>>();

        for (Program p : allPrograms.values()) {
            if (p.ParentProgramId != null) {
                if (!parentToChildren.containsKey(p.ParentProgramId)) {
                    parentToChildren.put(p.ParentProgramId, new Set<Id>());
                }
                parentToChildren.get(p.ParentProgramId).add(p.Id);
            }
        }

        // Query ALL Lead Programs for the converted Leads
        List<Lead_Program__c> leadPrograms = [
            SELECT Lead__c,
                Program__c,
                OwnerId,
                CreatedDate
            FROM Lead_Program__c
            WHERE Lead__c IN :leadIdToAccountId.keySet()
            ORDER BY CreatedDate DESC
        ];

        // Lead -> Program -> Lead Program
        Map<Id, Map<Id, Lead_Program__c>> leadProgramMap = new Map<Id, Map<Id, Lead_Program__c>>();

        for (Lead_Program__c lp : leadPrograms) {

            if (lp.OwnerId == null) {
                continue;
            }

            if (!leadProgramMap.containsKey(lp.Lead__c)) {
                leadProgramMap.put(lp.Lead__c, new Map<Id, Lead_Program__c>());
            }

            // Keep latest
            if (!leadProgramMap.get(lp.Lead__c).containsKey(lp.Program__c)) {
                leadProgramMap.get(lp.Lead__c).put(lp.Program__c, lp);
            }
        }

        // Build lookup map
        for (Id leadId : leadProgramMap.keySet()) {

            Id accountId = leadIdToAccountId.get(leadId);

            if (accountId == null) {
                continue;
            }

            Map<Id, Lead_Program__c> programsForLead = leadProgramMap.get(leadId);

            Set<Id> handledChildren = new Set<Id>();

            // Evaluate every parent
            for (Id parentId : parentToChildren.keySet()) {

                Set<Id> children = parentToChildren.get(parentId);

                Boolean hasAllChildren = true;

                for (Id childId : children) {
                    if (!programsForLead.containsKey(childId)) {
                        hasAllChildren = false;
                        break;
                    }
                }

                if (hasAllChildren) {

                    // Parent mapping
                    if (programIds.contains(parentId)) {

                        Lead_Program__c ownerSource =
                            programsForLead.get(children.iterator().next());

                        result.put(
                            accountProgramKey(accountId, parentId),
                            ownerSource.OwnerId
                        );
                    }

                    handledChildren.addAll(children);

                } else {

                    // Individual child mappings
                    for (Id childId : children) {

                        if (handledChildren.contains(childId)) {
                            continue;
                        }

                        if (programsForLead.containsKey(childId) &&
                            programIds.contains(childId)) {

                            result.put(
                                accountProgramKey(accountId, childId),
                                programsForLead.get(childId).OwnerId
                            );
                        }
                    }
                }
            }

            // Standalone programs
            for (Id progId : programsForLead.keySet()) {

                Program p = allPrograms.get(progId);

                if ((p == null || p.ParentProgramId == null) &&
                    programIds.contains(progId)) {

                    result.put(
                        accountProgramKey(accountId, progId),
                        programsForLead.get(progId).OwnerId
                    );
                }
            }
        }

        return result;
    }
        
        private static String accountProgramKey(Id accountId, Id programId) {
            return String.valueOf(accountId) + '_' + String.valueOf(programId);
        }
        
        
        
        
        /**
        * Loads {@code PersonEmail} for Person Accounts used to match open Leads.
        *
        * @param accountIds Account Ids from the opportunities.
        * @return Account Id → trimmed {@code PersonEmail}.
        */
        private static Map<Id, String> loadPersonEmailByAccountId(Set<Id> accountIds) {
            Map<Id, String> result = new Map<Id, String>();
            if (accountIds == null || accountIds.isEmpty()) {
                return result;
            }
            for (Account row : [SELECT Id, PersonEmail FROM Account WHERE Id IN :accountIds]) {
                if (String.isNotBlank(row.PersonEmail)) {
                    result.put(row.Id, row.PersonEmail.trim());
                }
            }
            return result;
        }
        
        /**
        * Open Leads with the same email as the Account and a {@code Lead_Program__c} row for the opportunity&apos;s program.
        *
        * @param accountIdToPersonEmail Account → email (not lowercased).
        * @param programIds Programs on the new opportunities.
        * @param accountIdsSkipOpenLeadLookup Accounts already resolved via converted Lead.
        * @return Normalized email + program Id key → Lead {@code OwnerId}.
        */
        private static Map<String, Id> resolveLeadOwnerIdByOpenLeadProgram(
            Map<Id, String> accountIdToPersonEmail,
        Set<Id> programIds,
        Set<Id> accountIdsSkipOpenLeadLookup
        ) {
            Map<String, Id> result = new Map<String, Id>();
            if (
                accountIdToPersonEmail == null ||
                accountIdToPersonEmail.isEmpty() ||
                programIds == null ||
                programIds.isEmpty()
            ) {
                return result;
            }
            Set<String> emailsToQuery = new Set<String>();
            for (Id accId : accountIdToPersonEmail.keySet()) {
                if (accountIdsSkipOpenLeadLookup != null && accountIdsSkipOpenLeadLookup.contains(accId)) {
                    continue;
                }
                String em = accountIdToPersonEmail.get(accId);
                if (String.isNotBlank(em)) {
                    emailsToQuery.add(em);
                }
            }
            if (emailsToQuery.isEmpty()) {
                return result;
            }
            Set<Id> openLeadIds = new Set<Id>();
            for (Lead row : [
                SELECT Id
                FROM Lead
                WHERE IsConverted = FALSE AND Email IN :emailsToQuery
            ]) {
                openLeadIds.add(row.Id);
            }
            if (openLeadIds.isEmpty()) {
                return result;
            }
            for (Lead_Program__c lp : [
                SELECT Program__c, Lead__r.Email, Lead__r.OwnerId, CreatedDate,OwnerId
                FROM Lead_Program__c
                WHERE Program__c IN :programIds AND Lead__c IN :openLeadIds
                ORDER BY CreatedDate DESC NULLS LAST
            ]) {
                if (lp.Lead__r == null || String.isBlank(lp.Lead__r.Email) || lp.Lead__r.OwnerId == null) {
                    continue;
                }
                String key = emailProgramKey(lp.Lead__r.Email, lp.Program__c);
                if (!result.containsKey(key)) {
                    result.put(key, lp.OwnerId);
                }
            }
            return result;
        }
        
        private static String emailProgramKey(String email, Id programId) {
            String e = normalizeEmail(email);
            return e + '_' + String.valueOf(programId);
        }
        
        private static String normalizeEmail(String email) {
            return String.isBlank(email) ? '' : email.trim().toLowerCase();
        }
        
        /**
        // * B2B Opportunity record type; when absent in the org, all Closed Won opportunities use the B2B contract path.
        // *
        // * @return {@code B2B_Opportunity} record type Id, or null if not available.
        // */
        // private static Id b2bOpportunityRecordTypeId() {
        //     Schema.RecordTypeInfo rti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
        //         .get('B2B_Opportunity');
        //     if (rti == null || !rti.isAvailable()) {
        //         return null;
        //     }
        //     return rti.getRecordTypeId();
        // }
        
        // private static Boolean quoteObjectHasContractIdLookup() {
        //     return Schema.SObjectType.Quote.fields.getMap().containsKey('contractid');
        // }
        
        /**
        * After update entry: routes newly Closed Won opportunities to B2B Draft-contract automation or legacy sync behavior.
        *
        * @param newList {@code Trigger.new} from after update.
        * @param oldMap {@code Trigger.oldMap} from after update.
        */
        // public static void handleAfterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        //     if (isB2BClosedWonContractAutomationRunning) {
        //         return;
        //     }
        //     if (newList == null || oldMap == null) {
        //         return;
        //     }
            
        //     Id b2bRtId = b2bOpportunityRecordTypeId();
        //     Set<Id> b2bClosedWonIds = new Set<Id>();
        //     Set<Id> legacyClosedWonIds = new Set<Id>();
            
        //     for (Opportunity opp : newList) {
        //         Opportunity oldOpp = oldMap.get(opp.Id);
        //         if (oldOpp == null) {
        //             continue;
        //         }
        //         if (opp.StageName != STAGE_CLOSED_WON || oldOpp.StageName == STAGE_CLOSED_WON) {
        //             continue;
        //         }
        //         if (b2bRtId == null || opp.RecordTypeId == b2bRtId) {
        //             b2bClosedWonIds.add(opp.Id);
        //         } else {
        //             legacyClosedWonIds.add(opp.Id);
        //         }
        //     }
            
        //     if (!b2bClosedWonIds.isEmpty()) {
        //         processB2BClosedWonContracts(b2bClosedWonIds);
        //     }
        //     if (!legacyClosedWonIds.isEmpty()) {
        //         runLegacyClosedWonContractAndQuoteSync(legacyClosedWonIds);
        //     }
        // }
        
        /**
        * Creates a Draft Contract for B2B Closed Won opportunities, sets Opportunity.ContractId, and stamps Quote.ContractId
        * when a winning quote is resolved (SyncedQuoteId, else latest modified Accepted quote).
        * Uses a static flag around follow-up updates to avoid recursion. DML failures throw and roll back the whole transaction
        * (after-update context cannot use {@code addError} on the Opportunity).
        *
        * @param opportunityIds Opportunities that just moved to Closed Won on the B2B path.
        */
        // private static void processB2BClosedWonContracts(Set<Id> opportunityIds) {
        //     if (opportunityIds == null || opportunityIds.isEmpty()) {
        //         return;
        //     }
            
        //     List<Opportunity> opps = [
        //         SELECT Id, AccountId, CloseDate, ContractId, SyncedQuoteId
        //         FROM Opportunity
        //         WHERE Id IN :opportunityIds
        //     ];
            
        //     Set<Id> syncedQuoteIds = new Set<Id>();
        //     Set<Id> oppsNeedingAcceptedFallback = new Set<Id>();
        //     Map<Id, Id> winningQuoteIdByOppId = new Map<Id, Id>();
            
        //     for (Opportunity o : opps) {
        //         if (o.ContractId != null) {
        //             continue;
        //         }
        //         if (o.AccountId == null) {
        //             throw new IllegalArgumentException(
        //                 'Cannot create Contract: Opportunity ' + String.valueOf(o.Id) + ' has no Account.'
        //                 );
        //         }
        //         if (o.SyncedQuoteId != null) {
        //             syncedQuoteIds.add(o.SyncedQuoteId);
        //             winningQuoteIdByOppId.put(o.Id, o.SyncedQuoteId);
        //         } else {
        //             oppsNeedingAcceptedFallback.add(o.Id);
        //         }
        //     }
            
        //     if (!syncedQuoteIds.isEmpty()) {
        //         Map<Id, Quote> syncedQuotes = new Map<Id, Quote>([
        //             SELECT Id, OpportunityId
        //             FROM Quote
        //             WHERE Id IN :syncedQuoteIds
        //         ]);
        //         for (Id oppId : new Set<Id>(winningQuoteIdByOppId.keySet())) {
        //             Id qId = winningQuoteIdByOppId.get(oppId);
        //             Quote sq = syncedQuotes.get(qId);
        //             if (sq == null || sq.OpportunityId != oppId) {
        //                 winningQuoteIdByOppId.remove(oppId);
        //                 oppsNeedingAcceptedFallback.add(oppId);
        //             }
        //         }
        //     }
            
        //     if (!oppsNeedingAcceptedFallback.isEmpty()) {
        //         List<Quote> acceptedQuotes = [
        //             SELECT Id, OpportunityId, LastModifiedDate
        //             FROM Quote
        //             WHERE OpportunityId IN :oppsNeedingAcceptedFallback AND Status = :QUOTE_STATUS_ACCEPTED
        //             ORDER BY LastModifiedDate DESC NULLS LAST
        //         ];
        //         for (Quote q : acceptedQuotes) {
        //             if (!winningQuoteIdByOppId.containsKey(q.OpportunityId)) {
        //                 winningQuoteIdByOppId.put(q.OpportunityId, q.Id);
        //             }
        //         }
        //     }
            
        //     List<Contract> contractsToInsert = new List<Contract>();
        //     List<Id> contractOppOrder = new List<Id>();
            
        //     for (Opportunity o : opps) {
        //         if (o.ContractId != null) {
        //             continue;
        //         }
        //         Contract c = new Contract();
        //         c.AccountId = o.AccountId;
        //         c.StartDate = o.CloseDate != null ? o.CloseDate : Date.today();
        //         c.ContractTerm = 12;
        //         c.Status = 'Draft';
        //         c.Description = B2B_AUTO_CONTRACT_DESCRIPTION;
        //         contractsToInsert.add(c);
        //         contractOppOrder.add(o.Id);
        //     }
            
        //     if (contractsToInsert.isEmpty()) {
        //         return;
        //     }
            
        //     try {
        //         insert contractsToInsert;
        //     } catch (DmlException e) {
        //         throw e;
        //     }
            
        //     Map<Id, Id> newContractIdByOppId = new Map<Id, Id>();
        //     for (Integer i = 0; i < contractsToInsert.size(); i++) {
        //         newContractIdByOppId.put(contractOppOrder[i], contractsToInsert[i].Id);
        //     }
            
        //     List<Opportunity> oppUpdates = new List<Opportunity>();
        //     List<Quote> quoteUpdates = new List<Quote>();
        //     Boolean quoteHasContract = quoteObjectHasContractIdLookup();
            
        //     for (Id oppId : newContractIdByOppId.keySet()) {
        //         Id conId = newContractIdByOppId.get(oppId);
        //         oppUpdates.add(new Opportunity(Id = oppId, ContractId = conId));
                
        //         if (quoteHasContract && winningQuoteIdByOppId.containsKey(oppId)) {
        //             Id qId = winningQuoteIdByOppId.get(oppId);
        //             if (qId != null) {
        //                 quoteUpdates.add(new Quote(Id = qId, ContractId = conId));
        //             }
        //         }
        //     }
            
        //     isB2BClosedWonContractAutomationRunning = true;
        //     try {
        //         try {
        //             if (!oppUpdates.isEmpty()) {
        //                 update oppUpdates;
        //             }
        //             if (!quoteUpdates.isEmpty()) {
        //                 update quoteUpdates;
        //             }
        //         } catch (DmlException e) {
        //             throw e;
        //         }
        //     } finally {
        //         isB2BClosedWonContractAutomationRunning = false;
        //     }
        // }
        
        /**
        * Original Closed Won behavior for non-B2B record types: sync contract from quote, activate Draft contracts, link quotes.
        *
        * @param justClosedWonOppIds Opportunity Ids that transitioned to Closed Won (legacy path only).
        */
        // private static void runLegacyClosedWonContractAndQuoteSync(Set<Id> justClosedWonOppIds) {
        //     if (justClosedWonOppIds == null || justClosedWonOppIds.isEmpty()) {
        //         return;
        //     }
            
        //     List<Opportunity> opportunities = [
        //         SELECT Id, Name, AccountId, CloseDate, ContractId, SyncedQuoteId
        //         FROM Opportunity
        //         WHERE Id IN :justClosedWonOppIds
        //     ];
            
        //     Map<Id, Quote> latestQuoteByOpportunity = new Map<Id, Quote>();
        //     Map<Id, Quote> quoteById = new Map<Id, Quote>();
        //     for (Quote q : [
        //         SELECT Id, OpportunityId, Name, Description, ExpirationDate, CreatedDate
        //         FROM Quote
        //         WHERE OpportunityId IN :justClosedWonOppIds
        //         ORDER BY CreatedDate DESC
        //     ]) {
        //         quoteById.put(q.Id, q);
        //         if (!latestQuoteByOpportunity.containsKey(q.OpportunityId)) {
        //             latestQuoteByOpportunity.put(q.OpportunityId, q);
        //         }
        //     }
            
        //     Map<Id, Contract> existingContractsById = new Map<Id, Contract>();
        //     Set<Id> contractIds = new Set<Id>();
        //     for (Opportunity opp : opportunities) {
        //         if (opp.ContractId != null) {
        //             contractIds.add(opp.ContractId);
        //         }
        //     }
        //     if (!contractIds.isEmpty()) {
        //         existingContractsById = new Map<Id, Contract>([
        //             SELECT Id, AccountId, Status, StartDate, ContractTerm, Description
        //             FROM Contract
        //             WHERE Id IN :contractIds
        //         ]);
        //     }
            
        //     List<Contract> contractsToInsert = new List<Contract>();
        //     List<Contract> contractsToUpdate = new List<Contract>();
        //     Map<Id, Contract> contractByOpportunityId = new Map<Id, Contract>();
            
        //     for (Opportunity opp : opportunities) {
        //         Quote selectedQuote = null;
        //         if (opp.SyncedQuoteId != null && quoteById.containsKey(opp.SyncedQuoteId)) {
        //             selectedQuote = quoteById.get(opp.SyncedQuoteId);
        //         } else {
        //             selectedQuote = latestQuoteByOpportunity.get(opp.Id);
        //         }
        //         if (selectedQuote == null) {
        //             continue;
        //         }
                
        //         Contract contractRecord;
        //         if (opp.ContractId != null && existingContractsById.containsKey(opp.ContractId)) {
        //             contractRecord = existingContractsById.get(opp.ContractId);
        //             contractRecord.StartDate = opp.CloseDate != null ? opp.CloseDate : Date.today();
        //             contractRecord.ContractTerm = contractRecord.ContractTerm != null ? contractRecord.ContractTerm : 12;
        //             contractRecord.Description = String.isNotBlank(selectedQuote.Description)
        //                 ? selectedQuote.Description
        //                 : 'Created from Quote: ' + selectedQuote.Name;
        //             contractRecord.Status = 'Activated';
        //             contractsToUpdate.add(contractRecord);
        //         } else {
        //             contractRecord = new Contract();
        //             contractRecord.AccountId = opp.AccountId;
        //             contractRecord.StartDate = opp.CloseDate != null ? opp.CloseDate : Date.today();
        //             contractRecord.ContractTerm = 12;
        //             contractRecord.Description = String.isNotBlank(selectedQuote.Description)
        //                 ? selectedQuote.Description
        //                 : 'Created from Quote: ' + selectedQuote.Name;
        //             contractRecord.Status = 'Draft';
        //             contractsToInsert.add(contractRecord);
        //         }
        //         contractByOpportunityId.put(opp.Id, contractRecord);
        //     }
            
        //     if (!contractsToInsert.isEmpty()) {
        //         insert contractsToInsert;
        //     }
            
        //     for (Opportunity opp : opportunities) {
        //         Contract c = contractByOpportunityId.get(opp.Id);
        //         if (c != null && c.Id != null && c.Status == 'Draft') {
        //             c.Status = 'Activated';
        //             contractsToUpdate.add(c);
        //         }
        //     }
        //     if (!contractsToUpdate.isEmpty()) {
        //         update contractsToUpdate;
        //     }
            
        //     List<Opportunity> opportunitiesToUpdate = new List<Opportunity>();
        //     List<Quote> quotesToUpdate = new List<Quote>();
            
        //     for (Opportunity opp : opportunities) {
        //         Contract linkedContract = contractByOpportunityId.get(opp.Id);
        //         if (linkedContract == null || linkedContract.Id == null) {
        //             continue;
        //         }
                
        //         if (opp.ContractId != linkedContract.Id) {
        //             opportunitiesToUpdate.add(new Opportunity(
        //                 Id = opp.Id,
        //             ContractId = linkedContract.Id
        //                 ));
        //         }
                
        //         Quote selectedQuote = null;
        //         if (opp.SyncedQuoteId != null && quoteById.containsKey(opp.SyncedQuoteId)) {
        //             selectedQuote = quoteById.get(opp.SyncedQuoteId);
        //         } else {
        //             selectedQuote = latestQuoteByOpportunity.get(opp.Id);
        //         }
        //         if (selectedQuote != null) {
        //             quotesToUpdate.add(new Quote(
        //                 Id = selectedQuote.Id,
        //             ContractId = linkedContract.Id
        //                 ));
        //         }
        //     }
            
        //     if (!opportunitiesToUpdate.isEmpty()) {
        //         update opportunitiesToUpdate;
        //     }
        //     if (!quotesToUpdate.isEmpty()) {
        //         update quotesToUpdate;
        //     }
        // }
    }