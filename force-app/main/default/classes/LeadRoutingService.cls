/**
 * Assigns the default B2C lead owner user on insert using {@code Lead_Routing_Defaults__mdt} (DeveloperName {@code Default}).
 * <p>
 * Declared {@code without sharing} so Experience Cloud guest (program registration, public APIs) can resolve the configured internal
 * {@code User} even though guests cannot read User rows under normal sharing. When a User row is visible, only active users are used;
 * when the query returns no rows (invisible user), the metadata Id is still applied and Lead DML enforces assignability.
 * <p>
 * {@code LeadTrigger} calls {@link #applyB2cDefaultOwnerIfConfigured(List)} on before insert. {@link LeadTriggerHelper#updateStudentOwnerRole}
 * (if enabled) runs after and may replace owner for guest submissions with the Student Counsellor user.
 *
 * @see Lead_Routing_Defaults__mdt
 * @see LeadProgramQueueSharingService
 * @see SPJIMRUtility
 */
public without sharing class LeadRoutingService {
    private static final String B2C_RECORD_TYPE_DEVELOPER_NAME = 'B2C';
    private static final String DEFAULT_ROUTING_ROW = 'Default';
    private static final String excludeStatus = 'Raw Data';
    @TestVisible
    private static Id testB2cDefaultOwnerUserIdOverride;

    /**
     * Sets {@code OwnerId} on a single new B2C lead when metadata (or test override) supplies a valid active user Id.
     *
     * @param leadRecord In-memory lead before insert; mutated when applicable.
     */
    public static void applyB2cDefaultOwnerIfConfigured(Lead leadRecord) {
        if (leadRecord != null && leadRecord.Id == null && isB2cRecordType(leadRecord.RecordTypeId)
            && leadRecord.Status !=excludeStatus) {
            Id ownerUserId = resolveB2cDefaultOwnerUserId();
            if (ownerUserId != null) {
                leadRecord.OwnerId = ownerUserId;
            }
        }
    }

    /**
     * Sets {@code OwnerId} on each new B2C lead in the list; resolves the user Id once per call.
     *
     * @param leads Leads about to be upserted or inserted (only rows with {@code Id == null} and B2C RT are updated).
     */
    public static void applyB2cDefaultOwnerIfConfigured(List<Lead> leads) {
        if (leads != null && !leads.isEmpty()) {
            Id ownerUserId = resolveB2cDefaultOwnerUserId();
            if (ownerUserId != null) {
                for (Lead l : leads) {
                    if (l != null && l.Id == null && isB2cRecordType(l.RecordTypeId) 
                    && l.Status!=excludeStatus) {
                        l.OwnerId = ownerUserId;
                    }
                }
            }
        }
    }

    /**
     * Returns the B2C default owner user Id from test override, custom metadata, and user validation.
     *
     * @return Active {@code User} Id, or null if not configured or invalid.
     */
    public static Id resolveB2cDefaultOwnerUserId() {
        Id result = null;
        if (Test.isRunningTest() && testB2cDefaultOwnerUserIdOverride != null) {
            result = testB2cDefaultOwnerUserIdOverride;
        } else {
            Lead_Routing_Defaults__mdt row = Lead_Routing_Defaults__mdt.getInstance(DEFAULT_ROUTING_ROW);
            if (row != null) {
                result = parseActiveUserId(row.B2C_Lead_Owner_User_Id__c);
            }
        }
        return result;
    }

    /**
     * Test-only: bypasses metadata and returns this Id from {@link #resolveB2cDefaultOwnerUserId}.
     *
     * @param userId B2C default owner user Id for tests, or null to clear.
     */
    @TestVisible
    static void setTestB2cDefaultOwnerUserIdOverride(Id userId) {
        testB2cDefaultOwnerUserIdOverride = userId;
    }

    /**
     * True when {@code recordTypeId} is the Lead B2C record type.
     *
     * @param recordTypeId Lead {@code RecordTypeId} (may be null).
     * @return Whether the developer name matches {@code B2C}.
     */
    private static Boolean isB2cRecordType(Id recordTypeId) {
        Boolean isB2c = false;
        if (recordTypeId != null) {
            Map<String, Schema.RecordTypeInfo> rti = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
            if (rti.containsKey(B2C_RECORD_TYPE_DEVELOPER_NAME)) {
                isB2c = recordTypeId == rti.get(B2C_RECORD_TYPE_DEVELOPER_NAME).getRecordTypeId();
            }
        }
        return isB2c;
    }

    /**
     * Resolves {@code B2C_Lead_Owner_User_Id__c} to a {@code User} Id for {@code Lead.OwnerId}.
     * Prefers an active user when the row is queryable; if the running user cannot see the User (typical for site guests), returns the
     * parsed Id so assignment can still succeed when the platform allows it.
     *
     * @param raw Value from {@code B2C_Lead_Owner_User_Id__c}.
     * @return User Id to assign, or null if the value is not a User Id.
     */
    private static Id parseActiveUserId(String raw) {
        Id candidate = SPJIMRUtility.parseSalesforceId(raw);
        if (candidate == null) {
            return null;
        }
        if (candidate.getSObjectType() != User.SObjectType) {
            return null;
        }
        try {
            List<User> users = [
                SELECT Id, IsActive
                FROM User
                WHERE Id = :candidate
                LIMIT 1
            ];
            if (!users.isEmpty()) {
                return users[0].IsActive ? users[0].Id : null;
            }
        } catch (Exception e) {
            return candidate;
        }
        return candidate;
    }
}