/**
 * @description Integration tests for the SE-1056/1047 handler + queueable: create,
 *              update (PATCH), cancel (DELETE on status→Cancelled and on delete),
 *              write-back, and the trigger re-entry guard. Callouts are mocked; a
 *              throwaway RSA key lets JWT signing succeed. Draft/Cancelled
 *              transitions are used so the Published email automation isn't invoked.
 */
@IsTest
private class SessionCalendarInviteHandlerTest {

    // Disposable PKCS8 key — not a secret; only so Crypto.sign runs in tests.
    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDT6wSR5EcWKJV3\nGaKguMZuYbfB1mFchbUcQ3UtrBKe2hRvCBEQGlD45lFgLrl6WiS8UaoE+uzNs3P4\nC7hnLUOc7k6kyi274ZI2BsIte2ISeTTCT2yWSsBZRuIuMHvlxttZbxPq1QcRTKCk\n1fU6mvEUqm+22smiSKJdWYjcBo7cIxt0OwsQSoLEefZKlexMK7cXHDDh7sh4kpOR\nIQDx+sYtG8EhnwmqQN9HqEGt6GD9FOibJvLZIFpFaxR2kjys1XhNqv6DjjR/pObC\nac6YqxPRQ+UuJEnSCuc0mPV4gQd3+gYJ8sjrp7+Rr1Exj7dOjI2cmkProA61GizN\nosOBp7SFAgMBAAECggEAaCz7RSDcFTeEKlVOzgWnfnHJHJ/fotUT8D31J6uUR8Tb\nEK39fVYCgijuzgKKKWyQ7IaUtvgHWyOhmclhME9fEpFP1dCR5O+Bqc9uu18RGhW9\natwSfFto7TpcS+qHrbAw+mkReHqai9WIjx+i+tlaNBeI7XHmd0GPl6ZBEjCjH/G4\n7l5TLNMGiZNiFz2gNch9H8e/ZXQj7crWsYfgLxCIvUFWo4VTQCLwn1RUuA7rNGsx\nz2aEz7h/3g7hER2jRTnU9IXdLfleETeiO0TA4/XqBR5Mww7ncSOYlM8ZCRWh4KHo\nfjAs2rbqJYhpp3tLSiD9Ig3RHZ9bZ+aQ1RM1RBr2rQKBgQD033T4/z8XFEq7Xptt\nzskvUEpV98Stw2DrNhFZMVWO0Cgfntiv2sR4ozaN4Sm4e5m2ENixnjE4VqK8xDYI\nZ3UTA0PYbVJkPDvAGH7qr01TGLDdKSnQnNRRSIFUujVyg2AW9/smziagwieQAFz9\niVEOqZH7SzTWi6G0D2pwwR56GwKBgQDdjDStGiAcBg0ET6YcWBSMRaIAkdri7z4A\nhdq6fWxpOgUa8cpPT1x7uq2BIdvFTMFuat5EvZDW2nltv0p1GrykA7Mn3jmevQ1g\ntfzhB4f+mN3mjC0gQDHHy/oFnCEselQD1y9Bd6/J+3nOx+eSuEk1dJQJ43jrEx5P\nJ+s+Q7d13wKBgQCDRmBxNHVgLBK8TEXLInaclNClMcUQ2pNUxZGbXWVewJ0iBoho\nDkIR4n3WpgU1z51iC7n/zqzYZSmtRQsqijwrSy7OEh1/ewMVQoyXyA8OI0h96Blw\nqwLv6IzdHU6V63RSG/NapF31BOEsw+UWTs1TrPiD3ZegBQ9VdoY7mGx8TQKBgAnt\ns5qiVhgLaV/tFdulUt5qbHUsFCwhXpz1YrUC0+3vTLVFarSdMN7Wodnso4W3B+Aj\n5+watrf6OIDjlrmixhtvkwLRYbGsdUIFRdzr0ntlbGRdmdQdLF3w1TaVJaNxo/w8\nE4ESlQ0vOOk8ajNYEOfVXqEG0a9vPud7OX6j2D/vAoGBALjr5XixEQfWHvj9YBf2\n9M6+W1kgy+uwRuhVNBCe4zpStsOZlme1uRDIHmsIOuLOPnl+R6LEnQa3E7ih2Idy\nUJOTx65Ivz8c+O6S2b+btgFVRX7s2sw/JkKSG4L56KsM4hL7gDeASbj9eWL5qIlU\nAHI1ng21+pZWSmyBfEtHP6EW\n-----END PRIVATE KEY-----\n';

