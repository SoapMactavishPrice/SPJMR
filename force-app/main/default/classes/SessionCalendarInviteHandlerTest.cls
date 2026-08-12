@IsTest
private class SessionCalendarInviteHandlerTest {

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

    private static List<String> capturedEndpoints = new List<String>();
    private static List<String> capturedBodies = new List<String>();

    private static Boolean sawEventCalloutWith(String fragment) {
        for (String endpoint : capturedEndpoints) {
            if (endpoint.contains('/calendar/v3/') && endpoint.contains(fragment)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean sawEventBodyWith(String fragment) {
        if (String.isBlank(fragment)) {
            return false;
        }
        String needle = fragment.toLowerCase();
        for (String body : capturedBodies) {
            if (String.isNotBlank(body) && body.toLowerCase().contains(needle)) {
                return true;
            }
        }
        return false;
    }

    /** True if any calendar create/update body has a non-empty attendees array. */
    private static Boolean sawNonEmptyAttendeesInBody() {
        for (String body : capturedBodies) {
            if (String.isBlank(body) || !body.contains('attendees')) {
                continue;
            }
            // Empty list looks like "attendees":[] (optional spaces)
            if (body.contains('"attendees":[]') || body.contains('"attendees": []')) {
                continue;
            }
            if (body.contains('"email"')) {
                return true;
            }
        }
        return false;
    }

    private class Mock implements HttpCalloutMock {

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            capturedEndpoints.add(req.getEndpoint());
            if (String.isNotBlank(req.getBody())
                    && req.getEndpoint() != null
                    && req.getEndpoint().contains('/calendar/v3/')) {
                capturedBodies.add(req.getBody());
            }
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

    @IsTest
    static void createStoresEventIdAndSynced() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;
            addFaculty(s.Id, 'fac1@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Draft';
            update s;
            Test.stopTest();

            Session__c after = [SELECT Google_Event_Id__c, Calendar_Sync_Status__c,
                                       Calendar_Last_Synced__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('evt_123', after.Google_Event_Id__c, 'event id should be written back');
            System.assertEquals('Synced', after.Calendar_Sync_Status__c);
            System.assertNotEquals(null, after.Calendar_Last_Synced__c);
        }
    }

    @IsTest
    static void updatePatchesExistingEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', 'pre_existing_evt');
            insert s;
            addFaculty(s.Id, 'fac2@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Draft';
            update s;
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Synced', after.Calendar_Sync_Status__c);
        }
    }

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

    @IsTest
    static void cancelOnDeleteDeletesEvent() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', 'evt_on_delete');
            insert s;
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            delete s;
            Test.stopTest();

            System.assertEquals(0, [SELECT COUNT() FROM Session__c WHERE Id = :s.Id],
                'session should be deleted; cancel callout runs without write-back');
        }
    }

    @IsTest
    static void skipNoAttendeesMarksFailed() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Test.startTest();
            s.Schedule_Type__c = 'Draft';
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

    @IsTest
    static void inactiveConfigDoesNotSync() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;
            addFaculty(s.Id, 'fac@example.com');
            Test.setMock(HttpCalloutMock.class, new Mock());
            GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
                Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
                Private_Key__c       = TEST_KEY,
                Impersonated_User__c = 'finessedirect@spjimr.org',
                Calendar_Id__c       = 'primary',
                Active__c            = false
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

    @IsTest
    static void noOpAndSuppressGuard() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Complete', null);
            insert s;
            seedConfig();

            Test.startTest();

            SessionCalendarInviteHandler.suppressInvites = true;
            SessionCalendarInviteHandler.handleSessionCalendarInvites(
                new Map<Id, Session__c>{ s.Id => s }, null);
            SessionCalendarInviteHandler.suppressInvites = false;
            Test.stopTest();

            System.assertEquals('Complete',
                [SELECT Schedule_Type__c FROM Session__c WHERE Id = :s.Id].Schedule_Type__c);
        }
    }

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
                new Set<Id>(), new Set<Id>{ s.Id }));
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c, Calendar_Sync_Error__c
                                FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Failed', after.Calendar_Sync_Status__c,
                'A non-success Calendar API response must mark the session Failed');
            System.assertNotEquals(null, after.Calendar_Sync_Error__c,
                'The failure reason should be captured for visibility / retry');
        }
    }

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

    @IsTest
    static void skipUserNotificationsStillSyncsButSuppressesEmails() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = newSession('Scheduled', null);
            insert s;
            addFaculty(s.Id, 'facSkip@example.com');
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());
            capturedEndpoints.clear();

            Test.startTest();
            SessionCalendarInviteHandler.skipUserNotifications = true;
            s.Schedule_Type__c = 'Draft';
            update s;
            SessionCalendarInviteHandler.skipUserNotifications = false;
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c, Google_Event_Id__c
                                FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Synced', after.Calendar_Sync_Status__c,
                'Choosing "No" must still create the Google Calendar event.');
            System.assertNotEquals(null, after.Google_Event_Id__c,
                'The event id must be stamped even when notifications are suppressed.');
            System.assert(sawEventCalloutWith('sendUpdates=none'),
                'The callout must use sendUpdates=none so Google emails nobody.');
            System.assert(!sawEventCalloutWith('sendUpdates=all'),
                'No callout may use sendUpdates=all when the user chose "No".');
            // EXPECTATION CHANGED (calendar notification ticket). This previously asserted that a
            // suppressed create must NOT attach faculty, an abandoned workaround that tried to make
            // faculty "new guests" at publish time so Google would email them.
            //
            // The agreed requirement is the opposite: creating with "No" must put the event on the
            // faculty member's calendar with no email (so they can see it), and publishing with
            // "Yes" must then send them an *Updated* invitation. Both require faculty to be guests
            // from the Draft push onwards. Silence is achieved by sendUpdates=none (asserted
            // above), not by withholding guests.
            System.assertEquals(true, sawNonEmptyAttendeesInBody(),
                'Creating with "No" must still attach faculty as guests so the event lands on their '
                + 'calendar; only the email is suppressed. BODIES=' + String.join(capturedBodies, ' || '));
        }
    }

    /**
     * Ticket path: silent Draft event already exists (no guests / no mail).
     * Notify=Yes (publish audience) must send faculty in the payload with sendUpdates=all.
     * Guests-omitted-on-No is covered by skipUserNotificationsStillSyncsButSuppressesEmails.
     */
    @IsTest
    static void draftNoThenPublishYesIncludesFacultyAndSendsAll() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = newSession('Draft', 'silent_evt_no_guests');
            s.Session_Date__c = Date.today().addDays(1);
            SessionCalendarInviteHandler.suppressInvites = true;
            insert s;
            SessionCalendarInviteHandler.suppressInvites = false;
            addFaculty(s.Id, 'facNoThenYes@example.com');

            capturedEndpoints.clear();
            capturedBodies.clear();

            Test.startTest();
            // Simulate publish+Yes: full audience, notifications not suppressed
            System.enqueueJob(new SessionCalendarInviteQueueable(
                new Set<Id>{ s.Id },
                new Set<Id>(),
                null,
                false
            ));
            Test.stopTest();

            Session__c after = [
                SELECT Calendar_Sync_Status__c, Google_Event_Id__c
                FROM Session__c WHERE Id = :s.Id
            ];
            System.assertEquals('Synced', after.Calendar_Sync_Status__c,
                'Notify=Yes after silent Draft must re-sync successfully.');
            System.assert(sawEventCalloutWith('sendUpdates=all'),
                'Notify=Yes must use sendUpdates=all so invite emails go out.');
            System.assert(sawEventBodyWith('facNoThenYes@example.com'),
                'Notify=Yes must attach faculty so Google can email them as new guests. Bodies='
                + String.join(capturedBodies, ' || '));
        }
    }

    @IsTest
    static void publishSessionsWithSendNotificationsFalseStillSyncs() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = newSession('Draft', null);
            s.Session_Date__c = Date.today().addDays(1);
            SessionCalendarInviteHandler.suppressInvites = true;
            insert s;
            SessionCalendarInviteHandler.suppressInvites = false;
            addFaculty(s.Id, 'facPublishNo@example.com');

            TimetableSessionController.SessionFilter filter = new TimetableSessionController.SessionFilter();
            filter.startDate = Date.today();
            filter.endDate = Date.today().addDays(2);
            filter.sendNotifications = false;
            capturedEndpoints.clear();

            Test.startTest();
            TimetableSessionController.publishSessions(JSON.serialize(filter));
            Test.stopTest();

            Session__c after = [SELECT Schedule_Type__c, Calendar_Sync_Status__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Published', after.Schedule_Type__c,
                'The session must be published.');
            System.assertEquals('Synced', after.Calendar_Sync_Status__c,
                'sendNotifications=false must still sync the event to Google Calendar.');
            System.assert(sawEventCalloutWith('sendUpdates=none'),
                'Publishing with sendNotifications=false must use sendUpdates=none.');
            System.assertEquals(false, SessionCalendarInviteHandler.skipUserNotifications,
                'The guard flag must be reset once the publish DML completes.');
        }
    }

    /**
     * @description Publishing now ALWAYS suppresses the per-session Google emails, whatever the
     *          modal answer was: Google sends one invitation per event, so a multi-session publish
     *          flooded every student. The Yes answer is served instead by the single consolidated
     *          email from SessionPublishSummaryEmailQueueable, covered in
     *          SessionPublishSummaryEmailTest. The event itself must still sync.
     */
    @IsTest
    static void publishSessionsDefaultSyncsSilently() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());
            // Default (no answer) counts as Yes, so publishing enqueues the consolidated summary
            // email. That job insists on a verified org-wide sender, which no test run has, so the
            // requirement is switched off here — this test is about the calendar callout, and the
            // sender rule itself is asserted in SessionPublishSummaryEmailTest.
            SessionPublishSummaryEmailQueueable.requireVerifiedSender = false;

            Session__c s = newSession('Draft', null);
            s.Session_Date__c = Date.today().addDays(1);
            SessionCalendarInviteHandler.suppressInvites = true;
            insert s;
            SessionCalendarInviteHandler.suppressInvites = false;
            addFaculty(s.Id, 'facPublishYes@example.com');

            TimetableSessionController.SessionFilter filter = new TimetableSessionController.SessionFilter();
            filter.startDate = Date.today();
            filter.endDate = Date.today().addDays(2);

            capturedEndpoints.clear();

            Test.startTest();
            TimetableSessionController.publishSessions(JSON.serialize(filter));
            Test.stopTest();

            Session__c after = [SELECT Calendar_Sync_Status__c FROM Session__c WHERE Id = :s.Id];
            System.assertEquals('Synced', after.Calendar_Sync_Status__c,
                'Default (sendNotifications unset) must preserve existing publish-sync behavior.');
            System.assert(sawEventCalloutWith('sendUpdates=none'),
                'Publishing must always use sendUpdates=none: the per-session Google invitation '
                + 'emails are replaced by one consolidated summary email.');
            System.assert(!sawEventCalloutWith('sendUpdates=all'),
                'No publish callout may use sendUpdates=all, or students get one email per session.');
        }
    }

    /** @description Counts how many calendar event callouts (not token calls) were made. */
    private static Integer eventCalloutCount() {
        Integer n = 0;
        for (String endpoint : capturedEndpoints) {
            if (endpoint != null && endpoint.contains('/calendar/v3/')) {
                n++;
            }
        }
        return n;
    }

    /**
     * @description Counts only the calendar calls that CHANGE the event, i.e. one per logical
     *          push. A PATCH costs two calendar callouts, because GoogleCalendarService first
     *          GETs the event to preserve each existing guest's responseStatus, and only the
     *          mutating call carries a request body.
     * @return The number of POST/PATCH calls made to the Calendar API.
     */
    private static Integer mutatingEventCalloutCount() {
        return capturedBodies.size();
    }

    /**
     * @description Creates a session that is already synced to Google, without letting the
     *          insert itself fire a push.
     * @param status The Schedule_Type__c to give the session.
     * @param eventId The Google event id to pretend it already has.
     * @return The inserted session.
     */
    private static Session__c syncedSession(String status, String eventId) {
        Session__c s = newSession(status, eventId);
        s.Session_Date__c = Date.today().addDays(1);
        SessionCalendarInviteHandler.suppressInvites = true;
        insert s;
        SessionCalendarInviteHandler.suppressInvites = false;
        return s;
    }

    /**
     * @description Fix 1 — the publish PATCH must carry the schedule status in the event body.
     *          Without it the Draft -> Published PATCH is byte-identical for the faculty already
     *          on the event (their responseStatus is deliberately re-sent unchanged), so Google
     *          has no change to announce and they receive no "Updated invitation" at all.
     */
    @IsTest
    static void publishBodyCarriesPublishedStatusSoFacultyGetAnUpdate() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Published', 'evt_status_line');
            addFaculty(s.Id, 'facStatusLine@example.com');

            capturedEndpoints.clear();
            capturedBodies.clear();

            Test.startTest();
            System.enqueueJob(new SessionCalendarInviteQueueable(
                new Set<Id>{ s.Id }, new Set<Id>(), null, false
            ));
            Test.stopTest();

            System.assert(sawEventBodyWith('Status: Published'),
                'The publish PATCH body must contain the schedule status, otherwise the PATCH is '
                + 'a no-op for existing faculty guests and Google emails nobody. Bodies='
                + String.join(capturedBodies, ' || '));
            System.assert(sawEventCalloutWith('evt_status_line'),
                'Publishing must PATCH the event created at Draft time, not create a second one — '
                + 'otherwise faculty receive a fresh "Invitation" instead of an "Updated '
                + 'invitation", and the student RSVPs already on the event are lost.');
            System.assert(sawEventCalloutWith('sendUpdates=all'),
                'Publishing with "Yes" must ask Google to notify the guests.');
            System.assert(sawEventBodyWith('facStatusLine@example.com'),
                'Faculty must remain a guest so Google has someone to send the update to.');
        }
    }

    /** @description The Draft push must carry the Draft status, so publishing is a real diff. */
    @IsTest
    static void draftBodyCarriesDraftStatus() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Draft', 'evt_draft_status');
            addFaculty(s.Id, 'facDraftStatus@example.com');

            capturedEndpoints.clear();
            capturedBodies.clear();

            Test.startTest();
            System.enqueueJob(new SessionCalendarInviteQueueable(
                new Set<Id>(), new Set<Id>{ s.Id }, null, true
            ));
            Test.stopTest();

            System.assert(sawEventBodyWith('Status: Draft'),
                'The Draft push must record Draft, so the later Published PATCH is a real change. '
                + 'Bodies=' + String.join(capturedBodies, ' || '));
        }
    }

    /**
     * @description Fix 2a — a Name-only edit on an already-Republished session must re-push.
     *          Republished -> Republished does not change the status, so before the widening this
     *          fell through to a 9-field comparison that excluded Name and sent nothing, even
     *          though Name is part of the Google event summary.
     */
    @IsTest
    static void nameOnlyEditOnRepublishedSessionRePushes() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Republished', 'evt_name_edit');
            addFaculty(s.Id, 'facNameEdit@example.com');

            capturedEndpoints.clear();
            capturedBodies.clear();

            Test.startTest();
            s.Name = 'Renamed Session For Calendar';
            update s;
            Test.stopTest();

            System.assert(eventCalloutCount() > 0,
                'Renaming a Republished session must re-push the Google event; the session name '
                + 'appears in the event summary.');
        }
    }

    /**
     * @description Fix 2a — an academic-context edit (Is_Joint_Session__c) on an already
     *          Republished session must also re-push rather than being silently ignored.
     */
    @IsTest
    static void contextOnlyEditOnRepublishedSessionRePushes() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Republished', 'evt_context_edit');
            addFaculty(s.Id, 'facContextEdit@example.com');

            capturedEndpoints.clear();

            Test.startTest();
            s.Is_Joint_Session__c = true;
            update s;
            Test.stopTest();

            System.assert(eventCalloutCount() > 0,
                'An academic-context edit on a Republished session must re-push the event.');
        }
    }

    /**
     * @description Fix 2b — a related-record change on a synced, published session patches it.
     */
    @IsTest
    static void relatedRecordChangePatchesSyncedSession() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Published', 'evt_related_ok');
            addFaculty(s.Id, 'facRelated@example.com');

            capturedEndpoints.clear();

            Test.startTest();
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ s.Id });
            Test.stopTest();

            System.assert(eventCalloutCount() > 0,
                'A division/faculty/enrolment change on a synced session must patch the event.');
        }
    }

    /**
     * @description Fix 2b — the related-record path is PATCH-only: a session that was never
     *          pushed to Google must be skipped, never created. Otherwise adding a division or a
     *          faculty member could publish an unsynced session as a side effect.
     */
    @IsTest
    static void relatedRecordChangeSkipsUnsyncedSession() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Published', null);
            addFaculty(s.Id, 'facUnsynced@example.com');

            capturedEndpoints.clear();

            Test.startTest();
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ s.Id });
            Test.stopTest();

            System.assertEquals(0, eventCalloutCount(),
                'A session with no Google_Event_Id__c must not be created from the related-record '
                + 'path; that path may only update an event that already exists.');
        }
    }

    /**
     * @description Fix 2b — a Cancelled session must not be resurrected by the cascade delete of
     *          its own enrolments, which fires the related-record path in the same transaction.
     */
    @IsTest
    static void relatedRecordChangeSkipsCancelledSession() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Cancelled', 'evt_cancelled_related');
            addFaculty(s.Id, 'facCancelledRelated@example.com');

            capturedEndpoints.clear();

            Test.startTest();
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ s.Id });
            Test.stopTest();

            System.assertEquals(0, eventCalloutCount(),
                'Cancelling deletes the enrolments, which fires this path. A Cancelled session '
                + 'must not be re-pushed.');
        }
    }

    /**
     * @description Fix 2b — the trigger-friendly overload collects parent ids off related rows.
     */
    @IsTest
    static void relatedRecordOverloadCollectsParentIds() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Published', 'evt_overload');
            addFaculty(s.Id, 'facOverload@example.com');

            capturedEndpoints.clear();

            Test.startTest();
            // In-memory rows only: the overload just reads the lookup, no DML needed.
            SessionCalendarInviteHandler.handleRelatedRecordChange(
                new List<Session_Division__c>{ new Session_Division__c(Session__c = s.Id) },
                'Session__c'
            );
            Test.stopTest();

            System.assert(eventCalloutCount() > 0,
                'The List<SObject> overload must resolve the parent session and push it.');
        }
    }

    /** @description The overload must no-op safely on null/empty input and a blank field name. */
    @IsTest
    static void relatedRecordOverloadHandlesEmptyInput() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());
            capturedEndpoints.clear();

            Test.startTest();
            SessionCalendarInviteHandler.handleRelatedRecordChange(null, 'Session__c');
            SessionCalendarInviteHandler.handleRelatedRecordChange(new List<Session_Division__c>(), 'Session__c');
            SessionCalendarInviteHandler.handleRelatedRecordChange(
                new List<Session_Division__c>{ new Session_Division__c() }, ''
            );
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>());
            Test.stopTest();

            System.assertEquals(0, eventCalloutCount(),
                'Empty related-record input must not produce any calendar callout.');
        }
    }

    /**
     * @description Fix 2b dedupe — one user action can touch the session AND its related records
     *          in a single transaction (removing a division stamps the session Republished and
     *          deletes Session_Division__c rows). Without the transaction guard that enqueued two
     *          PATCHes and guests received two "Updated invitation" emails for one click.
     */
    @IsTest
    static void repeatedPushInOneTransactionIsDeduped() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            seedConfig();
            Test.setMock(HttpCalloutMock.class, new Mock());

            Session__c s = syncedSession('Published', 'evt_dedupe');
            addFaculty(s.Id, 'facDedupe@example.com');

            capturedEndpoints.clear();

            capturedBodies.clear();

            Test.startTest();
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ s.Id });
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ s.Id });
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ s.Id });
            Test.stopTest();

            System.assertEquals(1, mutatingEventCalloutCount(),
                'Three pushes for the same session in one transaction must collapse to a single '
                + 'PATCH, so the guests get exactly one email instead of three.');
        }
    }
}