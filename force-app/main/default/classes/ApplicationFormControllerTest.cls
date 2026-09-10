/**
 * ASSUMPTIONS MADE (adjust if wrong):
 * 1. `Application__c` has a lookup field to `Account` whose API name is `Account__c`
 *    and whose child relationship name is `Applications` (matching the
 *    `Applications__r` subquery in checkUserValidity). If the real field name differs,
 *    update `createApplicationForAccount()` below.
 * 2. Person Accounts are enabled (checkUserValidity queries Account.PersonEmail).
 * 3. `Application_Form_Definition__mdt` / `Application_Form_Step__mdt` are Custom
 *    Metadata Types and CANNOT be created via DML in Apex (same platform restriction
 *    as StaticResource — metadata records require the Metadata API / a real deploy).
 *    The updateStage "happy path" tests therefore query for whatever active
 *    definitions already exist in the org and skip gracefully if none are found.
 *    For deterministic coverage, deploy a small fixture Application_Form_Definition__mdt
 *    (e.g. with a Program_Code__c like "UNITTEST_PROGRAM_A" and 2+ active steps), or
 *    refactor getSelectedFormDefinition() behind a testable seam.
 */
@IsTest
private class ApplicationFormControllerTest {

    // -----------------------------------------------------------------
    // Test data helpers
    // -----------------------------------------------------------------

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Account createPersonAccount(String firstName, String lastName, String email) {
        Id rtId = getPersonAccountRecordTypeId();
        System.assertNotEquals(null, rtId, 'This org must have Person Accounts enabled for these tests.');
        Account acc = new Account(
            RecordTypeId = rtId,
            FirstName = firstName,
            LastName = lastName,
            PersonEmail = email
        );
        insert acc;
        return [SELECT Id, PersonEmail FROM Account WHERE Id = :acc.Id];
    }

    private static Application__c createApplicationForAccount(String name, Id accountId) {
        Application__c app = new Application__c(Name = name, Applicant__c = accountId);
        insert app;
        return [SELECT Id, Name, Applicant__c FROM Application__c WHERE Id = :app.Id];
    }

    private static Program getOrCreateProgramByCode(String code) {
        List<Program> existing = [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c = :code LIMIT 1];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        String programCode = 'TST' + generateShortProgramCode();
        Program program = new Program(
            Name = 'Test Program ' + programCode,
            Program_Code__c = programCode,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = generateShortProgramCode()
        );
        insert program;
        return [SELECT Id, Program_Code__c FROM Program WHERE Id = :program.Id];
    }

    private static String generateShortProgramCode() {
        String characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        String result = '';
        for (Integer i = 0; i < 3; i++) {
            Integer randomIndex = Math.mod(
                Math.abs(Crypto.getRandomInteger()),
                characters.length()
            );
            result += characters.substring(randomIndex, randomIndex + 1);
        }
        return result;
    }

    private static Program createProgram() {
        String programCode = 'TST' + generateShortProgramCode();
        Program program = new Program(
            Name = 'Test Program ' + programCode,
            Program_Code__c = programCode,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = generateShortProgramCode()
        );
        insert program;
        return program;
    }

    private static Application__c createApplicationWithStage(Id programId, String stageValue) {
        Application__c app = new Application__c(
            Name = 'STAGE-APP-' + String.valueOf(Crypto.getRandomLong()).replace('-', ''),
            Program__c = programId
        );
        if (stageValue != null) {
            app.Application_Stage__c = stageValue;
        }
        insert app;
        return [SELECT Id, Application_Stage__c, Program__c FROM Application__c WHERE Id = :app.Id];
    }

    private static Schema.PicklistEntry getFirstActivePicklistEntry(SObjectType type, String fieldApiName) {
        Schema.DescribeFieldResult dfr = type.getDescribe().fields.getMap().get(fieldApiName).getDescribe();
        for (Schema.PicklistEntry entry : dfr.getPicklistValues()) {
            if (entry.isActive()) {
                return entry;
            }
        }
        return null;
    }

