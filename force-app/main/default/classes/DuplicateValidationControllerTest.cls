@IsTest
private class DuplicateValidationControllerTest {

    /*
     * ============================================================
     * DEPARTMENT MASTER TESTS
     * ============================================================
     */

    @IsTest
    static void testDepartmentCodeBlank() {

        Department_Master__c department = new Department_Master__c(
            Name = 'Test Department Blank',
            Department_Code__c = null
        );

        Test.startTest();

        DuplicateValidationController.validateDepartmentCodes(
            new List<Department_Master__c>{ department }
        );

        Test.stopTest();

        // No error should be added for blank code
        System.assertEquals(
            0,
            department.getErrors().size(),
            'Blank Department Code should not generate a duplicate error.'
        );
    }


    @IsTest
    static void testDepartmentCodeNoDuplicate() {

        Department_Master__c department = new Department_Master__c(
            Name = 'Test Department Unique',
            Department_Code__c = 'TEST-DP-001'
        );

        Test.startTest();

        DuplicateValidationController.validateDepartmentCodes(
            new List<Department_Master__c>{ department }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            department.getErrors().size(),
            'Unique Department Code should not generate an error.'
        );
    }


    @IsTest
    static void testDepartmentCodeExistingDuplicate() {

        // Create existing database record
        Department_Master__c existingDepartment = new Department_Master__c(
            Name = 'Existing Department',
            Department_Code__c = 'TEST-DP-002'
        );

        insert existingDepartment;

        // New record with same code
        Department_Master__c newDepartment = new Department_Master__c(
            Name = 'Duplicate Department',
            Department_Code__c = 'TEST-DP-002'
        );

        Test.startTest();

        DuplicateValidationController.validateDepartmentCodes(
            new List<Department_Master__c>{ newDepartment }
        );

        Test.stopTest();

        System.assertEquals(
            1,
            newDepartment.getErrors().size(),
            'Duplicate Department Code should generate an error.'
        );

        System.assertEquals(
            'Department Code already exists. Please enter a unique value.',
            newDepartment.getErrors()[0].getMessage(),
            'Incorrect Department Code duplicate error message.'
        );
    }


    @IsTest
    static void testDepartmentCodeUpdateSameRecord() {

        // Create existing record
        Department_Master__c department = new Department_Master__c(
            Name = 'Department Update Test',
            Department_Code__c = 'TEST-DP-003'
        );

        insert department;

        // Query the same record
        Department_Master__c departmentToUpdate = [
            SELECT Id, Name, Department_Code__c
            FROM Department_Master__c
            WHERE Id = :department.Id
            LIMIT 1
        ];

        Test.startTest();

        /*
         * The controller should NOT consider the same record
         * to be a duplicate.
         */
        DuplicateValidationController.validateDepartmentCodes(
            new List<Department_Master__c>{ departmentToUpdate }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            departmentToUpdate.getErrors().size(),
            'Updating the same Department record should not generate a duplicate error.'
        );
    }


    @IsTest
    static void testDepartmentCodeDuplicateInSameTransaction() {

        Department_Master__c department1 = new Department_Master__c(
            Name = 'Department Transaction 1',
            Department_Code__c = 'TEST-DP-004'
        );

        Department_Master__c department2 = new Department_Master__c(
            Name = 'Department Transaction 2',
            Department_Code__c = 'TEST-DP-004'
        );

        Test.startTest();

        DuplicateValidationController.validateDepartmentCodes(
            new List<Department_Master__c>{
                department1,
                department2
            }
        );

        Test.stopTest();

        /*
         * First record is allowed.
         * Second record should receive duplicate error.
         */
        System.assertEquals(
            0,
            department1.getErrors().size(),
            'First Department record should not have an error.'
        );

        System.assertEquals(
            1,
            department2.getErrors().size(),
            'Second Department record should have a duplicate error.'
        );

        System.assertEquals(
            'Department Code already exists. Please enter a unique value.',
            department2.getErrors()[0].getMessage(),
            'Incorrect same-transaction duplicate error message.'
        );
    }


    /*
     * ============================================================
     * SPECIALISATION MASTER TESTS
     * ============================================================
     */

