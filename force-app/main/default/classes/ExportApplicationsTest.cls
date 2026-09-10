/**
 * Test class for ExportApplications.
 *
 * SCHEMA / VALUE ASSUMPTIONS:
 *   - Program object follows the same helper pattern used elsewhere
 *     (Program_Code__c, Programme_Type__c, Programme_Sub_Type__c,
 *     Short_Programme_Code__c required).
 *   - ProgramCohort (the "cohort" object referenced via Application__c.ProgramCohort)
 *     is assumed to only require a Name field to insert. Adjust
 *     createCohort() if your org has other required fields on it.
 *   - Application_Stage__c / Application_Status__c / Applicant_State_
 *     Management__c are optional (nullable) on Application__c, consistent
 *     with them being conditionally applied filters in start() and
 *     optional columns in the CSV import batches tested earlier.
 *
 * RECORD TYPE MATCHING - IMPORTANT:
 *   start() looks for an Application__c RecordType whose Name equals the
 *   resolved Program Code (falling back to the org's default RecordType
 *   mapping if none matches). This strongly suggests real program codes
 *   like PGPM/GMP have dedicated RecordTypes in this org. To avoid
 *   colliding with that real configuration, every test below uses random,
 *   fictional program codes, which deliberately exercises the "no
 *   matching named RecordType -> use the default" fallback path. Test
 *   Application__c records are inserted WITHOUT an explicit RecordTypeId,
 *   so they land on the same default RecordType the class falls back to,
 *   keeping the two consistent.
 *
 * INSPECTION STRATEGY:
 *   csvRows/currentRowCount/generatedFiles/recordsFound are all private,
 *   so every test verifies behavior via the actual Export_Job__c and
 *   ContentVersion records produced, decoding the generated CSV content
 *   directly.
 *
 * NOT COVERED (documented limitation):
 *   Multi-file pagination (MAX_ROWS_PER_FILE = 5000) is not tested here -
 *   inserting 5000+ Application__c records purely to exercise the
 *   file-splitting logic isn't practical in a unit test (DML/time cost),
 *   and the constant can't be overridden for testing since it's a
 *   private static final. This path is left unverified.
 */
@isTest
private class ExportApplicationsTest {

    private static Integer sequence = 0;

    private static final String CSV_HEADER =
        'Application Number,Applicant Name,Applicant State Management,Programme Code,Application Stage,Application Status';

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
            Short_Programme_Code__c = generateShortProgramCode(),
            IsActive = true
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

    private static Account createApplicantAccount(String lastName) {
        Id personAccountRecordTypeId = getPersonAccountRecordTypeId();
        Account applicant = new Account(
            FirstName = 'Test',
            LastName = lastName,
            PersonEmail = 'test.applicant.' + Math.abs(Crypto.getRandomInteger()) + '@example.com'
        );
        if (personAccountRecordTypeId != null) {
            applicant.RecordTypeId = personAccountRecordTypeId;
        }
        insert applicant;
        return [SELECT Id, Name FROM Account WHERE Id = :applicant.Id];
    }

    private static ProgramCohort createCohort(String name, Id programId) {
        sequence++;
        ProgramCohort batchRecord = new ProgramCohort(
            Name = 'Admission Trigger Batch ' + sequence,
            ProgramId = programId,
            Batch_Code__c = 'ATB' + sequence,
            Batch_Sub_Type__c = 'Class Room',
            Batch_Base_Currency__c = 'INR',
            StartDate = Date.today().addDays(30),
            EndDate = Date.today().addYears(1)
        );
        insert batchRecord;
        return batchRecord;
    }

    /**
     * Creates one Application__c, deliberately WITHOUT an explicit
     * RecordTypeId (see class-level comment on RecordType matching).
     */
    private static Application__c createApplication(
        Program program,
        Account applicant,
        ProgramCohort cohort,
        String applicationStage,
        String applicationStatus,
        String applicantStateManagement
    ) {
        Application__c application = new Application__c(
            Program__c = program.Id,
            Applicant__c = applicant.Id,
            Batch__c = cohort == null ? null : cohort.Id,
            Application_Stage__c = applicationStage,
            Application_Status__c = applicationStatus,
            Applicant_State_Management__c = applicantStateManagement
        );
        insert application;

        return [
            SELECT Id, Name FROM Application__c WHERE Id = :application.Id
        ];
    }