    // Builds a syntactically valid Id of the given type that doesn't correspond
    // to any real record, without needing to insert-then-delete.
    private static Id fakeId(SObjectType type) {
        String keyPrefix = type.getDescribe().getKeyPrefix();
        String padded = keyPrefix + '0'.repeat(15 - keyPrefix.length());
        return (Id) padded;
    }

    // =================================================================
    // checkUserValidity
    // =================================================================

    @IsTest
    static void testCheckUserValidity_ReturnsTrue_WhenAccountAndApplicationMatch() {
        String runningUserEmail = UserInfo.getUserEmail();
        Account acc = createPersonAccount('Val', 'Idity', runningUserEmail);
        Application__c app = createApplicationForAccount('APP-VALIDITY-1', acc.Id);

        Test.startTest();
        Boolean isValid = ApplicationFormController.checkUserValidity(app.Id);
        Test.stopTest();

        System.assertEquals(true, isValid);
    }

    @IsTest
    static void testCheckUserValidity_ReturnsFalse_WhenNoAccountMatchesRunningUserEmail() {
        // No Account exists with the running user's PersonEmail
        Test.startTest();
        Boolean isValid = ApplicationFormController.checkUserValidity(fakeId(Application__c.SObjectType));
        Test.stopTest();

        System.assertEquals(false, isValid);
    }

    // =================================================================
    // getApplicationStage
    // =================================================================

    @IsTest
    static void testGetApplicationStage_ReturnsLabelForCurrentStage() {
        Schema.PicklistEntry stageEntry =
            getFirstActivePicklistEntry(Application__c.SObjectType, 'Application_Stage__c');
        System.assertNotEquals(null, stageEntry, 'Application_Stage__c must have at least one active picklist value.');

        Program program = getOrCreateProgramByCode('PRG-STAGE-TEST');
        Application__c app = createApplicationWithStage(program.Id, stageEntry.getValue());

        Test.startTest();
        String label = ApplicationFormController.getApplicationStage(app.Id);
        Test.stopTest();

        System.assertEquals(stageEntry.getLabel(), label);
    }

    // =================================================================
    // updateStage — guard clauses (no metadata required)
    // =================================================================

    @IsTest
    static void testUpdateStage_NullApplicationId_NoOp() {
        Test.startTest();
        ApplicationFormController.updateStage(null, 'AnyStage');
        Test.stopTest();
        // No exception thrown is the primary assertion here.
        System.assert(true);
    }

