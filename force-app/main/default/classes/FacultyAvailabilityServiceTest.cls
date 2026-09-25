/**
 * @description Unit tests for FacultyAvailabilityService. The freeBusy callout is faked with an
 *              HttpCalloutMock and GoogleAuthService.tokenOverride bypasses the JWT signing, so the
 *              happy path, the privacy guarantee, every fail-open branch and the 50-calendar
 *              chunking are all covered without a live Google connection.
 */
@IsTest
private class FacultyAvailabilityServiceTest {

    private static final Date RANGE_START = Date.newInstance(2026, 9, 28);
    private static final Date RANGE_END   = Date.newInstance(2026, 9, 28);

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
     * @description Creates faculty Person Accounts. The Faculty record type is deliberate: two
     *              learner records in one test trip the duplicate-student check on the Account
     *              trigger.
     * @param count How many faculty to create.
     * @param tag A per-test suffix keeping names and emails unique.
     * @return The inserted faculty, in creation order.
     */
    private static List<Account> makeFaculty(Integer count, String tag) {
        Id facultyRt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        List<Account> faculty = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            faculty.add(new Account(
                LastName = 'AvailFac' + tag + i,
                PersonEmail = 'availfac' + tag + i + '@spjimr.org',
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
     * @description A syntactically valid Account id that matches no record, built from the live key
     *              prefix so no id is hard-coded.
     * @return The unusable id, as the grid would send it.
     */
    private static String unusedFacultyId() {
        return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix()
            + '0'.repeat(12) + 'AAA';
    }

    /**
     * @description Deserialises a freeBusy calendars[<id>] fragment for the pure-parser tests.
     * @param fragment The JSON text of one calendar node.
     * @return The parsed node.
     */
    private static Object calendarNode(String fragment) {
        return JSON.deserializeUntyped(fragment);
    }

    @IsTest
    static void returnsBusyBlocksForEachFaculty() {
        seedIntegration();
        List<Account> faculty = makeFaculty(2, 'happy');
        // Google echoes the calendar id back in whatever case the account carries, which need not
        // be the lower-cased key we index rows by — hence the deliberate upper-casing here.
        String body = '{"calendars":{'
            + '"' + faculty[0].PersonEmail.toUpperCase() + '":{"busy":['
            + '{"start":"2026-09-28T09:00:00+05:30","end":"2026-09-28T10:30:00+05:30"},'
            + '{"start":"2026-09-28T14:00:00+05:30","end":"2026-09-28T15:00:00+05:30"}]},'
            + '"' + faculty[1].PersonEmail.toUpperCase() + '":{"busy":['
            + '{"start":"2026-09-28T11:00:00+05:30","end":"2026-09-28T12:00:00+05:30"}]}}}';
        FreeBusyMock mock = new FreeBusyMock(200, body);
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'One row per requested faculty');
        Assert.areEqual(1, mock.callCount, 'Two faculty still cost a single freeBusy callout');
        Assert.areEqual(2, result[0].busy.size(), 'First faculty has both busy blocks');
        Assert.areEqual(1, result[1].busy.size(), 'Second faculty has one busy block');
        Assert.areEqual(String.valueOf(faculty[0].Id), result[0].facultyId,
            'Rows keep the requested order');
        Assert.isTrue(result[0].facultyName.contains('AvailFachappy0'),
            'The faculty name is resolved for the overlay label');
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 9, 28, 3, 30, 0), result[0].busy[0].startTime,
            'A +05:30 start is converted to the right instant'
        );
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 9, 28, 5, 0, 0), result[0].busy[0].endTime,
            'A +05:30 end is converted to the right instant'
        );
    }

    @IsTest
    static void responseCarriesNoEventDetails() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'priv');
        // Google does not return titles from freeBusy; this body smuggles some in anyway to prove
        // the parser cannot carry them and the DTO has nowhere to put them.
        String body = '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T09:00:00+05:30","end":"2026-09-28T10:00:00+05:30",'
            + '"summary":"Board meeting","description":"confidential","location":"Room 1"}]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        String serialized = JSON.serialize(result);
        Assert.areEqual(1, result[0].busy.size(), 'The busy interval itself is still returned');
        Assert.isFalse(serialized.contains('Board meeting'), 'No event title reaches the caller');
        Assert.isFalse(serialized.contains('confidential'), 'No description reaches the caller');
        Assert.isFalse(serialized.contains('Room 1'), 'No location reaches the caller');
        Assert.isFalse(serialized.containsIgnoreCase('summary'), 'The DTO has no summary member');
        Assert.isFalse(
            serialized.contains(faculty[0].PersonEmail), 'The faculty email never leaves Apex'
        );
    }

    @IsTest
    static void calendarWithErrorsIsReportedFree() {
        seedIntegration();
        List<Account> faculty = makeFaculty(3, 'err');
        // faculty[2] is omitted from the response altogether, which is what Google actually does
        // with a calendar it cannot reach at all, rather than returning an errors entry for it.
        String body = '{"calendars":{'
            + '"' + faculty[0].PersonEmail + '":{"errors":[{"domain":"global","reason":"notFound"}]},'
            + '"' + faculty[1].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T11:00:00+05:30","end":"2026-09-28T12:00:00+05:30"}]},'
            + '"stranger@elsewhere.org":{"busy":['
            + '{"start":"2026-09-28T08:00:00+05:30","end":"2026-09-28T09:00:00+05:30"}]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(3, result.size(), 'An unreadable calendar still gets a row');
        Assert.areEqual(0, result[0].busy.size(), 'An errored calendar is reported as free');
        Assert.areEqual(1, result[1].busy.size(), 'The readable calendar is unaffected');
        Assert.areEqual(0, result[2].busy.size(),
            'A calendar missing from the response entirely is reported as free, not dropped');
        Assert.areEqual(String.valueOf(faculty[2].Id), result[2].facultyId,
            'The row for the absent calendar is still the faculty that was asked about');
    }

    @IsTest
    static void facultyWithoutEmailGetsAFreeRow() {
        seedIntegration();
        Id facultyRt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        Account noEmail = new Account(LastName = 'AvailFacNoMail', RecordTypeId = facultyRt);
        insert noEmail;
        List<Account> withEmail = makeFaculty(1, 'mail');
        String body = '{"calendars":{"' + withEmail[0].PersonEmail + '":{"busy":['
            + '{"start":"2026-09-28T11:00:00+05:30","end":"2026-09-28T12:00:00+05:30"}]}}}';
        FreeBusyMock mock = new FreeBusyMock(200, body);
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                new List<String>{ String.valueOf(noEmail.Id), String.valueOf(withEmail[0].Id) },
                RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'A faculty with no email is still returned, not skipped');
        Assert.areEqual(0, result[0].busy.size(), 'No email means no busy information, not an error');
        Assert.areEqual(1, result[1].busy.size(), 'The faculty with an email is still read');
        Assert.isTrue(
            mock.requests[0].getBody().contains(withEmail[0].PersonEmail),
            'Only the addressable faculty is sent to Google'
        );
    }

    @IsTest
    static void unresolvedAndMalformedIdsAreIgnored() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'bad');
        String body = '{"calendars":{"' + faculty[0].PersonEmail + '":{"busy":[]}}}';
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, body));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                new List<String>{
                    'not-an-id', '', String.valueOf(faculty[0].Id), String.valueOf(faculty[0].Id)
                },
                RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(1, result.size(), 'Blank, malformed and duplicate ids collapse to one row');
        Assert.areEqual(0, result[0].busy.size(), 'A free calendar returns an empty busy list');
    }

    @IsTest
    static void emptyAndNullInputReturnNothing() {
        GoogleCalendarHelper.configOverride = activeConfig();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.areEqual(0,
                FacultyAvailabilityService.getAvailability(null, RANGE_START, RANGE_END).size(),
                'Null faculty list yields no rows and no callout');
            Assert.areEqual(0,
                FacultyAvailabilityService.getAvailability(
                    new List<String>(), RANGE_START, RANGE_END).size(),
                'Empty faculty list yields no rows');
            Assert.areEqual(0,
                FacultyAvailabilityService.getAvailability(
                    new List<String>{ unusedFacultyId() }, null, RANGE_END).size(),
                'A missing range start yields no rows');
            Assert.areEqual(0, Limits.getCallouts(), 'No Google callout is spent on bad input');
        }
    }

    @IsTest
    static void invertedRangeReturnsNothing() {
        GoogleCalendarHelper.configOverride = activeConfig();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<FacultyAvailabilityService.FacultyAvailability> result =
                FacultyAvailabilityService.getAvailability(
                    new List<String>{ unusedFacultyId() },
                    Date.newInstance(2026, 9, 30),
                    Date.newInstance(2026, 9, 28)
                );
            Assert.areEqual(0, result.size(), 'An end before the start yields no rows');
            Assert.areEqual(0, Limits.getCallouts(), 'No Google callout is spent on a bad range');
        }
    }

    @IsTest
    static void inactiveIntegrationReturnsNothing() {
        Google_Calendar_Config__mdt inactive = activeConfig();
        inactive.Active__c = false;
        GoogleCalendarHelper.configOverride = inactive;
        List<Account> faculty = makeFaculty(1, 'off');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<FacultyAvailabilityService.FacultyAvailability> result =
                FacultyAvailabilityService.getAvailability(idsOf(faculty), RANGE_START, RANGE_END);
            Assert.areEqual(0, result.size(), 'The integration switch off means no availability data');
            Assert.areEqual(0, Limits.getCallouts(), 'No callout is attempted while switched off');
        }
    }

    @IsTest
    static void httpErrorFailsOpen() {
        seedIntegration();
        List<Account> faculty = makeFaculty(2, 'http');
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(500, '{"error":{"code":500}}'));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(2, result.size(), 'A Google outage still returns a row per faculty');
        Assert.areEqual(0, result[0].busy.size(), 'A non-200 fails open with no busy blocks');
        Assert.areEqual(0, result[1].busy.size(), 'A non-200 fails open with no busy blocks');
    }

    @IsTest
    static void malformedResponseFailsOpen() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'junk');
        Test.setMock(HttpCalloutMock.class, new FreeBusyMock(200, 'not json at all'));

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(1, result.size(), 'An unparseable body still returns the faculty row');
        Assert.areEqual(0, result[0].busy.size(), 'An unparseable body fails open, it does not throw');
    }

    @IsTest
    static void moreThanFiftyCalendarsAreChunked() {
        seedIntegration();
        List<Account> faculty = makeFaculty(51, 'chunk');
        EchoBusyMock mock = new EchoBusyMock();
        Test.setMock(HttpCalloutMock.class, mock);

        List<FacultyAvailabilityService.FacultyAvailability> result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            result = FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, RANGE_END
            );
            Test.stopTest();
        }

        Assert.areEqual(51, result.size(), 'Every requested faculty gets a row');
        Assert.areEqual(2, mock.callCount, '51 calendars need two requests at 50 per request');
        Assert.areEqual(50, mock.largestChunk, 'No request exceeds Google\'s 50-calendar limit');
        Assert.areEqual(51, mock.calendarsSeen, 'Every calendar is asked about exactly once');
        for (FacultyAvailabilityService.FacultyAvailability row : result) {
            Assert.areEqual(1, row.busy.size(), 'Both chunks are applied back to their rows');
        }
    }

    @IsTest
    static void busyBlocksSkipsUnusableIntervals() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Object node = calendarNode('{"busy":['
                + '"not an object",'
                + '{"end":"2026-09-28T10:00:00Z"},'
                + '{"start":"2026-09-28T10:00:00Z"},'
                + '{"start":"2026-09-28T11:00:00Z","end":"2026-09-28T10:00:00Z"},'
                + '{"start":"bad","end":"worse"},'
                + '{"start":"2026-09-28T09:00:00Z","end":"2026-09-28T09:30:00Z"}]}');
            List<FacultyAvailabilityService.BusyBlock> blocks =
                FacultyAvailabilityService.busyBlocks(node);
            Assert.areEqual(1, blocks.size(), 'Only the one well-formed interval survives');
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 9, 28, 9, 0, 0), blocks[0].startTime,
                'A trailing Z is read as UTC'
            );
            Assert.areEqual(0, FacultyAvailabilityService.busyBlocks('not a map').size(),
                'A non-object calendar node yields no busy blocks');
            Assert.areEqual(0, FacultyAvailabilityService.busyBlocks(calendarNode('{}')).size(),
                'A calendar node with no busy array yields no busy blocks');
        }
    }

    @IsTest
    static void unresolvedFacultyIdsYieldNoRows() {
        GoogleCalendarHelper.configOverride = activeConfig();
        GoogleAuthService.tokenOverride = 'tok';
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.areEqual(0,
                FacultyAvailabilityService.getAvailability(
                    new List<String>{ 'not-an-id', ' ' }, RANGE_START, RANGE_END).size(),
                'Ids that are not ids at all leave nothing to report on');
            Assert.areEqual(0,
                FacultyAvailabilityService.getAvailability(
                    new List<String>{ unusedFacultyId() }, RANGE_START, RANGE_END).size(),
                'A well-formed id matching no Account produces no row');
            Assert.areEqual(0, Limits.getCallouts(), 'Nothing resolved, so no callout is spent');
        }
    }

    @IsTest
    static void parsesRfc3339OffsetVariants() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Object node = calendarNode('{"busy":['
                + '{"start":"2026-09-28T09:00:00.000-08:00","end":"2026-09-28T10:00:00.000-08:00"},'
                + '{"start":"2026-09-28T20:00:00","end":"2026-09-28T21:00:00"}]}');
            List<FacultyAvailabilityService.BusyBlock> blocks =
                FacultyAvailabilityService.busyBlocks(node);
            Assert.areEqual(2, blocks.size(), 'Both offset shapes are parsed');
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 9, 28, 17, 0, 0), blocks[0].startTime,
                'Fractional seconds and a negative offset are handled'
            );
            Assert.areEqual(
                Datetime.newInstanceGmt(2026, 9, 28, 20, 0, 0), blocks[1].startTime,
                'A timestamp with no offset at all is read as UTC'
            );
        }
    }

    @IsTest
    static void timeWindowIsLocalMidnightWithOffset() {
        seedIntegration();
        List<Account> faculty = makeFaculty(1, 'win');
        FreeBusyMock mock = new FreeBusyMock(200, '{"calendars":{}}');
        Test.setMock(HttpCalloutMock.class, mock);

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            FacultyAvailabilityService.getAvailability(
                idsOf(faculty), RANGE_START, Date.newInstance(2026, 9, 30)
            );
            Test.stopTest();

            Map<String, Object> sent =
                (Map<String, Object>) JSON.deserializeUntyped(mock.requests[0].getBody());
            String timeMin = (String) sent.get('timeMin');
            String timeMax = (String) sent.get('timeMax');
            Assert.areEqual(
                'https://www.googleapis.com/calendar/v3/freeBusy', mock.requests[0].getEndpoint(),
                'The freeBusy endpoint is used, not events.list'
            );
            // Round-tripped through the parser rather than compared to toRfc3339's own output: an
            // implementation emitting the wrong offset would still equal itself, but it would not
            // survive being read back as an instant.
            List<FacultyAvailabilityService.BusyBlock> window =
                FacultyAvailabilityService.busyBlocks(calendarNode(
                    '{"busy":[{"start":"' + timeMin + '","end":"' + timeMax + '"}]}'
                ));
            Assert.areEqual(1, window.size(), 'The window Google was sent parses back cleanly');
            Assert.areEqual(
                Datetime.newInstance(RANGE_START, Time.newInstance(0, 0, 0, 0)),
                window[0].startTime,
                'timeMin is the instant at which the first local day of the range starts'
            );
            Assert.areEqual(
                Datetime.newInstance(Date.newInstance(2026, 10, 1), Time.newInstance(0, 0, 0, 0)),
                window[0].endTime,
                'timeMax is local midnight after the last day, so the last day is fully covered'
            );
            Assert.isTrue(
                Pattern.matches('2026-09-28T00:00:00[+-]\\d{2}:\\d{2}', timeMin),
                'timeMin is RFC 3339 with an explicit offset, e.g. +05:30. Got: ' + timeMin
            );
            Assert.isTrue(
                Pattern.matches('2026-10-01T00:00:00[+-]\\d{2}:\\d{2}', timeMax),
                'timeMax is RFC 3339 with an explicit offset. Got: ' + timeMax
            );
        }
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
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseBody);
            return res;
        }
    }

    /** @description A freeBusy mock echoing one busy block back for every calendar requested. */
    private class EchoBusyMock implements HttpCalloutMock {
        public Integer callCount = 0;
        public Integer calendarsSeen = 0;
        public Integer largestChunk = 0;

        /**
         * @description Returns one busy hour for each calendar in the request.
         * @param req The outbound request.
         * @return A freeBusy response covering exactly the requested calendars.
         */
        public HttpResponse respond(HttpRequest req) {
            callCount++;
            Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            List<Object> items = (List<Object>) sent.get('items');
            calendarsSeen += items.size();
            largestChunk = Math.max(largestChunk, items.size());
            Map<String, Object> calendars = new Map<String, Object>();
            for (Object item : items) {
                String calendarId = (String) ((Map<String, Object>) item).get('id');
                calendars.put(calendarId, new Map<String, Object>{
                    'busy' => new List<Object>{
                        new Map<String, Object>{
                            'start' => '2026-09-28T09:00:00+05:30',
                            'end'   => '2026-09-28T10:00:00+05:30'
                        }
                    }
                });
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(JSON.serialize(new Map<String, Object>{ 'calendars' => calendars }));
            return res;
        }
    }
}