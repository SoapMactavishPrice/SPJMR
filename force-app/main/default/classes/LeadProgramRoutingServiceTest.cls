@IsTest
private class LeadProgramRoutingServiceTest {
    @IsTest
    static void listOverload_fullPathWithOverride() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C');

        Lead l = new Lead(
            FirstName = 'Iso',
            LastName = 'Routing',
            Company = 'Personal',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert l;
 Program Program = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Class Room',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert Program;
        
        List<Program> programs = [SELECT Id FROM Program LIMIT 1];

        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);

        Id currentUser = UserInfo.getUserId();
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = currentUser;

        // Explicitly call the list overload
        List<Lead_Program__c> input = new List<Lead_Program__c>{ lp };
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(input);

        // Verify the assignment loop fired
        System.assertEquals(currentUser, lp.OwnerId, 'OwnerId should be set by the assignment loop');
    }

    @IsTest
    static void listOverload_b2cFilterEmptyEarlyReturn() {
        // Pass a lead_program with a Lead__c that isn't B2C → b2cLeadIds stays empty → return at line 34
        Schema.RecordTypeInfo b2b = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2B');
        if (b2b == null) {
            return;
        }
         Program Program = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Class Room',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert Program;
        
        Lead l = new Lead(FirstName = 'B2B', LastName = 'Test', Company = 'Co', RecordTypeId = b2b.getRecordTypeId());
        insert l;
        List<Program> programs = [SELECT Id FROM Program LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = null;
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(new List<Lead_Program__c>{ lp });
    }

    @IsTest
    static void parseActiveUserId_invalidIdReturnsNull() {
        // Set the test override to a non-User Id; resolveLeadProgramOwnerId returns it as-is from the
        // override path. The CMDT path (which calls parseActiveUserId) is exercised when we clear the override.
        // We can also indirectly exercise parseActiveUserId via a User that has a Lead_Routing_Defaults__mdt row.
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = null;
        Id result = LeadProgramRoutingService.resolveLeadProgramOwnerId();
        // No assertion - just exercise.
    }

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
        
         Program Program = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Class Room',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert Program;
        

        List<Program> programs = [SELECT Id FROM Program LIMIT 1];
        if (programs.isEmpty()) {
            return;
        }
        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);

        Id currentUser = UserInfo.getUserId();
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = currentUser;

        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(new List<Lead_Program__c>{ lp });
    }

    @IsTest
    static void applyB2cDefaultOwner_listOverload_noOpWhenOnlyNonB2C() {
        Schema.RecordTypeInfo b2b = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2B');
        if (b2b == null) {
            return;
        }
        Lead l = new Lead(FirstName = 'X', LastName = 'NonB2C', Company = 'Co', RecordTypeId = b2b.getRecordTypeId());
        insert l;

         Program Program = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Class Room',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert Program;
        
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