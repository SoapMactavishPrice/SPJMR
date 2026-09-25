/**
 * @description Adversarial tests for FacultyAvailabilityService covering the running user's
 *              timezone (including both daylight-saving transitions), 200-faculty bulk and the
 *              50-calendar chunk boundary, abusive id input, faculty identity when the response is
 *              reordered or two faculty share an address, and sharing for a real scheduler profile.
 *              Split from FacultyAvailabilityAdversarialTest only to keep each class under the
 *              PMD class-complexity gate.
 */
@IsTest
private class FacultyAvailabilityBulkTzTest {

    private static final Date DAY = Date.newInstance(2026, 9, 28);

    /**
     * @description An active Google Calendar config so GoogleCalendarHelper.isActive() is true.
     * @return The in-memory config record.
     */
    private static Google_Calendar_Config__mdt activeConfig() {
        return new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = '-----BEGIN PRIVATE KEY-----\nMIICdummy\n-----END PRIVATE KEY-----',
            Impersonated_User__c = 'finessedirect@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    /**
     * @description Puts an active config and a stub access token in place for a callout test.
     */
    private static void seedIntegration() {
        GoogleCalendarHelper.configOverride = activeConfig();
        GoogleAuthService.tokenOverride = 'tok';
    }

    /**
     * @description The Faculty person-account record type id.
     * @return The record type id.
     */
    private static Id facultyRecordTypeId() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
    }

