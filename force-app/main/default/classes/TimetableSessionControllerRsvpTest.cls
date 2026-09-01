/**
 * @description Tests for TimetableSessionController.refreshAttendees (RSVP read-back) and for
 *          assertFacultyCalendarAvailable (the reschedule availability re-check).
 *
 *          RSVP: covers the no-session / not-found / not-pushed branches (no callout) and the
 *          live-refresh branch (callout mocked, responses written onto enrollments then
 *          read back into the summary). No Person Account chain is inserted, so the summary
 *          simply reflects zero enrolled students — enough to exercise every branch.
 *
 *          Reschedule check: the helper is exercised directly rather than through saveSession,
 *          which needs a whole programme/batch/course/division chain to reach the same line;
 *          the branches that matter here are whether Google is read at all and what the screen
 *          is handed when a faculty turns out to be busy.
 */
@IsTest
private class TimetableSessionControllerRsvpTest {

    private static Google_Calendar_Config__mdt cfg() {
        return new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = '-----BEGIN PRIVATE KEY-----\nMIICdummy\n-----END PRIVATE KEY-----',
            Impersonated_User__c = 'organizer@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    private static Session__c makeSession(String eventId) {
        Session__c s = new Session__c(
            Schedule_Type__c   = 'Published',
            Google_Event_Id__c = eventId,
            Start_Time__c      = Datetime.now().addDays(1),
            End_Time__c        = Datetime.now().addDays(1).addHours(1)
        );
        insert s;
        return s;
    }

    @IsTest
    static void refreshReturnsMessageForNullAndMissing() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TimetableSessionController.AttendeeSummary noId =
                TimetableSessionController.refreshAttendees(null);
            Assert.areEqual('No session specified.', noId.message, 'Null id is reported');

