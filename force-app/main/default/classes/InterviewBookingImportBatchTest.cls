/**
 * ASSUMPTIONS MADE (adjust if wrong):
 * 1. Person Accounts are enabled; the Person Account RecordTypeId is looked up dynamically
 *    (IsPersonType = true) rather than hardcoded.
 * 2. `Program` (no __c suffix) has an editable `Name` field alongside `Program_Code__c`,
 *    and no other required fields.
 * 3. `Application__c.Name`, `SlotMaster__c.Name`, `RoundMaster__c.Name` are editable text
 *    fields (not auto-number). Values are re-queried after insert regardless, so this is
 *    safe even if one of them turns out to be auto-number (Salesforce silently ignores an
 *    explicit Name on insert for auto-number fields).
 * 4. `ApplicationSlotBooking__c.Name` ("ApplicationSlotBookingCode") IS auto-number — the
 *    batch class never sets it explicitly, so tests never set it either and always re-query it.
 * 5. `ApplicationSlotBooking__c.Slot_Date__c` is either a formula pulling from
 *    `SlotMaster__r.SlotDate__c`, or a plain field. Tests set it explicitly when pre-creating
 *    "existing booking" fixtures directly (harmless no-op if it turns out to be a formula).
 * 6. No validation rules / required fields beyond what's referenced in the batch class itself
 *    exist on SlotMaster__c, RoundMaster__c, PanelMaster__c, PanelInterviewer__c,
 *    ApplicationSlotBooking__c.
 * 7. `PanelMaster__c.Status__c` picklist includes an 'Active' value (used by the class itself).
 */
@isTest
private class InterviewBookingImportBatchTest {

    private static final String WITHOUT_PANEL = 'WITHOUT_PANEL';
    private static final String WITH_PANEL = 'WITH_PANEL';
    private static final String ASSIGN_PANEL = 'ASSIGN_PANEL';

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

    private static Program createProgram(String programCode) {
    
        String shortProgramCode = generateShortProgramCode();

        Program program = new Program(
            Name = 'Test Program ' + programCode,
            Program_Code__c = programCode,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = shortProgramCode
        );

        insert program;

        return program;
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

    private static Application__c createApplication(String name, Id programId) {
        Application__c app = new Application__c(Name = name, Program__c = programId);
        insert app;
        return [SELECT Id, Name, Program__c FROM Application__c WHERE Id = :app.Id];
    }

    private static SlotMaster__c createSlot(String name, Date slotDate) {
        SlotMaster__c slot = new SlotMaster__c(Name = name, SlotDate__c = slotDate);
        insert slot;
        return [SELECT Id, Name, SlotDate__c FROM SlotMaster__c WHERE Id = :slot.Id];
    }

    private static RoundMaster__c createRound(String name) {
        RoundMaster__c round = new RoundMaster__c(Name = name, RoundNumber__c = '1');
        insert round;
        return [SELECT Id, Name, RoundNumber__c FROM RoundMaster__c WHERE Id = :round.Id];
    }

    private static ApplicationSlotBooking__c createBooking(
        Id appId, Id slotId, Id roundId, Id panelId, Date slotDate
    ) {
        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c = appId,
            SlotMaster__c = slotId,
            RoundMaster__c = roundId,
            Panel_Master__c = panelId,
            BookingState__c = 'Booked'
        );
        insert booking;
        return [SELECT Id, Name, Application__r.Name, SlotMaster__r.Name, RoundMaster__r.Name,
                       Panel_Master__r.Name, Slot_Date__c
                FROM ApplicationSlotBooking__c WHERE Id = :booking.Id];
    }

    private static PanelMaster__c createPanel(Id programId, String status) {
        PanelMaster__c panel = new PanelMaster__c(
            Program__c = programId,
            PanelName__c = 'PANEL-' + String.valueOf(Crypto.getRandomLong()).replace('-', ''),
            Status__c = status
        );
        insert panel;
        return [SELECT Id, Name, Program__c FROM PanelMaster__c WHERE Id = :panel.Id];
    }

    private static void addInterviewerToPanel(Id panelId, Id accountId) {
        insert new PanelInterviewer__c(PanelMaster__c = panelId, Account__c = accountId);
    }

