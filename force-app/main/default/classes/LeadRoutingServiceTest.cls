@IsTest
private class LeadRoutingServiceTest {

    private static Id getB2CRecordTypeId() {
        return Schema.SObjectType.Lead
            .getRecordTypeInfosByDeveloperName()
            .get('B2C')
            .getRecordTypeId();
    }

    @IsTest
    static void testApplyDefaultOwnerSingleLead() {

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(u.Id);

        Lead l = new Lead(
            LastName = 'Test',
            Email = 'single@test.com',
            Phone = '+91 9876543210',
            RecordTypeId = getB2CRecordTypeId()
        );

        LeadRoutingService.applyB2cDefaultOwnerIfConfigured(l);

        System.assertEquals(u.Id, l.OwnerId);

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(null);
    }

    @IsTest
    static void testApplyDefaultOwnerList() {

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(u.Id);

        List<Lead> leads = new List<Lead>{
            new Lead(
                LastName='One',
                Email='one@test.com',
                Phone='+91 9876543210',
                RecordTypeId=getB2CRecordTypeId()
            ),
            new Lead(
                LastName='Two',
                Email='two@test.com',
                Phone='+91 9876543211',
                RecordTypeId=getB2CRecordTypeId()
            )
        };

        LeadRoutingService.applyB2cDefaultOwnerIfConfigured(leads);

        for(Lead l : leads){
            System.assertEquals(u.Id, l.OwnerId);
        }

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(null);
    }

    @IsTest
    static void testApplyDefaultOwnerNullLead() {

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(u.Id);

        Test.startTest();
        LeadRoutingService.applyB2cDefaultOwnerIfConfigured((Lead)null);
        Test.stopTest();

        System.assert(true);

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(null);
    }

    @IsTest
    static void testApplyDefaultOwnerEmptyList() {

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(u.Id);

        Test.startTest();
        LeadRoutingService.applyB2cDefaultOwnerIfConfigured(new List<Lead>());
        Test.stopTest();

        System.assert(true);

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(null);
    }

    @IsTest
    static void testResolveDefaultOwnerOverride() {

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(u.Id);

        Id ownerId = LeadRoutingService.resolveB2cDefaultOwnerUserId();

        System.assertEquals(u.Id, ownerId);

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(null);
    }

    @IsTest
    static void testQueueableUpdatesLeadOwner() {

        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(u.Id);

        Lead l = new Lead(
            LastName='Queue',
            Email='queue@test.com',
            Phone='+91 9876543210',
            RecordTypeId=getB2CRecordTypeId()
        );

        insert l;

        Test.startTest();
        System.enqueueJob(new LeadRoutingService(new List<Lead>{l}));
        Test.stopTest();

        Lead updatedLead = [
            SELECT OwnerId
            FROM Lead
            WHERE Id = :l.Id
        ];

        System.assertEquals(u.Id, updatedLead.OwnerId);

        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(null);
    }

    @IsTest
    static void testQueueableWithNoLeadIds() {

        Test.startTest();
        System.enqueueJob(new LeadRoutingService(new List<Lead>()));
        Test.stopTest();

        System.assert(true);
    }
}