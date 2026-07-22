/**
 * @description Tests the outbound push for student-scheduled meetings:
 *          CalendarMeetingTrigger → CalendarMeetingInviteHandler →
 *          CalendarMeetingInviteQueueable, plus the inbound echo-guard that keeps our
 *          own pushes from being re-ingested. Uses a disposable RSA key (so JWT signing
 *          succeeds) and a configurable HTTP mock, mirroring GoogleCalendarUpdateCancelTest.
 */
@IsTest
private class CalendarMeetingInviteTest {

    // Disposable 2048-bit PKCS8 key — NOT a secret; only so Crypto.sign runs in tests.
    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDT6wSR5EcWKJV3\nGaKguMZuYbfB1mFchbUcQ3UtrBKe2hRvCBEQGlD45lFgLrl6WiS8UaoE+uzNs3P4\nC7hnLUOc7k6kyi274ZI2BsIte2ISeTTCT2yWSsBZRuIuMHvlxttZbxPq1QcRTKCk\n1fU6mvEUqm+22smiSKJdWYjcBo7cIxt0OwsQSoLEefZKlexMK7cXHDDh7sh4kpOR\nIQDx+sYtG8EhnwmqQN9HqEGt6GD9FOibJvLZIFpFaxR2kjys1XhNqv6DjjR/pObC\nac6YqxPRQ+UuJEnSCuc0mPV4gQd3+gYJ8sjrp7+Rr1Exj7dOjI2cmkProA61GizN\nosOBp7SFAgMBAAECggEAaCz7RSDcFTeEKlVOzgWnfnHJHJ/fotUT8D31J6uUR8Tb\nEK39fVYCgijuzgKKKWyQ7IaUtvgHWyOhmclhME9fEpFP1dCR5O+Bqc9uu18RGhW9\natwSfFto7TpcS+qHrbAw+mkReHqai9WIjx+i+tlaNBeI7XHmd0GPl6ZBEjCjH/G4\n7l5TLNMGiZNiFz2gNch9H8e/ZXQj7crWsYfgLxCIvUFWo4VTQCLwn1RUuA7rNGsx\nz2aEz7h/3g7hER2jRTnU9IXdLfleETeiO0TA4/XqBR5Mww7ncSOYlM8ZCRWh4KHo\nfjAs2rbqJYhpp3tLSiD9Ig3RHZ9bZ+aQ1RM1RBr2rQKBgQD033T4/z8XFEq7Xptt\nzskvUEpV98Stw2DrNhFZMVWO0Cgfntiv2sR4ozaN4Sm4e5m2ENixnjE4VqK8xDYI\nZ3UTA0PYbVJkPDvAGH7qr01TGLDdKSnQnNRRSIFUujVyg2AW9/smziagwieQAFz9\niVEOqZH7SzTWi6G0D2pwwR56GwKBgQDdjDStGiAcBg0ET6YcWBSMRaIAkdri7z4A\nhdq6fWxpOgUa8cpPT1x7uq2BIdvFTMFuat5EvZDW2nltv0p1GrykA7Mn3jmevQ1g\ntfzhB4f+mN3mjC0gQDHHy/oFnCEselQD1y9Bd6/J+3nOx+eSuEk1dJQJ43jrEx5P\nJ+s+Q7d13wKBgQCDRmBxNHVgLBK8TEXLInaclNClMcUQ2pNUxZGbXWVewJ0iBoho\nDkIR4n3WpgU1z51iC7n/zqzYZSmtRQsqijwrSy7OEh1/ewMVQoyXyA8OI0h96Blw\nqwLv6IzdHU6V63RSG/NapF31BOEsw+UWTs1TrPiD3ZegBQ9VdoY7mGx8TQKBgAnt\ns5qiVhgLaV/tFdulUt5qbHUsFCwhXpz1YrUC0+3vTLVFarSdMN7Wodnso4W3B+Aj\n5+watrf6OIDjlrmixhtvkwLRYbGsdUIFRdzr0ntlbGRdmdQdLF3w1TaVJaNxo/w8\nE4ESlQ0vOOk8ajNYEOfVXqEG0a9vPud7OX6j2D/vAoGBALjr5XixEQfWHvj9YBf2\n9M6+W1kgy+uwRuhVNBCe4zpStsOZlme1uRDIHmsIOuLOPnl+R6LEnQa3E7ih2Idy\nUJOTx65Ivz8c+O6S2b+btgFVRX7s2sw/JkKSG4L56KsM4hL7gDeASbj9eWL5qIlU\nAHI1ng21+pZWSmyBfEtHP6EW\n-----END PRIVATE KEY-----\n';

