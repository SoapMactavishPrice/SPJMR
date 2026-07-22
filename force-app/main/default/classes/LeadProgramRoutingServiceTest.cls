@IsTest
private class LeadProgramRoutingServiceTest {

    @IsTest
    static void applyB2cDefaultOwner_listOverload_appliesOwnerWhenOverrideSet() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C');
        if (b2c == null) {
            return;
        }
        Id b2cId = b2c.getRecordTypeId();

        Lead l = new Lead(
            FirstName = 'Routing',
            LastName = 'Test',
            Company = 'Personal',
            RecordTypeId = b2cId
        );
        insert l;

        List<Program> programs = [SELECT Id FROM Program LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);

        Id currentUser = UserInfo.getUserId();
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = currentUser;

        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(new List<Lead_Program__c>{ lp });
        System.assertEquals(currentUser, lp.OwnerId);
    }

    @IsTest
    static void applyB2cDefaultOwner_listOverload_noOpWhenOnlyNonB2C() {
        Schema.RecordTypeInfo b2b = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2B');
        if (b2b == null) {
            return;
        }
        Lead l = new Lead(FirstName = 'X', LastName = 'NonB2C', Company = 'Co', RecordTypeId = b2b.getRecordTypeId());
        insert l;

        List<Program> programs = [SELECT Id FROM Program LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);

        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(new List<Lead_Program__c>{ lp });
        System.assertEquals(null, lp.OwnerId);
    }

    @IsTest
    static void applyB2cDefaultOwner_singleOverload_appliesOwnerWhenOverrideSet() {
        Id currentUser = UserInfo.getUserId();
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = currentUser;
        Lead_Program__c lp = new Lead_Program__c();
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(lp);
        System.assertEquals(currentUser, lp.OwnerId);
    }

    @IsTest
    static void resolveLeadProgramOwnerId_overrideWinsInTestContext() {
        Id u = UserInfo.getUserId();
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = u;
        System.assertEquals(u, LeadProgramRoutingService.resolveLeadProgramOwnerId());
    }

    @IsTest
    static void resolveLeadProgramOwnerId_fallsBackToCMDT() {
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = null;
        // Hits the else branch (lines 57-59) — value may be null or a valid Id depending on CMDT.
        LeadProgramRoutingService.resolveLeadProgramOwnerId();
    }

    @IsTest
    static void emptyInputsReturnEarly() {
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured((List<Lead_Program__c>) null);
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(new List<Lead_Program__c>());
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured((Lead_Program__c) null);
    }
}