@IsTest
private class ProgramRegistrationLocationServiceTest {

    @testSetup
    static void setup() {

        Country_Master__c country = new Country_Master__c(
            Name = 'India',
            Country_Code__c = '+91',
            AcceptedNumberLength__c = '10'
        );
        insert country;

        State__c state = new State__c(
            Name = 'Kerala',
            Country_Master__c = country.Id
        );
        insert state;

        City__c city = new City__c(
            Name = 'Kochi',
            State__c = state.Id,
            CityCode__c = '23'
        );
        insert city;
    }

    private static Country_Master__c getCountry() {
        return [
            SELECT Id, Name
            FROM Country_Master__c
            LIMIT 1
        ];
    }

    private static State__c getState() {
        return [
            SELECT Id, Name
            FROM State__c
            LIMIT 1
        ];
    }

    @IsTest
    static void getCountriesReturnsListOfValueLabelPairs() {

        Test.startTest();
        List<Map<String,String>> result =
            ProgramRegistrationLocationService.getCountries();
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('India', result[0].get('label'));
        System.assert(result[0].containsKey('value'));
    }

    @IsTest
    static void getStatesByCountryBlankReturnsEmpty() {

        System.assertEquals(
            0,
            ProgramRegistrationLocationService.getStatesByCountry(null).size()
        );

        System.assertEquals(
            0,
            ProgramRegistrationLocationService.getStatesByCountry('').size()
        );

        System.assertEquals(
            0,
            ProgramRegistrationLocationService.getStatesByCountry('   ').size()
        );
    }

    @IsTest
    static void getStatesByCountryReturnsForExistingCountry() {

        Test.startTest();

        List<Map<String,String>> result =
            ProgramRegistrationLocationService.getStatesByCountry(
                getCountry().Id
            );

        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('Kerala', result[0].get('label'));
    }

    @IsTest
    static void getCitiesByStateBlankReturnsEmpty() {

        System.assertEquals(
            0,
            ProgramRegistrationLocationService.getCitiesByState(null).size()
        );

        System.assertEquals(
            0,
            ProgramRegistrationLocationService.getCitiesByState('').size()
        );
    }

    @IsTest
    static void getCitiesByStateReturnsForExistingState() {

        Test.startTest();

        List<Map<String,String>> result =
            ProgramRegistrationLocationService.getCitiesByState(
                getState().Id
            );

        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('Kochi', result[0].get('label'));
    }

    @IsTest
    static void resolveCountryIdByNameBlankReturnsNull() {

        System.assertEquals(
            null,
            ProgramRegistrationLocationService.resolveCountryIdByName(null)
        );

        System.assertEquals(
            null,
            ProgramRegistrationLocationService.resolveCountryIdByName('')
        );

        System.assertEquals(
            null,
            ProgramRegistrationLocationService.resolveCountryIdByName('   ')
        );
    }

    @IsTest
    static void resolveCountryIdByNameUnknownReturnsNull() {

        System.assertEquals(
            null,
            ProgramRegistrationLocationService.resolveCountryIdByName('__NO_SUCH_COUNTRY__')
        );
    }

    @IsTest
    static void resolveCountryIdByNameExistingReturnsId() {

        Country_Master__c country = getCountry();

        Test.startTest();

        Id resolved =
            ProgramRegistrationLocationService.resolveCountryIdByName(
                country.Name
            );

        Test.stopTest();

        System.assertEquals(country.Id, resolved);
    }

    @IsTest
    static void getPhoneCountryOptionsBuildsDialAndLabels() {

        Test.startTest();

        List<Map<String,String>> opts =
            ProgramRegistrationLocationService.getPhoneCountryOptions();

        Test.stopTest();

        System.assertEquals(1, opts.size());

        System.assertEquals(
            '(+91) India',
            opts[0].get('label')
        );

        System.assertEquals(
            '+91',
            opts[0].get('value')
        );

        System.assertEquals(
            getCountry().Id,
            opts[0].get('countryMasterId')
        );
    }
}