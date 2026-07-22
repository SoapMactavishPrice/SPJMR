/**
 * @description Tests the inbound faculty-calendar poller (Requirement 3):
 *          GoogleCalendarInboundSchedulable (faculty watch list + chunking) and
 *          GoogleCalendarInboundQueueable (fetch + persist). Uses a disposable RSA key
 *          so JWT signing runs, and an HTTP mock for the token + events.list callouts.
 */
@IsTest
private class GoogleCalendarInboundDriverTest {

    // Disposable PKCS8 key — not a secret; only so Crypto.sign runs in tests.
    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDT6wSR5EcWKJV3\nGaKguMZuYbfB1mFchbUcQ3UtrBKe2hRvCBEQGlD45lFgLrl6WiS8UaoE+uzNs3P4\nC7hnLUOc7k6kyi274ZI2BsIte2ISeTTCT2yWSsBZRuIuMHvlxttZbxPq1QcRTKCk\n1fU6mvEUqm+22smiSKJdWYjcBo7cIxt0OwsQSoLEefZKlexMK7cXHDDh7sh4kpOR\nIQDx+sYtG8EhnwmqQN9HqEGt6GD9FOibJvLZIFpFaxR2kjys1XhNqv6DjjR/pObC\nac6YqxPRQ+UuJEnSCuc0mPV4gQd3+gYJ8sjrp7+Rr1Exj7dOjI2cmkProA61GizN\nosOBp7SFAgMBAAECggEAaCz7RSDcFTeEKlVOzgWnfnHJHJ/fotUT8D31J6uUR8Tb\nEK39fVYCgijuzgKKKWyQ7IaUtvgHWyOhmclhME9fEpFP1dCR5O+Bqc9uu18RGhW9\natwSfFto7TpcS+qHrbAw+mkReHqai9WIjx+i+tlaNBeI7XHmd0GPl6ZBEjCjH/G4\n7l5TLNMGiZNiFz2gNch9H8e/ZXQj7crWsYfgLxCIvUFWo4VTQCLwn1RUuA7rNGsx\nz2aEz7h/3g7hER2jRTnU9IXdLfleETeiO0TA4/XqBR5Mww7ncSOYlM8ZCRWh4KHo\nfjAs2rbqJYhpp3tLSiD9Ig3RHZ9bZ+aQ1RM1RBr2rQKBgQD033T4/z8XFEq7Xptt\nzskvUEpV98Stw2DrNhFZMVWO0Cgfntiv2sR4ozaN4Sm4e5m2ENixnjE4VqK8xDYI\nZ3UTA0PYbVJkPDvAGH7qr01TGLDdKSnQnNRRSIFUujVyg2AW9/smziagwieQAFz9\niVEOqZH7SzTWi6G0D2pwwR56GwKBgQDdjDStGiAcBg0ET6YcWBSMRaIAkdri7z4A\nhdq6fWxpOgUa8cpPT1x7uq2BIdvFTMFuat5EvZDW2nltv0p1GrykA7Mn3jmevQ1g\ntfzhB4f+mN3mjC0gQDHHy/oFnCEselQD1y9Bd6/J+3nOx+eSuEk1dJQJ43jrEx5P\nJ+s+Q7d13wKBgQCDRmBxNHVgLBK8TEXLInaclNClMcUQ2pNUxZGbXWVewJ0iBoho\nDkIR4n3WpgU1z51iC7n/zqzYZSmtRQsqijwrSy7OEh1/ewMVQoyXyA8OI0h96Blw\nqwLv6IzdHU6V63RSG/NapF31BOEsw+UWTs1TrPiD3ZegBQ9VdoY7mGx8TQKBgAnt\ns5qiVhgLaV/tFdulUt5qbHUsFCwhXpz1YrUC0+3vTLVFarSdMN7Wodnso4W3B+Aj\n5+watrf6OIDjlrmixhtvkwLRYbGsdUIFRdzr0ntlbGRdmdQdLF3w1TaVJaNxo/w8\nE4ESlQ0vOOk8ajNYEOfVXqEG0a9vPud7OX6j2D/vAoGBALjr5XixEQfWHvj9YBf2\n9M6+W1kgy+uwRuhVNBCe4zpStsOZlme1uRDIHmsIOuLOPnl+R6LEnQa3E7ih2Idy\nUJOTx65Ivz8c+O6S2b+btgFVRX7s2sw/JkKSG4L56KsM4hL7gDeASbj9eWL5qIlU\nAHI1ng21+pZWSmyBfEtHP6EW\n-----END PRIVATE KEY-----\n';

