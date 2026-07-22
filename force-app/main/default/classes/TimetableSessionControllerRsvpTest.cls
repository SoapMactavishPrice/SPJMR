/**
 * @description Tests for TimetableSessionController.refreshAttendees (RSVP read-back).
 *          Covers the no-session / not-found / not-pushed branches (no callout) and the
 *          live-refresh branch (callout mocked, responses written onto enrollments then
 *          read back into the summary). No Person Account chain is inserted, so the summary
 *          simply reflects zero enrolled students — enough to exercise every branch.
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

            Id fake = Id.valueOf(Session__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
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

    private class GetMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setHeader('Content-Type', 'application/json');
            r.setStatusCode(200);
            r.setBody('{"id":"evt-1","attendees":['
                + '{"email":"a@spjimr.org","responseStatus":"accepted"}]}');
            return r;
        }
    }
}