    private static void seedConfig() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = TEST_KEY,
            Impersonated_User__c = 'finessedirect@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    private class Mock implements HttpCalloutMock {
        /**
         * @description Returns mock HTTP responses for token, DELETE and Calendar API calls.
         * @param req the simulated HTTP request
         * @return the mock HTTP response
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":3600}');
            } else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(204);
            } else {
                res.setStatusCode(200);
                res.setBody('{"id":"evt_123","htmlLink":"https://calendar.google.com/event?eid=abc"}');
            }
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        /**
         * @description Mock that authenticates OK but fails the Calendar API / DELETE call.
         * @param req the simulated HTTP request
         * @return the mock HTTP response
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":3600}');
            } else {
                res.setStatusCode(400);
                res.setBody('{"error":{"message":"bad request"}}');
            }
            return res;
        }
    }

    private static Session__c newSession(String status, String eventId) {
        return new Session__c(
            Schedule_Type__c   = status,
            Google_Event_Id__c = eventId,
            Start_Time__c      = Datetime.now().addDays(1),
            End_Time__c        = Datetime.now().addDays(1).addHours(1)
        );
    }

    private static void addFaculty(Id sessionId, String email) {
        Id facRt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        Account fac = new Account(LastName = 'Test Faculty', PersonEmail = email, RecordTypeId = facRt);
        insert fac;
        insert new Session_Faculty__c(Session__c = sessionId, Session_Faculty__c = fac.Id);
    }

    // ── CREATE: Scheduled → Draft, faculty invited, event stored ──────────────
    @IsTest
    static void createStoresEventIdAndSynced() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;                                  // not an audience status → no enqueue
            addFaculty(s.Id, 'fac1@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Draft';
            update s;                                  // → faculty create
            Test.stopTest();                           // queueable runs

            Session__c after = [SELECT Google_Event_Id__c, Calendar_Sync_Status__c,
                                       Calendar_Last_Synced__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('evt_123', after.Google_Event_Id__c, 'event id should be written back');
            System.assertEquals('Synced', after.Calendar_Sync_Status__c);
            System.assertNotEquals(null, after.Calendar_Last_Synced__c);
        }
    }

    // ── UPDATE (PATCH): synced session whose details change ───────────────────
    @IsTest
    static void updatePatchesExistingEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', 'pre_existing_evt');
            insert s;
            addFaculty(s.Id, 'fac2@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Draft';              // statusChanged + has event id → PATCH
            update s;
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Synced', after.Calendar_Sync_Status__c);
        }
    }

    // ── CANCEL on status → Cancelled ──────────────────────────────────────────
    @IsTest
    static void cancelOnStatusCancelledDeletesAndMarksCancelled() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', 'evt_to_cancel');
            insert s;
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Cancelled';
            update s;
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c, Google_Event_Id__c
                                FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Cancelled', after.Calendar_Sync_Status__c);
            System.assertEquals(null, after.Google_Event_Id__c, 'event id cleared so re-publish creates fresh');
        }
    }

    // ── CANCEL on delete ──────────────────────────────────────────────────────
    @IsTest
    static void cancelOnDeleteDeletesEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', 'evt_on_delete');
            insert s;
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            delete s;                                  // after delete → cancel
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM Session__c WHERE Id = :s.Id],
                'session should be deleted; cancel callout runs without write-back');
        }
    }

    // ── SKIP is observable: audience status but no attendees → Failed recorded ─
    @IsTest
    static void skipNoAttendeesMarksFailed() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;                                  // no faculty / students at all
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Draft';              // audience status, but nobody to invite
            update s;
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c, Calendar_Sync_Error__c
                                FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Failed', after.Calendar_Sync_Status__c,
                'A session with no attendees must be recorded as Failed, not silently skipped.');
            System.assertNotEquals(null, after.Calendar_Sync_Error__c,
                'The skip reason should be captured for visibility / retry.');
        }
    }

    // ── Active__c master switch off → nothing enqueued, no sync ────────────────
    @IsTest
    static void inactiveConfigDoesNotSync() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;
            addFaculty(s.Id, 'fac@example.com');       // attendee exists, so only the
            Test.setMock(HttpCalloutMock.class, new Mock()); // gate can stop a sync
            GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
                Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
                Private_Key__c       = TEST_KEY,
                Impersonated_User__c = 'finessedirect@spjimr.org',
                Calendar_Id__c       = 'primary',
                Active__c            = false           // integration turned OFF
            );

            Test.startTest();
            s.Schedule_Type__c = 'Draft';
            update s;
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c FROM Session__c WHERE Id = :s.Id];
            System.assertNotEquals('Synced', after.Calendar_Sync_Status__c,
                'Inactive integration must not create a calendar event.');
            System.assertNotEquals('Failed', after.Calendar_Sync_Status__c,
                'Inactive integration should skip cleanly, not record a failure.');
        }
    }

    // ── Non-audience status → no work; suppress guard short-circuits ──────────
    @IsTest
    static void noOpAndSuppressGuard() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Complete', null);
            insert s;                                  // not synced → no enqueue
            seedConfig();

            Test.startTest();
            // Suppress guard: handler returns immediately, enqueues nothing.
            SessionCalendarInviteHandler.suppressInvites = true;
            SessionCalendarInviteHandler.handleSessionCalendarInvites(
                new Map<Id, Session__c>{ s.Id => s }, null);
            SessionCalendarInviteHandler.suppressInvites = false;
            Test.stopTest();

            // Suppressed handler enqueued nothing and left the record untouched.
            System.assertEquals('Complete',
                [SELECT Schedule_Type__c FROM Session__c WHERE Id = :s.Id].Schedule_Type__c);
        }
    }

    // ── Legacy 2-arg constructor + publish audience + full event (location/URL) ─
    @IsTest
    static void legacyConstructorPublishBuildsFullEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            s.Class_Room__c = 'Room 101';
            s.URL__c        = 'https://meet.example.com/abc';
            s.Description__c = 'Weekly lecture';
            insert s;
            addFaculty(s.Id, 'fac3@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            // 2-arg (backward-compatible) constructor; publish path resolves students too.
            System.enqueueJob(new SessionCalendarInviteQueueable(
                new Set<Id>{ s.Id }, new Set<Id>()));
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c, Google_Event_Id__c
                                FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Synced', after.Calendar_Sync_Status__c,
                'Publish via the legacy constructor should sync the event');
            System.assertEquals('evt_123', after.Google_Event_Id__c,
                'Created event id should be written back');
        }
    }

    // ── CREATE failure: non-success Calendar API response → Failed + error stamp ─
    @IsTest
    static void calloutFailureMarksFailed() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;
            addFaculty(s.Id, 'fac4@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new FailMock());

            Test.startTest();
            System.enqueueJob(new SessionCalendarInviteQueueable(
                new Set<Id>(), new Set<Id>{ s.Id }));   // draft → faculty only
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c, Calendar_Sync_Error__c
                                FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Failed', after.Calendar_Sync_Status__c,
                'A non-success Calendar API response must mark the session Failed');
            System.assertNotEquals(null, after.Calendar_Sync_Error__c,
                'The failure reason should be captured for visibility / retry');
        }
    }

    // ── CANCEL failure: failed DELETE → Failed recorded ───────────────────────
    @IsTest
    static void cancelFailureMarksFailed() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', 'evt_cancel_fail');
            insert s;
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new FailMock());

            Test.startTest();
            System.enqueueJob(new SessionCalendarInviteQueueable(
                new Set<Id>(), new Set<Id>(),
                new Map<Id, String>{ s.Id => 'evt_cancel_fail' }));
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Failed', after.Calendar_Sync_Status__c,
                'A failed DELETE must mark the session Failed');
        }
    }
}