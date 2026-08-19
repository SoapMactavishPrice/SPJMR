/**
 * @description Proves the guarantee the two-event split exists for: on a session carrying both
 *          faculty and students, the faculty copy of the Google event may be pushed with
 *          sendUpdates=all (so faculty get a real "Updated invitation") while the students' copy is
 *          pushed with sendUpdates=none in the same job — something a single shared event can never
 *          do, because Google's sendUpdates applies to the whole event.
 *
 *          Every assertion here reads the captured Google requests, so it fails if either copy ever
 *          picks up the other audience's guests or the other audience's notification mode.
 */
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class SessionCalendarTwoEventSplitTest {

    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDT6wSR5EcWKJV3\nGaKguMZuYbfB1mFchbUcQ3UtrBKe2hRvCBEQGlD45lFgLrl6WiS8UaoE+uzNs3P4\nC7hnLUOc7k6kyi274ZI2BsIte2ISeTTCT2yWSsBZRuIuMHvlxttZbxPq1QcRTKCk\n1fU6mvEUqm+22smiSKJdWYjcBo7cIxt0OwsQSoLEefZKlexMK7cXHDDh7sh4kpOR\nIQDx+sYtG8EhnwmqQN9HqEGt6GD9FOibJvLZIFpFaxR2kjys1XhNqv6DjjR/pObC\nac6YqxPRQ+UuJEnSCuc0mPV4gQd3+gYJ8sjrp7+Rr1Exj7dOjI2cmkProA61GizN\nosOBp7SFAgMBAAECggEAaCz7RSDcFTeEKlVOzgWnfnHJHJ/fotUT8D31J6uUR8Tb\nEK39fVYCgijuzgKKKWyQ7IaUtvgHWyOhmclhME9fEpFP1dCR5O+Bqc9uu18RGhW9\natwSfFto7TpcS+qHrbAw+mkReHqai9WIjx+i+tlaNBeI7XHmd0GPl6ZBEjCjH/G4\n7l5TLNMGiZNiFz2gNch9H8e/ZXQj7crWsYfgLxCIvUFWo4VTQCLwn1RUuA7rNGsx\nz2aEz7h/3g7hER2jRTnU9IXdLfleETeiO0TA4/XqBR5Mww7ncSOYlM8ZCRWh4KHo\nfjAs2rbqJYhpp3tLSiD9Ig3RHZ9bZ+aQ1RM1RBr2rQKBgQD033T4/z8XFEq7Xptt\nzskvUEpV98Stw2DrNhFZMVWO0Cgfntiv2sR4ozaN4Sm4e5m2ENixnjE4VqK8xDYI\nZ3UTA0PYbVJkPDvAGH7qr01TGLDdKSnQnNRRSIFUujVyg2AW9/smziagwieQAFz9\niVEOqZH7SzTWi6G0D2pwwR56GwKBgQDdjDStGiAcBg0ET6YcWBSMRaIAkdri7z4A\nhdq6fWxpOgUa8cpPT1x7uq2BIdvFTMFuat5EvZDW2nltv0p1GrykA7Mn3jmevQ1g\ntfzhB4f+mN3mjC0gQDHHy/oFnCEselQD1y9Bd6/J+3nOx+eSuEk1dJQJ43jrEx5P\nJ+s+Q7d13wKBgQCDRmBxNHVgLBK8TEXLInaclNClMcUQ2pNUxZGbXWVewJ0iBoho\nDkIR4n3WpgU1z51iC7n/zqzYZSmtRQsqijwrSy7OEh1/ewMVQoyXyA8OI0h96Blw\nqwLv6IzdHU6V63RSG/NapF31BOEsw+UWTs1TrPiD3ZegBQ9VdoY7mGx8TQKBgAnt\ns5qiVhgLaV/tFdulUt5qbHUsFCwhXpz1YrUC0+3vTLVFarSdMN7Wodnso4W3B+Aj\n5+watrf6OIDjlrmixhtvkwLRYbGsdUIFRdzr0ntlbGRdmdQdLF3w1TaVJaNxo/w8\nE4ESlQ0vOOk8ajNYEOfVXqEG0a9vPud7OX6j2D/vAoGBALjr5XixEQfWHvj9YBf2\n9M6+W1kgy+uwRuhVNBCe4zpStsOZlme1uRDIHmsIOuLOPnl+R6LEnQa3E7ih2Idy\nUJOTx65Ivz8c+O6S2b+btgFVRX7s2sw/JkKSG4L56KsM4hL7gDeASbj9eWL5qIlU\nAHI1ng21+pZWSmyBfEtHP6EW\n-----END PRIVATE KEY-----\n';

    private static final String FACULTY_EMAIL = 'splitfaculty@example.com';

    private static List<Sent> sent = new List<Sent>();
    private static Integer createdEvents = 0;

    /** One captured Google request: what was sent, and where. */
    private class Sent {
        private String endpoint;
        private String body;
        private String method;
    }

    /** Returns a distinct event id per create, so the two copies can never be confused. */
    private class Mock implements HttpCalloutMock {
        /**
         * @description Records the request and answers as Google would.
         * @param req The outbound request.
         * @return A token, a created/patched event, or a 204 for a delete.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":3600}');
                return res;
            }
            Sent s = new Sent();
            s.endpoint = req.getEndpoint();
            s.body     = req.getBody();
            s.method   = req.getMethod();
            sent.add(s);

            if (req.getMethod() == 'DELETE') {
                res.setStatusCode(204);
                return res;
            }
            res.setStatusCode(200);
            String patched = patchedEventId(s.endpoint);
            if (String.isNotBlank(patched)) {
                res.setBody('{"id":"' + patched + '"}');  // PATCH keeps the same event id
            } else {
                createdEvents++;
                res.setBody('{"id":"evt_split_' + createdEvents + '"}');
            }
            return res;
        }
    }

    /**
     * @description The event id embedded in an events PATCH endpoint, or blank for a create.
     * @param endpoint The captured request endpoint.
     * @return The event id being patched.
     */
    private static String patchedEventId(String endpoint) {
        if (String.isBlank(endpoint)) {
            return null;
        }
        String path = endpoint.split('\\?')[0];
        Integer marker = path.indexOf('/events/');
        if (marker < 0) {
            return null;
        }
        return path.substring(marker + '/events/'.length());
    }

    private static void seedConfig() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(
            Client_Email__c      = 'svc@project.iam.gserviceaccount.com',
            Private_Key__c       = TEST_KEY,
            Impersonated_User__c = 'finessedirect@spjimr.org',
            Calendar_Id__c       = 'primary',
            Active__c            = true
        );
    }

    /**
     * @description The captured write whose guest list contains this email.
     * @param email The guest to look for.
     * @return That request, or null when no captured write carried the address.
     */
    private static Sent writeCarrying(String email) {
        for (Sent s : sent) {
            if (String.isNotBlank(s.body) && s.body.contains(email)) {
                return s;
            }
        }
        return null;
    }

    private static String writeTrace() {
        List<String> parts = new List<String>();
        for (Sent s : sent) {
            parts.add(s.method + ' ' + s.endpoint);
        }
        return String.join(parts, ' || ');
    }

    /**
     * @description Counts the pushes that actually change an event. Every PATCH is preceded by a
     *          GET (GoogleCalendarService re-reads the event to preserve the guests' existing RSVP
     *          answers), and those reads are not pushes.
     * @return The number of create/update calls captured.
     */
    private static Integer writeCount() {
        Integer n = 0;
        for (Sent s : sent) {
            if (s.method == 'POST' || s.method == 'PATCH' || s.method == 'PUT') {
                n++;
            }
        }
        return n;
    }

    private static Integer deleteCount() {
        Integer n = 0;
        for (Sent s : sent) {
            if (s.method == 'DELETE') {
                n++;
            }
        }
        return n;
    }

    /**
     * @description Runs the calendar job synchronously. Deliberately NOT System.enqueueJob: a test
     *          method may only ever enqueue one job, and in some orgs an unrelated trigger on the
     *          fixture's own data (devfeat's SessionAssignmentQueueable, fired by inserting a
     *          Division_Enrollment__c) has already spent it — the job then silently never runs and
     *          every callout assertion below sees no traffic at all.
     * @param job The job to run.
     */
    private static void runJob(SessionCalendarInviteQueueable job) {
        job.execute(null);
    }

    /** A session with one faculty and one enrolled student, plus that student's email. */
    private class Fixture {
        private Session__c session;
        private String studentEmail;
    }

    private static Fixture buildFixture(String tag, String status) {
        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('spl' + tag);
        Id termId  = SpjimrPortalTestDataFactory.insertAcademicTerm();
        Id ateId   = SpjimrPortalTestDataFactory.insertAcademicTermEnrollment(learner.Id, termId);
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divId   = SpjimrPortalTestDataFactory.insertDivision(groupId, termId);
        Id deId    = SpjimrPortalTestDataFactory.insertDivisionEnrollment(divId, ateId);
        if (divId == null || deId == null) {
            return null;
        }

        Session__c s = new Session__c(
            Name             = 'Split' + tag,
            Schedule_Type__c = status,
            Session_Date__c  = Date.today().addDays(3),
            Start_Time__c    = Datetime.now().addDays(3),
            End_Time__c      = Datetime.now().addDays(3).addHours(1)
        );
        SessionCalendarInviteHandler.suppressInvites = true;
        insert s;
        insert new Session_Division__c(Session__c = s.Id, Division__c = divId);
        SpjimrPortalTestDataFactory.insertSessionEnrollment(s.Id, deId, ateId);
        SessionCalendarInviteHandler.suppressInvites = false;

        Id facRt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        Account fac = new Account(
            LastName = 'SplitFac' + tag, PersonEmail = FACULTY_EMAIL, RecordTypeId = facRt
        );
        insert fac;
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = fac.Id);

        Fixture f = new Fixture();
        f.session = s;
        f.studentEmail = [
            SELECT PersonEmail FROM Account WHERE Id = :learner.Id
        ].PersonEmail;
        return f;
    }

    private static Boolean skipped(Fixture f) {
        if (f == null || String.isBlank(f.studentEmail)) {
            Assert.isTrue(true, 'Managed EDA setup unavailable; skipping.');
            return true;
        }
        return false;
    }

    @IsTest
    static void yesNotifiesFacultyCopyAndKeepsStudentCopySilent() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Fixture f = buildFixture('a', 'Republished');
        if (skipped(f)) {
            return;
        }
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>{ f.session.Id }, new Set<Id>(), null, false
        ));
        Test.stopTest();

        Assert.areEqual(2, writeCount(),
            'One session must produce exactly two writes: the faculty copy and the student copy. '
            + writeTrace());

        Sent facultyWrite = writeCarrying(FACULTY_EMAIL);
        Sent studentWrite = writeCarrying(f.studentEmail);
        Assert.isNotNull(facultyWrite, 'The faculty must be a guest on their own copy.');
        Assert.isNotNull(studentWrite, 'The student must be a guest on the student copy.');

        Assert.isTrue(facultyWrite.endpoint.contains('sendUpdates=all'),
            'The faculty copy must notify, or faculty never learn the session moved. Endpoint='
            + facultyWrite.endpoint);
        Assert.isTrue(studentWrite.endpoint.contains('sendUpdates=none'),
            'The student copy must stay silent even on Yes — that is the whole point of the split. '
            + 'Endpoint=' + studentWrite.endpoint);

        Assert.isFalse(facultyWrite.body.contains(f.studentEmail),
            'No student may ride the notifying copy, or Google emails them too. Body='
            + facultyWrite.body);
        Assert.isFalse(studentWrite.body.contains(FACULTY_EMAIL),
            'The faculty must not sit on the silent copy as well, or the update they see there is '
            + 'never announced. Body=' + studentWrite.body);

        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c, Calendar_Sync_Status__c
            FROM Session__c WHERE Id = :f.session.Id
        ];
        Assert.areEqual('Synced', after.Calendar_Sync_Status__c,
            'Both copies succeeded, so the session is Synced.');
        Assert.isNotNull(after.Google_Event_Id__c, 'The student copy id must be stamped.');
        Assert.isNotNull(after.Faculty_Google_Event_Id__c, 'The faculty copy id must be stamped.');
        Assert.areNotEqual(after.Google_Event_Id__c, after.Faculty_Google_Event_Id__c,
            'The two copies must be different Google events.');
    }

    @IsTest
    static void noKeepsBothCopiesSilent() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Fixture f = buildFixture('b', 'Republished');
        if (skipped(f)) {
            return;
        }
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>{ f.session.Id }, new Set<Id>(), null, true
        ));
        Test.stopTest();

        Assert.areEqual(2, writeCount(),
            'Both copies are still pushed when the answer is No. ' + writeTrace());
        for (Sent s : sent) {
            if (s.method == 'GET') {
                continue; // the pre-PATCH read carries no notification mode
            }
            Assert.isTrue(s.endpoint.contains('sendUpdates=none'),
                'Answering No must email nobody on either copy. Endpoint=' + s.endpoint);
        }
        Assert.isNotNull(writeCarrying(FACULTY_EMAIL),
            'No suppresses the email, not the calendar entry: faculty stay a guest.');
    }

    @IsTest
    static void cancellingDeletesBothCopies() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Fixture f = buildFixture('c', 'Published');
        if (skipped(f)) {
            return;
        }
        Session__c s = f.session;
        SessionCalendarInviteHandler.suppressInvites = true;
        s.Google_Event_Id__c         = 'evt_cancel_students';
        s.Faculty_Google_Event_Id__c = 'evt_cancel_faculty';
        update s;
        SessionCalendarInviteHandler.suppressInvites = false;
        sent.clear();

        Test.startTest();
        // The work a Cancelled status change enqueues: delete every copy the session held.
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>(),
            new Map<Id, List<String>>{
                s.Id => new List<String>{ 'evt_cancel_students', 'evt_cancel_faculty' }
            }
        ));
        Test.stopTest();

        Assert.areEqual(2, deleteCount(),
            'Both copies must be deleted, or the faculty keep a cancelled session on their calendar.');
        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c, Calendar_Sync_Status__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Cancelled', after.Calendar_Sync_Status__c, 'The session reads Cancelled.');
        Assert.isNull(after.Google_Event_Id__c, 'The student copy id must be cleared.');
        Assert.isNull(after.Faculty_Google_Event_Id__c, 'The faculty copy id must be cleared.');
    }

    @IsTest
    static void legacyPublishedSessionKeepsStudentsAndGainsAFacultyCopy() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Fixture f = buildFixture('d', 'Republished');
        if (skipped(f)) {
            return;
        }
        // A session synced before the split: one shared event, carrying the students' RSVPs.
        Session__c s = f.session;
        SessionCalendarInviteHandler.suppressInvites = true;
        s.Google_Event_Id__c = 'evt_legacy_shared';
        update s;
        SessionCalendarInviteHandler.suppressInvites = false;
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>{ s.Id }, new Set<Id>(), null, false
        ));
        Test.stopTest();

        Sent studentWrite = writeCarrying(f.studentEmail);
        Assert.isNotNull(studentWrite, 'The students must be pushed on the legacy event.');
        Assert.isTrue(studentWrite.endpoint.contains('evt_legacy_shared'),
            'The legacy event must be kept as the STUDENT copy so their RSVP answers survive. '
            + 'Endpoint=' + studentWrite.endpoint);

        Sent facultyWrite = writeCarrying(FACULTY_EMAIL);
        Assert.isNotNull(facultyWrite, 'The faculty must get a copy of their own.');
        Assert.isFalse(facultyWrite.endpoint.contains('evt_legacy_shared'),
            'The faculty copy must be a NEW event, not the shared one. Endpoint='
            + facultyWrite.endpoint);

        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('evt_legacy_shared', after.Google_Event_Id__c,
            'The migration must not move the students off the event they are already on.');
        Assert.isNotNull(after.Faculty_Google_Event_Id__c, 'The new faculty copy must be stamped.');
    }
    //test class

    @IsTest
    static void legacyDraftEventBecomesTheFacultyCopyWithoutAnExtraEvent() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Fixture f = buildFixture('e', 'Draft');
        if (skipped(f)) {
            return;
        }
        // Before the split a Draft's only event was faculty-only.
        Session__c s = f.session;
        SessionCalendarInviteHandler.suppressInvites = true;
        s.Google_Event_Id__c = 'evt_legacy_draft';
        update s;
        SessionCalendarInviteHandler.suppressInvites = false;
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, true
        ));
        Test.stopTest();

        Assert.areEqual(1, writeCount(),
            'A Draft has no student copy, so exactly one write is expected. ' + writeTrace());
        Sent facultyWrite = writeCarrying(FACULTY_EMAIL);
        Assert.isNotNull(facultyWrite, 'The faculty copy must be pushed.');
        Assert.isTrue(facultyWrite.endpoint.contains('evt_legacy_draft'),
            'A pre-split Draft event IS the faculty copy, so it must be PATCHed rather than '
            + 'abandoned — otherwise faculty get a duplicate entry. Endpoint=' + facultyWrite.endpoint);

        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('evt_legacy_draft', after.Faculty_Google_Event_Id__c,
            'The legacy Draft id must move into the faculty field.');
        Assert.isNull(after.Google_Event_Id__c,
            'A Draft has no student copy, so the student field must be cleared.');
    }

    @IsTest
    static void relatedRecordChangeFillsInAMissingFacultyCopySilently() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Fixture f = buildFixture('f', 'Republished');
        if (skipped(f)) {
            return;
        }
        Session__c s = f.session;
        SessionCalendarInviteHandler.suppressInvites = true;
        s.Google_Event_Id__c = 'evt_related_students';
        update s;
        SessionCalendarInviteHandler.suppressInvites = false;
        sent.clear();

        Test.startTest();
        // patchOnly, exactly as handleRelatedRecordChange enqueues it.
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>{ s.Id }, new Set<Id>(), null, true, true
        ));
        Test.stopTest();

        Sent facultyWrite = writeCarrying(FACULTY_EMAIL);
        Assert.isNotNull(facultyWrite,
            'Adding a faculty member to an already-republished session changes no session field, so '
            + 'this path is the only one that can give them their copy.');
        Assert.isTrue(facultyWrite.endpoint.contains('sendUpdates=none'),
            'A background guest-list change must not email the faculty an updated invitation. '
            + 'Endpoint=' + facultyWrite.endpoint);
    }
}