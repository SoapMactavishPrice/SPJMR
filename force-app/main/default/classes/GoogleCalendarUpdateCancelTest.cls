/**
 * @description Tests for the SE-1047 update (PATCH) and cancel (DELETE) branches on
 *              GoogleCalendarService and GoogleCalendarHelper. Uses a throwaway RSA
 *              key (signs cleanly) plus a configurable HTTP mock so success/failure
 *              status handling can be asserted directly.
 */
@IsTest
private class GoogleCalendarUpdateCancelTest {

    // A disposable 2048-bit PKCS8 key — NOT a secret, generated only so Crypto.sign
    // succeeds in tests and the callout path runs end to end.
    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDT6wSR5EcWKJV3\nGaKguMZuYbfB1mFchbUcQ3UtrBKe2hRvCBEQGlD45lFgLrl6WiS8UaoE+uzNs3P4\nC7hnLUOc7k6kyi274ZI2BsIte2ISeTTCT2yWSsBZRuIuMHvlxttZbxPq1QcRTKCk\n1fU6mvEUqm+22smiSKJdWYjcBo7cIxt0OwsQSoLEefZKlexMK7cXHDDh7sh4kpOR\nIQDx+sYtG8EhnwmqQN9HqEGt6GD9FOibJvLZIFpFaxR2kjys1XhNqv6DjjR/pObC\nac6YqxPRQ+UuJEnSCuc0mPV4gQd3+gYJ8sjrp7+Rr1Exj7dOjI2cmkProA61GizN\nosOBp7SFAgMBAAECggEAaCz7RSDcFTeEKlVOzgWnfnHJHJ/fotUT8D31J6uUR8Tb\nEK39fVYCgijuzgKKKWyQ7IaUtvgHWyOhmclhME9fEpFP1dCR5O+Bqc9uu18RGhW9\natwSfFto7TpcS+qHrbAw+mkReHqai9WIjx+i+tlaNBeI7XHmd0GPl6ZBEjCjH/G4\n7l5TLNMGiZNiFz2gNch9H8e/ZXQj7crWsYfgLxCIvUFWo4VTQCLwn1RUuA7rNGsx\nz2aEz7h/3g7hER2jRTnU9IXdLfleETeiO0TA4/XqBR5Mww7ncSOYlM8ZCRWh4KHo\nfjAs2rbqJYhpp3tLSiD9Ig3RHZ9bZ+aQ1RM1RBr2rQKBgQD033T4/z8XFEq7Xptt\nzskvUEpV98Stw2DrNhFZMVWO0Cgfntiv2sR4ozaN4Sm4e5m2ENixnjE4VqK8xDYI\nZ3UTA0PYbVJkPDvAGH7qr01TGLDdKSnQnNRRSIFUujVyg2AW9/smziagwieQAFz9\niVEOqZH7SzTWi6G0D2pwwR56GwKBgQDdjDStGiAcBg0ET6YcWBSMRaIAkdri7z4A\nhdq6fWxpOgUa8cpPT1x7uq2BIdvFTMFuat5EvZDW2nltv0p1GrykA7Mn3jmevQ1g\ntfzhB4f+mN3mjC0gQDHHy/oFnCEselQD1y9Bd6/J+3nOx+eSuEk1dJQJ43jrEx5P\nJ+s+Q7d13wKBgQCDRmBxNHVgLBK8TEXLInaclNClMcUQ2pNUxZGbXWVewJ0iBoho\nDkIR4n3WpgU1z51iC7n/zqzYZSmtRQsqijwrSy7OEh1/ewMVQoyXyA8OI0h96Blw\nqwLv6IzdHU6V63RSG/NapF31BOEsw+UWTs1TrPiD3ZegBQ9VdoY7mGx8TQKBgAnt\ns5qiVhgLaV/tFdulUt5qbHUsFCwhXpz1YrUC0+3vTLVFarSdMN7Wodnso4W3B+Aj\n5+watrf6OIDjlrmixhtvkwLRYbGsdUIFRdzr0ntlbGRdmdQdLF3w1TaVJaNxo/w8\nE4ESlQ0vOOk8ajNYEOfVXqEG0a9vPud7OX6j2D/vAoGBALjr5XixEQfWHvj9YBf2\n9M6+W1kgy+uwRuhVNBCe4zpStsOZlme1uRDIHmsIOuLOPnl+R6LEnQa3E7ih2Idy\nUJOTx65Ivz8c+O6S2b+btgFVRX7s2sw/JkKSG4L56KsM4hL7gDeASbj9eWL5qIlU\nAHI1ng21+pZWSmyBfEtHP6EW\n-----END PRIVATE KEY-----\n';

    private static final String SUB = 'finessedirect@spjimr.org';

    private static void seedConfig() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = TEST_KEY,
            Impersonated_User__c = SUB,
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    private static GoogleCalendarEvent sampleEvent() {
        GoogleCalendarEvent ev = new GoogleCalendarEvent(
            'Unit Test Session',
            new Map<String, Object>{ 'dateTime' => '2026-06-20T10:00:00+05:30', 'timeZone' => 'Asia/Kolkata' },
            new Map<String, Object>{ 'dateTime' => '2026-06-20T11:00:00+05:30', 'timeZone' => 'Asia/Kolkata' },
            'Asia/Kolkata'
        );
        ev.location = 'Room 1';
        ev.description = 'desc';
        return ev;
    }

