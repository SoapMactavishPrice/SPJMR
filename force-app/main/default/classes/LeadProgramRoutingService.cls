public without sharing class LeadProgramRoutingService {
private static final String B2C_RECORD_TYPE_DEVELOPER_NAME = 'B2C';
private static final String DEFAULT_ROUTING_ROW = 'Default';
private static final String excludeStatus = 'Raw Data';    
    @TestVisible
    private static Id testB2cDefaultOwnerUserIdOverride;
    
    public static void applyB2cDefaultOwnerIfConfigured(Lead_Program__c leadProgramRecord) {
        if (leadProgramRecord != null && leadProgramRecord.Id == null  
        && leadProgramRecord.Lead_Source__c !=excludeStatus) {
            Id ownerUserId = resolveLeadProgramOwnerId();
            if (ownerUserId != null) {
                leadProgramRecord.OwnerId = ownerUserId;
            }
        }
    }
    
    public static void applyB2cDefaultOwnerIfConfigured(List<Lead_Program__c> leadPrograms) {
        if (leadPrograms != null && !leadPrograms.isEmpty()) {
            /*Filter out B2C Leads only*/
            Id b2cRecordTypeId = Schema.SobjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();
            Set<Id> LeadIds = new Set<Id>();
            for (Lead_Program__c l : leadPrograms) {
                LeadIds.add(l.Lead__c);
            }
            Set<Id> b2cLeadIds = new Set<Id>();
             for (Lead l : [
                    SELECT Id
                    FROM Lead
                    WHERE Id IN :leadIds
                    AND Status != :excludeStatus
                    AND RecordTypeId = :b2cRecordTypeId
                ]) {
                    b2cLeadIds.add(l.Id);
                }
            if(b2cLeadIds.isEmpty()) return;
            List<Lead_Program__c> filteredLeadPrograms = new List<Lead_Program__c>();
            for (Lead_Program__c lp : leadPrograms) {
                if (b2cLeadIds.contains(lp.Lead__c)) {
                    filteredLeadPrograms.add(lp);
                }
            }
            Id ownerUserId = resolveLeadProgramOwnerId();
            if (ownerUserId != null) {
                for (Lead_Program__c l : leadPrograms) {
                    if (l != null && l.Id == null) {
                        l.OwnerId = ownerUserId;
                    }
                }
            }
        }
    }
    
    public static Id resolveLeadProgramOwnerId() {
        Id result = null;
        if (Test.isRunningTest() && testB2cDefaultOwnerUserIdOverride != null) {
            result = testB2cDefaultOwnerUserIdOverride;
        } else {
            Lead_Routing_Defaults__mdt row = Lead_Routing_Defaults__mdt.getInstance(DEFAULT_ROUTING_ROW);
            if (row != null) {
                result = parseActiveUserId(row.B2C_Lead_Program_Default_Owner__c);
            }
        }
        return result;
    }
    
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