@IsTest(seeAllData=true)
private class LeadProgramTriggerHandlerTest {

    @IsTest
    static void beforeInsert_delegatesToHelpers() {
        // beforeInsert calls LeadProgramRoutingService + LeadProgramTriggerHelper; with empty list it's a no-op.
        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        h.beforeInsert(new List<Lead_Program__c>());
    }

    @IsTest
    static void beforeUpdate_delegatesToHelper() {
        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        h.beforeUpdate(new List<Lead_Program__c>(), new Map<Id, Lead_Program__c>());
    }

    @IsTest
    static void afterInsert_runsAllBranchesWithRealLeadProgram() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C');
        if (b2c == null) {
            return;
        }
        Lead l = new Lead(
            FirstName = 'LP',
            LastName = 'AfterInsert',
            Company = 'Personal',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert l;
        List<Program> programs = [SELECT Id FROM Program LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);
        insert lp;

        // Directly call afterInsert with the fresh row to exercise the syncB2cLeadProgramCodes branch
        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        h.afterInsert(new List<Lead_Program__c>{ lp }, new Map<Id, Lead_Program__c>{ lp.Id => lp });
    }

    @IsTest
    static void afterUpdate_collectsLeadIdsWhenProgramOrLeadChanges() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C');
        if (b2c == null) {
            return;
        }
        Lead l1 = new Lead(FirstName = 'A', LastName = 'One', Company = 'Personal', RecordTypeId = b2c.getRecordTypeId());
        Lead l2 = new Lead(FirstName = 'B', LastName = 'Two', Company = 'Personal', RecordTypeId = b2c.getRecordTypeId());
        insert new List<Lead>{ l1, l2 };

        List<Program> programs = [SELECT Id FROM Program LIMIT 2];
        if (programs.size() < 1) {
            return;
        }
        Lead_Program__c lp = new Lead_Program__c(Lead__c = l1.Id, Program__c = programs[0].Id);
        insert lp;

        // Construct an "old" version where Lead__c is different so the branch fires
        Lead_Program__c oldLp = lp.clone(true, true, true, true);
        oldLp.Lead__c = l2.Id;
        oldLp.Program__c = programs.size() > 1 ? programs[1].Id : programs[0].Id;

        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        h.afterUpdate(new List<Lead_Program__c>{ lp }, new Map<Id, Lead_Program__c>{ lp.Id => oldLp });
    }

    @IsTest
    static void afterUpdate_noOpWhenOldMissing() {
        // When oldMap doesn't contain the id, the continue branch runs.
        Lead_Program__c lp = new Lead_Program__c();
        lp.Id = Schema.SObjectType.Lead_Program__c.getKeyPrefix() + '000000000001';
        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        h.afterUpdate(new List<Lead_Program__c>{ lp }, new Map<Id, Lead_Program__c>());
    }

    @IsTest
    static void afterDelete_collectsLeadIdsAndSyncs() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C');
        if (b2c == null) {
            return;
        }
        Lead l = new Lead(FirstName = 'D', LastName = 'Del', Company = 'Personal', RecordTypeId = b2c.getRecordTypeId());
        insert l;
        Lead_Program__c lp = new Lead_Program__c();
        lp.Lead__c = l.Id;
        LeadProgramTriggerHandler h = new LeadProgramTriggerHandler();
        h.afterDelete(new List<Lead_Program__c>{ lp });
    }
}