    private static void seedConfig(Boolean active) {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = TEST_KEY,
            Impersonated_User__c = 'finessedirect@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = active
        );
    }

    private static Calendar_Meeting__c newMeeting() {
        return new Calendar_Meeting__c(
            Subject__c        = 'Peer study session',
            Start_Time__c     = Datetime.now().addDays(1),
            End_Time__c       = Datetime.now().addDays(1).addHours(1),
            Location__c       = 'Library',
            Meeting_Link__c   = 'https://meet.example.com/x',
            Description__c    = 'Revision',
            Attendee_Emails__c = 'bala.student@spjimr.org, asha.faculty@spjimr.org',
            Source__c         = 'Salesforce',
            Meeting_Status__c = 'Scheduled',
            Sync_Status__c    = 'Pending'
        );
    }

    /** Configurable mock: 200 for token + POST/PATCH; deleteStatus drives DELETE; GET returns echoEventId. */
    private class Mock implements HttpCalloutMock {
        Integer eventStatus;
        Integer deleteStatus;
        String echoEventId;
        public String lastMethod;
        Mock(Integer eventStatus, Integer deleteStatus, String echoEventId) {
            this.eventStatus = eventStatus;
            this.deleteStatus = deleteStatus;
            this.echoEventId = echoEventId;
        }
        /**
         * @description Returns a canned HTTP response based on the request endpoint/method.
         * @param req The inbound HTTP request being mocked.
         * @return The mock HTTP response.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            lastMethod = req.getMethod();
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","token_type":"Bearer","expires_in":3600}');
            } else if (req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('{"items":[{"id":"' + echoEventId + '","summary":"Echo",' +
                    '"status":"confirmed","start":{"dateTime":"2026-08-01T10:00:00+05:30"},' +
                    '"end":{"dateTime":"2026-08-01T11:00:00+05:30"}}]}');
            } else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(deleteStatus);
                res.setBody(deleteStatus == 204 ? '' : '{"error":{"message":"x"}}');
            } else {
                res.setStatusCode(eventStatus);
                res.setBody(eventStatus == 200
                    ? '{"id":"evt_123","htmlLink":"https://calendar.google.com/event?eid=abc"}'
                    : '{"error":{"message":"bad"}}');
            }
            return res;
        }
    }

    @IsTest
    static void insertPushesCreateEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock(200, 204, null));
            Test.startTest();
            insert newMeeting();
            Test.stopTest();
            Calendar_Meeting__c m = [
                SELECT Google_Event_Id__c, Sync_Status__c, Event_Status__c
                FROM Calendar_Meeting__c LIMIT 1
            ];
            System.assertEquals('evt_123', m.Google_Event_Id__c, 'Create should store the Google event id');
            System.assertEquals('Synced', m.Sync_Status__c, 'Successful push is Synced');
            System.assertEquals('Confirmed', m.Event_Status__c, 'Created event is Confirmed');
        }
    }

    @IsTest
    static void googleSourcedMeetingIsNotPushed() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock(200, 204, null));
            Calendar_Meeting__c m = newMeeting();
            m.Source__c = 'Google'; // inbound-ingested copy — must NOT be pushed back out
            m.Sync_Status__c = 'Synced';
            Test.startTest();
            insert m;
            Test.stopTest();
            Calendar_Meeting__c after = [SELECT Google_Event_Id__c FROM Calendar_Meeting__c WHERE Id = :m.Id];
            System.assertEquals(null, after.Google_Event_Id__c, 'Google-sourced meetings are never pushed');
        }
    }

    @IsTest
    static void inactiveConfigDoesNotPush() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig(false); // master switch OFF
            Test.setMock(HttpCalloutMock.class, new Mock(200, 204, null));
            Test.startTest();
            insert newMeeting();
            Test.stopTest();
            Calendar_Meeting__c m = [SELECT Google_Event_Id__c FROM Calendar_Meeting__c LIMIT 1];
            System.assertEquals(null, m.Google_Event_Id__c, 'No push when integration is inactive');
        }
    }

    @IsTest
    static void updatePatchesExistingEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            CalendarMeetingInviteHandler.suppressInvites = true;
            Calendar_Meeting__c m = newMeeting();
            m.Google_Event_Id__c = 'evt_123';
            m.Sync_Status__c = 'Synced';
            insert m;
            CalendarMeetingInviteHandler.suppressInvites = false;

            seedConfig(true);
            Mock mock = new Mock(200, 204, null);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            m.Subject__c = 'Rescheduled study session';
            update m;
            Test.stopTest();

            System.assertEquals('PATCH', mock.lastMethod, 'Existing event must be updated via PATCH');
            Calendar_Meeting__c after = [SELECT Sync_Status__c FROM Calendar_Meeting__c WHERE Id = :m.Id];
            System.assertEquals('Synced', after.Sync_Status__c, 'Update should mark Synced');
        }
    }

    @IsTest
    static void cancelDeletesEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            CalendarMeetingInviteHandler.suppressInvites = true;
            Calendar_Meeting__c m = newMeeting();
            m.Google_Event_Id__c = 'evt_123';
            m.Sync_Status__c = 'Synced';
            insert m;
            CalendarMeetingInviteHandler.suppressInvites = false;

            seedConfig(true);
            Mock mock = new Mock(200, 204, null);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            m.Meeting_Status__c = 'Cancelled';
            update m;
            Test.stopTest();

            System.assertEquals('DELETE', mock.lastMethod, 'Cancel must issue a DELETE');
            Calendar_Meeting__c after = [
                SELECT Google_Event_Id__c, Event_Status__c FROM Calendar_Meeting__c WHERE Id = :m.Id
            ];
            System.assertEquals(null, after.Google_Event_Id__c, 'Cancel should clear the event id');
            System.assertEquals('Cancelled', after.Event_Status__c, 'Cancel should set Event_Status__c');
        }
    }

    @IsTest
    static void failedCalloutWritesError() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock(500, 204, null));
            Test.startTest();
            insert newMeeting();
            Test.stopTest();
            Calendar_Meeting__c m = [SELECT Sync_Status__c, Sync_Error__c FROM Calendar_Meeting__c LIMIT 1];
            System.assertEquals('Failed', m.Sync_Status__c, 'A 500 must mark the meeting Failed');
            System.assertNotEquals(null, m.Sync_Error__c, 'The failure reason must be recorded');
        }
    }

    @IsTest
    static void missingTimesFailsValidation() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            CalendarMeetingInviteHandler.suppressInvites = true;
            Calendar_Meeting__c m = newMeeting();
            m.Start_Time__c = null;
            m.End_Time__c = null;
            insert m;
            CalendarMeetingInviteHandler.suppressInvites = false;

            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock(200, 204, null));
            Test.startTest();
            System.enqueueJob(new CalendarMeetingInviteQueueable(new Set<Id>{ m.Id }));
            Test.stopTest();

            Calendar_Meeting__c after = [SELECT Sync_Status__c, Sync_Error__c FROM Calendar_Meeting__c WHERE Id = :m.Id];
            System.assertEquals('Failed', after.Sync_Status__c, 'Missing times should fail validation');
            System.assert(after.Sync_Error__c.containsIgnoreCase('start_time'), 'Error should mention the missing times');
        }
    }

    @IsTest
    static void deleteCancelsEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            CalendarMeetingInviteHandler.suppressInvites = true;
            Calendar_Meeting__c m = newMeeting();
            m.Google_Event_Id__c = 'evt_123';
            insert m;
            CalendarMeetingInviteHandler.suppressInvites = false;

            seedConfig(true);
            Mock mock = new Mock(200, 204, null);
            Test.setMock(HttpCalloutMock.class, mock);
            Test.startTest();
            delete m;
            Test.stopTest();
            System.assertEquals('DELETE', mock.lastMethod, 'Deleting a meeting must cancel its Google event');
        }
    }

    /** Mock for the inbound ingest path: token + a GET returning one rich, new event. */
    private class IngestMock implements HttpCalloutMock {
        /**
         * @description Returns a token for the token endpoint and a single fresh event
         *          (with attendees, location, link and status) for the events GET.
         * @param req The inbound HTTP request being mocked.
         * @return The mock HTTP response.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","token_type":"Bearer","expires_in":3600}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"items":[{"id":"evt_inbound_new","summary":"Peer meetup",' +
                    '"location":"Cafeteria","hangoutLink":"https://meet.google.com/abc",' +
                    '"status":"confirmed","organizer":{"email":"host@spjimr.org"},' +
                    '"attendees":[{"email":"x@spjimr.org"},{"email":"y@spjimr.org"}],' +
                    '"start":{"dateTime":"2026-09-01T09:30:00+05:30"},' +
                    '"end":{"dateTime":"2026-09-01T10:30:00+05:30"}}]}');
            }
            return res;
        }
    }

    @IsTest
    static void inboundIngestCreatesMeeting() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new IngestMock());
            Test.startTest();
            GoogleCalendarInboundService.InboundResult r =
                GoogleCalendarInboundService.syncCalendar('cal@spjimr.org', Datetime.now().addDays(-2));
            Test.stopTest();

            System.assertEquals(1, r.created, 'A fresh Google event should be ingested');
            Calendar_Meeting__c m = [
                SELECT Subject__c, Location__c, Source__c, Event_Status__c, Attendee_Emails__c
                FROM Calendar_Meeting__c WHERE Google_Event_Id__c = 'evt_inbound_new'
            ];
            System.assertEquals('Google', m.Source__c, 'Ingested meeting is Google-sourced');
            System.assertEquals('Peer meetup', m.Subject__c, 'Summary maps to Subject__c');
            System.assert(m.Attendee_Emails__c.contains('x@spjimr.org'), 'Attendees are captured');
        }
    }

    @IsTest
    static void echoGuardSkipsSalesforceMeeting() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // A Salesforce-originated meeting we already pushed, with a known event id.
            CalendarMeetingInviteHandler.suppressInvites = true;
            Calendar_Meeting__c m = newMeeting();
            m.Google_Event_Id__c = 'evt_echo';
            insert m;
            CalendarMeetingInviteHandler.suppressInvites = false;

            Integer before = [SELECT COUNT() FROM Calendar_Meeting__c WHERE Source__c = 'Google'];
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock(200, 204, 'evt_echo'));
            Test.startTest();
            GoogleCalendarInboundService.InboundResult r =
                GoogleCalendarInboundService.syncCalendar('cal@spjimr.org', null);
            Test.stopTest();

            Integer after = [SELECT COUNT() FROM Calendar_Meeting__c WHERE Source__c = 'Google'];
            System.assertEquals(0, r.created, 'Our own pushed event must not be re-ingested');
            System.assertEquals(before, after, 'No Google-sourced copy should be created for evt_echo');
        }
    }
}