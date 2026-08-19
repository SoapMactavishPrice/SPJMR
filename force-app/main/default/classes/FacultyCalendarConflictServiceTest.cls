/**
 * @description Unit tests for FacultyCalendarConflictService. The pure overlap/busy filter
 *              is tested with in-memory event maps (no callout); the callout path uses
 *              GoogleAuthService.tokenOverride to bypass JWT signing and an HttpCalloutMock
 *              for events.list, including the fail-open branches.
 */
@IsTest
private class FacultyCalendarConflictServiceTest {

    private static final String FAC = 'faculty@spjimr.org';
    // Window: 2026-07-16 02:00–03:00 UTC.
    private static final Datetime WIN_START = Datetime.newInstanceGmt(2026, 7, 16, 2, 0, 0);
    private static final Datetime WIN_END   = Datetime.newInstanceGmt(2026, 7, 16, 3, 0, 0);

    private static Object items(String arrJson) {
        return ((Map<String, Object>) JSON.deserializeUntyped('{"items":' + arrJson + '}')).get('items');
    }

    private static Google_Calendar_Config__mdt cfg() {
        return new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = '-----BEGIN PRIVATE KEY-----\nMIICdummy\n-----END PRIVATE KEY-----',
            Impersonated_User__c = 'organizer@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    @IsTest
    static void overlappingBusyFlagsGenuineOverlap() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Object it = items('[{"id":"evt-123","summary":"xyz session","status":"confirmed",'
                + '"start":{"dateTime":"2026-07-16T02:30:00Z"},'
                + '"end":{"dateTime":"2026-07-16T03:30:00Z"}}]');
            List<FacultyCalendarConflictService.BusyEvent> r =
                FacultyCalendarConflictService.overlappingBusy(it, FAC, WIN_START, WIN_END, null);
            Assert.areEqual(1, r.size(), 'A timed overlapping event is a conflict');
            Assert.areEqual('xyz session', r[0].summary, 'Summary carried through');
            Assert.areEqual('evt-123', r[0].eventId, 'Google event id is captured');
        }
    }

    @IsTest
    static void overlappingBusyExcludesOwnEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Object it = items('[{"id":"self-evt","summary":"my own session",'
                + '"start":{"dateTime":"2026-07-16T02:30:00Z"},'
                + '"end":{"dateTime":"2026-07-16T03:30:00Z"}}]');
            List<FacultyCalendarConflictService.BusyEvent> r =
                FacultyCalendarConflictService.overlappingBusy(
                    it, FAC, WIN_START, WIN_END, new Set<String>{ 'self-evt' });
            Assert.areEqual(0, r.size(), 'The own session event is not a self-conflict');
        }
    }

    @IsTest
    static void overlappingBusySkipsNonConflicts() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Object it = items('['
                + '{"summary":"all day","start":{"date":"2026-07-16"},"end":{"date":"2026-07-17"}},'
                + '{"summary":"free","transparency":"transparent","start":{"dateTime":"2026-07-16T02:30:00Z"},"end":{"dateTime":"2026-07-16T02:45:00Z"}},'
                + '{"summary":"cancelled","status":"cancelled","start":{"dateTime":"2026-07-16T02:10:00Z"},"end":{"dateTime":"2026-07-16T02:20:00Z"}},'
                + '{"summary":"declined","start":{"dateTime":"2026-07-16T02:30:00Z"},"end":{"dateTime":"2026-07-16T02:45:00Z"},"attendees":[{"self":true,"responseStatus":"declined"}]},'
                + '{"summary":"before","start":{"dateTime":"2026-07-16T00:00:00Z"},"end":{"dateTime":"2026-07-16T01:00:00Z"}},'
                + '{"summary":"after","start":{"dateTime":"2026-07-16T04:00:00Z"},"end":{"dateTime":"2026-07-16T05:00:00Z"}}]');
            List<FacultyCalendarConflictService.BusyEvent> r =
                FacultyCalendarConflictService.overlappingBusy(it, FAC, WIN_START, WIN_END, null);
            Assert.areEqual(0, r.size(), 'All-day, free, cancelled, declined and non-overlapping events are skipped');
        }
    }

    @IsTest
    static void overlappingBusyHandlesBadInput() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.areEqual(0,
                FacultyCalendarConflictService.overlappingBusy('not a list', FAC, WIN_START, WIN_END, null).size(),
                'Non-list input yields no conflicts');
        }
    }

    @IsTest
    static void findOverlapsReturnsConflictsFromCallout() {
        GoogleCalendarHelper.configOverride = cfg();
        GoogleAuthService.tokenOverride = 'tok';
        Test.setMock(HttpCalloutMock.class, new OkMock());
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<FacultyCalendarConflictService.BusyEvent> r =
                FacultyCalendarConflictService.findOverlaps(FAC, WIN_START, WIN_END);
            Test.stopTest();
            Assert.areEqual(1, r.size(), 'The overlapping event from the API is returned');
            Assert.areEqual('xyz session', r[0].summary, 'Summary carried through the callout path');
        }
    }

    @IsTest
    static void findOverlapsFailsOpenOnError() {
        GoogleCalendarHelper.configOverride = cfg();
        GoogleAuthService.tokenOverride = 'tok';
        Test.setMock(HttpCalloutMock.class, new ErrorMock());
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<FacultyCalendarConflictService.BusyEvent> r =
                FacultyCalendarConflictService.findOverlaps(FAC, WIN_START, WIN_END);
            Test.stopTest();
            Assert.areEqual(0, r.size(), 'A non-200 response fails open (no conflicts, no exception)');
        }
    }

    @IsTest
    static void findOverlapsGuardsBlankInput() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.areEqual(0, FacultyCalendarConflictService.findOverlaps(null, WIN_START, WIN_END).size(),
                'Blank email → no conflicts, no callout');
            Assert.areEqual(0, FacultyCalendarConflictService.findOverlaps(FAC, null, WIN_END).size(),
                'Null window → no conflicts');
        }
    }

    private class OkMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(200);
            r.setHeader('Content-Type', 'application/json');
            r.setBody('{"items":[{"summary":"xyz session","status":"confirmed",'
                + '"start":{"dateTime":"2026-07-16T02:30:00Z"},'
                + '"end":{"dateTime":"2026-07-16T03:30:00Z"}}]}');
            return r;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(500);
            r.setBody('{"error":"boom"}');
            return r;
        }
    }
}