            Id fake = Id.valueOf(Session__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000001');
            TimetableSessionController.AttendeeSummary missing =
                TimetableSessionController.refreshAttendees(fake);
            Assert.areEqual('Session not found.', missing.message, 'Unknown id is reported');
        }
    }

    @IsTest
    static void refreshReportsNotPushedWhenNoEventId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = makeSession(null);
            Test.startTest();
            TimetableSessionController.AttendeeSummary summary =
                TimetableSessionController.refreshAttendees(s.Id);
            Test.stopTest();
            Assert.areEqual('This session has not been pushed to Google Calendar yet.', summary.message,
                'A session without a Google event id is reported as not pushed');
            Assert.areEqual(0, summary.total, 'No enrolled students, so the summary is empty');
        }
    }

    @IsTest
    static void refreshRunsLiveRefresh() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarHelper.configOverride = cfg();
            GoogleAuthService.tokenOverride = 'tok';
            Session__c s = makeSession('evt-1');
            Test.setMock(HttpCalloutMock.class, new GetMock());

            Test.startTest();
            TimetableSessionController.AttendeeSummary summary =
                TimetableSessionController.refreshAttendees(s.Id);
            Test.stopTest();

            // Callout + applyToEnrollments + read-back all ran; no enrolled students to count.
            Assert.areEqual(0, summary.total, 'No enrolled students exist for this session');
        }
    }

    private class GetMock implements HttpCalloutMock {
        /**
         * @description Serves the mocked Google response.
         * @param req The outbound request.
         * @return The canned response.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(200);
            r.setBody('{"id":"evt-1","attendees":['
                + '{"email":"a@spjimr.org","responseStatus":"accepted"}]}');
            return r;
        }
    }

    /**
     * @description A faculty Person Account the availability check can read a calendar for.
     * @param email The PersonEmail used as the Google calendar id.
     * @return The inserted faculty Account.
     */
    private static Account makeFaculty(String email) {
        Id facultyRecordTypeId = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        Account faculty = new Account(
            LastName = 'RescheduleFac', PersonEmail = email, RecordTypeId = facultyRecordTypeId
        );
        insert faculty;
        return faculty;
    }

    /**
     * @description The save request for a reschedule of the given session.
     * @param sessionId The session being moved.
     * @param newStart The proposed start.
     * @param facultyId The assigned faculty, or null to omit the faculty list.
     * @return The populated request.
     */
    private static TimetableSessionController.SessionInput rescheduleRequest(
        Id sessionId, Datetime newStart, Id facultyId
    ) {
        TimetableSessionController.SessionInput request = new TimetableSessionController.SessionInput();
        request.sessionId = sessionId;
        request.sessionName = 'Reschedule Test';
        request.sessionDate = newStart.date();
        request.startTime = newStart;
        request.endTime = newStart.addHours(1);
        if (facultyId != null) {
            request.selectedFacultyIds = new List<String>{ String.valueOf(facultyId) };
        }
        return request;
    }

    @IsTest
    static void rescheduleBlocksSaveWhenFacultyIsBusy() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarHelper.configOverride = cfg();
            GoogleAuthService.tokenOverride = 'tok';
            Account faculty = makeFaculty('busyfac@spjimr.org');
            Session__c existing = makeSession('evt-student');
            Test.setMock(HttpCalloutMock.class, new BusyWindowMock());

            Datetime newStart = existing.Start_Time__c.addDays(3);
            Boolean blocked = false;
            Test.startTest();
            try {
                TimetableSessionController.assertFacultyCalendarAvailable(
                    existing, rescheduleRequest(existing.Id, newStart, faculty.Id)
                );
            } catch (AuraHandledException e) {
                blocked = true;
            }
            // The payload the screen receives is asserted through the shared method the helper
            // delegates to: an AuraHandledException hides its message from Apex in a test context.
            List<TimetableSessionController.FacultyCalendarConflictDetail> details =
                TimetableSessionController.getFacultyCalendarConflictsForSessions(JSON.serialize(
                    new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'sessionId'          => String.valueOf(existing.Id),
                            'sessionName'        => 'Reschedule Test',
                            'sessionDate'        => String.valueOf(newStart.date()),
                            'startTime'          => newStart.format('HH:mm'),
                            'endTime'            => newStart.addHours(1).format('HH:mm'),
                            'selectedFacultyIds' => new List<String>{ String.valueOf(faculty.Id) }
                        }
                    }
                ));
            Test.stopTest();

            Assert.isTrue(blocked, 'A busy faculty calendar blocks the reschedule');
            Assert.areEqual(1, details.size(), 'The one busy faculty is reported');
            Assert.areEqual('busyfac@spjimr.org', details[0].facultyEmail,
                'The conflict names the faculty whose calendar was busy');
            Assert.isNotNull(details[0].conflictingTimeStr,
                'The scheduler is shown when the faculty is already booked');
        }
    }

    @IsTest
    static void rescheduleAllowsSaveWhenCalendarIsFree() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarHelper.configOverride = cfg();
            GoogleAuthService.tokenOverride = 'tok';
            Account faculty = makeFaculty('freefac@spjimr.org');
            Session__c existing = makeSession('evt-student-2');
            Test.setMock(HttpCalloutMock.class, new EmptyCalendarMock());

            Boolean blocked = false;
            Test.startTest();
            try {
                TimetableSessionController.assertFacultyCalendarAvailable(
                    existing, rescheduleRequest(existing.Id, existing.Start_Time__c.addDays(3), faculty.Id)
                );
            } catch (AuraHandledException e) {
                blocked = true;
            }
            Test.stopTest();

            Assert.isFalse(blocked, 'An empty calendar lets the reschedule through');
        }
    }

    @IsTest
    static void unchangedTimingAndCreateSkipTheCalendarRead() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c existing = makeSession('evt-student-3');
            TimetableSessionController.SessionInput sameTiming =
                rescheduleRequest(existing.Id, existing.Start_Time__c, null);
            sameTiming.endTime = existing.End_Time__c;
            sameTiming.selectedFacultyIds = new List<String>{ String.valueOf(UserInfo.getUserId()) };

            Test.startTest();
            // Same date and times: an edit that renamed the session must not call Google.
            TimetableSessionController.assertFacultyCalendarAvailable(existing, sameTiming);
            Assert.areEqual(0, Limits.getCallouts(),
                'A save that did not move the session spends no callout');

            // Create: there is no previous version to compare, and the screen already checked.
            TimetableSessionController.assertFacultyCalendarAvailable(
                null, rescheduleRequest(existing.Id, existing.Start_Time__c.addDays(3), null)
            );
            Assert.areEqual(0, Limits.getCallouts(), 'A create spends no callout here');

            // Reschedule with no faculty assigned: nobody to check.
            TimetableSessionController.assertFacultyCalendarAvailable(
                existing, rescheduleRequest(existing.Id, existing.Start_Time__c.addDays(3), null)
            );
            Assert.areEqual(0, Limits.getCallouts(), 'A session with no faculty spends no callout');
            Test.stopTest();
        }
    }

    /**
     * @description events.list mock that reports the faculty busy for exactly the window the
     *          service asked about, echoing the request's own timeMin/timeMax so the overlap
     *          holds whatever time zone the running user is in.
     */
    private class BusyWindowMock implements HttpCalloutMock {
        /**
         * @description Serves the mocked Google response.
         * @param req The outbound request.
         * @return The canned response.
         */
        public HttpResponse respond(HttpRequest req) {
            String endpoint = req.getEndpoint();
            String timeMin = EncodingUtil.urlDecode(
                endpoint.substringAfter('timeMin=').substringBefore('&'), 'UTF-8');
            String timeMax = EncodingUtil.urlDecode(endpoint.substringAfter('timeMax='), 'UTF-8');
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(200);
            r.setBody('{"items":[{"id":"other-evt","summary":"Board meeting","status":"confirmed",'
                + '"start":{"dateTime":"' + timeMin + '"},'
                + '"end":{"dateTime":"' + timeMax + '"}}]}');
            return r;
        }
    }

    /** @description events.list mock for a faculty with nothing booked in the window. */
    private class EmptyCalendarMock implements HttpCalloutMock {
        /**
         * @description Serves the mocked Google response.
         * @param req The outbound request.
         * @return The canned response.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(200);
            r.setBody('{"items":[]}');
            return r;
        }
    }
}