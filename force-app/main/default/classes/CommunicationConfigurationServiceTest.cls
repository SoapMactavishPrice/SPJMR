@isTest
private class CommunicationConfigurationServiceTest {

    @isTest
    static void testGetConfigurationReturnsMatchingRecordForKnownProgramAndScenario() {
        CommunicationConfiguration__mdt configuration =
            CommunicationConfigurationService.getConfiguration(
                'PGPM',
                CommunicationsController.CommunicationScenario.OFFER_ACCEPTED
            );

        System.assertNotEquals(
            null,
            configuration,
            'Expected a configuration record to be returned.'
        );
        System.assertEquals('PGPM', configuration.ProgramCode__c);
        System.assertEquals('OFFER_ACCEPTED', configuration.Scenario__c);
    }

    @isTest
    static void testGetConfigurationReturnsMatchingRecordForDifferentProgramAndScenario() {
        CommunicationConfiguration__mdt configuration =
            CommunicationConfigurationService.getConfiguration(
                'GMP',
                CommunicationsController.CommunicationScenario.INTERVIEW_SCHEDULED
            );

        System.assertNotEquals(
            null,
            configuration,
            'Expected a configuration record to be returned.'
        );
        System.assertEquals('GMP', configuration.ProgramCode__c);
        System.assertEquals('INTERVIEW_SCHEDULED', configuration.Scenario__c);
    }

    @isTest
    static void testGetConfigurationThrowsWhenProgramCodeDoesNotExist() {
        Boolean exceptionThrown = false;

        try {
            CommunicationConfigurationService.getConfiguration(
                'DOES_NOT_EXIST',
                CommunicationsController.CommunicationScenario.OFFER_ACCEPTED
            );
        } catch (CommunicationConfigurationService.CommunicationConfigurationException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('DOES_NOT_EXIST'),
                'Expected the exception message to reference the missing ' +
                'Program Code, got: ' + e.getMessage()
            );
            System.assert(
                e.getMessage().contains('OFFER_ACCEPTED'),
                'Expected the exception message to reference the Scenario, ' +
                'got: ' + e.getMessage()
            );
        }

        System.assert(
            exceptionThrown,
            'Expected a CommunicationConfigurationException when no ' +
            'configuration matches the given Program Code.'
        );
    }

    @isTest
    static void testGetConfigurationThrowsWhenScenarioHasNoConfigurationForProgram() {
        // GMP only has configuration records for INTERVIEW_SCHEDULED and
        // OFFER_AVAILABLE, so GMP + OFFER_ACCEPTED is a valid enum value
        // with no matching CMDT record - a genuine "found program, wrong
        // scenario" case, as opposed to an entirely unknown program code.
        Boolean exceptionThrown = false;

        try {
            CommunicationConfigurationService.getConfiguration(
                'GMP',
                CommunicationsController.CommunicationScenario.OFFER_ACCEPTED
            );
        } catch (CommunicationConfigurationService.CommunicationConfigurationException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('GMP'),
                'Expected the exception message to reference the Program ' +
                'Code, got: ' + e.getMessage()
            );
        }

        System.assert(
            exceptionThrown,
            'Expected a CommunicationConfigurationException when the ' +
            'Program Code is known but has no configuration for the given ' +
            'Scenario.'
        );
    }

    @isTest
    static void testGetConfigurationThrowsWhenProgramCodeIsNull() {
        Boolean exceptionThrown = false;

        try {
            CommunicationConfigurationService.getConfiguration(
                null,
                CommunicationsController.CommunicationScenario.OFFER_ACCEPTED
            );
        } catch (CommunicationConfigurationService.CommunicationConfigurationException e) {
            exceptionThrown = true;
        }

        System.assert(
            exceptionThrown,
            'Expected a CommunicationConfigurationException when ' +
            'programCode is null, since a null bind should not match any ' +
            'configuration record.'
        );
    }
}