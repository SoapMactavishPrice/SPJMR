@IsTest
private class ProgramRegistrationLeadServiceTest {

    @IsTest
    static void saveRegistration_blankProgramId() {

        ProgramRegistrationFormController.SaveLeadResult result =
            ProgramRegistrationLeadService.saveRegistration(
                '',
                '{"email":"test@test.com"}',
                null,
                null,
                false
            );

        System.assertEquals(false, result.success);
        System.assertEquals(
            'Program Id is required.',
            result.message
        );
    }

    @IsTest
    static void saveRegistration_blankFormData() {

        ProgramRegistrationFormController.SaveLeadResult result =
            ProgramRegistrationLeadService.saveRegistration(
                'TEST',
                '',
                null,
                null,
                false
            );

        System.assertEquals(false, result.success);
        System.assertEquals(
            'Form data is required.',
            result.message
        );
    }

    @IsTest
    static void saveRegistration_invalidJson() {

        ProgramRegistrationFormController.SaveLeadResult result =
            ProgramRegistrationLeadService.saveRegistration(
                'TEST',
                '{bad json}',
                null,
                null,
                false
            );

        System.assertEquals(false, result.success);
        System.assertEquals(
            'Invalid form data.',
            result.message
        );
    }

    @IsTest
    static void saveRegistration_missingConfig() {

        ProgramRegistrationFormController.SaveLeadResult result =
            ProgramRegistrationLeadService.saveRegistration(
                'NON_EXISTING_PROGRAM',
                '{"email":"test@test.com"}',
                null,
                null,
                false
            );

        System.assertEquals(false, result.success);
        System.assertEquals(
            'Program configuration not found.',
            result.message
        );
    }

   @IsTest
static void saveRegistration_invalidJson_usingMetadataProgramId() {

    Program_Registration_Config__mdt config = [
        SELECT Program_Id__c
        FROM Program_Registration_Config__mdt
        LIMIT 1
    ];

    Test.startTest();

    ProgramRegistrationFormController.SaveLeadResult result =
        ProgramRegistrationLeadService.saveRegistration(
            config.Program_Id__c,
            '{bad json}',
            null,
            null,
            false
        );

    Test.stopTest();

    System.assertEquals(false, result.success);
    System.assertEquals(
        'Invalid form data.',
        result.message
    );
}

   

   
}