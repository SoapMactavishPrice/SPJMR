/**
 * Test class for WithdrawalRequestNotificationService.
 *
 * SCHEMA NOTES (verified against the SPJIMRAcademics org):
 *   - Withdrawal_Request__c.Programme_Master__c is a lookup to the standard
 *     Education Cloud "Program" object (API name: Program). There is NO custom
 *     "Programme_Master__c" object. Programmes are created through
 *     SpjimrPortalTestDataFactory.insertProgram(), which populates the required
 *     fields / satisfies the validation rules a bare insert would trip.
 *   - Program_Team__c        : Name (Text), Program__c (lookup Program),
 *                              Type__c (picklist, 'Office User').
 *   - Program_Team_Members__c: Program_Team__c (lookup), User__c (lookup User),
 *                              Role__c (picklist, 'Programme Office').
 *   - Recipients are resolved ONLY from the Programme Office team
 *     (Programme_Master__c -> Program_Team_Members__c via Program_Team__r.Program__c,
 *     Role__c = 'Programme Office'), the same way Deferment / Leave resolve
 *     approvers. There is no queue and no fallback: a request whose Programme
 *     has no Programme Office team member is logged as a STOP and skipped.
 *   - Approver users are taken from existing active Standard users rather than
 *     inserted, so the happy-path tests stay free of setup/non-setup mixed DML.
 *     The one test that needs an inactive user creates it inside a System.runAs
 *     block, which permits mixed DML.
 *
 * WithdrawalRequestTrigger (after insert) already calls sendNotifications on
 * insert, so each test also invokes it explicitly and asserts on the persisted
 * Notification_Debug__c trace. Re-running the service is harmless - it just
 * rewrites the diagnostic field.
 */
@isTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class WithdrawalRequestNotificationServiceTest {

    private static final String PROGRAMME_OFFICE_ROLE = 'Programme Office';
    private static final String OFFICE_USER_TYPE = 'Office User';

    // ---------------------------------------------------------------
    // Test data builders
    // ---------------------------------------------------------------

    private static User activeStandardUser() {
        return [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND Email != NULL
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
    }

    private static Id newProgramme() {
        Id programmeId = SpjimrPortalTestDataFactory.insertProgram();
        System.assertNotEquals(null, programmeId,
            'Program could not be created via SpjimrPortalTestDataFactory.insertProgram().');
        return programmeId;
    }

    private static void addOfficeTeamMember(Id programmeId, Id userId) {
        Program_Team__c team = new Program_Team__c(
            Name = 'Withdrawal Office Team',
            Program__c = programmeId,
            Type__c = OFFICE_USER_TYPE
        );
        insert team;
        insert new Program_Team_Members__c(
            Program_Team__c = team.Id,
            User__c = userId,
            Role__c = PROGRAMME_OFFICE_ROLE
        );
    }

    private static Account newStudentAccount() {
        Account acc = new Account(Name = 'Test Student Account');
        insert acc;
        return acc;
    }

    private static Withdrawal_Request__c newWithdrawalRequest(Id studentAccountId, Id programmeId) {
        Withdrawal_Request__c req = new Withdrawal_Request__c(
            Student__c = studentAccountId,
            Programme_Master__c = programmeId,
            Status__c = 'Applied',
            Roll_Number__c = 'TEST-ROLL-001',
            Application_ID__c = 'TEST-APP-001'
        );
        insert req;
        return req;
    }

    private static String debugLog(Id requestId) {
        return [
            SELECT Notification_Debug__c FROM Withdrawal_Request__c WHERE Id = :requestId
        ].Notification_Debug__c;
    }

    private static void assertNoUncaughtException(String log) {
        System.assertNotEquals(null, log, 'A diagnostic trace should always be persisted.');
        System.assert(!log.contains('UNCAUGHT EXCEPTION'),
            'The service must not raise an uncaught exception. Trace:\n' + log);
    }

    // ---------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------

    @isTest
    static void testNullAndEmptyListDoNothing() {
        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(null);
        WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>());
        Test.stopTest();
        // Nothing to assert beyond "did not throw and attempted no DML".
    }

    @isTest
    static void testTeamBasedRoutingSendsEmailAndNotification() {
        User approver = activeStandardUser();
        Account student = newStudentAccount();
        Id programmeId = newProgramme();
        addOfficeTeamMember(programmeId, approver.Id);
        Withdrawal_Request__c req = newWithdrawalRequest(student.Id, programmeId);

        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>{ req });
        Test.stopTest();

        String log = debugLog(req.Id);
        assertNoUncaughtException(log);
        System.assert(log.contains('Done.'),
            'Team-based routing should run to completion. Trace:\n' + log);
        System.assert(log.contains('Emails sent:'),
            'An email should have been prepared for the resolved team member. Trace:\n' + log);
    }

    @isTest
    static void testProgrammeWithoutOfficeTeamMemberStops() {
        // A Programme that has no Programme Office team member: with the queue
        // fallback removed, this request is logged as a STOP and nothing is sent.
        Account student = newStudentAccount();
        Id programmeId = newProgramme();
        // Deliberately no Program_Team_Members__c for this Programme.
        Withdrawal_Request__c req = newWithdrawalRequest(student.Id, programmeId);

        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>{ req });
        Test.stopTest();

        String log = debugLog(req.Id);
        assertNoUncaughtException(log);
        System.assert(log.contains('STOP'),
            'A Programme with no Programme Office team member should STOP. Trace:\n' + log);
        System.assert(!log.contains('Emails sent:'),
            'No email should be prepared when there is no recipient. Trace:\n' + log);
    }

    @isTest
    static void testNoProgrammeOnRequestStops() {
        Account student = newStudentAccount();
        Withdrawal_Request__c req = new Withdrawal_Request__c(
            Student__c = student.Id,
            Status__c = 'Applied'
        );
        insert req;

        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>{ req });
        Test.stopTest();

        String log = debugLog(req.Id);
        assertNoUncaughtException(log);
        // No Programme_Master__c -> nothing to resolve -> STOP, no send.
        System.assert(log.contains('STOP'),
            'A request with no Programme must STOP. Trace:\n' + log);
    }

    @isTest
    static void testInactiveUserYieldsNoActiveRecipients() {
        User thisUser = new User(Id = UserInfo.getUserId());
        Id reqId;

        System.runAs(thisUser) {
            Profile p = [
                SELECT Id FROM Profile WHERE UserType = 'Standard' ORDER BY CreatedDate ASC LIMIT 1
            ];
            String uniq = 'wrns' + String.valueOf(DateTime.now().getTime());
            User inactive = new User(
                FirstName = 'Inactive',
                LastName = 'Approver',
                Alias = 'winact',
                Email = uniq + '@spjimr.test.invalid',
                Username = uniq + '@spjimr.test.invalid',
                TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = p.Id,
                IsActive = true
            );
            insert inactive;
            inactive.IsActive = false;
            update inactive;

            Account student = newStudentAccount();
            Id programmeId = newProgramme();
            addOfficeTeamMember(programmeId, inactive.Id);
            Withdrawal_Request__c req = newWithdrawalRequest(student.Id, programmeId);
            reqId = req.Id;

            Test.startTest();
            WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>{ req });
            Test.stopTest();
        }

        String log = debugLog(reqId);
        assertNoUncaughtException(log);
        // Team routing resolves exactly one candidate and that user is inactive,
        // so the "none of the candidate users are Active" STOP branch fires.
        System.assert(log.contains('STOP'),
            'An inactive-only candidate set should hit a STOP branch. Trace:\n' + log);
    }

    @isTest
    static void testEmailRecipientResolvedForTeamMember() {
        // A truly blank User.Email cannot be created in most orgs, so this
        // instead confirms the positive path: a resolved, email-bearing team
        // member produces a prepared email and the run completes.
        User approver = activeStandardUser();
        Account student = newStudentAccount();
        Id programmeId = newProgramme();
        addOfficeTeamMember(programmeId, approver.Id);
        Withdrawal_Request__c req = newWithdrawalRequest(student.Id, programmeId);

        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>{ req });
        Test.stopTest();

        String log = debugLog(req.Id);
        assertNoUncaughtException(log);
        System.assert(log.contains('Emails sent:'),
            'A resolved email-bearing recipient should yield a prepared email. Trace:\n' + log);
    }

    @isTest
    static void testBulkMultipleRequestsInSingleCall() {
        User approver = activeStandardUser();
        Account student = newStudentAccount();
        Id programmeId = newProgramme();
        addOfficeTeamMember(programmeId, approver.Id);

        List<Withdrawal_Request__c> requests = new List<Withdrawal_Request__c>();
        for (Integer i = 0; i < 5; i++) {
            requests.add(new Withdrawal_Request__c(
                Student__c = student.Id,
                Programme_Master__c = programmeId,
                Status__c = 'Applied',
                Roll_Number__c = 'TEST-ROLL-' + i,
                Application_ID__c = 'TEST-APP-' + i
            ));
        }
        insert requests;

        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(requests);
        Test.stopTest();

        List<Withdrawal_Request__c> updated = [
            SELECT Id, Notification_Debug__c FROM Withdrawal_Request__c WHERE Id IN :requests
        ];
        System.assertEquals(5, updated.size(), 'Every bulk request should be retrievable.');
        for (Withdrawal_Request__c r : updated) {
            assertNoUncaughtException(r.Notification_Debug__c);
            System.assert(r.Notification_Debug__c.contains('Done.'),
                'Every record in the bulk call should reach completion. Trace:\n' + r.Notification_Debug__c);
        }
    }

    @isTest
    static void testCustomNotificationHandlingIsLogged() {
        // Passes whether or not the 'Withdrawal_Request_Notification' custom
        // notification type is deployed: it exercises either the "sent" path or
        // the "not found" WARN path, both of which are logged.
        User approver = activeStandardUser();
        Account student = newStudentAccount();
        Id programmeId = newProgramme();
        addOfficeTeamMember(programmeId, approver.Id);
        Withdrawal_Request__c req = newWithdrawalRequest(student.Id, programmeId);

        Test.startTest();
        WithdrawalRequestNotificationService.sendNotifications(new List<Withdrawal_Request__c>{ req });
        Test.stopTest();

        String log = debugLog(req.Id);
        assertNoUncaughtException(log);
        System.assert(
            log.contains('Custom notifications sent:') || log.contains('not found'),
            'Custom notification handling should be logged either way. Trace:\n' + log
        );
    }
}