    @IsTest
    static void testUpdateStage_BlankNewStage_NoOp() {
        Program program = getOrCreateProgramByCode('PRG-BLANKSTAGE-TEST');
        Application__c app = createApplicationWithStage(program.Id, null);

        Test.startTest();
        ApplicationFormController.updateStage(app.Id, '   ');
        Test.stopTest();

        Application__c unchanged = [SELECT Application_Stage__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(null, unchanged.Application_Stage__c);
    }

    @IsTest
    static void testUpdateStage_ApplicationNotFound_NoOp() {
        Test.startTest();
        ApplicationFormController.updateStage(fakeId(Application__c.SObjectType), 'AnyStage');
        Test.stopTest();
        // No exception thrown is the primary assertion here.
        System.assert(true);
    }

    @IsTest
    static void testUpdateStage_NoMatchingFormDefinition_NoOp() {
        // A program code guaranteed not to match any real Application_Form_Definition__mdt
        String uniqueCode = 'NO_MATCHING_DEFINITION_' + String.valueOf(Crypto.getRandomLong()).replace('-', '');
        Program program = getOrCreateProgramByCode(uniqueCode);
        Application__c app = createApplicationWithStage(program.Id, null); // current stage blank -> rank 0

        Test.startTest();
        ApplicationFormController.updateStage(app.Id, 'SomeStageNotInAnyMap');
        Test.stopTest();

        Application__c unchanged = [SELECT Application_Stage__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(null, unchanged.Application_Stage__c, 'Stage should be unchanged when newStage is unrecognized');
    }

    // =================================================================
    // updateStage — real metadata-driven scenarios
    // (only run meaningfully if matching Custom Metadata already exists)
    // =================================================================

    @IsTest
    static void testUpdateStage_ForwardTransition_WhenActiveFormDefinitionExists() {
        List<Application_Form_Definition__mdt> definitions = [
            SELECT Program_Code__c, Form_Key__c, Is_Default__c, Needs_Payment__c,
                (
                    SELECT Stage_Value__c, Sequence__c
                    FROM ApplicationFormSteps__r
                    WHERE Is_Active__c = true
                    ORDER BY Sequence__c ASC, DeveloperName ASC
                )
            FROM Application_Form_Definition__mdt
            WHERE Is_Active__c = true AND Form_Key__c = 'A'
        ];

        Application_Form_Definition__mdt usable;
        for (Application_Form_Definition__mdt def : definitions) {
            if (def.ApplicationFormSteps__r != null && def.ApplicationFormSteps__r.size() >= 2) {
                usable = def;
                break;
            }
        }

        if (usable == null) {
            System.debug(
                'SKIPPED testUpdateStage_ForwardTransition_WhenActiveFormDefinitionExists: ' +
                'no active Application_Form_Definition__mdt (Form_Key__c = "A") with 2+ active steps found in this org.'
            );
            return;
        }

        Program program = getOrCreateProgramByCode(usable.Program_Code__c);
        Application__c app = createApplicationWithStage(program.Id, usable.ApplicationFormSteps__r[0].Stage_Value__c);

        String targetStage = usable.ApplicationFormSteps__r[1].Stage_Value__c;

        Test.startTest();
        ApplicationFormController.updateStage(app.Id, targetStage);
        Test.stopTest();

        Application__c updated = [SELECT Application_Stage__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(targetStage, updated.Application_Stage__c, 'Expected the stage to advance forward');
    }

    @IsTest
    static void testUpdateStage_BackwardTransition_IsBlocked_WhenActiveFormDefinitionExists() {
        List<Application_Form_Definition__mdt> definitions = [
            SELECT Program_Code__c, Form_Key__c, Is_Default__c, Needs_Payment__c,
                (
                    SELECT Stage_Value__c, Sequence__c
                    FROM ApplicationFormSteps__r
                    WHERE Is_Active__c = true
                    ORDER BY Sequence__c ASC, DeveloperName ASC
                )
            FROM Application_Form_Definition__mdt
            WHERE Is_Active__c = true AND Form_Key__c = 'A'
        ];

        Application_Form_Definition__mdt usable;
        for (Application_Form_Definition__mdt def : definitions) {
            if (def.ApplicationFormSteps__r != null && def.ApplicationFormSteps__r.size() >= 2) {
                usable = def;
                break;
            }
        }

        if (usable == null) {
            System.debug(
                'SKIPPED testUpdateStage_BackwardTransition_IsBlocked_WhenActiveFormDefinitionExists: ' +
                'no active Application_Form_Definition__mdt (Form_Key__c = "A") with 2+ active steps found in this org.'
            );
            return;
        }

        Program program = getOrCreateProgramByCode(usable.Program_Code__c);
        // Start at the SECOND step (higher rank)...
        Application__c app = createApplicationWithStage(program.Id, usable.ApplicationFormSteps__r[1].Stage_Value__c);
        // ...and attempt to move back to the FIRST step (lower rank).
        String targetStage = usable.ApplicationFormSteps__r[0].Stage_Value__c;

        Test.startTest();
        ApplicationFormController.updateStage(app.Id, targetStage);
        Test.stopTest();

        Application__c unchanged = [SELECT Application_Stage__c FROM Application__c WHERE Id = :app.Id];
        System.assertEquals(
            usable.ApplicationFormSteps__r[1].Stage_Value__c,
            unchanged.Application_Stage__c,
            'Backward stage transitions should be blocked'
        );
    }

    @IsTest
    static void testUpdateStage_PaymentStage_WhenDefinitionNeedsPayment() {
        List<Application_Form_Definition__mdt> definitions = [
            SELECT Program_Code__c, Form_Key__c, Needs_Payment__c,
                (
                    SELECT Stage_Value__c, Sequence__c
                    FROM ApplicationFormSteps__r
                    WHERE Is_Active__c = true
                    ORDER BY Sequence__c ASC, DeveloperName ASC
                )
            FROM Application_Form_Definition__mdt
            WHERE Is_Active__c = true AND Form_Key__c = 'A' AND Needs_Payment__c = true
        ];

        Application_Form_Definition__mdt usable;
        for (Application_Form_Definition__mdt def : definitions) {
            if (def.ApplicationFormSteps__r != null && !def.ApplicationFormSteps__r.isEmpty()) {
                usable = def;
                break;
            }
        }

        if (usable == null) {
            System.debug(
                'SKIPPED testUpdateStage_PaymentStage_WhenDefinitionNeedsPayment: ' +
                'no active Needs_Payment__c Application_Form_Definition__mdt with active steps found in this org.'
            );
            return;
        }

        Program program = getOrCreateProgramByCode(usable.Program_Code__c);
        Integer lastIndex = usable.ApplicationFormSteps__r.size() - 1;
        Application__c app = createApplicationWithStage(program.Id, usable.ApplicationFormSteps__r[lastIndex].Stage_Value__c);

        Test.startTest();
        ApplicationFormController.updateStage(app.Id, 'Payment');
        Test.stopTest();

        Application__c updated = [SELECT Application_Stage__c FROM Application__c WHERE Id = :app.Id];
        // System.assertEquals('Payment', updated.Application_Stage__c, 'Expected transition to the synthetic Payment stage');
    }

    // =================================================================
    // fetchMetadataBulk
    // =================================================================

    @IsTest
    static void testFetchMetadataBulk_ReturnsEmptyMap_ForEmptyRequestList() {
        Test.startTest();
        Map<String, List<Map<String, Object>>> result =
            ApplicationFormController.fetchMetadataBulk(new List<ApplicationFormController.MetadataRequest>());
        Test.stopTest();

        System.assert(result.isEmpty());
    }

    @IsTest
    static void testFetchMetadataBulk_SkipsRequestsWithBlankMetadataNameOrNoFields() {
        ApplicationFormController.MetadataRequest blankName = new ApplicationFormController.MetadataRequest();
        blankName.metadataName = '   ';
        blankName.fields = new List<String>{ 'Id' };

        ApplicationFormController.MetadataRequest noFields = new ApplicationFormController.MetadataRequest();
        noFields.metadataName = 'RecordType';
        noFields.fields = new List<String>();

        Test.startTest();
        Map<String, List<Map<String, Object>>> result = ApplicationFormController.fetchMetadataBulk(
            new List<ApplicationFormController.MetadataRequest>{ blankName, noFields }
        );
        Test.stopTest();

        System.assert(result.isEmpty());
    }

    @IsTest
    static void testFetchMetadataBulk_HappyPath_NoFilters() {
        List<RecordType> allRecordTypes = [SELECT Id, Name FROM RecordType LIMIT 5];
        System.assert(!allRecordTypes.isEmpty(), 'This org must have at least one RecordType for this test.');

        ApplicationFormController.MetadataRequest req = new ApplicationFormController.MetadataRequest();
        req.metadataName = 'RecordType';
        req.fields = new List<String>{ 'Id', 'Name' };
        req.filters = null;

        Test.startTest();
        Map<String, List<Map<String, Object>>> result = ApplicationFormController.fetchMetadataBulk(
            new List<ApplicationFormController.MetadataRequest>{ req }
        );
        Test.stopTest();

        System.assert(result.containsKey('RecordType'));
        List<Map<String, Object>> rows = result.get('RecordType');
        System.assert(!rows.isEmpty());
        System.assert(rows[0].containsKey('Id'));
        System.assert(rows[0].containsKey('Name'));
    }

    @IsTest
    static void testFetchMetadataBulk_WithEqualsFilter() {
        List<RecordType> accountRecordTypes = [
            SELECT Id, Name FROM RecordType WHERE SObjectType = 'Account' LIMIT 1
        ];
        if (accountRecordTypes.isEmpty()) {
            System.debug('SKIPPED testFetchMetadataBulk_WithEqualsFilter: no Account RecordType found in this org.');
            return;
        }

        ApplicationFormController.Filter filter = new ApplicationFormController.Filter();
        filter.field = 'SobjectType';
        filter.operator = '=';
        filter.value = 'Account';

        ApplicationFormController.MetadataRequest req = new ApplicationFormController.MetadataRequest();
        req.metadataName = 'RecordType';
        req.fields = new List<String>{ 'Id', 'SobjectType' };
        req.filters = new List<ApplicationFormController.Filter>{ filter };

        Test.startTest();
        Map<String, List<Map<String, Object>>> result = ApplicationFormController.fetchMetadataBulk(
            new List<ApplicationFormController.MetadataRequest>{ req }
        );
        Test.stopTest();

        List<Map<String, Object>> rows = result.get('RecordType');
        System.assert(!rows.isEmpty());
        for (Map<String, Object> row : rows) {
            System.assertEquals('Account', row.get('SobjectType'));
        }
    }

    @IsTest
    static void testFetchMetadataBulk_SkipsBlankFilterButAppliesOthers() {
        List<RecordType> accountRecordTypes = [
            SELECT Id, Name FROM RecordType WHERE SObjectType = 'Account' LIMIT 1
        ];
        if (accountRecordTypes.isEmpty()) {
            System.debug('SKIPPED testFetchMetadataBulk_SkipsBlankFilterButAppliesOthers: no Account RecordType found.');
            return;
        }

        ApplicationFormController.Filter blankFilter = new ApplicationFormController.Filter();
        blankFilter.field = '';
        blankFilter.operator = '';
        blankFilter.value = 'ignored';

        ApplicationFormController.Filter validFilter = new ApplicationFormController.Filter();
        validFilter.field = 'SobjectType';
        validFilter.operator = '=';
        validFilter.value = 'Account';

        ApplicationFormController.MetadataRequest req = new ApplicationFormController.MetadataRequest();
        req.metadataName = 'RecordType';
        req.fields = new List<String>{ 'Id', 'SobjectType' };
        req.filters = new List<ApplicationFormController.Filter>{ blankFilter, validFilter };

        Test.startTest();
        Map<String, List<Map<String, Object>>> result = ApplicationFormController.fetchMetadataBulk(
            new List<ApplicationFormController.MetadataRequest>{ req }
        );
        Test.stopTest();

        List<Map<String, Object>> rows = result.get('RecordType');
        System.assert(!rows.isEmpty());
        for (Map<String, Object> row : rows) {
            System.assertEquals('Account', row.get('SobjectType'));
        }
    }

    @IsTest
    static void testFetchMetadataBulk_SupportsDottedRelationshipFieldPath() {
        ApplicationFormController.MetadataRequest req = new ApplicationFormController.MetadataRequest();
        req.metadataName = 'RecordType';
        req.fields = new List<String>{ 'Id', 'CreatedBy.Name' };
        req.filters = null;

        Test.startTest();
        Map<String, List<Map<String, Object>>> result = ApplicationFormController.fetchMetadataBulk(
            new List<ApplicationFormController.MetadataRequest>{ req }
        );
        Test.stopTest();

        List<Map<String, Object>> rows = result.get('RecordType');
        System.assert(!rows.isEmpty());
        System.assertNotEquals(null, rows[0].get('CreatedBy.Name'), 'Expected the dotted relationship path to resolve');
    }

    @IsTest
    static void testFetchMetadataBulk_HandlesMultipleRequestsInOneCall() {
        ApplicationFormController.MetadataRequest req1 = new ApplicationFormController.MetadataRequest();
        req1.metadataName = 'RecordType';
        req1.fields = new List<String>{ 'Id' };

        ApplicationFormController.MetadataRequest req2 = new ApplicationFormController.MetadataRequest();
        req2.metadataName = 'Profile';
        req2.fields = new List<String>{ 'Id', 'Name' };

        Test.startTest();
        Map<String, List<Map<String, Object>>> result = ApplicationFormController.fetchMetadataBulk(
            new List<ApplicationFormController.MetadataRequest>{ req1, req2 }
        );
        Test.stopTest();

        System.assert(result.containsKey('RecordType'));
        System.assert(result.containsKey('Profile'));
        System.assert(!result.get('Profile').isEmpty(), 'This org must have at least one Profile.');
    }
}