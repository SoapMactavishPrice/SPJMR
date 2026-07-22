@IsTest
private class ProgramRegLocationServiceTest {
    @IsTest
    static void allLookups() {
        System.assertNotEquals(null, ProgramRegistrationLocationService.getCountries());
        System.assertNotEquals(null, ProgramRegistrationLocationService.getStatesByCountry(null));
        System.assertNotEquals(null, ProgramRegistrationLocationService.getStatesByCountry(''));
        System.assertNotEquals(null, ProgramRegistrationLocationService.getCitiesByState(null));
        System.assertNotEquals(null, ProgramRegistrationLocationService.getCitiesByState(''));
        Id fake = UserInfo.getOrganizationId();
        try {
            ProgramRegistrationLocationService.getStatesByCountry(String.valueOf(fake));
            ProgramRegistrationLocationService.getCitiesByState(String.valueOf(fake));
        } catch (Exception e) {}
    }
}