    private static final String FACULTY_EMAIL = 'fac@spjimr.org';

    private static User thisUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static void seedConfig(Boolean active) {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = TEST_KEY,
            Impersonated_User__c = 'finessedirect@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = active
        );
    }

    /** Mock: token for the token endpoint; one fresh faculty-created event for the GET. */
    private class Mock implements HttpCalloutMock {
        /**
         * @description Returns the token or a single ingestible event depending on endpoint.
         * @param req The inbound HTTP request being mocked.
         * @return The mock HTTP response.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":3600}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"items":[{"id":"evt_faculty_1","summary":"Faculty-created meeting",' +
                    '"status":"confirmed","organizer":{"email":"' + FACULTY_EMAIL + '"},' +
                    '"attendees":[{"email":"stud@spjimr.org"}],' +
                    '"start":{"dateTime":"2026-08-01T10:00:00+05:30"},' +
                    '"end":{"dateTime":"2026-08-01T11:00:00+05:30"}}]}');
            }
            return res;
        }
    }

    private static void addFaculty(String email) {
        Id facRt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        Account fac = new Account(LastName = 'Test Faculty', PersonEmail = email, RecordTypeId = facRt);
        insert fac;
        Session__c s = new Session__c(
            Schedule_Type__c = 'Scheduled',
            Start_Time__c = Datetime.now().addDays(1),
            End_Time__c = Datetime.now().addDays(1).addHours(1)
        );
        insert s;
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = fac.Id);
    }

    @IsTest
    static void watchedCalendarsReturnsFacultyEmails() {
        System.runAs(thisUser()) {
            addFaculty(FACULTY_EMAIL);
            Set<String> cals = new GoogleCalendarInboundSchedulable().watchedCalendars();
            System.assert(cals.contains(FACULTY_EMAIL), 'Faculty email should be in the watch list');
        }
    }

    @IsTest
    static void facultyPollIngestsCreatedEvent() {
        System.runAs(thisUser()) {
            addFaculty(FACULTY_EMAIL);
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock());
            Test.startTest();
            new GoogleCalendarInboundSchedulable().execute(null);
            Test.stopTest();

            Calendar_Meeting__c m = [
                SELECT Subject__c, Source__c, Google_Event_Id__c
                FROM Calendar_Meeting__c WHERE Google_Event_Id__c = 'evt_faculty_1'
            ];
            System.assertEquals('Google', m.Source__c, 'Ingested faculty event is Google-sourced');
            System.assertEquals('Faculty-created meeting', m.Subject__c, 'Event summary maps to Subject__c');
        }
    }

    @IsTest
    static void inactiveConfigDoesNotPoll() {
        System.runAs(thisUser()) {
            addFaculty(FACULTY_EMAIL);
            seedConfig(false);
            Test.setMock(HttpCalloutMock.class, new Mock());
            Test.startTest();
            new GoogleCalendarInboundSchedulable().execute(null);
            Test.stopTest();
            System.assertEquals(0, [SELECT COUNT() FROM Calendar_Meeting__c WHERE Google_Event_Id__c = 'evt_faculty_1'],
                'Inactive config must not poll or ingest');
        }
    }

    @IsTest
    static void queueableEmptyCalendarsIsNoop() {
        System.runAs(thisUser()) {
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock());
            Test.startTest();
            System.enqueueJob(new GoogleCalendarInboundQueueable(new Set<String>(), null));
            Test.stopTest();
            System.assertEquals(0, [SELECT COUNT() FROM Calendar_Meeting__c WHERE Google_Event_Id__c = 'evt_faculty_1'],
                'Empty calendar set should be a no-op');
        }
    }

    @IsTest
    static void queueableIngestsForCalendar() {
        System.runAs(thisUser()) {
            seedConfig(true);
            Test.setMock(HttpCalloutMock.class, new Mock());
            Test.startTest();
            System.enqueueJob(new GoogleCalendarInboundQueueable(new Set<String>{ FACULTY_EMAIL }, Datetime.now().addHours(-24)));
            Test.stopTest();
            System.assertEquals(1, [SELECT COUNT() FROM Calendar_Meeting__c WHERE Google_Event_Id__c = 'evt_faculty_1'],
                'Queueable should ingest the faculty event for the given calendar');
        }
    }
}