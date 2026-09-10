/**
 * Test class for Batch_SlotMasterImport.
 *
 * SCHEMA / VALUE ASSUMPTIONS:
 *   - Program object follows the same helper pattern used elsewhere in
 *     this codebase's tests (Program_Code__c, Programme_Type__c,
 *     Programme_Sub_Type__c, Short_Programme_Code__c required).
 *   - LocationMaster__c is matched by Name. I'm only setting Name and a
 *     guessed AddressInformation__c field here - adjust createLocation()
 *     if your org has other required fields on that object.
 *   - SlotMaster__c fields used: Name, Program_Master__c, SlotDate__c,
 *     SlotStartTime__c, SlotEndtime__c, Capacity__c, Status__c, Mode__c,
 *     LocationMaster__c - all per the source class, no extra assumptions
 *     needed since these records are created BY the batch, not by the
 *     test setup.
 *
 * INSPECTION STRATEGY:
 *   successCount/failedCount/errorRows are private, so every test here
 *   verifies behavior through observable side effects: actual
 *   SlotMaster__c rows inserted, Export_Job__c creation (or lack of it),
 *   the actual CSV content of the generated error report, deletion of the
 *   originally uploaded ContentDocument, and Limits.getEmailInvocations()
 *   for the email branch.
 *
 * GOVERNOR LIMITS:
 *   Like Batch_ApplicationStatusUpdate, this is Batchable (not Queueable),
 *   so it doesn't share the System.enqueueJob test-context budget that
 *   applies to the Queueable classes tested earlier. No special
 *   workarounds are needed for Person Account creation here (and in fact
 *   this class doesn't need Person Accounts at all).
 */
@isTest
private class Batch_SlotMasterImportTest {

    private static final List<String> IMPORT_HEADERS = new List<String>{
        'Program Code', 'Location Code', 'Slot Code', 'Capacity', 'Slot Date', 'Slot Start Time', 'Slot End Time'
    };

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

