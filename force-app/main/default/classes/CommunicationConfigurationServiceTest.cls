@isTest
private class CommunicationConfigurationServiceTest {

    @testSetup
    static void setup() {

        Map<String, Id> permissionSetIds = new Map<String, Id>();

        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('Admissions_Team')
        ]) {
            permissionSetIds.put(ps.Name, ps.Id);
        }

        User adminUser = [
            SELECT Id
            FROM User
            WHERE Email = 'ramakrishnan@finessedirect.com'
            AND Profile.Name = 'System Administrator'
            LIMIT 1
        ];

        Id admissionsTeamPsId = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Admissions_Team'
            LIMIT 1
        ].Id;

        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :adminUser.Id
            AND PermissionSetId = :admissionsTeamPsId
            LIMIT 1
        ];

        if (existingAssignments.isEmpty()) {
            insert new PermissionSetAssignment(
                AssigneeId = adminUser.Id,
                PermissionSetId = admissionsTeamPsId
            );
        }
    }

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
                'PGPM',
                CommunicationsController.CommunicationScenario.INTERVIEW_SCHEDULED
            );

        System.assertNotEquals(
            null,
            configuration,
            'Expected a configuration record to be returned.'
        );
        System.assertEquals('PGPM', configuration.ProgramCode__c);
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
        // PGPM only has configuration records for INTERVIEW_SCHEDULED and
        // OFFER_AVAILABLE, so GMPM + OFFER_ACCEPTED is a valid enum value
        // with no matching CMDT record - a genuine "found program, wrong
        // scenario" case, as opposed to an entirely unknown program code.
        Boolean exceptionThrown = false;

        try {
            CommunicationConfigurationService.getConfiguration(
                'GMPM',
                CommunicationsController.CommunicationScenario.OFFER_ACCEPTED
            );
        } catch (CommunicationConfigurationService.CommunicationConfigurationException e) {
            exceptionThrown = true;
            System.assert(
                e.getMessage().contains('GMPM'),
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