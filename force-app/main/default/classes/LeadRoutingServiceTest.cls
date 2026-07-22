@IsTest
private class LeadRoutingServiceTest {
    @IsTest
    static void applyB2cDefaultOwnerIfConfigured_sets_owner_when_b2c_and_override_user() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required for this test.');

        Id runAsUserId = UserInfo.getUserId();
        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(runAsUserId);
        Lead l = new Lead(
            LastName = 'RoutingTest',
            Company = 'RoutingTest Co',
            RecordTypeId = b2c.getRecordTypeId()
        );

        LeadRoutingService.applyB2cDefaultOwnerIfConfigured(l);

        System.assertEquals(runAsUserId, l.OwnerId, 'B2C insert-row should receive configured default user owner.');
    }

    @IsTest
    static void applyB2cDefaultOwnerIfConfigured_bulk_sets_owner_once_per_batch() {
        Schema.RecordTypeInfo b2c = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C');
        System.assertNotEquals(null, b2c, 'B2C Lead record type required for this test.');
        Id b2cRt = b2c.getRecordTypeId();

        Id runAsUserId = UserInfo.getUserId();
        LeadRoutingService.setTestB2cDefaultOwnerUserIdOverride(runAsUserId);
        List<Lead> leads = new List<Lead>{
            new Lead(LastName = 'A', Company = 'Co', RecordTypeId = b2cRt),
            new Lead(LastName = 'B', Company = 'Co', RecordTypeId = b2cRt)
        };

        LeadRoutingService.applyB2cDefaultOwnerIfConfigured(leads);

        System.assertEquals(runAsUserId, leads[0].OwnerId);
        System.assertEquals(runAsUserId, leads[1].OwnerId);
    }
}