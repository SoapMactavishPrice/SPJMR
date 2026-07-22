@IsTest
private class ProgramConfigServiceTest {
    @IsTest
    static void getConfigPopulatesCacheAndReturnsNullForUnknown() {
        // The cache load runs once. With no matching metadata records, the query returns
        // empty and getConfig returns null for any lookup.
        Program_Object_Config__mdt cfg = ProgramConfigService.getConfig('Unknown_Object__c');
        System.assertEquals(null, cfg);
        // Second call exercises the cached branch.
        Program_Object_Config__mdt cfg2 = ProgramConfigService.getConfig('Unknown_Object__c');
        System.assertEquals(null, cfg2);
    }
}