    /**
     * @description Creates faculty person accounts with unique names and addresses.
     * @param count How many faculty to create.
     * @param tag A per-test suffix keeping names and emails unique.
     * @return The inserted faculty, in creation order.
     */
    private static List<Account> makeFaculty(Integer count, String tag) {
        Id facultyRt = facultyRecordTypeId();
        List<Account> faculty = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            faculty.add(new Account(
                LastName = 'AdvFac' + tag + i,
                PersonEmail = 'advfac' + tag + i + '@spjimr.org',
                RecordTypeId = facultyRt
            ));
        }
        insert faculty;
        return faculty;
    }

    /**
     * @description The ids of the given accounts as the strings the grid would send.
     * @param accounts The faculty records.
     * @return Their ids as strings.
     */
    private static List<String> idsOf(List<Account> accounts) {
        List<String> ids = new List<String>();
        for (Account a : accounts) {
            ids.add(String.valueOf(a.Id));
        }
        return ids;
    }

    /**
     * @description Creates and inserts a user in a given timezone, sidestepping the mixed-DML rule.
     * @param timeZoneId The TimeZoneSidKey to give the user.
     * @param profileName The profile to assign.
     * @param tag A per-test suffix keeping the username unique.
     * @return The inserted user.
     */
    private static User insertUser(String timeZoneId, String profileName, String tag) {
        Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        String uniqueSuffix = tag + String.valueOf(Math.abs(Crypto.getRandomLong()));
        User u = new User(
            FirstName        = 'Avail',
            LastName         = 'Adv' + tag,
            Email            = 'availadv@example.invalid',
            Username         = 'availadv' + uniqueSuffix + '@spjdev.invalid.test',
            Alias            = tag.left(8),
            ProfileId        = p.Id,
            TimeZoneSidKey   = timeZoneId,
            LocaleSidKey     = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    /**
     * @description Reads the timeMin/timeMax pair out of a recorded freeBusy request.
     * @param req The request the mock captured.
     * @return timeMin and timeMax keyed by name.
     */
    private static Map<String, String> windowOf(HttpRequest req) {
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
        return new Map<String, String>{
            'timeMin' => (String) sent.get('timeMin'),
            'timeMax' => (String) sent.get('timeMax')
        };
    }

    @IsTest
    static void windowIsLocalMidnightForAnAmericanUser() {
        seedIntegration();
        User tzUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tzUser = insertUser('America/Los_Angeles', 'System Administrator', 'tzla');
        }
        List<Account> faculty = makeFaculty(1, 'tzla');
        FreeBusyMock mock = new FreeBusyMock(200,
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T16:00:00Z","end":"2026-09-28T17:00:00Z"}]}}}');
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(tzUser) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Map<String, String> window = windowOf(mock.requests[0]);
        Assert.areEqual('2026-09-28T00:00:00-07:00', window.get('timeMin'),
            'timeMin is local midnight for a Pacific-time user, with the PDT offset');
        Assert.areEqual('2026-09-29T00:00:00-07:00', window.get('timeMax'),
            'timeMax is the following local midnight, so the last day is fully covered');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 28, 16, 0, 0), result[0].busy[0].startTime,
            'A Z timestamp is an absolute instant regardless of the running user timezone');
    }

    @IsTest
    static void windowIsLocalMidnightForAPlusFourteenUser() {
        seedIntegration();
        User tzUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tzUser = insertUser('Pacific/Kiritimati', 'System Administrator', 'tzki');
        }
        List<Account> faculty = makeFaculty(1, 'tzki');
        FreeBusyMock mock = new FreeBusyMock(200, '{"calendars":{}}');
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(tzUser) {
            Test.startTest();
            FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Map<String, String> window = windowOf(mock.requests[0]);
        Assert.areEqual('2026-09-28T00:00:00+14:00', window.get('timeMin'),
            'A +14:00 zone is rendered with a two-digit hour offset, not "+2:00" or "+14"');
        Assert.areEqual('2026-09-29T00:00:00+14:00', window.get('timeMax'),
            'The exclusive end is the next local midnight in the same extreme zone');
    }

    @IsTest
    static void windowSpansTheWholeRangeForAnIndianUser() {
        seedIntegration();
        User tzUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tzUser = insertUser('Asia/Kolkata', 'System Administrator', 'tzin');
        }
        List<Account> faculty = makeFaculty(1, 'tzin');
        // 23:30 IST on the last day of the range = 18:00Z, which must fall inside the window.
        FreeBusyMock mock = new FreeBusyMock(200,
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-30T18:00:00Z","end":"2026-09-30T18:30:00Z"}]}}}');
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(tzUser) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), DAY, Date.newInstance(2026, 9, 30));
            Test.stopTest();
        }

        Map<String, String> window = windowOf(mock.requests[0]);
        Assert.areEqual('2026-09-28T00:00:00+05:30', window.get('timeMin'),
            'timeMin is IST midnight on the first day');
        Assert.areEqual('2026-10-01T00:00:00+05:30', window.get('timeMax'),
            'timeMax rolls into the next month so 30 September is covered to its last minute');
        Assert.areEqual(1, result[0].busy.size(),
            'A late-evening block on the final day of the range is inside the requested window');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 30, 18, 0, 0), result[0].busy[0].startTime,
            'The late block keeps its instant');
    }

    @IsTest
    static void windowHandlesADaylightSavingFallBack() {
        seedIntegration();
        User tzUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tzUser = insertUser('America/Los_Angeles', 'System Administrator', 'tzdst1');
        }
        List<Account> faculty = makeFaculty(1, 'tzdst1');
        FreeBusyMock mock = new FreeBusyMock(200, '{"calendars":{}}');
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(tzUser) {
            Test.startTest();
            FacultyAvailabilityService.getAvailability(
                idsOf(faculty), Date.newInstance(2026, 10, 30), Date.newInstance(2026, 11, 2));
            Test.stopTest();
        }

        Map<String, String> window = windowOf(mock.requests[0]);
        Assert.areEqual('2026-10-30T00:00:00-07:00', window.get('timeMin'),
            'The start of a range before the clocks go back carries the PDT offset');
        Assert.areEqual('2026-11-03T00:00:00-08:00', window.get('timeMax'),
            'The end of the same range carries the PST offset — a single fixed offset would be wrong');
    }

    @IsTest
    static void windowHandlesADaylightSavingSpringForward() {
        seedIntegration();
        User tzUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            tzUser = insertUser('America/Los_Angeles', 'System Administrator', 'tzdst2');
        }
        List<Account> faculty = makeFaculty(1, 'tzdst2');
        FreeBusyMock mock = new FreeBusyMock(200, '{"calendars":{}}');
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(tzUser) {
            Test.startTest();
            FacultyAvailabilityService.getAvailability(
                idsOf(faculty), Date.newInstance(2026, 3, 7), Date.newInstance(2026, 3, 8));
            Test.stopTest();
        }

        Map<String, String> window = windowOf(mock.requests[0]);
        Assert.areEqual('2026-03-07T00:00:00-08:00', window.get('timeMin'),
            'The day before the spring-forward carries the PST offset');
        Assert.areEqual('2026-03-09T00:00:00-07:00', window.get('timeMax'),
            'The exclusive end after the spring-forward carries the PDT offset');
    }

    @IsTest
    static void twoHundredFacultyAreChunkedAndAllAnswered() {
        seedIntegration();
        List<Account> faculty = makeFaculty(200, 'bulk');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        Integer queriesUsed;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            Integer before = Limits.getQueries();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            queriesUsed = Limits.getQueries() - before;
            Assert.areEqual(4, Limits.getCallouts(), '200 calendars cost exactly four callouts');
            Test.stopTest();
        }

        Assert.areEqual(200, result.size(), 'Every requested faculty gets a row');
        Assert.areEqual(1, queriesUsed, 'The faculty lookup is a single bulk query');
        Assert.areEqual(4, mock.callCount, '200 calendars at 50 per request is four requests');
        Assert.areEqual(50, mock.largestChunk, 'No request exceeds Google\'s 50-calendar limit');
        Assert.areEqual(200, mock.calendarsSeen, 'Each calendar is asked about exactly once');
        Set<String> seenIds = new Set<String>();
        for (FacultyAvailabilityService.FacultyAvailability row : result) {
            Assert.areEqual(1, row.busy.size(), 'Every row in every chunk is filled in');
            seenIds.add(row.facultyId);
        }
        Assert.areEqual(200, seenIds.size(), 'No faculty is duplicated or dropped across chunks');
    }

    @IsTest
    static void exactlyFiftyFacultyStayInOneCallout() {
        seedIntegration();
        List<Account> faculty = makeFaculty(50, 'fifty');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(50, result.size(), 'All fifty faculty are reported');
        Assert.areEqual(1, mock.callCount, 'Exactly fifty calendars is still a single request');
        Assert.areEqual(50, mock.largestChunk, 'The boundary request carries the full fifty');
    }

    @IsTest
    static void fifteenAndEighteenCharacterIdsCollapseToOneRow() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'idlen');
        String longId = String.valueOf(faculty[0].Id);
        String shortId = longId.substring(0, 15);
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                new List<String>{ shortId, longId, '  ' + longId + '  ' }, DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(1, result.size(),
            'The same record sent as a 15-char id, an 18-char id and a padded id is one faculty');
        Assert.areEqual(18, result[0].facultyId.length(), 'The row carries the full 18-char id');
        Assert.areEqual(1, mock.calendarsSeen, 'Google is asked about that calendar only once');
        Assert.areEqual(1, result[0].busy.size(), 'The single row still receives its busy block');
    }

    @IsTest
    static void foreignAndJunkIdsAreDroppedWithoutThrowing() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'junkids');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);
        String unusedAccountId = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getKeyPrefix() + '0'.repeat(12) + 'AAA';

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                new List<String>{
                    null,
                    '',
                    '   ',
                    'not-an-id',
                    '0'.repeat(15),
                    '001',
                    String.valueOf(UserInfo.getUserId()),
                    String.valueOf(UserInfo.getProfileId()),
                    unusedAccountId,
                    '<script>alert(1)</script>',
                    'a@b.com',
                    String.valueOf(faculty[0].Id)
                },
                DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(1, result.size(),
            'Nulls, junk, a User id and a Profile id are all dropped, leaving the one real faculty');
        Assert.areEqual(String.valueOf(faculty[0].Id), result[0].facultyId,
            'The surviving row is the real faculty');
        Assert.areEqual(1, mock.calendarsSeen, 'Only the resolvable faculty is sent to Google');
    }

    @IsTest
    static void aVeryLongIdListIsHandled() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'longlist');
        List<String> ids = new List<String>();
        for (Integer i = 0; i < 5000; i++) {
            ids.add(String.valueOf(faculty[0].Id)); // 5000 duplicates of one faculty
        }
        ids.add('rubbish');
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(ids, DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(1, result.size(), '5000 copies of one id collapse to a single row');
        Assert.areEqual(1, mock.callCount, 'A duplicate-stuffed list still costs one callout');
    }

    @IsTest
    static void aBusinessAccountWithNoPersonEmailIsAFreeRow() {
        seedIntegration();
        Account org = new Account(
            Name = 'AdvFac Business Org',
            RecordTypeId = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByName().get('Business Organization').getRecordTypeId()
        );
        insert org;
        List<Account> faculty = makeFaculty(1, 'biz');
        FreeBusyMock mock = new FreeBusyMock(200,
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T04:30:00Z"}]}}}');
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                new List<String>{ String.valueOf(org.Id), String.valueOf(faculty[0].Id) }, DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'A non-person Account still produces a row, not an error');
        Assert.areEqual(0, result[0].busy.size(),
            'An Account with no person email is permanently free');
        Assert.areEqual(1, result[1].busy.size(), 'The real faculty is unaffected');
        Assert.areEqual(1, mock.requests.size(), 'Only one freeBusy call is made');
    }

    @IsTest
    static void busyIsAttributedToTheRightFacultyWhenTheResponseIsReordered() {
        seedIntegration();
        List<Account> faculty = makeFaculty(3, 'order');
        // Response deliberately lists calendar 3, then 1, then 2, with distinct block counts.
        String body = '{"calendars":{'
            + '"' + faculty[2].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T01:00:00Z","end":"2026-09-28T02:00:00Z"},'
            + '{"start":"2026-09-28T03:00:00Z","end":"2026-09-28T04:00:00Z"},'
            + '{"start":"2026-09-28T05:00:00Z","end":"2026-09-28T06:00:00Z"}]},'
            + '"' + faculty[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T07:00:00Z","end":"2026-09-28T08:00:00Z"}]},'
            + '"' + faculty[1].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T09:00:00Z","end":"2026-09-28T10:00:00Z"},'
            + '{"start":"2026-09-28T11:00:00Z","end":"2026-09-28T12:00:00Z"}]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        Map<String, FacultyAvailabilityService.FacultyAvailability> byId =
            new Map<String, FacultyAvailabilityService.FacultyAvailability>();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            for (FacultyAvailabilityService.FacultyAvailability row :
                FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY)) {
                byId.put(row.facultyId, row);
            }
            Test.stopTest();
        }

        Assert.areEqual(3, byId.size(), 'Three distinct faculty rows come back');
        Assert.areEqual(1, byId.get(String.valueOf(faculty[0].Id)).busy.size(),
            'Faculty 1 keeps its own single block despite being second in the response');
        Assert.areEqual(2, byId.get(String.valueOf(faculty[1].Id)).busy.size(),
            'Faculty 2 keeps its own two blocks');
        Assert.areEqual(3, byId.get(String.valueOf(faculty[2].Id)).busy.size(),
            'Faculty 3 keeps its own three blocks despite being first in the response');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 28, 7, 0, 0),
            byId.get(String.valueOf(faculty[0].Id)).busy[0].startTime,
            'Faculty 1 gets faculty 1\'s instant, not a neighbour\'s');
    }

    @IsTest
    static void twoFacultySharingAnAddressBothReceiveTheBusyBlocks() {
        seedIntegration();
        Id facultyRt = facultyRecordTypeId();
        List<Account> twins = new List<Account>{
            new Account(LastName = 'AdvFacTwinA', PersonEmail = 'advtwin@spjimr.org',
                RecordTypeId = facultyRt),
            new Account(LastName = 'AdvFacTwinB', PersonEmail = 'ADVTWIN@spjimr.org',
                RecordTypeId = facultyRt)
        };
        insert twins;
        FreeBusyMock mock = new FreeBusyMock(200,
            '{"calendars":{"advtwin@spjimr.org":{"busy":['
            + '{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T04:30:00Z"}]}}}');
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(twins), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'Both records that share an address get their own row');
        Assert.areEqual(1, result[0].busy.size(), 'The first twin gets the shared calendar busy block');
        Assert.areEqual(1, result[1].busy.size(),
            'The second twin gets it too rather than appearing free');
        Map<String, Object> sent =
            (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0].getBody());
        Assert.areEqual(1, ((List<Object>) sent.get('items')).size(),
            'The shared address is asked about only once');
    }

    @IsTest
    static void sharingIsEnforcedForARealSchedulerProfile() {
        seedIntegration();
        User scheduler;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            scheduler = insertUser('Asia/Kolkata', 'Program Office Member', 'pom');
        }
        List<Account> faculty = makeFaculty(2, 'share');
        insert new AccountShare(
            AccountId = faculty[0].Id,
            UserOrGroupId = scheduler.Id,
            AccountAccessLevel = 'Read',
            OpportunityAccessLevel = 'None',
            CaseAccessLevel = 'None'
        );
        EchoMock mock = new EchoMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        Integer visibleToScheduler;
        System.runAs(scheduler) {
            List<Id> asked = new List<Id>{ faculty[0].Id, faculty[1].Id };
            visibleToScheduler = [SELECT COUNT() FROM Account WHERE Id IN :asked];
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(1, visibleToScheduler,
            'Account OWD is Private, so the scheduler sees only the explicitly shared faculty');
        Assert.areEqual(visibleToScheduler, result.size(),
            'The service reports on exactly the faculty the running user is allowed to see');
        Assert.areEqual(String.valueOf(faculty[0].Id), result[0].facultyId,
            'The shared faculty is the one reported');
        Assert.areEqual(1, mock.calendarsSeen,
            'The unshared faculty calendar is never even sent to Google');
        Assert.isFalse(JSON.serialize(result).contains('@spjimr.org'),
            'No address is returned to a non-admin caller either');
    }

    /**
     * @description Builds a freeBusy response giving every calendar in the request one busy hour.
     * @param req The outbound request whose items are echoed back.
     * @return The response body as JSON text.
     */
    private static String echoBody(HttpRequest req) {
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
        Map<String, Object> calendars = new Map<String, Object>();
        for (Object item : (List<Object>) sent.get('items')) {
            calendars.put((String) ((Map<String, Object>) item).get('id'), new Map<String, Object>{
                'busy' => new List<Object>{
                    new Map<String, Object>{
                        'start' => '2026-09-28T03:30:00Z',
                        'end'   => '2026-09-28T04:30:00Z'
                    }
                }
            });
        }
        return JSON.serialize(new Map<String, Object>{ 'calendars' => calendars });
    }

    /** @description A freeBusy mock returning a fixed status and body, recording what was sent. */
    private class FreeBusyMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String responseBody;
        public Integer callCount = 0;
        public List<HttpRequest> requests = new List<HttpRequest>();

        /**
         * @description Builds the mock.
         * @param statusCode The HTTP status to return.
         * @param responseBody The body to return.
         */
        public FreeBusyMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        /**
         * @description Records the request and returns the canned response.
         * @param req The outbound request.
         * @return The canned response.
         */
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            requests.add(req);
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            return res;
        }
    }

    /** @description A mock that answers every requested calendar with one busy hour. */
    private class EchoMock implements HttpCalloutMock {
        public Integer callCount = 0;
        public Integer calendarsSeen = 0;
        public Integer largestChunk = 0;

        /**
         * @description Echoes one busy hour back for every calendar in the request.
         * @param req The outbound request.
         * @return The freeBusy response.
         */
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            Integer items = ((List<Object>) sent.get('items')).size();
            calendarsSeen += items;
            largestChunk = Math.max(largestChunk, items);
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(echoBody(req));
            return res;
        }
    }
}