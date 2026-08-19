@IsTest
private class AccountTriggerHandlerTest {
  /*  @IsTest
    static void smokeTest() {
        try {
            Type t = AccountTriggerHandler.class;
            System.assertNotEquals(null, t);
        } catch (Exception e) {}
    }*/
    // ---------------------------------------------------------
    // Helper method to get Student Record Type
    // ---------------------------------------------------------
    
     // =========================================================
    // 1. DUPLICATE FACULTY CODE - INSERT
    // =========================================================
    @IsTest
    static void testDuplicateFacultyCodeOnInsert() {

        Account existingFaculty = new Account(
            FirstName = 'Existing',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC001'
        );

        insert existingFaculty;

        Account newFaculty = new Account(
            FirstName = 'New',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC001'
        );

        Test.startTest();

        AccountTriggerHandler.checkDuplicateFacultyCode(
            new List<Account>{ newFaculty },
            null
        );

        Test.stopTest();

        System.assert(
            newFaculty.hasErrors(),
            'An error should be added when the Faculty Code already exists.'
        );

        System.assertEquals(
            'Duplicate value found: Faculty Code already exists.',
            newFaculty.getErrors()[0].getMessage()
        );
    }


    // =========================================================
    // 2. UNIQUE FACULTY CODE
    // =========================================================
    @IsTest
    static void testUniqueFacultyCode() {

        Account existingFaculty = new Account(
            FirstName = 'Existing',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC001'
        );

        insert existingFaculty;

        Account newFaculty = new Account(
            FirstName = 'New',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC002'
        );

        Test.startTest();

        AccountTriggerHandler.checkDuplicateFacultyCode(
            new List<Account>{ newFaculty },
            null
        );

        Test.stopTest();

        System.assert(
            !newFaculty.hasErrors(),
            'No error should be added for a unique Faculty Code.'
        );
    }


    // =========================================================
    // 3. BLANK FACULTY CODE
    // =========================================================
    @IsTest
    static void testBlankFacultyCode() {

        Account faculty = new Account(
            FirstName = 'Faculty',
            LastName = 'NoCode'
        );

        Test.startTest();

        AccountTriggerHandler.checkDuplicateFacultyCode(
            new List<Account>{ faculty },
            null
        );

        Test.stopTest();

        System.assert(
            !faculty.hasErrors(),
            'Blank Faculty Code should be ignored.'
        );
    }


    // =========================================================
    // 4. FACULTY CODE UNCHANGED ON UPDATE
    // =========================================================
    @IsTest
    static void testFacultyCodeUnchangedOnUpdate() {

        Account faculty = new Account(
            FirstName = 'Faculty',
            LastName = 'One',
            SPJIMR_Faculty_Code__c = 'FAC100'
        );

        insert faculty;

        // Simulate Trigger.old
        Account oldFaculty = faculty.clone(
            true,   // preserveId
            true,   // isDeepClone
            false,  // preserveReadonlyTimestamps
            false   // preserveAutonumber
        );

        // Simulate Trigger.new
        Account updatedFaculty = faculty.clone(
            true,
            true,
            false,
            false
        );

        updatedFaculty.FirstName = 'Updated';

        Map<Id, Account> oldMap = new Map<Id, Account>{
            faculty.Id => oldFaculty
        };

        Test.startTest();

        AccountTriggerHandler.checkDuplicateFacultyCode(
            new List<Account>{ updatedFaculty },
            oldMap
        );

        Test.stopTest();

        System.assert(
            !updatedFaculty.hasErrors(),
            'An unchanged Faculty Code should not be treated as duplicate.'
        );
    }


    // =========================================================
    // 5. FACULTY CODE CHANGED TO EXISTING CODE
    // =========================================================
    @IsTest
    static void testFacultyCodeChangedToExistingCode() {

        Account facultyOne = new Account(
            FirstName = 'Faculty',
            LastName = 'One',
            SPJIMR_Faculty_Code__c = 'FAC101'
        );

        Account facultyTwo = new Account(
            FirstName = 'Faculty',
            LastName = 'Two',
            SPJIMR_Faculty_Code__c = 'FAC102'
        );

        insert new List<Account>{
            facultyOne,
            facultyTwo
        };

        // Represents Trigger.old
        Account oldFacultyTwo = facultyTwo.clone(
            true,
            true,
            false,
            false
        );

        // Represents Trigger.new
        Account updatedFacultyTwo = facultyTwo.clone(
            true,
            true,
            false,
            false
        );

        // Change FAC102 -> FAC101
        updatedFacultyTwo.SPJIMR_Faculty_Code__c = 'FAC101';

        Map<Id, Account> oldMap = new Map<Id, Account>{
            facultyTwo.Id => oldFacultyTwo
        };

        Test.startTest();

        AccountTriggerHandler.checkDuplicateFacultyCode(
            new List<Account>{ updatedFacultyTwo },
            oldMap
        );

        Test.stopTest();

        System.assert(
            updatedFacultyTwo.hasErrors(),
            'Changing the Faculty Code to an existing code should produce an error.'
        );

        System.assertEquals(
            'Duplicate value found: Faculty Code already exists.',
            updatedFacultyTwo.getErrors()[0].getMessage()
        );
    }


    // =========================================================
    // 6. MULTIPLE ACCOUNTS - BULK TEST
    // =========================================================
    @IsTest
    static void testMultipleFacultyCodes() {

        Account existingFaculty = new Account(
            FirstName = 'Existing',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC200'
        );

        insert existingFaculty;

        Account duplicateFaculty = new Account(
            FirstName = 'Duplicate',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC200'
        );

        Account uniqueFaculty = new Account(
            FirstName = 'Unique',
            LastName = 'Faculty',
            SPJIMR_Faculty_Code__c = 'FAC201'
        );

        Test.startTest();

        AccountTriggerHandler.checkDuplicateFacultyCode(
            new List<Account>{
                duplicateFaculty,
                uniqueFaculty
            },
            null
        );

        Test.stopTest();

        System.assert(
            duplicateFaculty.hasErrors(),
            'Duplicate Faculty Code should have an error.'
        );

        System.assert(
            !uniqueFaculty.hasErrors(),
            'Unique Faculty Code should not have an error.'
        );
    }
}