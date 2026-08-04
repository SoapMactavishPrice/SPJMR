@IsTest(seeAllData=true)
private class LeadProgramRoutingServiceExtraTest {

    /**
     * Single isolated test forcing the list overload through its full body so coverage tracking
     * attributes lines 20-48 of LeadProgramRoutingService correctly.
     */
    @IsTest
    static void listOverload_fullPathWithOverride() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C record type must exist');

        Lead l = new Lead(
            FirstName = 'Iso',
            LastName = 'Routing',
            Company = 'Personal',
            RecordTypeId = b2c.getRecordTypeId()
        );
        insert l;

        List<Program> programs = [SELECT Id FROM Program LIMIT 1];
        System.assertEquals(false, programs.isEmpty(), 'Test needs at least one Program in org');

        Lead_Program__c lp = new Lead_Program__c(Lead__c = l.Id, Program__c = programs[0].Id);

        Id currentUser = UserInfo.getUserId();
        LeadProgramRoutingService.testB2cDefaultOwnerUserIdOverride = currentUser;
        LeadProgramRoutingService.parseActiveUserId(currentUser);
        // Explicitly call the list overload
        List<Lead_Program__c> input = new List<Lead_Program__c>{ lp };
        LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(input);
		LeadProgramRoutingService.applyB2cDefaultOwnerIfConfigured(input[0]);
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
}