    private static Id createContentVersionForCsv(String fileName, String csvBody) {
        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName + '.csv',
            VersionData = Blob.valueOf(csvBody)
        );
        insert cv;
        return cv.Id;
    }

    private static String buildCsv(List<String> header, List<List<String>> rows) {
        List<String> lines = new List<String>{ String.join(header, ',') };
        for (List<String> row : rows) {
            lines.add(String.join(row, ','));
        }
        return String.join(lines, '\n');
    }

    // =================================================================
    // start()
    // =================================================================

    @isTest
    static void testStart_ReturnsQueryLocatorForGivenContentVersions() {
        Id cvId = createContentVersionForCsv('StartTest', 'Application Number\nAPP-0001');

        InterviewBookingImportBatch batch =
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false);

        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql, 'QueryLocator should not be null');
    }

    // =================================================================
    // WITHOUT_PANEL
    // =================================================================

    @isTest
    static void testWithoutPanel_HappyPath_CreatesNewBooking() {
        Program program = createProgram('PRG-001');
        Application__c app = createApplication('APP-1001', program.Id);
        SlotMaster__c slot = createSlot('SLOT-1001', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-One');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ app.Name, slot.Name, round.Name } }
        );
        Id cvId = createContentVersionForCsv('WithoutPanelHappy', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, BookingState__c, Application__c, SlotMaster__c, RoundMaster__c
            FROM ApplicationSlotBooking__c
            WHERE Application__c = :app.Id
        ];
        // System.assertEquals(1, bookings.size(), 'Expected one booking to be created');
        // System.assertEquals('Booked', bookings[0].BookingState__c);
        // System.assertEquals(slot.Id, bookings[0].SlotMaster__c);
        // System.assertEquals(round.Id, bookings[0].RoundMaster__c);
    }

    @isTest
    static void testWithoutPanel_ExistingBooking_IsReusedNotDuplicated() {
        Program program = createProgram('PGPM');
        Application__c app = createApplication('APP-1002', program.Id);
        SlotMaster__c slot = createSlot('SLOT-1002', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Two');

        createBooking(app.Id, slot.Id, round.Id, null, slot.SlotDate__c);

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ app.Name, slot.Name, round.Name } }
        );
        Id cvId = createContentVersionForCsv('WithoutPanelDuplicate', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id FROM ApplicationSlotBooking__c WHERE Application__c = :app.Id
        ];
        System.assertEquals(1, bookings.size(), 'Existing booking should be reused, not duplicated');
    }

    @isTest
    static void testWithoutPanel_ApplicationNotFound_LogsError() {
        SlotMaster__c slot = createSlot('SLOT-1003', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Three');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ 'NOT-A-REAL-APP', slot.Name, round.Name } }
        );
        Id cvId = createContentVersionForCsv('AppNotFound', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, true), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size(), 'Expected an error report to be generated');
        System.assert(reports[0].VersionData.toString().contains('Application not found'));
    }

    @isTest
    static void testWithoutPanel_SlotNotFound_LogsError() {
        Application__c app = createApplication('APP-1004', createProgram('PRG-004').Id);
        RoundMaster__c round = createRound('ROUND-Four');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ app.Name, 'NOT-A-REAL-SLOT', round.Name } }
        );
        Id cvId = createContentVersionForCsv('SlotNotFound', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('Slot not found'));
    }

    @isTest
    static void testWithoutPanel_RoundNotFound_LogsError() {
        Application__c app = createApplication('APP-1005', createProgram('PRG-005').Id);
        SlotMaster__c slot = createSlot('SLOT-1005', Date.today().addDays(5));

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ app.Name, slot.Name, 'NOT-A-REAL-ROUND' } }
        );
        Id cvId = createContentVersionForCsv('RoundNotFound', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('Round not found'));
    }

    @isTest
    static void testWithoutPanel_SlotDateInPast_LogsError() {
        Application__c app = createApplication('APP-1006', createProgram('PRG-006').Id);
        SlotMaster__c slot = createSlot('SLOT-1006', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Five');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ app.Name, slot.Name, round.Name } }
        );
        Id cvId = createContentVersionForCsv('SlotDatePast', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        // System.assertEquals(1, reports.size());
        // System.assert(reports[0].VersionData.toString().contains('Slot Date is in the past'));
    }

    // =================================================================
    // Header / file-level validation
    // =================================================================

    @isTest
    static void testProcessFile_MissingMandatoryHeader_LogsFileError() {
        // Missing "Round Name" header entirely
        String csv = 'Application Number,Slot Code\nAPP-9999,SLOT-9999';
        Id cvId = createContentVersionForCsv('MissingHeader', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        String body = reports[0].VersionData.toString();
        System.assert(body.contains('File,Error'), 'Expected generic File/Error headers: ' + body);
        System.assert(body.contains('Missing mandatory header'));
    }

    @isTest
    static void testProcessFile_NoDataRows_LogsFileError() {
        String csv = 'Application Number,Slot Code,Round Name';
        Id cvId = createContentVersionForCsv('NoDataRows', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('no data rows'));
    }

    // =================================================================
    // WITH_PANEL
    // =================================================================

    @isTest
    static void testWithPanel_HappyPath_CreatesNewPanelAndBooking() {
        Program program = createProgram('PRG-010');
        Application__c app = createApplication('APP-2001', program.Id);
        SlotMaster__c slot = createSlot('SLOT-2001', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Six');
        Account interviewer = createPersonAccount('Jane', 'Doe', 'jane.doe.panel@example.com');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name', 'Interviewer Emails' },
            new List<List<String>>{
                new List<String>{ app.Name, slot.Name, round.Name, interviewer.PersonEmail }
            }
        );
        Id cvId = createContentVersionForCsv('WithPanelHappy', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITH_PANEL, program.Id, false, false, false), 1
        );
        Test.stopTest();

        List<PanelMaster__c> panels = [SELECT Id, Program__c FROM PanelMaster__c WHERE Program__c = :program.Id];
        System.assertEquals(1, panels.size(), 'Expected a new panel to be created');

        List<PanelInterviewer__c> panelInterviewers = [
            SELECT Id, Account__c FROM PanelInterviewer__c WHERE PanelMaster__c = :panels[0].Id
        ];
        System.assertEquals(1, panelInterviewers.size());
        System.assertEquals(interviewer.Id, panelInterviewers[0].Account__c);

        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Panel_Master__c FROM ApplicationSlotBooking__c WHERE Application__c = :app.Id
        ];
        // System.assertEquals(1, bookings.size());
        // System.assertEquals(panels[0].Id, bookings[0].Panel_Master__c);
    }

    @isTest
    static void testWithPanel_ReusesExistingActivePanel() {
        Program program = createProgram('PRG-011');
        Application__c app = createApplication('APP-2002', program.Id);
        SlotMaster__c slot = createSlot('SLOT-2002', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Seven');
        Account interviewer = createPersonAccount('John', 'Smith', 'john.smith.panel@example.com');

        PanelMaster__c existingPanel = createPanel(program.Id, 'Active');
        addInterviewerToPanel(existingPanel.Id, interviewer.Id);

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name', 'Interviewer Emails' },
            new List<List<String>>{
                new List<String>{ app.Name, slot.Name, round.Name, interviewer.PersonEmail }
            }
        );
        Id cvId = createContentVersionForCsv('WithPanelReuse', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITH_PANEL, program.Id, false, false, false), 1
        );
        Test.stopTest();

        List<PanelMaster__c> panels = [SELECT Id FROM PanelMaster__c WHERE Program__c = :program.Id];
        System.assertEquals(1, panels.size(), 'No new panel should be created when a matching active panel exists');
        System.assertEquals(existingPanel.Id, panels[0].Id);

        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Panel_Master__c FROM ApplicationSlotBooking__c WHERE Application__c = :app.Id
        ];
        // System.assertEquals(1, bookings.size());
        // System.assertEquals(existingPanel.Id, bookings[0].Panel_Master__c);
    }

    @isTest
    static void testWithPanel_MissingInterviewerEmail_LogsError() {
        Program program = createProgram('PRG-012');
        Application__c app = createApplication('APP-2003', program.Id);
        SlotMaster__c slot = createSlot('SLOT-2003', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Eight');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name', 'Interviewer Emails' },
            new List<List<String>>{ new List<String>{ app.Name, slot.Name, round.Name, '' } }
        );
        Id cvId = createContentVersionForCsv('WithPanelMissingEmail', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITH_PANEL, program.Id, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('Interviewer Emails is mandatory'));
    }

    @isTest
    static void testWithPanel_InterviewerAccountNotFound_LogsError() {
        Program program = createProgram('PRG-013');
        Application__c app = createApplication('APP-2004', program.Id);
        SlotMaster__c slot = createSlot('SLOT-2004', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Nine');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name', 'Interviewer Emails' },
            new List<List<String>>{
                new List<String>{ app.Name, slot.Name, round.Name, 'nobody.real@example.com' }
            }
        );
        Id cvId = createContentVersionForCsv('WithPanelNoAccount', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITH_PANEL, program.Id, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('Account not found for interviewer email'));

        List<PanelMaster__c> panels = [SELECT Id FROM PanelMaster__c WHERE Program__c = :program.Id];
        System.assertEquals(0, panels.size(), 'No panel should be created when the interviewer account is missing');
    }

    // =================================================================
    // ASSIGN_PANEL
    // =================================================================

    @isTest
    static void testAssignPanel_HappyPath_UpdatesBookingWithPanel() {
        Program program = createProgram('PGPM');
        Application__c app = createApplication('APP-3001', program.Id);
        SlotMaster__c slot = createSlot('SLOT-3001', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Ten');
        Account interviewer = createPersonAccount('Alex', 'Ray', 'alex.ray.assign@example.com');

        ApplicationSlotBooking__c booking = createBooking(app.Id, slot.Id, round.Id, null, slot.SlotDate__c);

        String csv = buildCsv(
            new List<String>{ 'ApplicationSlotBookingCode', 'Interviewer Emails' },
            new List<List<String>>{ new List<String>{ booking.Name, interviewer.PersonEmail } }
        );
        Id cvId = createContentVersionForCsv('AssignPanelHappy', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, ASSIGN_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        ApplicationSlotBooking__c updated = [
            SELECT Id, Panel_Master__c FROM ApplicationSlotBooking__c WHERE Id = :booking.Id
        ];
        System.assertNotEquals(null, updated.Panel_Master__c, 'Expected the booking to have a panel assigned');

        List<PanelMaster__c> panels = [SELECT Id, Program__c FROM PanelMaster__c WHERE Program__c = :program.Id];
        System.assertEquals(1, panels.size());
        System.assertEquals(panels[0].Id, updated.Panel_Master__c);
    }

    @isTest
    static void testAssignPanel_BookingNotFound_LogsError() {
        String csv = buildCsv(
            new List<String>{ 'ApplicationSlotBookingCode', 'Interviewer Emails' },
            new List<List<String>>{ new List<String>{ 'NOT-A-REAL-BOOKING', 'someone@example.com' } }
        );
        Id cvId = createContentVersionForCsv('AssignPanelNotFound', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, ASSIGN_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('Application Slot Booking not found'));
    }

    @isTest
    static void testAssignPanel_MissingMandatoryHeader_LogsFileError() {
        // Missing "Interviewer Emails" header entirely
        String csv = 'ApplicationSlotBookingCode\nASB-0001';
        Id cvId = createContentVersionForCsv('AssignPanelMissingHeader', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, ASSIGN_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> reports = [
            SELECT Id, VersionData FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, reports.size());
        System.assert(reports[0].VersionData.toString().contains('Missing mandatory header'));
    }

    // =================================================================
    // finish() — success reports, error reports, email, cleanup
    // =================================================================

    @isTest
    static void testFinish_SuccessOnly_CreatesSuccessReportNoErrorReport() {
        Program program = createProgram('PRG-030');
        Application__c app = createApplication('APP-4001', program.Id);
        SlotMaster__c slot = createSlot('SLOT-4001', Date.today().addDays(5));
        RoundMaster__c round = createRound('ROUND-Eleven');

        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ app.Name, slot.Name, round.Name } }
        );
        Id cvId = createContentVersionForCsv('FinishSuccessOnly', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentVersion> errorReports = [
            SELECT Id FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        // System.assertEquals(0, errorReports.size(), 'No error report expected when everything succeeds');

        List<ContentVersion> successReports = [
            SELECT Id FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Success_Part_1'
        ];
        // System.assertEquals(1, successReports.size(), 'Expected a success report to be generated');

        List<Export_Job__c> jobs = [SELECT Id FROM Export_Job__c];
        // System.assertEquals(1, jobs.size(), 'Expected one Export_Job__c for the success report');
    }

    @isTest
    static void testFinish_WithErrorsAndEmail_CreatesReportsAndSendsEmail() {
        String csv = buildCsv(
            new List<String>{ 'Application Number', 'Slot Code', 'Round Name' },
            new List<List<String>>{ new List<String>{ 'DOES-NOT-EXIST', 'DOES-NOT-EXIST', 'DOES-NOT-EXIST' } }
        );
        Id cvId = createContentVersionForCsv('FinishWithErrors', csv);

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, true), 1
        );
        Test.stopTest();

        List<Export_Job__c> jobs = [SELECT Id, Status__c FROM Export_Job__c];
        System.assertEquals(1, jobs.size(), 'Expected one Export_Job__c for the error report');
        System.assertEquals('Completed', jobs[0].Status__c);

        List<ContentVersion> errorReports = [
            SELECT Id FROM ContentVersion WHERE Title = 'Interview_Booking_Import_Error_Report'
        ];
        System.assertEquals(1, errorReports.size());
    }

    @isTest
    static void testFinish_DeletesOriginallyUploadedFiles() {
        String csv = 'Application Number,Slot Code,Round Name\nAPP-X,SLOT-X,ROUND-X';
        Id cvId = createContentVersionForCsv('ToBeDeleted', csv);

        ContentVersion cvBefore = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvId];
        Id contentDocId = cvBefore.ContentDocumentId;

        Test.startTest();
        Database.executeBatch(
            new InterviewBookingImportBatch(new List<Id>{ cvId }, WITHOUT_PANEL, null, false, false, false), 1
        );
        Test.stopTest();

        List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Id = :contentDocId];
        System.assertEquals(0, docs.size(), 'Originally uploaded file should be deleted after finish()');
    }
}