/**
 * @description Adversarial tests for FacultyAvailabilityService. Where FacultyAvailabilityServiceTest
 *              proves the intended behaviour, this class attacks it: privacy leakage through hostile
 *              payloads, calendar-id case drift, timezone and DST correctness under runAs users in
 *              other zones, malformed and partial Google responses, sharing enforcement for a real
 *              scheduler profile, 200-faculty bulk, and input abuse.
 */
@IsTest
private class FacultyAvailabilityAdversarialTest {

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

    // ---------------------------------------------------------------- privacy

    @IsTest
    static void hostilePayloadLeaksNoEventDetail() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'leak');
        String email = faculty[0].PersonEmail;
        String body = '{"kind":"calendar#freeBusy",'
            + '"organizer":"vc@spjimr.org",'
            + '"calendars":{"' + email + '":{'
            + '"summary":"Private one-to-one",'
            + '"errors":[],'
            + '"busy":[{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T05:00:00Z",'
            + '"summary":"Board meeting","description":"TopSecretAgenda","location":"Dean Cabin",'
            + '"eventId":"evt_9xTOKEN","attendees":[{"email":"student@spjimr.org"}],'
            + '"organizer":{"email":"chair@spjimr.org"},"visibility":"private"}]}},'
            + '"groups":{"g":{"calendars":["' + email + '"]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        String serialized = JSON.serialize(result);
        Assert.areEqual(1, result[0].busy.size(), 'The busy interval itself is still reported');
        Assert.isFalse(serialized.contains('Board meeting'), 'No event title reaches the caller');
        Assert.isFalse(serialized.contains('TopSecretAgenda'), 'No description reaches the caller');
        Assert.isFalse(serialized.contains('Dean Cabin'), 'No location reaches the caller');
        Assert.isFalse(serialized.contains('evt_9xTOKEN'), 'No event id reaches the caller');
        Assert.isFalse(serialized.contains('student@spjimr.org'), 'No attendee reaches the caller');
        Assert.isFalse(serialized.contains('chair@spjimr.org'), 'No organizer reaches the caller');
        Assert.isFalse(serialized.contains('Private one-to-one'),
            'A calendar-level summary is not carried either');
        Assert.isFalse(serialized.containsIgnoreCase('spjimr.org'),
            'No address of any kind, faculty or otherwise, reaches the caller');
    }

    @IsTest
    static void authFailureNeitherThrowsNorLeaksTheResponse() {
        GoogleCalendarHelper.configOverride = activeConfig();
        GoogleAuthService.tokenOverride = null; // force the real (dummy-key) signing path to blow up
        List<Account> faculty = makeFaculty(2, 'auth');
        Test.setMock(HttpCalloutMock.class,
            new FreeBusyMock(401, '{"error":"invalid_grant","message":"leaky@spjimr.org"}'));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'An auth failure still returns one row per faculty');
        Assert.areEqual(0, result[0].busy.size(), 'An auth failure fails open, it does not throw');
        Assert.areEqual(0, result[1].busy.size(), 'An auth failure fails open, it does not throw');
        Assert.isFalse(JSON.serialize(result).contains('leaky@spjimr.org'),
            'No fragment of the Google error body escapes to the caller');
    }

    // ------------------------------------------------------- calendar id case

    @IsTest
    static void calendarKeyReturnedInADifferentCaseStillMatches() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'case');
        String shouty = faculty[0].PersonEmail.toUpperCase();
        String body = '{"calendars":{"' + shouty + '":{"busy":['
            + '{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T05:00:00Z"}]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(1, result.size(), 'The faculty is still reported on');
        Assert.areEqual(1, result[0].busy.size(),
            'A calendar id echoed back in a different case must not silently mark the faculty free');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 28, 3, 30, 0), result[0].busy[0].startTime,
            'The busy block is the one Google returned');
    }

    @IsTest
    static void mixedCaseStoredEmailIsStillSentAndMatched() {
        seedIntegration();
        Account faculty = new Account(
            LastName = 'AdvFacMixed',
            PersonEmail = 'AdvFac.Mixed@SPJIMR.org',
            RecordTypeId = facultyRecordTypeId()
        );
        insert faculty;
        FreeBusyMock mock = new FreeBusyMock(200,
            '{"calendars":{"advfac.mixed@spjimr.org":{"busy":['
            + '{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T04:30:00Z"}]}}}');
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                new List<String>{ String.valueOf(faculty.Id) }, DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(1, result[0].busy.size(),
            'A stored address with capitals is matched against the response');
        Assert.isTrue(mock.requests[0].getBody().containsIgnoreCase('advfac.mixed@spjimr.org'),
            'The address is actually asked about');
    }

    // --------------------------------------------------- real Google payloads

    @IsTest
    static void mergedAndAllDayIntervalsFromTheRealApiShape() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'shape');
        // Exactly what the live probe returned: UTC with a Z, merged blocks, an all-day event as
        // local-midnight-to-midnight (18:30Z to 18:30Z for IST).
        String body = '{"kind":"calendar#freeBusy",'
            + '"timeMin":"2026-09-24T18:30:00.000Z","timeMax":"2026-09-26T18:30:00.000Z",'
            + '"calendars":{"' + faculty[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-22T03:30:00Z","end":"2026-09-22T06:00:00Z"},'
            + '{"start":"2026-09-25T18:30:00Z","end":"2026-09-26T18:30:00Z"}]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), Date.newInstance(2026, 9, 22), Date.newInstance(2026, 9, 27));
            Test.stopTest();
        }

        Assert.areEqual(2, result[0].busy.size(), 'Both merged intervals survive the parse');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 22, 3, 30, 0), result[0].busy[0].startTime,
            'A merged interval keeps its real start');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 22, 6, 0, 0), result[0].busy[0].endTime,
            'A merged interval keeps its real end');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 25, 18, 30, 0), result[0].busy[1].startTime,
            'An all-day event starts at the previous local midnight expressed in UTC');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 26, 18, 30, 0), result[0].busy[1].endTime,
            'An all-day event spans exactly 24 hours, ending at the next local midnight');
    }

    @IsTest
    static void calendarAbsentFromTheResponseIsFree() {
        seedIntegration();
        List<Account> faculty = makeFaculty(2, 'absent');
        // The live probe showed an unreachable external calendar is simply missing from the map,
        // with no errors entry at all.
        String body = '{"calendars":{"' + faculty[1].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T04:30:00Z"}]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'A calendar missing from the response still gets a row');
        Assert.areEqual(String.valueOf(faculty[0].Id), result[0].facultyId,
            'The missing calendar is the first row');
        Assert.areEqual(0, result[0].busy.size(),
            'A calendar absent from the response is reported free, not shifted onto another faculty');
        Assert.areEqual(1, result[1].busy.size(),
            'The calendar that did come back keeps its own block');
    }

    // ------------------------------------------------ malformed / hostile bodies

    @IsTest
    static void everyMalformedBodyShapeFailsOpen() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'shapes');
        List<String> ids = idsOf(faculty);
        List<String> bodies = new List<String>{
            '',
            'null',
            '[]',
            '"just a string"',
            '<html><head><title>502 Bad Gateway</title></head></html>',
            '{"calendars":null}',
            '{"calendars":[]}',
            '{"calendars":[{"id":"x"}]}',
            '{}',
            '{"calendars":{"' + faculty[0].PersonEmail + '":null}}',
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":null}}}',
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":{"0":{"start":"x"}}}}}',
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":[{"start":null,"end":null}]}}}',
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":[{"start":"2026-13-45T99:99:99Z",'
                + '"end":"2026-09-28T05:00:00Z"}]}}}',
            '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":[{"start":"2026-09-28T03:30",'
                + '"end":"2026-09-28T05:00:00Z"}]}}}'
        };
        CyclingMock mock = new CyclingMock(200, bodies);
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            for (Integer i = 0; i < bodies.size(); i++) {
                List<FacultyAvailabilityService.FacultyAvailability> result =
                    FacultyAvailabilityService.getAvailability(ids, DAY, DAY);
                Assert.areEqual(1, result.size(),
                    'Body shape ' + i + ' must still return the faculty row');
                Assert.areEqual(0, result[0].busy.size(),
                    'Body shape ' + i + ' must fail open with no busy blocks: ' + bodies[i]);
            }
            Test.stopTest();
        }
        Assert.areEqual(bodies.size(), mock.callCount, 'Each attempt really did call Google');
    }

    @IsTest
    static void everyErrorStatusFailsOpen() {
        seedIntegration();
        List<Account> faculty = makeFaculty(2, 'status');
        List<String> ids = idsOf(faculty);
        List<Integer> statuses = new List<Integer>{ 400, 401, 403, 404, 429, 500, 503 };
        StatusCyclingMock mock = new StatusCyclingMock(statuses,
            '{"error":{"message":"quota exceeded for finessedirect@spjimr.org"}}');
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            for (Integer i = 0; i < statuses.size(); i++) {
                List<FacultyAvailabilityService.FacultyAvailability> result =
                    FacultyAvailabilityService.getAvailability(ids, DAY, DAY);
                Assert.areEqual(2, result.size(),
                    'HTTP ' + statuses[i] + ' still returns one row per faculty');
                Assert.areEqual(0, result[0].busy.size(),
                    'HTTP ' + statuses[i] + ' fails open rather than throwing');
                Assert.isFalse(JSON.serialize(result).contains('finessedirect@spjimr.org'),
                    'HTTP ' + statuses[i] + ' must not leak the impersonated address');
            }
            Test.stopTest();
        }
        Assert.areEqual(statuses.size(), mock.callCount, 'Every status was actually exercised');
    }

    @IsTest
    static void calloutExceptionFailsOpen() {
        seedIntegration();
        List<Account> faculty = makeFaculty(3, 'boom');
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(3, result.size(), 'A dropped connection still returns a row per faculty');
        for (FacultyAvailabilityService.FacultyAvailability row : result) {
            Assert.areEqual(0, row.busy.size(), 'A CalloutException fails open with no busy blocks');
        }
    }

    @IsTest
    static void aBadFirstChunkMustNotSuppressTheSecondChunk() {
        seedIntegration();
        List<Account> faculty = makeFaculty(60, 'partial');
        // Chunk 1 comes back 200 with an HTML error page; chunk 2 would answer perfectly well.
        CyclingMock mock = new CyclingMock(200, new List<String>{
            '<html><body>502 Bad Gateway</body></html>',
            'ECHO'
        });
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(idsOf(faculty), DAY, DAY);
            Test.stopTest();
        }

        Assert.areEqual(60, result.size(), 'Every requested faculty still gets a row');
        Assert.areEqual(2, mock.callCount,
            'A garbage body in the first chunk must not abandon the remaining chunks');
        Integer withBusy = 0;
        for (FacultyAvailabilityService.FacultyAvailability row : result) {
            if (!row.busy.isEmpty()) {
                withBusy++;
            }
        }
        Assert.areEqual(10, withBusy,
            'The 10 faculty in the healthy second chunk must still get their busy blocks');
    }

    // ------------------------------------------------------------- input abuse

    // --------------------------------------------------------------- pure parser

    /**
     * @description Runs one candidate interval through the parser.
     * @param startValue The raw start timestamp as JSON text (already quoted or not).
     * @param endValue The raw end timestamp as JSON text.
     * @return The number of busy blocks the parser produced (0 or 1).
     */
    private static Integer blockCount(String startValue, String endValue) {
        Object node = JSON.deserializeUntyped(
            '{"busy":[{"start":' + startValue + ',"end":' + endValue + '}]}');
        return FacultyAvailabilityService.busyBlocks(node).size();
    }

    @IsTest
    static void parserRejectsHostileTimestampTails() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String outcome = ''
                + blockCount('"2026-09-28T03:30:00+0530"', '"2026-09-28T05:00:00+0530"')
                + blockCount('"2026-09-28T03:30:00z"', '"2026-09-28T05:00:00z"')
                + blockCount('"2026-09-28T03:30"', '"2026-09-28T05:00"')
                + blockCount('""', '""')
                + blockCount('"2026-09-28T03:30:00Z"', '"2026-09-28T03:30:00Z"')
                + blockCount('"2026-09-28T03:30:00.123456789Z"', '"2026-09-28T04:30:00.123456789Z"');
            Assert.areEqual('010001', outcome,
                'An offset with no colon, a truncated timestamp, an empty string and a zero-length '
                + 'interval are all rejected; a lower-case z and nanosecond precision are accepted');
            Object node = JSON.deserializeUntyped('{"busy":['
                + '{"start":"2026-09-28T03:30:00z","end":"2026-09-28T05:00:00z"}]}');
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 9, 28, 3, 30, 0),
                FacultyAvailabilityService.busyBlocks(node)[0].startTime,
                'A lower-case z is read as UTC, not silently shifted'
            );
        }
    }

    @IsTest
    static void parserRejectsAnImpossibleClockTime() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.areEqual(0,
                blockCount('"2026-09-28T25:99:99Z"', '"2026-09-28T26:99:99Z"'),
                'An out-of-range clock time is not a real instant and must be dropped, not rolled '
                + 'over into a plausible-looking busy block on the following day');
        }
    }

    @IsTest
    static void parserDoesNotThrowOnNonStringTimestamps() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Object node = JSON.deserializeUntyped('{"busy":['
                + '{"start":123,"end":456},'
                + '{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T04:30:00Z"}]}');
            List<FacultyAvailabilityService.BusyBlock> blocks =
                FacultyAvailabilityService.busyBlocks(node);
            Assert.areEqual(1, blocks.size(),
                'A numeric start/end must be skipped, not abort the whole calendar node');
            Assert.areEqual(Datetime.newInstanceGmt(2026, 9, 28, 3, 30, 0), blocks[0].startTime,
                'The well-formed interval that follows the hostile one still survives');
        }
    }

    @IsTest
    static void parserIgnoresNonBusyCalendarShapes() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.areEqual(0, FacultyAvailabilityService.busyBlocks(null).size(),
                'A null calendar node yields no busy blocks');
            Assert.areEqual(0,
                FacultyAvailabilityService.busyBlocks(
                    JSON.deserializeUntyped('{"busy":[],"errors":[]}')).size(),
                'An empty errors array is not treated as an error but still has no busy');
            Assert.areEqual(0,
                FacultyAvailabilityService.busyBlocks(JSON.deserializeUntyped(
                    '{"errors":[{"domain":"global","reason":"notFound"}],'
                    + '"busy":[{"start":"2026-09-28T03:30:00Z","end":"2026-09-28T04:30:00Z"}]}')).size(),
                'An errors entry wins over any busy array that came with it');
            Assert.areEqual(0,
                FacultyAvailabilityService.busyBlocks(JSON.deserializeUntyped('[1,2,3]')).size(),
                'An array where a calendar object was expected yields no busy blocks');
        }
    }

    // ----------------------------------------------------------------- mocks

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

    /**
     * @description A mock that walks through a list of bodies, one per call. The literal 'ECHO'
     *              body is replaced with a well-formed response covering the requested calendars.
     */
    private class CyclingMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final List<String> bodies;
        public Integer callCount = 0;

        /**
         * @description Builds the mock.
         * @param statusCode The HTTP status every response carries.
         * @param bodies The bodies to return in order; the last one repeats.
         */
        public CyclingMock(Integer statusCode, List<String> bodies) {
            this.statusCode = statusCode;
            this.bodies = bodies;
        }

        /**
         * @description Returns the next scripted body.
         * @param req The outbound request.
         * @return The scripted response.
         */
        public HttpResponse respond(HttpRequest req) {
            String body = bodies[Math.min(callCount, bodies.size() - 1)];
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body == 'ECHO' ? echoBody(req) : body);
            return res;
        }
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

    /** @description A mock that walks through a list of HTTP statuses, one per call. */
    private class StatusCyclingMock implements HttpCalloutMock {
        private final List<Integer> statuses;
        private final String responseBody;
        public Integer callCount = 0;

        /**
         * @description Builds the mock.
         * @param statuses The statuses to return in order; the last one repeats.
         * @param responseBody The body every response carries.
         */
        public StatusCyclingMock(List<Integer> statuses, String responseBody) {
            this.statuses = statuses;
            this.responseBody = responseBody;
        }

        /**
         * @description Returns the next scripted status.
         * @param req The outbound request.
         * @return The scripted response.
         */
        public HttpResponse respond(HttpRequest req) {
            Integer status = statuses[Math.min(callCount, statuses.size() - 1)];
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(responseBody);
            return res;
        }
    }

    /** @description A mock that fails the way a dropped connection or timeout does. */
    private class ThrowingMock implements HttpCalloutMock {
        /**
         * @description Always throws, simulating an unreachable Google endpoint.
         * @param req The outbound request.
         * @return Never returns.
         */
        public HttpResponse respond(HttpRequest req) {
            throw new CalloutException('Read timed out');
        }
    }
}