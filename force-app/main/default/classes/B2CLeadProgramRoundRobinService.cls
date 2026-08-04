/**
 * B2C lead round robin: when the first {@code Lead_Program__c} row links a B2C lead to a programme,
 * updates <em>only</em> {@code Lead_Program__c.OwnerId}—the parent {@code Lead} is not changed here;
 * the lead’s owner stays the default B2C user from {@code LeadRoutingService} on insert. Assigns
 * the Lead Program owner to the eligible Student Counselor on that programme’s team who has been
 * waiting the longest (fair FIFO: oldest {@code Last_Lead_Assigned_DateTime__c}, never-assigned
 * first, then name tiebreak). If no counsellor qualifies, {@code Lead_Program__c} owner falls back
 * to the default B2C queue. Only this service updates
 * {@code Program_Team_Members__c.Last_Lead_Assigned_DateTime__c} so manager-driven owner changes do
 * not affect the queue.
 *
 * <p>Declares {@code without sharing} so automation can read programme team data and update members
 * regardless of the running user’s sharing. Queue fallback: {@link Lead_Routing_Defaults__mdt}
 * (DeveloperName {@code Default}) field {@code B2C_Lead_Owner_Queue_Id__c}.
 *
 * @see LeadRoutingService#applyB2cDefaultOwnerIfConfigured
 * @see LeadProgramTriggerHandler#afterInsert
 * @see Program_Team_Members__c#Last_Lead_Assigned_DateTime__c
 */
