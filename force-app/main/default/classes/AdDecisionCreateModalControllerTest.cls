@IsTest
private class AdDecisionCreateModalControllerTest {
    @IsTest
    static void returnsEnabledConfigurationForConfiguredProgramCode() {
        Test.startTest();
        AdAdmissionDecisionCreateModalController.ModalConfiguration configuration =
            AdAdmissionDecisionCreateModalController.getModalConfiguration(
                ' pgdm '
            );
        Test.stopTest();

        System.assertEquals(
            true,
            configuration.showSpecialization,
            'Specialization should be visible for the configured program.'
        );
        System.assertEquals(
            true,
            configuration.waitlistNumberRequired,
            'Waitlist Number should be required for the configured program.'
        );
    }

    @IsTest
    static void specializationCompatibilityMethodUsesModalConfiguration() {
        Test.startTest();
        Boolean shouldShowSpecialization =
            AdAdmissionDecisionCreateModalController.shouldShowSpecialization(
                'PGDM'
            );
        Test.stopTest();

        System.assertEquals(
            true,
            shouldShowSpecialization,
            'The compatibility method should return the specialization configuration.'
        );
    }

    @IsTest
    static void returnsDisabledConfigurationForDifferentProgramCode() {
        Test.startTest();
        AdAdmissionDecisionCreateModalController.ModalConfiguration configuration =
            AdAdmissionDecisionCreateModalController.getModalConfiguration(
                'PGPM'
            );
        Test.stopTest();

        System.assertEquals(
            false,
            configuration.showSpecialization,
            'Specialization should not be visible for a different program.'
        );
        System.assertEquals(
            false,
            configuration.waitlistNumberRequired,
            'Waitlist Number should not be required for a different program.'
        );
    }

    @IsTest
    static void returnsDefaultConfigurationForBlankProgramCode() {
        Test.startTest();
        AdAdmissionDecisionCreateModalController.ModalConfiguration nullConfiguration =
            AdAdmissionDecisionCreateModalController.getModalConfiguration(null);
        AdAdmissionDecisionCreateModalController.ModalConfiguration blankConfiguration =
            AdAdmissionDecisionCreateModalController.getModalConfiguration('   ');
        Test.stopTest();

        System.assertEquals(false, nullConfiguration.showSpecialization);
        System.assertEquals(false, nullConfiguration.waitlistNumberRequired);
        System.assertEquals(false, blankConfiguration.showSpecialization);
        System.assertEquals(false, blankConfiguration.waitlistNumberRequired);
    }

    @IsTest
    static void modalConfigurationDefaultsToFalse() {
        AdAdmissionDecisionCreateModalController.ModalConfiguration configuration =
            new AdAdmissionDecisionCreateModalController.ModalConfiguration();

        System.assertEquals(
            false,
            configuration.showSpecialization,
            'Specialization should default to false.'
        );
        System.assertEquals(
            false,
            configuration.waitlistNumberRequired,
            'Waitlist Number requirement should default to false.'
        );
    }
}