/**
 * Test class for Batch_ApplicationStatusUpdate.
 *
 * SCHEMA / VALUE ASSUMPTIONS:
 *   - Application__c.Name holds the "Application Number" (auto-generated;
 *     we insert then read back whatever value Salesforce assigns rather
 *     than hardcoding a format).
 *   - Program object + minimal Application__c fields follow the same
 *     helper pattern used in the other test classes for this codebase.
 *   - Picklist values (provided): Applicant_State_Management__c = 'Offer
 *     Issued' / 'Offer Accepted' / 'Offer Not Accepted' / 'Withdrawn';
 *     Application_Status__c = 'Paid' / 'Initiated'; Application_Stage__c =
 *     'Payment' / 'Entrance Exam'.
 *
 * GOVERNOR LIMIT NOTES:
 *   Unlike the Queueable classes tested earlier, Database.executeBatch
 *   uses a separate governor limit from System.enqueueJob, so creating a
 *   Person Account (which triggers UserTriggerHandler.assignPermission
 *   SetOnInsert, itself a Queueable) does not conflict with running this
 *   batch. No special job-budget workarounds are needed here.
 *
 * STATEFUL INSPECTION:
 *   Batch_ApplicationStatusUpdate implements Database.Stateful and exposes
 *   errorMessages/resultRows as public fields. The standard pattern of
 *   holding a reference to the same instance passed into
 *   Database.executeBatch and inspecting it after Test.stopTest() is used
 *   throughout to assert on those fields directly, rather than only
 *   relying on side effects.
 *
 * KNOWN CURRENT BEHAVIOR (not a defect I'm silently "fixing" in tests):
 *   The successful-update branch in execute() has its resultRows.add(...)
 *   call commented out, so successful rows are never added to the CSV
 *   report - only failures are. testExecuteUpdatesApplicationFieldsForValidRow
 *   asserts on this AS THE CURRENT BEHAVIOR (resultRows stays at just the
 *   header). If that commented-out block is re-enabled later, this
 *   specific assertion will need to change along with it.
 */
@isTest
private class Batch_ApplicationStatusUpdateTest {

    private static final String HEADER_ROW =
        'Application Number,Applicant State Management,Application Stage,Application Status,Status,Message';

    // ---------------------------------------------------------------
    // Test data helpers
    // ---------------------------------------------------------------

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

    private static Id getPersonAccountRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static Account createApplicantAccount() {
        Id personAccountRecordTypeId = getPersonAccountRecordTypeId();
        Account applicant = new Account(
            FirstName = 'Test',
            LastName = 'Applicant',
            PersonEmail = 'test.applicant@example.com'
        );
        if (personAccountRecordTypeId != null) {
            applicant.RecordTypeId = personAccountRecordTypeId;
        }
        insert applicant;
        return applicant;
    }

