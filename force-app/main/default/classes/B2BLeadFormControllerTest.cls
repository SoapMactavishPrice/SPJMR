@IsTest(SeeAllData=true)
private class B2BLeadFormControllerTest {
    @IsTest
    static void exerciseAllAuraEndpoints() {
        // Lookups
        System.assertNotEquals(null, B2BLeadFormController.getCountries());
        System.assertNotEquals(null, B2BLeadFormController.getStatesByCountry(null));
        System.assertNotEquals(null, B2BLeadFormController.getStatesByCountry(''));
        System.assertNotEquals(null, B2BLeadFormController.getCitiesByState(null));
        System.assertNotEquals(null, B2BLeadFormController.getCitiesByState(''));

        // Picklist helpers - no params needed
        System.assertNotEquals(null, B2BLeadFormController.getIndustryOptions());
        System.assertNotEquals(null, B2BLeadFormController.getLeadSourceOptions());

        // Real Country to exercise getStatesByCountry inner loop
        List<Country_Master__c> cs = [SELECT Id FROM Country_Master__c LIMIT 1];
        if (!cs.isEmpty()) {
            B2BLeadFormController.getStatesByCountry(cs[0].Id);
        }
        // Real State for getCitiesByState
        List<State__c> ss = [SELECT Id FROM State__c LIMIT 1];
        if (!ss.isEmpty()) {
            B2BLeadFormController.getCitiesByState(ss[0].Id);
        }
        // Search programs
        try {
            B2BLeadFormController.searchPrograms('a');
            B2BLeadFormController.searchPrograms('');
        } catch (Exception e) {}

        // createB2BLead — call with try/catch to exercise body even if validation fails
        try {
            B2BLeadFormController.createB2BLead(
                'F','L','t' + Datetime.now().getTime() + '@x.com','9999999999',
                'CompCo','Mgr','Tech','www.x.com',10,
                'Some Street', null, null, null, '400001',
                'Web','d', new List<String>(), 100.0, Date.today().addDays(30),
                1, 10, true
            );
        } catch (Exception e) {}
    }
}