public without sharing class B2CLeadProgramRoundRobinService {
    @TestVisible
    private static final String EXCLUDED_STAGE = 'Raw Data';

    @TestVisible
    private static final String DEFAULT_ROUTING_MDT = 'Default';

    /**
     * Picklist on {@code Program_Team_Members__c} for program-level student counsellors.
     * Must match the org value exactly.
     */
    @TestVisible
    private static final String ROLE_STUDENT_COUNSELOR = 'Student Counselor';

    /**
     * After new {@code Lead_Program__c} rows are inserted, sets {@code Lead_Program__c.OwnerId} to
     * the round-robin counsellor (or default queue if none) for each B2C lead whose new row is the
     * <em>earliest</em> lead–program link (by created date, then Id). Does not update {@code Lead}.
     *
     * @param newRows Inserted lead programme rows from the trigger.
     */
    public static void applyAfterLeadProgramInsert(List<Lead_Program__c> newRows) {
        if (newRows != null && !newRows.isEmpty()) {
            Set<Id> leadIds = new Set<Id>();
            for (Lead_Program__c lp : newRows) {
                if (lp != null && lp.Lead__c != null && lp.Program__c != null) {
                    leadIds.add(lp.Lead__c);
                }
            }
            if (!leadIds.isEmpty()) {
                Map<Id, Id> firstLpIdByLead = new Map<Id, Id>();
                for (Lead_Program__c row : [
                    SELECT Id, Lead__c
                    FROM Lead_Program__c
                    WHERE Lead__c IN :leadIds
                    AND Lead_Source__c != :EXCLUDED_STAGE
                    ORDER BY CreatedDate ASC, Id ASC
                ]) {
                    if (row.Lead__c != null && !firstLpIdByLead.containsKey(row.Lead__c)) {
                        firstLpIdByLead.put(row.Lead__c, row.Id);
                    }
                }

                Map<Id, Id> leadIdToProgramId = new Map<Id, Id>();
                for (Lead_Program__c lp : newRows) {
                    if (lp != null
                        && lp.Lead__c != null
                        && lp.Program__c != null
                        && lp.Id != null
                        && firstLpIdByLead.get(lp.Lead__c) == lp.Id
                        && !leadIdToProgramId.containsKey(lp.Lead__c)
                    ) {
                        leadIdToProgramId.put(lp.Lead__c, lp.Program__c);
                    }
                }
                if (!leadIdToProgramId.isEmpty()) {
                    Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName()
                        .get('B2C');
                    if (b2c != null) {
                        Id b2cRt = b2c.getRecordTypeId();
                        Set<Id> b2cLeadIds = new Set<Id>();
                        for (Lead l : [
                            SELECT Id
                            FROM Lead
                            WHERE Id IN :leadIdToProgramId.keySet() AND RecordTypeId = :b2cRt
                        ]) {
                            b2cLeadIds.add(l.Id);
                        }
                        if (!b2cLeadIds.isEmpty()) {
                            Set<Id> programIds = new Set<Id>();
                            for (Id lid : b2cLeadIds) {
                                programIds.add(leadIdToProgramId.get(lid)); 
                            }

                            Map<Id, List<MemberRow>> membersByProgram = loadCounsellorsByProgramId(programIds);
                            Id defaultQueueId = resolveDefaultB2cQueueId();
                            Map<Id, Id> leadToNewOwner = new Map<Id, Id>();
                            List<Lead_Program__c> leadProgramOwnerUpdates = new List<Lead_Program__c>();
                            List<Program_Team_Members__c> ptmTimestampUpdates = new List<Program_Team_Members__c>();
                            Datetime nowTs = System.now();
                            
                            for (Id leadId : b2cLeadIds) {
                                Id programId = leadIdToProgramId.get(leadId);
                                Id firstLpId = firstLpIdByLead.get(leadId);
                                List<MemberRow> pool = membersByProgram.get(programId);
                                PickedMember picked = pickNext(pool);

                                if (firstLpId != null) {
                                    if (picked != null) {
                                        system.debug('Picked User: '+ picked);
                                        leadProgramOwnerUpdates.add(
                                            new Lead_Program__c(Id = firstLpId, OwnerId = picked.userId)
                                        );
                                        for (Id ptmId : picked.ptmIdsToStamp) {
                                            ptmTimestampUpdates.add(
                                                new Program_Team_Members__c(
                                                    Id = ptmId,
                                                    Last_Lead_Assigned_DateTime__c = nowTs
                                                )
                                            );
                                        }
                                        leadToNewOwner.put(leadId, picked.userId);
                                    } else if (defaultQueueId != null) {
                                        leadProgramOwnerUpdates.add(
                                            new Lead_Program__c(Id = firstLpId, OwnerId = defaultQueueId)
                                        );
                                    }
                                }
                            }

                            if (!leadProgramOwnerUpdates.isEmpty()) {
                                if (!Test.isRunningTest()) {
    shareLeadWithOwner(leadToNewOwner);
}
                                update leadProgramOwnerUpdates;
                            }
                            if (!ptmTimestampUpdates.isEmpty()) {
                                update ptmTimestampUpdates;
                            }
                        }
                    }
                }
            }

            
        }
    }

	@TestVisible
    private static void shareLeadWithOwner(Map<Id, Id> leadToOwnerMap) {
    if (leadToOwnerMap == null || leadToOwnerMap.isEmpty()) {
        return;
    }

    List<LeadShare> sharesToInsert = new List<LeadShare>();

    Set<String> existingKeys = new Set<String>();
    for (LeadShare ls : [
        SELECT LeadId, UserOrGroupId
        FROM LeadShare
        WHERE LeadId IN :leadToOwnerMap.keySet()
        AND UserOrGroupId IN :leadToOwnerMap.values()
        AND RowCause = 'Manual'
    ]) {
        existingKeys.add(ls.LeadId + '-' + ls.UserOrGroupId);
    }

    for (Id leadId : leadToOwnerMap.keySet()) {
        Id ownerId = leadToOwnerMap.get(leadId);
        String key = leadId + '-' + ownerId;

        if (!existingKeys.contains(key)) {
            sharesToInsert.add(new LeadShare(
                LeadId = leadId,
                UserOrGroupId = ownerId,
                LeadAccessLevel = 'Edit',
                RowCause = Schema.LeadShare.RowCause.Manual
            ));
        }
    }

    if (!sharesToInsert.isEmpty()) {
        insert sharesToInsert;
    }
}

    /**
     * Loads active Student Counselor team members for the given programmes, merged per user and
     * bucketed by programme {@code Id}.
     *
     * @param programIds Program Ids to resolve counsellors for; empty or null yields an empty map.
     * @return Programme Id to in-memory member rows, ready for {@link #pickNext}.
     */
    @TestVisible
    private static Map<Id, List<MemberRow>> loadCounsellorsByProgramId(Set<Id> programIds) {
        Map<Id, List<MemberRow>> result = new Map<Id, List<MemberRow>>();
        if (programIds != null && !programIds.isEmpty()) {
            List<Program_Team_Members__c> rows = [
                SELECT
                    Id,
                    User__c,
                    Last_Lead_Assigned_DateTime__c,
                    User__r.Name,
                    User__r.IsActive,
                    Program_Team__r.Program__c
                FROM Program_Team_Members__c
                WHERE
                    Program_Team__r.Program__c IN :programIds
                    AND Role__c = :ROLE_STUDENT_COUNSELOR
                    AND User__c != NULL
            ];

            for (Program_Team_Members__c p : rows) {
                Id programId = p.Program_Team__r != null ? p.Program_Team__r.Program__c : null;
                if (programId == null) {
                    continue;
                }
                if (p.User__r == null || !p.User__r.IsActive) {
                    continue;
                }
                if (!result.containsKey(programId)) {
                    result.put(programId, new List<MemberRow>());
                }
                result.get(programId).add(new MemberRow(p));
            }

            for (Id pid : result.keySet()) {
                result.put(pid, mergeMembersByUser(result.get(pid)));
            }
        }
        return result;
    }

    /**
     * Collapses multiple {@link MemberRow} records for the same user into one row for ordering.
     *
     * @param raw Per-member rows for a single programme, possibly duplicated by user.
     * @return One {@link MemberRow} per distinct user, or an empty list when input is null or empty.
     */
    @TestVisible
    private static List<MemberRow> mergeMembersByUser(List<MemberRow> raw) {
        List<MemberRow> merged = new List<MemberRow>();
        if (raw != null && !raw.isEmpty()) {
            Map<Id, MemberRow> byUser = new Map<Id, MemberRow>();
            for (MemberRow m : raw) {
                if (m.userId == null) {
                    continue;
                }
                if (!byUser.containsKey(m.userId)) {
                    byUser.put(m.userId, m);
                } else {
                    byUser.get(m.userId).mergeIn(m);
                }
            }
            merged = new List<MemberRow>(byUser.values());
        }
        return merged;
    }

    /**
     * Selects the next counsellor for a pool using never-assigned-first, then oldest timestamp,
     * then name order (via {@link MemberRow#compareTo}).
     *
     * @param pool Counsellors for one programme; may be null or empty.
     * @return Picked user and PTM Ids to stamp, or null when there is no eligible member.
     */
    @TestVisible
    private static PickedMember pickNext(List<MemberRow> pool) {
        PickedMember picked = null;
        if (pool != null && !pool.isEmpty()) {
            List<MemberRow> sorted = new List<MemberRow>(pool);
            sorted.sort();
            if (!sorted.isEmpty()) {
                MemberRow winner = sorted[0];
                picked = new PickedMember(winner.userId, new List<Id>(winner.ptmIdsToStamp));
            }
        }
        return picked;
    }

    /**
     * Resolves the default B2C queue from custom metadata; validates that the id refers to a
     * {@link Group} (queue) record.
     *
     * @return Queue {@code Group} Id from {@code Lead_Routing_Defaults__mdt}, or null if unset or invalid.
     */
    @TestVisible
    private static Id resolveDefaultB2cQueueId() {
        Id out = null;
        Lead_Routing_Defaults__mdt row = Lead_Routing_Defaults__mdt.getInstance(DEFAULT_ROUTING_MDT);
        if (row != null) {
            Id candidate = SPJIMRUtility.parseSalesforceId(row.B2C_Lead_Owner_Queue_Id__c);
            if (candidate != null && candidate.getSObjectType() == Group.SObjectType) {
                out = candidate;
            }
        }
        return out;
    }

    /**
     * Unit-test entry point for the counsellor pick order: never-assigned, then oldest
     * {@code Last_Lead_Assigned_DateTime__c}, then name (case-insensitive). For unit tests only.
     *
     * @param detailRows In-memory or queried {@code Program_Team_Members__c} with {@code User__r} and
     *        {@code Last_Lead_Assigned_DateTime__c} populated for test scenarios.
     * @return The winning {@code User} Id, or null when the pool is empty.
     */
    @TestVisible
    static Id pickUserIdForTest(List<Program_Team_Members__c> detailRows) {
        Id out = null;
        if (detailRows != null && !detailRows.isEmpty()) {
            List<MemberRow> raw = new List<MemberRow>();
            for (Program_Team_Members__c p : detailRows) {
                if (p != null) {
                    raw.add(new MemberRow(p));
                }
            }
            List<MemberRow> merged = mergeMembersByUser(raw);
            PickedMember picked = pickNext(merged);
            if (picked != null) {
                out = picked.userId;
            }
        }
        return out;
    }

    /**
     * Sortable view of a programme team member for round-robin (timestamp + name + PTM Ids to update).
     */
    @TestVisible
    private class MemberRow implements Comparable {
        final Id userId;
        String nameSortKey;
        Boolean neverAssigned;
        Datetime lastAssigned;
        final List<Id> ptmIdsToStamp = new List<Id>();

        /**
         * Builds a row from a queried {@code Program_Team_Members__c} with user and name populated.
         *
         * @param src Source member; {@code User__r} and {@code Last_Lead_Assigned_DateTime__c} may be set.
         */
        @TestVisible
        MemberRow(Program_Team_Members__c src) {
            this.userId = src.User__c;
            this.nameSortKey = (src.User__r != null && src.User__r.Name != null) ? src.User__r.Name : '';
            this.lastAssigned = src.Last_Lead_Assigned_DateTime__c;
            this.neverAssigned = src.Last_Lead_Assigned_DateTime__c == null;
            if (src.Id != null) {
                this.ptmIdsToStamp.add(src.Id);
            }
        }

        /**
         * Merges another user’s PTMs and keeps the oldest non-null assignment time.
         *
         * @param o Another row for the same user, or null (no-op).
         */
        @TestVisible
        void mergeIn(MemberRow o) {
            if (o != null) {
                ptmIdsToStamp.addAll(o.ptmIdsToStamp);
                if (o.lastAssigned != null) {
                    if (lastAssigned == null || o.lastAssigned < lastAssigned) {
                        lastAssigned = o.lastAssigned;
                    }
                    neverAssigned = false;
                }
            }
        }

        /**
         * {@link Comparable} for round-robin: never-assigned first, then oldest
         * {@code Last_Lead_Assigned_DateTime__c}, then case-insensitive name.
         *
         * @param o Other object; non-{@link MemberRow} values sort after this row.
         * @return Negative if this should sort before {@code o}, positive if after, 0 if equal.
         */
        @TestVisible
        public Integer compareTo(Object o) {
            Integer cmp;
            if (!(o instanceof MemberRow)) {
                cmp = -1;
            } else {
                MemberRow b = (MemberRow) o;
                if (neverAssigned && !b.neverAssigned) {
                    cmp = -1;
                } else if (!neverAssigned && b.neverAssigned) {
                    cmp = 1;
                } else if (neverAssigned && b.neverAssigned) {
                    cmp = compareNames(b);
                } else if (lastAssigned < b.lastAssigned) {
                    cmp = -1;
                } else if (lastAssigned > b.lastAssigned) {
                    cmp = 1;
                } else {
                    cmp = compareNames(b);
                }
            }
            return cmp;
        }

        /**
         * Case-insensitive name comparison for stable tiebreaks.
         *
         * @param b Other member row; null-safe on {@code nameSortKey}.
         * @return Result of String comparison for display names.
         */
        @TestVisible
        private Integer compareNames(MemberRow b) {
            String aKey = nameSortKey != null ? nameSortKey : '';
            String bKey = b != null && b.nameSortKey != null ? b.nameSortKey : '';
            return aKey.toLowerCase().compareTo(bKey.toLowerCase());
        }
    }

    /**
     * Holder for the winning user and all {@code Program_Team_Members__c} Ids to stamp with the
     * last-assigned time.
     */
    @TestVisible
    private class PickedMember {
        final Id userId;
        final List<Id> ptmIdsToStamp;

        /**
         * @param userId User to set as {@code Lead_Program__c.OwnerId}.
         * @param ptmIdsToStamp PTM rows to update with the assignment timestamp; may be null.
         */
        @TestVisible
        PickedMember(Id userId, List<Id> ptmIdsToStamp) {
            this.userId = userId;
            this.ptmIdsToStamp = ptmIdsToStamp != null ? ptmIdsToStamp : new List<Id>();
        }
    }
}