    @IsTest
    static void testSpecialisationCodeBlank() {

        Specialisation_Master__c specialisation =
            new Specialisation_Master__c(
                Name = 'Test Specialisation Blank',
                Specialisation_Code__c = null
            );

        Test.startTest();

        DuplicateValidationController.validateSpecialisationCodes(
            new List<Specialisation_Master__c>{ specialisation }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            specialisation.getErrors().size(),
            'Blank Specialisation Code should not generate a duplicate error.'
        );
    }


    @IsTest
    static void testSpecialisationCodeNoDuplicate() {

        Specialisation_Master__c specialisation =
            new Specialisation_Master__c(
                Name = 'Test Specialisation Unique',
                Specialisation_Code__c = 'TEST-SP-001'
            );

        Test.startTest();

        DuplicateValidationController.validateSpecialisationCodes(
            new List<Specialisation_Master__c>{ specialisation }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            specialisation.getErrors().size(),
            'Unique Specialisation Code should not generate an error.'
        );
    }


    @IsTest
    static void testSpecialisationCodeExistingDuplicate() {

        // Existing database record
        Specialisation_Master__c existingSpecialisation =
            new Specialisation_Master__c(
                Name = 'Existing Specialisation',
                Specialisation_Code__c = 'TEST-SP-002'
            );

        insert existingSpecialisation;

        // New record with duplicate code
        Specialisation_Master__c newSpecialisation =
            new Specialisation_Master__c(
                Name = 'Duplicate Specialisation',
                Specialisation_Code__c = 'TEST-SP-002'
            );

        Test.startTest();

        DuplicateValidationController.validateSpecialisationCodes(
            new List<Specialisation_Master__c>{ newSpecialisation }
        );

        Test.stopTest();

        System.assertEquals(
            1,
            newSpecialisation.getErrors().size(),
            'Duplicate Specialisation Code should generate an error.'
        );

        System.assertEquals(
            'Specialisation Code already exists. Please enter a unique value.',
            newSpecialisation.getErrors()[0].getMessage(),
            'Incorrect Specialisation Code duplicate error message.'
        );
    }


    @IsTest
    static void testSpecialisationCodeUpdateSameRecord() {

        // Create existing record
        Specialisation_Master__c specialisation =
            new Specialisation_Master__c(
                Name = 'Specialisation Update Test',
                Specialisation_Code__c = 'TEST-SP-003'
            );

        insert specialisation;

        // Query same record
        Specialisation_Master__c specialisationToUpdate = [
            SELECT Id, Name, Specialisation_Code__c
            FROM Specialisation_Master__c
            WHERE Id = :specialisation.Id
            LIMIT 1
        ];

        Test.startTest();

        DuplicateValidationController.validateSpecialisationCodes(
            new List<Specialisation_Master__c>{
                specialisationToUpdate
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            specialisationToUpdate.getErrors().size(),
            'Updating the same Specialisation record should not generate a duplicate error.'
        );
    }


    @IsTest
    static void testSpecialisationCodeDuplicateInSameTransaction() {

        Specialisation_Master__c specialisation1 =
            new Specialisation_Master__c(
                Name = 'Specialisation Transaction 1',
                Specialisation_Code__c = 'TEST-SP-004'
            );

        Specialisation_Master__c specialisation2 =
            new Specialisation_Master__c(
                Name = 'Specialisation Transaction 2',
                Specialisation_Code__c = 'TEST-SP-004'
            );

        Test.startTest();

        DuplicateValidationController.validateSpecialisationCodes(
            new List<Specialisation_Master__c>{
                specialisation1,
                specialisation2
            }
        );

        Test.stopTest();

        System.assertEquals(
            0,
            specialisation1.getErrors().size(),
            'First Specialisation record should not have an error.'
        );

        System.assertEquals(
            1,
            specialisation2.getErrors().size(),
            'Second Specialisation record should have a duplicate error.'
        );

        System.assertEquals(
            'Specialisation Code already exists. Please enter a unique value.',
            specialisation2.getErrors()[0].getMessage(),
            'Incorrect same-transaction duplicate error message.'
        );
    }
}