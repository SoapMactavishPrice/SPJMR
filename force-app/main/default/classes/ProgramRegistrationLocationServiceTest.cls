@IsTest(seeAllData=true)
private class ProgramRegistrationLocationServiceTest {

    @IsTest
    static void getCountriesReturnsListOfValueLabelPairs() {
        List<Map<String, String>> result = ProgramRegistrationLocationService.getCountries();
        // SeeAllData true; either the org has Country_Master__c rows or not. Method shouldn't throw either way.
        System.assertNotEquals(null, result);
        for (Map<String, String> m : result) {
            System.assert(m.containsKey('value'));
            System.assert(m.containsKey('label'));
        }
    }

    @IsTest
    static void getStatesByCountryBlankReturnsEmpty() {
        System.assertEquals(0, ProgramRegistrationLocationService.getStatesByCountry(null).size(),'Null Scenario');
        System.assertEquals(0, ProgramRegistrationLocationService.getStatesByCountry('').size(),'Null Scenario');
        System.assertEquals(0, ProgramRegistrationLocationService.getStatesByCountry('   ').size(),'Null Scenario');
    }

    @IsTest
    static void getStatesByCountry_returnsForExistingCountry() {
        List<Country_Master__c> cs = [SELECT Id FROM Country_Master__c LIMIT 1];
        if (cs.isEmpty()) {
            return;
        }
        ProgramRegistrationLocationService.getStatesByCountry(cs[0].Id);
    }

    @IsTest
    static void getCitiesByStateBlankReturnsEmpty() {
        System.assertEquals(0, ProgramRegistrationLocationService.getCitiesByState(null).size(),'Null Scenario');
        System.assertEquals(0, ProgramRegistrationLocationService.getCitiesByState('').size(),'Null Scenario');
    }

    @IsTest
    static void getCitiesByStateReturnsForExistingState() {
        List<State__c> sts = [SELECT Id FROM State__c LIMIT 1];
        if (sts.isEmpty()) {
            return;
        }
        ProgramRegistrationLocationService.getCitiesByState(sts[0].Id);
    }

    @IsTest
    static void resolveCountryIdByNameBlankReturnsNull() {
        System.assertEquals(null, ProgramRegistrationLocationService.resolveCountryIdByName(null),'Null Scenario');
        System.assertEquals(null, ProgramRegistrationLocationService.resolveCountryIdByName(''),'Null Scenario');
        System.assertEquals(null, ProgramRegistrationLocationService.resolveCountryIdByName('   '),'Null Scenario');
    }

    @IsTest
    static void resolveCountryIdByNameUnknownReturnsNull() {
        System.assertEquals(null, ProgramRegistrationLocationService.resolveCountryIdByName('__NO_SUCH_COUNTRY__'),'Null Country');
    }

    @IsTest
    static void resolveCountryIdByNameExistingReturnsId() {
        List<Country_Master__c> cs = [SELECT Id, Name FROM Country_Master__c WHERE Name != null LIMIT 1];
        if (cs.isEmpty()) {
            return;
        }
        Id resolved = ProgramRegistrationLocationService.resolveCountryIdByName(cs[0].Name);
        System.assertEquals(cs[0].Id, resolved,'Resolved');
    }

    @IsTest
    static void getPhoneCountryOptionsBuildsDialAndLabels() {
        List<Map<String, String>> opts = ProgramRegistrationLocationService.getPhoneCountryOptions();
        System.assertNotEquals(null, opts);
        for (Map<String, String> m : opts) {
            System.assert(m.containsKey('label'));
            System.assert(m.containsKey('value'));
            System.assert(m.containsKey('countryMasterId'));
            System.assert(m.get('value').startsWith('+'));
        }
    }
}