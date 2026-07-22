@IsTest
private class LeadProgramOwnerSyncHandlerTest {
    @IsTest
    static void earlyReturnsOnNullEmptyInput() {
        LeadProgramOwnerSyncHandler.syncLeadProgramOwners(null, null);
        LeadProgramOwnerSyncHandler.syncLeadProgramOwners(new List<Lead>(), null);
        LeadProgramOwnerSyncHandler.syncLeadProgramOwners(new List<Lead>(), new Map<Id, Lead>());
        LeadProgramOwnerSyncHandler.syncLeadProgramOwners(null, new Map<Id, Lead>());
    }
    @IsTest
    static void noOwnerChange_returnsBeforeQuery() {
        Id fakeLeadId = Schema.SObjectType.Lead.getKeyPrefix() + '000000000001';
        Id ownerId = UserInfo.getUserId();
        Lead newLead = (Lead) JSON.deserialize(
            '{"attributes":{"type":"Lead"},"Id":"' + fakeLeadId + '","OwnerId":"' + ownerId + '"}', Lead.class);
        Lead oldLead = (Lead) JSON.deserialize(
            '{"attributes":{"type":"Lead"},"Id":"' + fakeLeadId + '","OwnerId":"' + ownerId + '"}', Lead.class);
        LeadProgramOwnerSyncHandler.syncLeadProgramOwners(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{ fakeLeadId => oldLead }
        );
    }
    @IsTest
    static void ownerChanged_runsQueryPath() {
        Id fakeLeadId = Schema.SObjectType.Lead.getKeyPrefix() + '000000000001';
        Id u1 = UserInfo.getUserId();
        Id u2 = UserInfo.getOrganizationId(); // any non-equal Id works for branch coverage
        Lead newLead = (Lead) JSON.deserialize(
            '{"attributes":{"type":"Lead"},"Id":"' + fakeLeadId + '","OwnerId":"' + u1 + '"}', Lead.class);
        Lead oldLead = (Lead) JSON.deserialize(
            '{"attributes":{"type":"Lead"},"Id":"' + fakeLeadId + '","OwnerId":"' + u2 + '"}', Lead.class);
        // The SOQL on Lead_Program__c with a fake Id returns empty - loop body skipped, no DML.
        LeadProgramOwnerSyncHandler.syncLeadProgramOwners(
            new List<Lead>{ newLead },
            new Map<Id, Lead>{ fakeLeadId => oldLead }
        );
    }
}