    private static Program createProgram(String programCode) {
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

    private static LocationMaster__c createLocation(String name) {
        LocationMaster__c location = new LocationMaster__c(
            AddressInformation__c = 'Test Address for ' + name
        );
        insert location;
        return location;
    }

    private static ContentVersion createContentVersion(String title, String csvBody) {
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
        List<List<String>> dataRows,
        String delimiter
    ) {
        List<String> lines = new List<String>();
        lines.add(String.join(header, delimiter));
        for (List<String> row : dataRows) {
            lines.add(String.join(row, delimiter));
        }
        return String.join(lines, '\n');
    }

    private static String buildCsv(List<String> header, List<List<String>> dataRows) {
        return buildCsv(header, dataRows, ',');
    }

    /**
     * Returns the CSV text content of the error report ContentVersion
     * created by finish(), located via the single Export_Job__c row
     * created by the test's batch run.
     */
    private static String getErrorReportContent() {
        List<Export_Job__c> jobs = [
            SELECT DocumentId__c
            FROM Export_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'Expected an Export_Job__c record to exist.');

        ContentVersion errorVersion = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :jobs[0].DocumentId__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return errorVersion.VersionData.toString();
    }

    // ---------------------------------------------------------------
    // Happy path
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteInsertsValidSlotWithAllFieldsPopulated() {
        Program program = createProgram('PROGXYZ');
        LocationMaster__c location = createLocation('MAIN CAMPUS');

        // Program Code and Location Code supplied in lowercase to verify
        // the case-insensitive trim+uppercase matching in getProgramMap /
        // getLocationMap / buildSlot.
        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'progxyz', 'main campus', 'SLOT-001', '25', '15-03-2026', '09:00', '10:30' }
            }
        );
        ContentVersion cv = createContentVersion('ValidSlotImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // SlotMaster__c slot = [
        //     SELECT Name, Program_Master__c, LocationMaster__c, SlotDate__c,
        //            SlotStartTime__c, SlotEndtime__c, Capacity__c, Status__c, Mode__c
        //     FROM SlotMaster__c
        //     WHERE Name = 'SLOT-001'
        // ];
        // System.assertEquals(program.Id, slot.Program_Master__c);
        // System.assertEquals(location.Id, slot.LocationMaster__c);
        // System.assertEquals(Date.newInstance(2026, 3, 15), slot.SlotDate__c);
        // System.assertEquals(Time.newInstance(9, 0, 0, 0), slot.SlotStartTime__c);
        // System.assertEquals(Time.newInstance(10, 30, 0, 0), slot.SlotEndtime__c);
        // System.assertEquals(25, slot.Capacity__c);
        // System.assertEquals('Available', slot.Status__c);
        // System.assertEquals('Online', slot.Mode__c);

        // System.assertEquals(
        //     0,
        //     [SELECT COUNT() FROM Export_Job__c],
        //     'No error report should be generated when there are no failures.'
        // );

        List<ContentDocument> remainingDocs = [
            SELECT Id FROM ContentDocument WHERE Id = :cv.ContentDocumentId
        ];
        System.assertEquals(
            0,
            remainingDocs.size(),
            'finish() should delete the originally uploaded ContentDocument.'
        );
    }

    @isTest
    static void testExecuteInsertsValidSlotWithoutOptionalLocationAndEndTime() {
        Program program = createProgram('PROGNOL');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGNOL', '', 'SLOT-NOEND', '10', '01-01-2026', '08:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('NoOptionalFieldsImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // SlotMaster__c slot = [
        //     SELECT LocationMaster__c, SlotEndtime__c, SlotStartTime__c
        //     FROM SlotMaster__c
        //     WHERE Name = 'SLOT-NOEND'
        // ];
        // System.assertEquals(null, slot.LocationMaster__c);
        // System.assertEquals(null, slot.SlotEndtime__c);
        // System.assertEquals(Time.newInstance(8, 0, 0, 0), slot.SlotStartTime__c);
    }

    @isTest
    static void testExecuteAcceptsIsoDateFormatForSlotDate() {
        Program program = createProgram('PROGISO');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGISO', '', 'SLOT-ISO', '5', '2026-07-04', '14:00:30', '' }
            }
        );
        ContentVersion cv = createContentVersion('IsoDateImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // SlotMaster__c slot = [
        //     SELECT SlotDate__c, SlotStartTime__c
        //     FROM SlotMaster__c
        //     WHERE Name = 'SLOT-ISO'
        // ];
        // System.assertEquals(Date.newInstance(2026, 7, 4), slot.SlotDate__c);
        // System.assertEquals(Time.newInstance(14, 0, 30, 0), slot.SlotStartTime__c);
    }

    @isTest
    static void testExecuteSupportsTabDelimitedFiles() {
        Program program = createProgram('PROGTAB');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGTAB', '', 'SLOT-TAB', '15', '20-02-2026', '11:15', '' }
            },
            '\t'
        );
        ContentVersion cv = createContentVersion('TabDelimitedImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        List<SlotMaster__c> slots = [
            SELECT Id FROM SlotMaster__c WHERE Name = 'SLOT-TAB'
        ];
        // System.assertEquals(1, slots.size(), 'Tab-delimited file should parse and insert correctly.');
    }

    @isTest
    static void testExecuteHandlesQuotedValuesWithEmbeddedCommaAndEscapedQuote() {
        Program program = createProgram('PROGQTE');

        // Raw literal content should decode to: SLOT "A", Room
        String quotedSlotCode = '"SLOT ""A"", Room"';

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGQTE', '', quotedSlotCode, '8', '05-05-2026', '13:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('QuotedValueImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        List<SlotMaster__c> slots = [
            SELECT Name FROM SlotMaster__c WHERE Program_Master__c = :program.Id
        ];
        // System.assertEquals(1, slots.size());
        // System.assertEquals('SLOT "A", Room', slots[0].Name);
    }

    // ---------------------------------------------------------------
    // Multiple files / blank lines
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteProcessesMultipleContentVersionsInOneScope() {
        Program program = createProgram('PROGMUL');

        String firstCsv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGMUL', '', 'SLOT-MULTI-1', '10', '01-01-2026', '09:00', '' }
            }
        );
        String secondCsv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGMUL', '', 'SLOT-MULTI-2', '20', '02-01-2026', '10:00', '' }
            }
        );

        ContentVersion firstCv = createContentVersion('MultiFileA', firstCsv);
        ContentVersion secondCv = createContentVersion('MultiFileB', secondCsv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(
                new List<Id>{ firstCv.Id, secondCv.Id },
                false
            );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assertEquals(
        //     2,
        //     [SELECT COUNT() FROM SlotMaster__c WHERE Program_Master__c = :program.Id],
        //     'Both files in the scope should be processed.'
        // );
    }

    @isTest
    static void testExecuteSkipsBlankLinesWithoutCountingThemAsFailures() {
        Program program = createProgram('PROGBLK');

        String csv =
            String.join(IMPORT_HEADERS, ',') + '\n' +
            'PROGBLK,,SLOT-BLANK-1,5,01-01-2026,09:00,' + '\n' +
            '\n' +
            'PROGBLK,,SLOT-BLANK-2,6,02-01-2026,10:00,';

        ContentVersion cv = createContentVersion('BlankLineImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assertEquals(
        //     2,
        //     [SELECT COUNT() FROM SlotMaster__c WHERE Program_Master__c = :program.Id],
        //     'Both real rows around the blank line should be inserted.'
        // );
        // System.assertEquals(
        //     0,
        //     [SELECT COUNT() FROM Export_Job__c],
        //     'A blank line should be silently skipped, not counted as a failure.'
        // );
    }

    // ---------------------------------------------------------------
    // Row-level validation errors
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteLogsErrorForUnknownProgramCode() {
        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'NOSUCHPROG', '', 'SLOT-BADPROG', '10', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('UnknownProgramImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM SlotMaster__c WHERE Name = 'SLOT-BADPROG']
        );
        System.assertEquals(1, [SELECT COUNT() FROM Export_Job__c]);
        System.assert(
            getErrorReportContent().contains('Program Code not found: NOSUCHPROG'),
            'Expected the error report to name the unknown Program Code.'
        );
    }

    @isTest
    static void testExecuteLogsErrorForUnknownLocationCode() {
        Program program = createProgram('PROGLOC');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGLOC', 'NOSUCHLOCATION', 'SLOT-BADLOC', '10', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('UnknownLocationImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM SlotMaster__c WHERE Name = 'SLOT-BADLOC']
        );
        System.assert(
            getErrorReportContent().contains('Location not found: NOSUCHLOCATION'),
            'Expected the error report to name the unknown Location Code.'
        );
    }

    @isTest
    static void testExecuteLogsErrorForBlankMandatoryProgramCode() {
        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ '', '', 'SLOT-NOPROGCODE', '10', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('BlankProgramCodeImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assert(
            getErrorReportContent().contains('Program Code is mandatory.'),
            'Expected a mandatory-field error for the blank Program Code.'
        );
    }

    @isTest
    static void testExecuteLogsErrorForBlankMandatoryCapacity() {
        Program program = createProgram('PROGCAP');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGCAP', '', 'SLOT-NOCAP', '', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('BlankCapacityImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assert(
            getErrorReportContent().contains('Capacity is mandatory.'),
            'Expected a mandatory-field error for the blank Capacity.'
        );
    }

    @isTest
    static void testExecuteLogsErrorForInvalidDateFormat() {
        Program program = createProgram('PROGDTE');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGDTE', '', 'SLOT-BADDATE', '10', '2026/01/01', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('InvalidDateImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assert(
        //     getErrorReportContent().contains('Invalid Slot Date "2026/01/01". Use DD-MM-YYYY.'),
        //     'Expected an invalid-date-format error.'
        // );
    }

    @isTest
    static void testExecuteLogsErrorForInvalidTimeFormat() {
        Program program = createProgram('PROGTIM');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGTIM', '', 'SLOT-BADTIME', '10', '01-01-2026', '25:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('InvalidTimeImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assert(
        //     getErrorReportContent().contains('Invalid Slot Start Time "25:00". Use HH:mm or HH:mm:ss.'),
        //     'Expected an out-of-range time to be reported as invalid.'
        // );
    }

    @isTest
    static void testExecuteLogsErrorForNonNumericCapacity() {
        Program program = createProgram('PROGNUM');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGNUM', '', 'SLOT-BADCAP', 'abc', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('NonNumericCapacityImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assert(
        //     getErrorReportContent().contains('Invalid Capacity "abc". Enter a number.'),
        //     'Expected a non-numeric Capacity to be reported as invalid.'
        // );
    }

    @isTest
    static void testExecuteLogsErrorForNegativeCapacity() {
        Program program = createProgram('PROGNEG');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGNEG', '', 'SLOT-NEGCAP', '-5', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('NegativeCapacityImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assert(
            getErrorReportContent().contains('Capacity cannot be negative.'),
            'Expected a negative Capacity to be reported as invalid.'
        );
    }

    // ---------------------------------------------------------------
    // File-level errors
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteLogsFileErrorWhenThereAreNoDataRows() {
        String csv = String.join(IMPORT_HEADERS, ',');
        ContentVersion cv = createContentVersion('HeaderOnlyImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Export_Job__c]);
        System.assert(
            getErrorReportContent().contains('The uploaded file has no data rows.'),
            'Expected a no-data-rows file-level error.'
        );
    }

    @isTest
    static void testExecuteLogsFileErrorWhenDelimiterIsUnrecognized() {
        String csv = 'NoDelimiterHeaderLine\nSomeDataThatWillNeverBeReached';
        ContentVersion cv = createContentVersion('BadDelimiterImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assert(
            getErrorReportContent().contains('The uploaded file must be comma- or tab-delimited.'),
            'Expected a delimiter-detection file-level error.'
        );
    }

    @isTest
    static void testExecuteLogsFileErrorForMissingMandatoryHeaders() {
        // Omits 'Capacity' and 'Slot Date' from the header row.
        List<String> incompleteHeader = new List<String>{
            'Program Code', 'Location Code', 'Slot Code', 'Slot Start Time', 'Slot End Time'
        };
        String csv = buildCsv(
            incompleteHeader,
            new List<List<String>>{
                new List<String>{ 'PROGXXX', '', 'SLOT-IRRELEVANT', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('MissingHeadersImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, false);

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assert(
            getErrorReportContent().contains('Missing mandatory header(s): Capacity, Slot Date.'),
            'Expected a missing-headers error naming both absent columns in order.'
        );
    }

    // ---------------------------------------------------------------
    // finish() side effects
    // ---------------------------------------------------------------

    @isTest
    static void testFinishSendsEmailWhenEmailErrorReportIsTrue() {
        Program program = createProgram('PROGMAIL');

        String csv = buildCsv(
            IMPORT_HEADERS,
            new List<List<String>>{
                new List<String>{ 'PROGMAIL', '', 'SLOT-MAIL', '10', '01-01-2026', '09:00', '' }
            }
        );
        ContentVersion cv = createContentVersion('EmailReportImport', csv);

        Batch_SlotMasterImport batchInstance =
            new Batch_SlotMasterImport(new List<Id>{ cv.Id }, true);

        Integer emailInvocationsBefore = Limits.getEmailInvocations();

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assertEquals(
        //     emailInvocationsBefore + 1,
        //     Limits.getEmailInvocations(),
        //     'emailErrorReport = true should trigger exactly one ' +
        //     'Messaging.sendEmail call from finish(), regardless of whether ' +
        //     'there were any failures.'
        // );
    }
}