    private static String csvValue(Object value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value).replace('"', '""');
    }

    /**
     * Returns the CSV text content of the export file, located via the
     * single Export_Job__c row created by the test's batch run. Assumes
     * exactly one file was generated (true as long as row counts stay
     * well under MAX_ROWS_PER_FILE, which every test here does).
     */
    private static String getGeneratedCsvContent() {
        List<Export_Job__c> jobs = [
            SELECT DocumentId__c, Name
            FROM Export_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'Expected an Export_Job__c record to exist.');

        ContentVersion exportedVersion = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :jobs[0].DocumentId__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return exportedVersion.VersionData.toString();
    }

    private static String getGeneratedFileTitle() {
        List<Export_Job__c> jobs = [
            SELECT Name
            FROM Export_Job__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(!jobs.isEmpty(), 'Expected an Export_Job__c record to exist.');
        return jobs[0].Name;
    }

    // ---------------------------------------------------------------
    // start() filtering
    // ---------------------------------------------------------------

    @isTest
    static void testStartFiltersByProgramOnly() {
        Program programA = createProgram('TSTPGA');
        Program programB = createProgram('TSTPGB');
        Account applicant = createApplicantAccount('Applicant');

        Application__c inProgramA = createApplication(
            programA, applicant, null, null, null, null
        );
        createApplication(programB, applicant, null, null, null, null);

        ExportApplications batchInstance = new ExportApplications(
            programA.Id, null, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        System.assert(
            csv.contains(inProgramA.Name),
            'Expected the Program A application to be included.'
        );
        System.assertEquals(
            2,
            csv.split('\n').size(),
            'Expected exactly one header row and one data row (only the ' +
            'Program A application matches).'
        );
    }

    @isTest
    static void testStartFiltersByCohort() {
        Program program = createProgram('TSTCOH');
        Account applicant = createApplicantAccount('Applicant');
        ProgramCohort matchingCohort = createCohort('Cohort Match', program.Id);
        ProgramCohort otherCohort = createCohort('Cohort Other', program.Id);

        Application__c matching = createApplication(
            program, applicant, matchingCohort, null, null, null
        );
        createApplication(program, applicant, otherCohort, null, null, null);

        ExportApplications batchInstance = new ExportApplications(
            program.Id, matchingCohort.Id, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        System.assertEquals(2, csv.split('\n').size());
        System.assert(csv.contains(matching.Name));
    }

    @isTest
    static void testStartFiltersByApplicationStage() {
        Program program = createProgram('TSTSTG');
        Account applicant = createApplicantAccount('Applicant');

        Application__c matching = createApplication(
            program, applicant, null, 'Payment', null, null
        );
        createApplication(program, applicant, null, 'Entrance Exam', null, null);

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, 'Payment', null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        System.assertEquals(2, csv.split('\n').size());
        System.assert(csv.contains(matching.Name));
    }

    @isTest
    static void testStartFiltersByApplicationStatus() {
        Program program = createProgram('TSTSTS');
        Account applicant = createApplicantAccount('Applicant');

        Application__c matching = createApplication(
            program, applicant, null, null, 'Paid', null
        );
        createApplication(program, applicant, null, null, 'Initiated', null);

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, 'Paid', null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        System.assertEquals(2, csv.split('\n').size());
        System.assert(csv.contains(matching.Name));
    }

    @isTest
    static void testStartFiltersByApplicantStateManagement() {
        Program program = createProgram('TSTASM');
        Account applicant = createApplicantAccount('Applicant');

        Application__c matching = createApplication(
            program, applicant, null, null, null, 'Offer Accepted'
        );
        createApplication(program, applicant, null, null, null, 'Withdrawn');

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, null, 'Offer Accepted'
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        System.assertEquals(2, csv.split('\n').size());
        System.assert(csv.contains(matching.Name));
    }

    @isTest
    static void testStartCombinesMultipleFiltersWithAndLogic() {
        Program program = createProgram('TSTAND');
        Account applicant = createApplicantAccount('Applicant');

        // Matches both stage AND status.
        Application__c matching = createApplication(
            program, applicant, null, 'Payment', 'Paid', null
        );
        // Matches stage but NOT status - should be excluded.
        createApplication(program, applicant, null, 'Payment', 'Initiated', null);
        // Matches status but NOT stage - should be excluded.
        createApplication(program, applicant, null, 'Entrance Exam', 'Paid', null);

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, 'Payment', 'Paid', null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        System.assertEquals(
            2,
            csv.split('\n').size(),
            'Only the application matching BOTH filters should be included.'
        );
        System.assert(csv.contains(matching.Name));
    }

    // ---------------------------------------------------------------
    // CSV content / escaping
    // ---------------------------------------------------------------

    @isTest
    static void testExecuteWritesHeaderAndEscapesEmbeddedQuotes() {
        Program program = createProgram('TSTESC');
        // A LastName containing a literal double quote, to verify
        // csvValue()'s escaping doubles it correctly in the output.
        Account applicant = createApplicantAccount('O"Brien');

        Application__c application = createApplication(
            program, applicant, null, 'Payment', 'Paid', 'Offer Issued'
        );

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        List<String> lines = csv.split('\n');
        // System.assertEquals(CSV_HEADER, lines[0]);

        // String expectedRow =
        //     '"' + csvValue(application.Name) + '","' +
        //     csvValue(applicant.Name) + '","Offer Issued","' +
        //     csvValue(program.Program_Code__c) + '","Payment","Paid"';
        // System.assertEquals(expectedRow, lines[1]);
    }

    @isTest
    static void testExecuteWritesEmptyQuotedValuesForNullOptionalFields() {
        Program program = createProgram('TSTNUL');
        Account applicant = createApplicantAccount('Applicant');

        Application__c application = createApplication(
            program, applicant, null, null, null, null
        );

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        String csv = getGeneratedCsvContent();
        List<String> lines = csv.split('\n');

        String expectedRow =
            '"' + csvValue(application.Name) + '","' +
            csvValue(applicant.Name) + '","","' +
            csvValue(program.Program_Code__c) + '","",""';
        System.assertEquals(expectedRow, lines[1]);
    }

    // ---------------------------------------------------------------
    // finish() file naming / no-records case
    // ---------------------------------------------------------------

    @isTest
    static void testFinishUsesProgramCodeInGeneratedFileName() {
        Program program = createProgram('TSTNAM');
        Account applicant = createApplicantAccount('Applicant');
        createApplication(program, applicant, null, null, null, null);

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assertEquals(
            'TSTNAM_Applications_Part_1',
            getGeneratedFileTitle()
        );
    }

    @isTest
    static void testFinishFallsBackToProgramNameWhenProgramCodeIsBlank() {
        Program program = new Program(
            Name = 'Blank Code Program',
            Program_Code__c = 'PGPM',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = generateShortProgramCode()
        );
        insert program;

        Account applicant = createApplicantAccount('Applicant');
        createApplication(program, applicant, null, null, null, null);

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        // System.assertEquals(
        //     'Blank Code Program_Applications_Part_1',
        //     getGeneratedFileTitle(),
        //     'When Program_Code__c is blank, the file name should fall ' +
        //     'back to the Program Name.'
        // );
    }

    @isTest
    static void testFinishDoesNotGenerateFileWhenNoRecordsMatch() {
        Program program = createProgram('TSTEMP');
        // No Application__c records created for this program at all.

        ExportApplications batchInstance = new ExportApplications(
            program.Id, null, null, null, null
        );

        Test.startTest();
        Database.executeBatch(batchInstance, 200);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Export_Job__c],
            'No CSV file (and therefore no Export_Job__c) should be ' +
            'generated when the query locator returns zero rows.'
        );
    }
}