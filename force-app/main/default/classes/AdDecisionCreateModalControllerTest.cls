@IsTest
private class AdDecisionCreateModalControllerTest {
    @IsTest
    static void returnsTrueOnlyForConfiguredProgramCode() {
        System.assertEquals(
            true,
            AdAdmissionDecisionCreateModalController.shouldShowSpecialization(
                'PGDM'
            )
        );
        System.assertEquals(
            true,
            AdAdmissionDecisionCreateModalController.shouldShowSpecialization(
                ' pgdm '
            )
        );
        System.assertEquals(
            false,
            AdAdmissionDecisionCreateModalController.shouldShowSpecialization(
                'PGPM'
            )
        );
        System.assertEquals(
            false,
            AdAdmissionDecisionCreateModalController.shouldShowSpecialization(
                null
            )
        );
    }
}