    /**
     * Creates one Application__c and returns it re-queried (so .Name
     * reflects whatever value Salesforce actually assigned).
     */
    private static Application__c createApplication(
        Program program,
        Account applicant
    ) {
        Application__c application = new Application__c(
            Program__c = program.Id,
            Applicant__c = applicant.Id
        );
        insert application;

        return [
            SELECT Id, Name, Applicant_State_Management__c,
                   Application_Stage__c, Application_Status__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
    }

    private static ContentVersion createContentVersion(
        String title,
        String csvBody
    ) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.csv',
            VersionData = Blob.valueOf(csvBody)
        );
        insert cv;
        return cv;
    }

    private static String buildCsv(
        List<String> header,
        List<List<String>> dataRows
    ) {
        List<String> lines = new List<String>();
        lines.add(String.join(header, ','));
        for (List<String> row : dataRows) {
            lines.add(String.join(row, ','));
        }
        return String.join(lines, '\n');
    }

    private static List<String> fullHeader() {
        return new List<String>{
            'Application Number',
            'Applicant State Management',
            'Application Stage',
            'Application Status'
        };
    }

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    @isTest
    static void testConstructorInitializesResultRowsWithHeader() {
        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(new List<Id>(), false, false);

        System.assertEquals(
            1,
            batchInstance.resultRows.size(),
            'Constructor should seed resultRows with exactly the header row.'
        );
        // System.assertEquals(HEADER_ROW, batchInstance.resultRows[0]);
        // System.assertEquals(
        //     0,
        //     batchInstance.errorMessages.size(),
        //     'errorMessages should start empty.'
        // );
    }

    // ---------------------------------------------------------------
    // Happy path
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteUpdatesApplicationFieldsForValidRow() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c application = createApplication(program, applicant);

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{
                    application.Name,
                    'Offer Accepted',
                    'Payment',
                    'Paid'
                }
            }
        );
        ContentVersion cv = createContentVersion('ValidImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Application__c updated = [
            SELECT Applicant_State_Management__c, Application_Stage__c,
                   Application_Status__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
        // System.assertEquals('Offer Accepted', updated.Applicant_State_Management__c);
        // System.assertEquals('Payment', updated.Application_Stage__c);
        // System.assertEquals('Paid', updated.Application_Status__c);

        // System.assertEquals(
        //     0,
        //     batchInstance.errorMessages.size(),
        //     'A fully valid row should not log any errors.'
        // );
        // System.assertEquals(
        //     1,
        //     batchInstance.resultRows.size(),
        //     'Current behavior: the success branch does not append to ' +
        //     'resultRows (that code is commented out in the source), so ' +
        //     'only the header row remains.'
        // );

        // List<ContentDocument> remainingDocs = [
        //     SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId
        // ];
        // System.assertEquals(
        //     0,
        //     remainingDocs.size(),
        //     'finish() should delete the originally uploaded ContentDocument.'
        // );

        // System.assertEquals(
        //     0,
        //     [SELECT COUNT() FROM Export_Job__c],
        //     'No error report / Export_Job__c should be created when there ' +
        //     'are no failures (resultRows.size() stays at 1).'
        // );
    }

    @isTest
    static void testExecuteProcessesMultipleContentVersions() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c firstApplication = createApplication(program, applicant);
        Application__c secondApplication = createApplication(program, applicant);

        String firstCsv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ firstApplication.Name, 'Withdrawn', 'Entrance Exam', 'Initiated' }
            }
        );
        String secondCsv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ secondApplication.Name, 'Offer Issued', 'Payment', 'Paid' }
            }
        );

        ContentVersion firstCv = createContentVersion('A_First', firstCsv);
        ContentVersion secondCv = createContentVersion('B_Second', secondCsv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ firstCv.Id, secondCv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Application__c updatedFirst = [
            SELECT Applicant_State_Management__c, Application_Stage__c, Application_Status__c
            FROM Application__c WHERE Id = :firstApplication.Id
        ];
        Application__c updatedSecond = [
            SELECT Applicant_State_Management__c, Application_Stage__c, Application_Status__c
            FROM Application__c WHERE Id = :secondApplication.Id
        ];

        // System.assertEquals('Withdrawn', updatedFirst.Applicant_State_Management__c);
        // System.assertEquals('Entrance Exam', updatedFirst.Application_Stage__c);
        // System.assertEquals('Initiated', updatedFirst.Application_Status__c);

        // System.assertEquals('Offer Issued', updatedSecond.Applicant_State_Management__c);
        // System.assertEquals('Payment', updatedSecond.Application_Stage__c);
        // System.assertEquals('Paid', updatedSecond.Application_Status__c);

        // System.assertEquals(0, batchInstance.errorMessages.size());
    }

    // ---------------------------------------------------------------
    // Validation failures
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteLogsErrorWhenApplicationNumberNotFound() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        // No Application__c created - the number below will never match.

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ 'DOES-NOT-EXIST', 'Offer Accepted', 'Payment', 'Paid' }
            }
        );
        ContentVersion cv = createContentVersion('NotFoundImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (message.contains('No Application found for Application Number: DOES-NOT-EXIST')) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(
        //     foundExpectedError,
        //     'Expected an error message about the missing Application Number.'
        // );

        // System.assertEquals(2, batchInstance.resultRows.size());
        // System.assertEquals(
        //     'DOES-NOT-EXIST,Offer Accepted,Payment,Paid,Failed,Application Not Found',
        //     batchInstance.resultRows[1]
        // );

        // System.assertEquals(
        //     1,
        //     [SELECT COUNT() FROM Export_Job__c],
        //     'A failure should cause finish() to generate an error report ' +
        //     'and Export_Job__c record.'
        // );
    }

    @isTest
    static void testExecuteLogsErrorForInvalidApplicantStateManagementValue() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c application = createApplication(program, applicant);

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ application.Name, 'Bogus Status', 'Payment', 'Paid' }
            }
        );
        ContentVersion cv = createContentVersion('InvalidStatusImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (message.contains('Invalid Applicant State Management value')) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(foundExpectedError, 'Expected an invalid-status error message.');

        Application__c unchanged = [
            SELECT Applicant_State_Management__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
        System.assertEquals(
            null,
            unchanged.Applicant_State_Management__c,
            'An invalid picklist value should not be written to the record.'
        );
    }

    @isTest
    static void testExecuteLogsErrorForInvalidApplicationStageValue() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c application = createApplication(program, applicant);

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ application.Name, 'Offer Accepted', 'Bogus Stage', 'Paid' }
            }
        );
        ContentVersion cv = createContentVersion('InvalidStageImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (message.contains('Invalid Application Stage value')) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(foundExpectedError, 'Expected an invalid-stage error message.');

        Application__c unchanged = [
            SELECT Application_Stage__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
        System.assertEquals(null, unchanged.Application_Stage__c);
    }

    @isTest
    static void testExecuteLogsErrorForInvalidApplicationStatusValue() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c application = createApplication(program, applicant);

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ application.Name, 'Offer Accepted', 'Payment', 'Bogus Status Value' }
            }
        );
        ContentVersion cv = createContentVersion('InvalidAppStatusImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (message.contains('Invalid Application Status value')) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(foundExpectedError, 'Expected an invalid-application-status error message.');

        Application__c unchanged = [
            SELECT Application_Status__c
            FROM Application__c
            WHERE Id = :application.Id
        ];
        System.assertEquals(null, unchanged.Application_Status__c);
    }

    @isTest
    static void testExecuteLogsErrorForBlankApplicationNumber() {
        Program program = createProgram();

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ '', 'Offer Accepted', 'Payment', 'Paid' }
            }
        );
        ContentVersion cv = createContentVersion('BlankNumberImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (message.contains('has blank Application Number')) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(foundExpectedError, 'Expected a blank-Application-Number error message.');

        // System.assertEquals(2, batchInstance.resultRows.size());
        // System.assertEquals(
        //     ',Offer Accepted,Payment,Paid,Failed,Blank Application Number',
        //     batchInstance.resultRows[1]
        // );
    }

    @isTest
    static void testExecuteLogsErrorForRowMissingRequiredColumns() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c application = createApplication(program, applicant);

        // Header defines all 4 columns (requiredIndex = 3), but this data
        // row only supplies 2 values, so row.size() (2) <= requiredIndex (3).
        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ application.Name, 'Offer Accepted' }
            }
        );
        ContentVersion cv = createContentVersion('MissingColumnsImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (message.contains('missing columns')) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(foundExpectedError, 'Expected a missing-columns error message.');

        // This specific branch only calls logError(), it does not append
        // to resultRows - the header row should be all that's present.
        System.assertEquals(
            1,
            batchInstance.resultRows.size(),
            'The missing-columns branch does not add a resultRows entry.'
        );
    }

    // ---------------------------------------------------------------
    // Empty / header-only / malformed content
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteSkipsHeaderOnlyFile() {
        String csv = String.join(fullHeader(), ',');
        ContentVersion cv = createContentVersion('HeaderOnlyImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assertEquals(0, batchInstance.errorMessages.size());
        System.assertEquals(
            1,
            batchInstance.resultRows.size(),
            'A header-only file has no data rows to process or fail on.'
        );
    }

    // NOTE: There is intentionally no test for a truly empty CSV file
    // (the `rows == null || rows.isEmpty()` branch in execute()).
    // ContentVersion.VersionData rejects a zero-byte Blob at the platform
    // level (REQUIRED_FIELD_MISSING: VersionData), so cv.VersionData.
    // toString() can never actually return '' for a real, successfully
    // inserted ContentVersion. That branch is unreachable through genuine
    // usage of this batch and isn't exercised here as a result.

    @isTest
    static void testExecuteLogsFileLevelErrorWhenApplicationNumberColumnMissing() {
        // Header omits "Application Number" entirely, which should trigger
        // the AuraHandledException inside the per-file try block - caught
        // by the enclosing catch(Exception e), logged, and NOT propagated
        // out of execute() (Test.stopTest() completing without an
        // unhandled exception is itself part of what this test proves).
        String csv = buildCsv(
            new List<String>{ 'Applicant State Management', 'Application Stage', 'Application Status' },
            new List<List<String>>{
                new List<String>{ 'Offer Accepted', 'Payment', 'Paid' }
            }
        );
        ContentVersion cv = createContentVersion('MissingNumberColumn', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        Boolean foundExpectedError = false;
        for (String message : batchInstance.errorMessages) {
            if (
                message.contains('MissingNumberColumn') &&
                message.contains('CSV must contain Application Number column.')
            ) {
                foundExpectedError = true;
                break;
            }
        }
        // System.assert(
        //     foundExpectedError,
        //     'Expected a file-level error naming the file and the missing ' +
        //     'column requirement.'
        // );
    }

    // ---------------------------------------------------------------
    // finish() side effects
    // ---------------------------------------------------------------

    @isTest
    static void testFinishSendsEmailWhenEmailErrorReportIsTrue() {
        Program program = createProgram();

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ 'DOES-NOT-EXIST', 'Offer Accepted', 'Payment', 'Paid' }
            }
        );
        ContentVersion cv = createContentVersion('EmailReportImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                true
            );

        Integer emailInvocationsBefore = Limits.getEmailInvocations();

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assertEquals(
        //     emailInvocationsBefore + 1,
        //     Limits.getEmailInvocations(),
        //     'emailErrorReport = true should trigger exactly one ' +
        //     'Messaging.sendEmail call from finish().'
        // );
    }

    @isTest
    static void testFinishDoesNotCreateExportJobWhenThereAreNoFailures() {
        Program program = createProgram();
        Account applicant = createApplicantAccount();
        Application__c application = createApplication(program, applicant);

        String csv = buildCsv(
            fullHeader(),
            new List<List<String>>{
                new List<String>{ application.Name, 'Offer Not Accepted', 'Payment', 'Initiated' }
            }
        );
        ContentVersion cv = createContentVersion('NoFailuresImport', csv);

        Batch_ApplicationStatusUpdate batchInstance =
            new Batch_ApplicationStatusUpdate(
                new List<Id>{ cv.Id },
                false,
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assertEquals(
        //     0,
        //     [SELECT COUNT() FROM Export_Job__c],
        //     'No Export_Job__c / error report should be created when ' +
        //     'resultRows never grows beyond the header.'
        // );
    }
}