    /** Configurable mock: 200 for token + create/patch; deleteStatus drives DELETE. */
    private class Mock implements HttpCalloutMock {
        Integer eventStatus;
        Integer deleteStatus;
        public String lastMethod;
        public String lastBody;
        Mock(Integer eventStatus, Integer deleteStatus) {
            this.eventStatus = eventStatus;
            this.deleteStatus = deleteStatus;
        }
        /**
         * @description Returns a canned HTTP response based on the request endpoint/method.
         * @param req the inbound HTTP request being mocked
         * @return the mock HTTP response
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            lastMethod = req.getMethod();
            lastBody = req.getBody();
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","token_type":"Bearer","expires_in":3600}');
            } else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(deleteStatus);
                res.setBody(deleteStatus == 204 ? '' : '{"error":{"message":"x"}}');
            } else { // POST / PATCH
                res.setStatusCode(eventStatus);
                res.setBody(eventStatus == 200
                    ? '{"id":"evt_123","htmlLink":"https://calendar.google.com/event?eid=abc"}'
                    : '{"error":{"message":"bad"}}');
            }
            return res;
        }
    }

    // ── UPDATE (PATCH) ────────────────────────────────────────────────────────
    @IsTest
    static void updateSuccessReturnsEventId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Mock m = new Mock(200, 204);
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarHelper.updateEventWithStoredCredentials('evt_123', sampleEvent());
            Test.stopTest();
            System.assert(r.success, 'PATCH 200 should succeed: ' + r.errorMessage);
            System.assertEquals('evt_123', r.eventId);
            System.assertEquals('PATCH', m.lastMethod, 'Update must use HTTP PATCH');
        }
    }

    @IsTest
    static void updateBlankEventIdErrors() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarService.updateCalendarEvent('primary', '', sampleEvent(), SUB);
            System.assert(!r.success);
            System.assert(r.errorMessage.containsIgnoreCase('eventId'), r.errorMessage);
        }
    }

    @IsTest
    static void updateNon200Fails() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock(404, 204));
            Test.startTest();
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarHelper.updateEventWithStoredCredentials('evt_123', sampleEvent());
            Test.stopTest();
            System.assert(!r.success);
            System.assert(r.errorMessage.contains('404'), r.errorMessage);
        }
    }

    // ── DELETE (cancel) ───────────────────────────────────────────────────────
    @IsTest
    static void delete204Succeeds() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Mock m = new Mock(200, 204);
            Test.setMock(HttpCalloutMock.class, m);
            Test.startTest();
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarHelper.deleteEventWithStoredCredentials('evt_123');
            Test.stopTest();
            System.assert(r.success, 'DELETE 204 should succeed: ' + r.errorMessage);
            System.assertEquals('DELETE', m.lastMethod);
        }
    }

    @IsTest
    static void delete410TreatedAsSuccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock(200, 410));
            Test.startTest();
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarHelper.deleteEventWithStoredCredentials('evt_123');
            Test.stopTest();
            System.assert(r.success, '410 Gone (already deleted) should be idempotent success');
        }
    }

    @IsTest
    static void delete404Fails() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock(200, 404));
            Test.startTest();
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarHelper.deleteEventWithStoredCredentials('evt_123');
            Test.stopTest();
            System.assert(!r.success);
            System.assert(r.errorMessage.contains('404'), r.errorMessage);
        }
    }

    @IsTest
    static void deleteBlankEventIdErrors() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarService.deleteCalendarEvent('primary', null, SUB);
            System.assert(!r.success);
            System.assert(r.errorMessage.containsIgnoreCase('eventId'), r.errorMessage);
        }
    }

    // ── CREATE path / buildEventMap attendee filtering ────────────────────────
    @IsTest
    static void createFiltersImpersonatedUserFromAttendees() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Mock m = new Mock(200, 204);
            Test.setMock(HttpCalloutMock.class, m);
            GoogleCalendarEvent ev = sampleEvent();
            ev.attendees = new List<String>{ SUB, 'student@example.com' };
            Test.startTest();
            GoogleCalendarService.GoogleCalendarResponse r =
                GoogleCalendarHelper.createEventWithStoredCredentials(ev);
            Test.stopTest();
            System.assert(r.success, r.errorMessage);
            System.assertEquals('POST', m.lastMethod);
            System.assert(m.lastBody.contains('student@example.com'), 'attendee should be kept');
            System.assert(!m.lastBody.contains(SUB), 'impersonated organiser must be filtered out');
        }
    }

    // ── Helper guard clauses ──────────────────────────────────────────────────
    @IsTest
    static void helperUpdateThrowsWhenUnconfigured() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(); // blank
            Boolean threw = false;
            try {
                GoogleCalendarHelper.updateEventWithStoredCredentials('evt_123', sampleEvent());
            } catch (GoogleCalendarHelper.GoogleCalendarException e) {
                threw = true;
            }
            System.assert(threw, 'update should require configuration');
        }
    }

    @IsTest
    static void helperDeleteThrowsWhenUnconfigured() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(); // blank
            Boolean threw = false;
            try {
                GoogleCalendarHelper.deleteEventWithStoredCredentials('evt_123');
            } catch (GoogleCalendarHelper.GoogleCalendarException e) {
                threw = true;
            }
            System.assert(threw, 'delete should require configuration');
        }
    }
}