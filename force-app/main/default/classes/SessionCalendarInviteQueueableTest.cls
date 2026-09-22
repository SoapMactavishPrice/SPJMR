/**
 * @description Guards the Term-level Programme Email on the Google Calendar push.
 *
 *          A session reaches a programme office two ways: the session header's own Term__c, and
 *          every Session_Division__c row's Division__r.Term__r. A session shared across programmes
 *          has several of the latter, and every one of those offices must ride the SAME faculty
 *          event — never a second calendar entry, never twice on one entry, and never on the
 *          student copy, which students read.
 *
 *          The two sources are deliberately NOT symmetrical. The header-term address is added
 *          unconditionally, as it always was, so an unstaffed session still reaches its own
 *          programme office. The division walk is new, so it may only ADD offices to a guest list
 *          that already has somebody on it — it must never be the sole reason an event exists for
 *          a session nobody is teaching, which would hide the missing teacher behind a Synced
 *          status.
 *
 *          Every assertion below reads the captured Google request bodies and counts the actual
 *          attendee entries, so it fails if an address is dropped, duplicated, blanked, or leaks to
 *          the wrong audience.
 */
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs,PMD.NcssCount,PMD.NcssTypeCount,PMD.NcssMethodCount,PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
@IsTest
private class SessionCalendarInviteQueueableTest {

    private static final String TEST_KEY =
        '-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDT6wSR5EcWKJV3\nGaKguMZuYbfB1mFchbUcQ3UtrBKe2hRvCBEQGlD45lFgLrl6WiS8UaoE+uzNs3P4\nC7hnLUOc7k6kyi274ZI2BsIte2ISeTTCT2yWSsBZRuIuMHvlxttZbxPq1QcRTKCk\n1fU6mvEUqm+22smiSKJdWYjcBo7cIxt0OwsQSoLEefZKlexMK7cXHDDh7sh4kpOR\nIQDx+sYtG8EhnwmqQN9HqEGt6GD9FOibJvLZIFpFaxR2kjys1XhNqv6DjjR/pObC\nac6YqxPRQ+UuJEnSCuc0mPV4gQd3+gYJ8sjrp7+Rr1Exj7dOjI2cmkProA61GizN\nosOBp7SFAgMBAAECggEAaCz7RSDcFTeEKlVOzgWnfnHJHJ/fotUT8D31J6uUR8Tb\nEK39fVYCgijuzgKKKWyQ7IaUtvgHWyOhmclhME9fEpFP1dCR5O+Bqc9uu18RGhW9\natwSfFto7TpcS+qHrbAw+mkReHqai9WIjx+i+tlaNBeI7XHmd0GPl6ZBEjCjH/G4\n7l5TLNMGiZNiFz2gNch9H8e/ZXQj7crWsYfgLxCIvUFWo4VTQCLwn1RUuA7rNGsx\nz2aEz7h/3g7hER2jRTnU9IXdLfleETeiO0TA4/XqBR5Mww7ncSOYlM8ZCRWh4KHo\nfjAs2rbqJYhpp3tLSiD9Ig3RHZ9bZ+aQ1RM1RBr2rQKBgQD033T4/z8XFEq7Xptt\nzskvUEpV98Stw2DrNhFZMVWO0Cgfntiv2sR4ozaN4Sm4e5m2ENixnjE4VqK8xDYI\nZ3UTA0PYbVJkPDvAGH7qr01TGLDdKSnQnNRRSIFUujVyg2AW9/smziagwieQAFz9\niVEOqZH7SzTWi6G0D2pwwR56GwKBgQDdjDStGiAcBg0ET6YcWBSMRaIAkdri7z4A\nhdq6fWxpOgUa8cpPT1x7uq2BIdvFTMFuat5EvZDW2nltv0p1GrykA7Mn3jmevQ1g\ntfzhB4f+mN3mjC0gQDHHy/oFnCEselQD1y9Bd6/J+3nOx+eSuEk1dJQJ43jrEx5P\nJ+s+Q7d13wKBgQCDRmBxNHVgLBK8TEXLInaclNClMcUQ2pNUxZGbXWVewJ0iBoho\nDkIR4n3WpgU1z51iC7n/zqzYZSmtRQsqijwrSy7OEh1/ewMVQoyXyA8OI0h96Blw\nqwLv6IzdHU6V63RSG/NapF31BOEsw+UWTs1TrPiD3ZegBQ9VdoY7mGx8TQKBgAnt\ns5qiVhgLaV/tFdulUt5qbHUsFCwhXpz1YrUC0+3vTLVFarSdMN7Wodnso4W3B+Aj\n5+watrf6OIDjlrmixhtvkwLRYbGsdUIFRdzr0ntlbGRdmdQdLF3w1TaVJaNxo/w8\nE4ESlQ0vOOk8ajNYEOfVXqEG0a9vPud7OX6j2D/vAoGBALjr5XixEQfWHvj9YBf2\n9M6+W1kgy+uwRuhVNBCe4zpStsOZlme1uRDIHmsIOuLOPnl+R6LEnQa3E7ih2Idy\nUJOTx65Ivz8c+O6S2b+btgFVRX7s2sw/JkKSG4L56KsM4hL7gDeASbj9eWL5qIlU\nAHI1ng21+pZWSmyBfEtHP6EW\n-----END PRIVATE KEY-----\n';

    private static final String FACULTY_EMAIL = 'progmailfaculty@example.com';
    private static final String PROG_EMAIL_A  = 'programme.office.a@example.com';
    private static final String PROG_EMAIL_B  = 'programme.office.b@example.com';

    private static List<Sent> sent = new List<Sent>();
    private static Integer createdEvents = 0;

    /** One captured Google request: what was sent, and where. */
    private class Sent {
        private String endpoint;
        private String body;
        private String method;
    }

    /** Returns a distinct event id per create, so a second event can never hide as the first. */
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
                res.setBody('{"id":"evt_prog_' + createdEvents + '"}');
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
     * @description Every push that actually writes an event. The GET that precedes each PATCH
     *          (GoogleCalendarService re-reads the event to preserve RSVP answers) is not a push.
     * @return The captured create/update requests, in order.
     */
    private static List<Sent> writes() {
        List<Sent> out = new List<Sent>();
        for (Sent s : sent) {
            if (s.method == 'POST' || s.method == 'PATCH' || s.method == 'PUT') {
                out.add(s);
            }
        }
        return out;
    }

    private static String writeTrace() {
        List<String> parts = new List<String>();
        for (Sent s : sent) {
            parts.add(s.method + ' ' + s.endpoint + ' guests=' + attendeesOf(s));
        }
        return String.join(parts, ' || ');
    }

    /**
     * @description The attendee addresses Google was actually asked to put on an event, read back
     *          out of the request body so duplicates and blanks are visible rather than collapsed.
     * @param s The captured request.
     * @return Every attendee email in the body, in order, including repeats.
     */
    private static List<String> attendeesOf(Sent s) {
        List<String> emails = new List<String>();
        if (s == null || String.isBlank(s.body)) {
            return emails;
        }
        Object parsed = JSON.deserializeUntyped(s.body);
        if (!(parsed instanceof Map<String, Object>)) {
            return emails;
        }
        Object raw = ((Map<String, Object>) parsed).get('attendees');
        if (!(raw instanceof List<Object>)) {
            return emails;
        }
        for (Object row : (List<Object>) raw) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }
            Object email = ((Map<String, Object>) row).get('email');
            emails.add(email == null ? null : String.valueOf(email));
        }
        return emails;
    }

    /**
     * @description How many times an address was handed to Google on one event.
     * @param emails The attendee list read back from the request.
     * @param target The address to count.
     * @return The number of entries equal to target, ignoring case.
     */
    private static Integer occurrences(List<String> emails, String target) {
        Integer n = 0;
        for (String e : emails) {
            if (e != null && e.equalsIgnoreCase(target)) {
                n++;
            }
        }
        return n;
    }

    /**
     * @description The write that carries a given guest.
     * @param email The guest to look for.
     * @return That request, or null when no captured write carried the address.
     */
    private static Sent writeCarrying(String email) {
        for (Sent s : writes()) {
            if (occurrences(attendeesOf(s), email) > 0) {
                return s;
            }
        }
        return null;
    }

    /**
     * @description Runs the calendar job synchronously. Deliberately NOT System.enqueueJob: a test
     *          method may only ever enqueue one job, and an unrelated trigger on the fixture's own
     *          data can already have spent it, leaving the assertions with no traffic to read.
     * @param job The job to run.
     */
    private static void runJob(SessionCalendarInviteQueueable job) {
        job.execute(null);
    }

    /**
     * @description An AcademicTerm carrying (or deliberately missing) a programme office address.
     * @param email The Programme_Email__c to stamp, or blank to leave the term without one.
     * @return The new term's id, or null when the managed term object is unavailable.
     */
    private static Id newTerm(String email) {
        Id termId = SpjimrPortalTestDataFactory.insertAcademicTerm();
        if (termId == null || String.isBlank(email)) {
            return termId;
        }
        update new AcademicTerm(Id = termId, Programme_Email__c = email);
        return termId;
    }

    /**
     * @description A division hung off a term. Term__c is a required lookup, so it is always set.
     * @param groupId The division group.
     * @param termId The term that owns the division and therefore its programme office.
     * @param divisionName The division's display name.
     * @return The new division's id.
     */
    private static Id newDivision(Id groupId, Id termId, String divisionName) {
        Division__c d = new Division__c(
            Division_Name__c  = divisionName,
            Division_Group__c = groupId,
            Term__c           = termId
        );
        insert d;
        return d.Id;
    }

    /**
     * @description A future-dated session, inserted with the calendar push suppressed so the test
     *          controls exactly when the job runs. Future dates matter: SessionTrigger rewrites the
     *          times of past-dated sessions.
     * @param tag A per-test suffix that keeps session names unique.
     * @param status The Schedule_Type__c to save.
     * @param termId The session header's own Term__c, or null to leave it empty.
     * @return The inserted session.
     */
    private static Session__c newSession(String tag, String status, Id termId) {
        Session__c s = new Session__c(
            Name             = 'ProgMail' + tag,
            Schedule_Type__c = status,
            Session_Date__c  = Date.today().addDays(5),
            Start_Time__c    = Datetime.now().addDays(5),
            End_Time__c      = Datetime.now().addDays(5).addHours(1),
            Term__c          = termId
        );
        SessionCalendarInviteHandler.suppressInvites = true;
        insert s;
        SessionCalendarInviteHandler.suppressInvites = false;
        return s;
    }

    /**
     * @description A faculty-record-type Account. The Faculty type is used deliberately: two
     *          learner person accounts in one transaction trip the duplicate-student check.
     * @param tag A per-test suffix.
     * @param email The address that must appear on the faculty copy.
     * @return The new account's id.
     */
    private static Id newFaculty(String tag, String email) {
        Id facRt = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByName().get('Faculty').getRecordTypeId();
        Account fac = new Account(
            LastName = 'ProgFac' + tag, PersonEmail = email, RecordTypeId = facRt
        );
        insert fac;
        return fac.Id;
    }

    /**
     * @description Links divisions to a session, allowing the same division to be linked twice —
     *          which real data does carry.
     * @param sessionId The session.
     * @param divisionIds The divisions to attach, one Session_Division__c row each.
     */
    private static void attachDivisions(Id sessionId, List<Id> divisionIds) {
        List<Session_Division__c> rows = new List<Session_Division__c>();
        for (Id divId : divisionIds) {
            rows.add(new Session_Division__c(Session__c = sessionId, Division__c = divId));
        }
        SessionCalendarInviteHandler.suppressInvites = true;
        insert rows;
        SessionCalendarInviteHandler.suppressInvites = false;
    }

    /**
     * @description Whether the managed academic-term stack is unavailable in this org, in which
     *          case the fixture cannot be built and the test has nothing to prove.
     * @param termId The term the fixture depends on.
     * @return True when the test should stop.
     */
    private static Boolean termUnavailable(Id termId) {
        if (termId == null) {
            Assert.isTrue(true, 'Managed AcademicTerm setup unavailable; skipping.');
            return true;
        }
        return false;
    }

    // ---------------------------------------------------------------------------------------
    // Part 1 regression: the single-term session must be unchanged by the multi-term fix.
    // ---------------------------------------------------------------------------------------

    @IsTest
    static void singleTermSessionInvitesItsOneProgrammeOfficeExactlyOnce() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divA    = newDivision(groupId, termA, 'A1');
        Session__c s = newSession('one', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{ divA });
        Id facId = newFaculty('one', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'A faculty-only session must produce exactly one event. ' + writeTrace());

        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'The header term and the division term are the SAME programme office, so it must be '
            + 'invited once, not twice. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, FACULTY_EMAIL),
            'The faculty must still be on their own copy. Guests=' + guests);
        Assert.areEqual(2, guests.size(),
            'Nobody beyond the faculty and the one programme office belongs on this event. Guests='
            + guests);

        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c, Calendar_Sync_Status__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Synced', after.Calendar_Sync_Status__c, 'The one push succeeded.');
        Assert.areEqual('evt_prog_1', after.Faculty_Google_Event_Id__c,
            'The faculty copy id must be stamped.');
        Assert.isNull(after.Google_Event_Id__c,
            'A programme office is a guest, never a reason to create a student event.');
    }

    // ---------------------------------------------------------------------------------------
    // The fix itself: a shared session reaches several programme offices.
    // ---------------------------------------------------------------------------------------

    @IsTest
    static void sharedSessionPutsEveryDivisionTermProgrammeOfficeOnTheOneFacultyEvent() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divA    = newDivision(groupId, termA, 'A1');
        Id divB    = newDivision(groupId, termB, 'B1');
        // Shared session: the header term is A, but division B drags a second programme in.
        Session__c s = newSession('shared', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{ divA, divB });
        Id facId = newFaculty('shared', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'Two programme offices must share ONE faculty event. A second write here means the '
            + 'second office got a calendar entry of its own. ' + writeTrace());
        Assert.areEqual('POST', pushes[0].method, 'The first push creates the faculty event.');

        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'Division A\'s programme office must be invited exactly once. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_B),
            'Division B\'s programme office is reached only through the division term, and is '
            + 'the whole point of the fix. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, FACULTY_EMAIL),
            'The faculty must still be on the event. Guests=' + guests);
        Assert.areEqual(3, guests.size(),
            'Exactly the faculty and the two programme offices. Guests=' + guests);

        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c, Calendar_Sync_Status__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Synced', after.Calendar_Sync_Status__c, 'The one push succeeded.');
        Assert.areEqual('evt_prog_1', after.Faculty_Google_Event_Id__c,
            'Exactly one faculty event id may be stamped — the mock hands out a fresh id per '
            + 'create, so a second create would show here.');
        Assert.isNull(after.Google_Event_Id__c,
            'No student event exists for a faculty-only session, before or after the fix.');
    }

    @IsTest
    static void rePushOfASharedSessionPatchesTheExistingEventRatherThanCreatingASecond() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Session__c s = newSession('repush', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        Id facId = newFaculty('repush', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        // The session was already synced by an earlier save, in its own transaction.
        SessionCalendarInviteHandler.suppressInvites = true;
        update new Session__c(Id = s.Id, Faculty_Google_Event_Id__c = 'evt_existing_faculty');
        SessionCalendarInviteHandler.suppressInvites = false;
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'The second programme office must join the event that already exists. ' + writeTrace());
        Assert.areEqual('PATCH', pushes[0].method,
            'A POST here would leave the faculty with a duplicate calendar entry. ' + writeTrace());
        Assert.areEqual('evt_existing_faculty', patchedEventId(pushes[0].endpoint),
            'The patch must target the stored event. Endpoint=' + pushes[0].endpoint);

        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'Programme office A stays on the updated event. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_B),
            'Programme office B must be added to the SAME event. Guests=' + guests);
        Assert.areEqual(3, guests.size(),
            'Faculty plus the two offices, on one event. Guests=' + guests);

        Session__c after = [
            SELECT Google_Event_Id__c, Faculty_Google_Event_Id__c FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('evt_existing_faculty', after.Faculty_Google_Event_Id__c,
            'The stored event id must be unchanged: no second event was created.');
        Assert.isNull(after.Google_Event_Id__c,
            'A faculty-only session must never gain a student event.');
    }

    @IsTest
    static void onlyTheDivisionTermThatHasAnAddressIsInvited() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(null);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divA    = newDivision(groupId, termA, 'A1');
        Id divB    = newDivision(groupId, termB, 'B1');
        // Header term is the one WITHOUT an address, so the only source is division A's term.
        Session__c s = newSession('partial', 'Draft', termB);
        attachDivisions(s.Id, new List<Id>{ divA, divB });
        Id facId = newFaculty('partial', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(), 'One faculty event. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'The term that has an address must be invited. Guests=' + guests);
        Assert.areEqual(2, guests.size(),
            'The term with no address must contribute nothing at all — not a blank guest, not a '
            + 'null one. Guests=' + guests);
        for (String guest : guests) {
            Assert.isTrue(String.isNotBlank(guest),
                'A blank attendee would make Google reject the whole event. Guests=' + guests);
        }
    }

    @IsTest
    static void theSameDivisionAttachedTwiceInvitesItsProgrammeOfficeOnce() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divA    = newDivision(groupId, termA, 'A1');
        // Header term left empty so the duplicated division rows are the ONLY source.
        Session__c s = newSession('dupe', 'Draft', null);
        attachDivisions(s.Id, new List<Id>{ divA, divA });
        Id facId = newFaculty('dupe', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        Assert.areEqual(2, [
            SELECT COUNT() FROM Session_Division__c WHERE Session__c = :s.Id
        ], 'The fixture must really hold the duplicate row the assertion is about.');
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(), 'One faculty event. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'Two rows pointing at one division are one programme office, not two guests. Guests='
            + guests);
        Assert.areEqual(2, guests.size(),
            'Faculty plus the single programme office. Guests=' + guests);
    }

    @IsTest
    static void twoDivisionsSharingOneTermInviteThatOfficeOnce() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        // Two genuinely different divisions, one term — the ordinary "A1 and A2 sit together" case.
        Session__c s = newSession('sameterm', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termA, 'A2')
        });
        Id facId = newFaculty('sameterm', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(), 'One faculty event. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'One programme office owns both divisions, so it is one guest, not two. Guests='
            + guests);
        Assert.areEqual(2, guests.size(),
            'Faculty plus the single shared programme office. Guests=' + guests);
    }

    @IsTest
    static void oneMailboxTypedInTwoCasingsIsNotInvitedTwice() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        // The same programme office, typed by two different admins on two different terms.
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_A.toUpperCase());
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Session__c s = newSession('casing', 'Draft', null);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        Id facId = newFaculty('casing', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        String storedA = [SELECT Programme_Email__c FROM AcademicTerm WHERE Id = :termA]
            .Programme_Email__c;
        String storedB = [SELECT Programme_Email__c FROM AcademicTerm WHERE Id = :termB]
            .Programme_Email__c;
        if (storedA == storedB) {
            // Salesforce normalised the address on save, so there is no divergence to guard.
            Assert.areEqual(storedA, storedB, 'Email storage normalised the casing; nothing to test.');
            return;
        }
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(), 'One faculty event. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'An email address is case-insensitive, so one mailbox must be one guest however the '
            + 'two terms spell it. Guests=' + guests);
        Assert.areEqual(2, guests.size(),
            'Faculty plus the single mailbox. Guests=' + guests);
    }

    @IsTest
    static void unstaffedSessionWithOnlyAHeaderAddressStillInvitesThatOfficeAlone() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        // Nobody teaches this session yet and it has no divisions: the header term address is the
        // only guest there has ever been. This is the ORIGINAL pre-fix behaviour and the fix must
        // not take it away — a session can sit unstaffed for weeks while the office still needs it
        // on their calendar.
        Session__c s = newSession('hdronly', 'Draft', termA);
        Assert.areEqual(0, [SELECT COUNT() FROM Session_Faculty__c WHERE Session__c = :s.Id],
            'This case is about a session nobody teaches yet.');
        Assert.areEqual(0, [SELECT COUNT() FROM Session_Division__c WHERE Session__c = :s.Id],
            'And one the division walk cannot contribute anything to.');
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'The header-term address alone must still produce the faculty-side event it always '
            + 'has. Losing this is the regression the guard nearly introduced. ' + writeTrace());
        Assert.areEqual(new List<String>{ PROG_EMAIL_A }, attendeesOf(pushes[0]),
            'The programme office is the sole guest. Guests=' + attendeesOf(pushes[0]));

        Session__c after = [
            SELECT Calendar_Sync_Status__c, Faculty_Google_Event_Id__c, Google_Event_Id__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Synced', after.Calendar_Sync_Status__c,
            'An office-only push is a successful push, exactly as before the fix.');
        Assert.areEqual('evt_prog_1', after.Faculty_Google_Event_Id__c,
            'The faculty copy id must be stamped.');
        Assert.isNull(after.Google_Event_Id__c, 'No student event exists for a Draft.');
    }

    @IsTest
    static void headerAddressUnlocksTheDivisionWalkEvenWithNoFaculty() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        // Unstaffed, but the header address makes the guest list non-empty, so the new division
        // walk is allowed to ADD to the event the header address already justified.
        Session__c s = newSession('hdrunlock', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        Assert.areEqual(0, [SELECT COUNT() FROM Session_Faculty__c WHERE Session__c = :s.Id],
            'This case is about a session nobody teaches yet.');
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'Still one event, not one per office. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'The header office anchors the event. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_B),
            'The shared division\'s office joins the event the header office anchored — that is '
            + 'the whole point of the shared-session fix. Guests=' + guests);
        Assert.areEqual(2, guests.size(),
            'Exactly the two offices, nobody else. Guests=' + guests);
    }

    @IsTest
    static void divisionAddressesAloneNeverCreateAnEvent() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        // No faculty AND no header address: the division walk is the only possible source, and
        // the new code must never be the sole reason an event exists.
        Session__c s = newSession('divonly', 'Draft', null);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        Assert.areEqual(0, [SELECT COUNT() FROM Session_Faculty__c WHERE Session__c = :s.Id],
            'This case is about a session nobody teaches yet.');
        Assert.areEqual(2, [
            SELECT COUNT() FROM Session_Division__c
            WHERE Session__c = :s.Id AND Division__r.Term__r.Programme_Email__c != NULL
        ], 'The fixture really does offer the division walk two addresses to find.');
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        Assert.areEqual(0, writes().size(),
            'The division walk may only ADD offices to an event something else justified. '
            + 'Creating one here would hide that this session has no teacher. ' + writeTrace());

        Session__c after = [
            SELECT Calendar_Sync_Status__c, Calendar_Sync_Error__c, Faculty_Google_Event_Id__c,
                   Google_Event_Id__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Failed', after.Calendar_Sync_Status__c,
            'The session must keep the Failed flag that marks it as needing a teacher.');
        Assert.areEqual('No attendees with a valid email were found for this session.',
            after.Calendar_Sync_Error__c,
            'The reason shown must still name the real problem.');
        Assert.isNull(after.Faculty_Google_Event_Id__c, 'No faculty event may be created.');
        Assert.isNull(after.Google_Event_Id__c, 'No student event may be created.');
    }

    @IsTest
    static void oneFacultyMemberIsEnoughToCarryEveryProgrammeOffice() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Session__c s = newSession('onefac', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        // The boundary the guard turns on: exactly one faculty member.
        Id facId = newFaculty('onefac', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'The moment a session has a teacher, its offices ride that one event. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(3, guests.size(),
            'One faculty member unlocks BOTH offices, not just the header one. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A), 'Office A rides along. ' + guests);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_B), 'Office B rides along. ' + guests);
    }

    @IsTest
    static void facultyWithoutAnEmailDoesNotLetTheDivisionWalkCreateAnEvent() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        // A faculty record IS attached but carries no address, so it contributes no guest. With no
        // header address either, the division walk is again the only candidate — the boundary just
        // below "has a reachable teacher".
        Session__c s = newSession('facnomail', 'Draft', null);
        attachDivisions(s.Id, new List<Id>{ newDivision(groupId, termA, 'A1') });
        Id facId = newFaculty('facnomail', null);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        Assert.areEqual(1, [SELECT COUNT() FROM Session_Faculty__c WHERE Session__c = :s.Id],
            'The fixture really does attach a teacher — just an unreachable one.');
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        Assert.areEqual(0, writes().size(),
            'A faculty row with no address is no guest at all, so the division walk still has '
            + 'nothing to add to and must not invent an event. ' + writeTrace());
        Session__c after = [
            SELECT Calendar_Sync_Status__c, Faculty_Google_Event_Id__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Failed', after.Calendar_Sync_Status__c,
            'A session whose only teacher has no email address stays flagged.');
        Assert.isNull(after.Faculty_Google_Event_Id__c, 'No faculty event may be created.');
    }

    @IsTest
    static void sessionWithNoDivisionsFallsBackToTheHeaderTermAddress() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        Session__c s = newSession('nodiv', 'Draft', termA);
        Id facId = newFaculty('nodiv', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        Assert.areEqual(0, [
            SELECT COUNT() FROM Session_Division__c WHERE Session__c = :s.Id
        ], 'This case is about a session with no division rows at all.');
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(), 'One faculty event. ' + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'With no divisions to walk, the header term remains the fallback — dropping it would '
            + 'silently cut the programme office out of every unshared session. Guests=' + guests);
        Assert.areEqual(2, guests.size(), 'Faculty plus the header programme office. Guests='
            + guests);
    }

    @IsTest
    static void divisionTermsWithNoAddressLeaveTheGuestListUntouched() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(null);
        Id termB = newTerm(null);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Session__c s = newSession('noaddr', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        Id facId = newFaculty('noaddr', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(), 'One faculty event, exactly as before the fix. '
            + writeTrace());
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(new List<String>{ FACULTY_EMAIL }, guests,
            'With no programme address anywhere, the guest list must be the faculty alone. Guests='
            + guests);

        Session__c after = [
            SELECT Calendar_Sync_Status__c, Calendar_Sync_Error__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Synced', after.Calendar_Sync_Status__c,
            'A term with no programme address is normal, not a sync failure. Error='
            + after.Calendar_Sync_Error__c);
    }

    // ---------------------------------------------------------------------------------------
    // The confidentiality guarantee: students must never see a programme office address.
    // ---------------------------------------------------------------------------------------

    @IsTest
    static void studentCopyCarriesNoProgrammeOfficeAddressFromAnyTerm() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('pml');
        Id ateId   = SpjimrPortalTestDataFactory.insertAcademicTermEnrollment(learner.Id, termA);
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divA    = newDivision(groupId, termA, 'A1');
        Id divB    = newDivision(groupId, termB, 'B1');
        Id deId    = SpjimrPortalTestDataFactory.insertDivisionEnrollment(divA, ateId);
        String studentEmail = [SELECT PersonEmail FROM Account WHERE Id = :learner.Id].PersonEmail;
        if (deId == null || String.isBlank(studentEmail)) {
            Assert.isTrue(true, 'Managed enrolment setup unavailable; skipping.');
            return;
        }

        Session__c s = newSession('leak', 'Republished', termA);
        attachDivisions(s.Id, new List<Id>{ divA, divB });
        SessionCalendarInviteHandler.suppressInvites = true;
        SpjimrPortalTestDataFactory.insertSessionEnrollment(s.Id, deId, ateId);
        SessionCalendarInviteHandler.suppressInvites = false;
        Id facId = newFaculty('leak', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        sent.clear();

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>{ s.Id }, new Set<Id>(), null, false
        ));
        Test.stopTest();

        Assert.areEqual(2, writes().size(),
            'A student-facing session is two events: the faculty copy and the silent student copy. '
            + writeTrace());

        Sent studentWrite = writeCarrying(studentEmail);
        Assert.isNotNull(studentWrite, 'The student must be on the student copy. ' + writeTrace());
        List<String> studentGuests = attendeesOf(studentWrite);
        Assert.areEqual(0, occurrences(studentGuests, PROG_EMAIL_A),
            'A programme office address on the students\' event exposes an internal mailbox to '
            + 'every student in the division. Guests=' + studentGuests);
        Assert.areEqual(0, occurrences(studentGuests, PROG_EMAIL_B),
            'The second programme office must not leak to students either. Guests='
            + studentGuests);
        Assert.areEqual(new List<String>{ studentEmail }, studentGuests,
            'The student copy carries the students and nobody else. Guests=' + studentGuests);

        Sent facultyWrite = writeCarrying(FACULTY_EMAIL);
        Assert.isNotNull(facultyWrite, 'The faculty copy must exist. ' + writeTrace());
        List<String> facultyGuests = attendeesOf(facultyWrite);
        Assert.areEqual(1, occurrences(facultyGuests, PROG_EMAIL_A),
            'Both programme offices belong on the faculty copy. Guests=' + facultyGuests);
        Assert.areEqual(1, occurrences(facultyGuests, PROG_EMAIL_B),
            'Both programme offices belong on the faculty copy. Guests=' + facultyGuests);
        Assert.areEqual(0, occurrences(facultyGuests, studentEmail),
            'No student may ride the notifying faculty copy. Guests=' + facultyGuests);
    }

    // ---------------------------------------------------------------------------------------
    // Bulk / governor: one full chunk of work must still cost a fixed number of queries.
    // ---------------------------------------------------------------------------------------

    @IsTest
    static void fullChunkOfSharedSessionsResolvesEveryOfficeAtConstantQueryCost() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Id divA    = newDivision(groupId, termA, 'A1');
        Id divB    = newDivision(groupId, termB, 'B1');
        Id facId   = newFaculty('bulk', FACULTY_EMAIL);

        // 30 faculty-only sessions is exactly one full chunk: the handler budgets 30 callouts a job
        // and a faculty-only session costs one.
        Integer volume = 30;
        List<Session__c> sessions = new List<Session__c>();
        for (Integer i = 0; i < volume; i++) {
            sessions.add(new Session__c(
                Name             = 'ProgMailBulk' + i,
                Schedule_Type__c = 'Draft',
                Session_Date__c  = Date.today().addDays(5),
                Start_Time__c    = Datetime.now().addDays(5),
                End_Time__c      = Datetime.now().addDays(5).addHours(1),
                Term__c          = termA
            ));
        }
        SessionCalendarInviteHandler.suppressInvites = true;
        insert sessions;
        List<Session_Division__c> links = new List<Session_Division__c>();
        List<Session_Faculty__c> facs   = new List<Session_Faculty__c>();
        for (Session__c s : sessions) {
            links.add(new Session_Division__c(Session__c = s.Id, Division__c = divA));
            links.add(new Session_Division__c(Session__c = s.Id, Division__c = divB));
            facs.add(new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId));
        }
        insert links;
        insert facs;
        SessionCalendarInviteHandler.suppressInvites = false;

        Set<Id> ids = new Map<Id, Session__c>(sessions).keySet();
        sent.clear();

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        runJob(new SessionCalendarInviteQueueable(new Set<Id>(), ids, null, false));
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.areEqual(volume, writes().size(),
            'Every session in the chunk must be pushed, once each.');
        Assert.isTrue(queriesUsed <= 6,
            'Resolving programme offices must stay a single bulk query, not one per session. '
            + volume + ' sessions cost ' + queriesUsed + ' queries.');

        for (Sent push : writes()) {
            List<String> guests = attendeesOf(push);
            Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
                'Every session in the chunk owes programme office A once. Guests=' + guests);
            Assert.areEqual(1, occurrences(guests, PROG_EMAIL_B),
                'Every session in the chunk owes programme office B once. Guests=' + guests);
            Assert.areEqual(3, guests.size(),
                'Faculty plus the two offices, on every session. Guests=' + guests);
        }

        Integer synced = [
            SELECT COUNT() FROM Session__c WHERE Id IN :ids AND Calendar_Sync_Status__c = 'Synced'
        ];
        Assert.areEqual(volume, synced, 'Every session in the chunk must end up Synced.');
    }

    // ---------------------------------------------------------------------------------------
    // Negative path: Google rejecting the faculty copy must not be reported as a success.
    // ---------------------------------------------------------------------------------------

    /** Fails every event write, so the error path can be asserted rather than assumed. */
    private class FailingMock implements HttpCalloutMock {
        /**
         * @description Answers the token call and then refuses every event write.
         * @param req The outbound request.
         * @return A token, or a 403 for an event write.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('oauth2.googleapis.com/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"mock_token","expires_in":3600}');
                return res;
            }
            res.setStatusCode(403);
            res.setBody('{"error":{"message":"forbiddenForServiceAccounts"}}');
            return res;
        }
    }

    @IsTest
    static void googleRefusingTheFacultyCopyIsRecordedAsAFailureNotASync() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new FailingMock());
        Id termA = newTerm(PROG_EMAIL_A);
        if (termUnavailable(termA)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Session__c s = newSession('fail', 'Draft', null);
        attachDivisions(s.Id, new List<Id>{ newDivision(groupId, termA, 'A1') });
        Id facId = newFaculty('fail', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);

        Test.startTest();
        runJob(new SessionCalendarInviteQueueable(
            new Set<Id>(), new Set<Id>{ s.Id }, null, false
        ));
        Test.stopTest();

        Session__c after = [
            SELECT Calendar_Sync_Status__c, Calendar_Sync_Error__c, Faculty_Google_Event_Id__c
            FROM Session__c WHERE Id = :s.Id
        ];
        Assert.areEqual('Failed', after.Calendar_Sync_Status__c,
            'A rejected push must surface, or the programme office silently never gets the invite.');
        Assert.isTrue(after.Calendar_Sync_Error__c.contains('Faculty event:'),
            'The error must name the copy that broke. Error=' + after.Calendar_Sync_Error__c);
        Assert.isNull(after.Faculty_Google_Event_Id__c,
            'No event id may be stamped for a push Google refused.');
    }

    // ---------------------------------------------------------------------------------------
    // Security: the same guarantees must hold when the save comes from a real, restricted user.
    // ---------------------------------------------------------------------------------------

    /**
     * @description The non-admin who actually publishes timetables in this org: a Normal Users
     *          profile carrying the SPJIMR_Programme_Manager permission set. Built inside a runAs
     *          block so the setup-object DML does not collide with the fixture's own DML.
     * @return The saved user.
     */
    private static User buildProgrammeManagerUser() {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Normal Users' LIMIT 1];
            u = new User(
                ProfileId         = p.Id,
                LastName          = 'ProgOfficeTester',
                Email             = 'progoffice.tester@example.com',
                Username          = 'progoffice.tester' + DateTime.now().getTime() + '@example.com',
                Alias             = 'pofc',
                TimeZoneSidKey    = 'Asia/Kolkata',
                LocaleSidKey      = 'en_IN',
                EmailEncodingKey  = 'UTF-8',
                LanguageLocaleKey = 'en_US'
            );
            insert u;
            List<PermissionSet> sets = [
                SELECT Id FROM PermissionSet WHERE Name = 'SPJIMR_Programme_Manager' LIMIT 1
            ];
            if (!sets.isEmpty()) {
                insert new PermissionSetAssignment(
                    AssigneeId = u.Id, PermissionSetId = sets[0].Id
                );
            }
        }
        return u;
    }

    @IsTest
    static void programmeManagersSaveStillRoutesTheOfficeToFacultyOnly() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new Mock());
        User restricted = buildProgrammeManagerUser();

        Id termA = newTerm(PROG_EMAIL_A);
        Id termB = newTerm(PROG_EMAIL_B);
        if (termUnavailable(termA) || termUnavailable(termB)) {
            return;
        }
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        Session__c s = newSession('runas', 'Draft', termA);
        attachDivisions(s.Id, new List<Id>{
            newDivision(groupId, termA, 'A1'), newDivision(groupId, termB, 'B1')
        });
        Id facId = newFaculty('runas', FACULTY_EMAIL);
        insert new Session_Faculty__c(Session__c = s.Id, Session_Faculty__c = facId);
        // Already synced by an earlier save, so the user's edit re-pushes the existing event.
        SessionCalendarInviteHandler.suppressInvites = true;
        update new Session__c(Id = s.Id, Faculty_Google_Event_Id__c = 'evt_runas_faculty');
        SessionCalendarInviteHandler.suppressInvites = false;
        sent.clear();

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();
        System.runAs(restricted) {
            // The real entry point: a Programme Manager moves the session to another room. The
            // queueable this enqueues then runs asynchronously, at stopTest below.
            update new Session__c(Id = s.Id, Class_Room__c = 'Room 42');
        }
        Assert.isTrue(Limits.getQueueableJobs() > jobsBefore,
            'A Programme Manager editing a session must enqueue the calendar push, or the '
            + 'programme offices never see the change when anyone but an admin saves. Jobs before='
            + jobsBefore + ' after=' + Limits.getQueueableJobs());
        Test.stopTest();

        List<Sent> pushes = writes();
        Assert.areEqual(1, pushes.size(),
            'A restricted user\'s save must still produce exactly one faculty event — and no '
            + 'student event, because nobody is enrolled. ' + writeTrace());
        Assert.areEqual('evt_runas_faculty', patchedEventId(pushes[0].endpoint),
            'The existing faculty event must be patched. Endpoint=' + pushes[0].endpoint);
        List<String> guests = attendeesOf(pushes[0]);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_A),
            'Programme office A must be reachable for a non-admin save. Guests=' + guests);
        Assert.areEqual(1, occurrences(guests, PROG_EMAIL_B),
            'Programme office B is reached only through the division term, and a restricted '
            + 'profile\'s field visibility must not silently drop it. Guests=' + guests);
        Assert.areEqual(3, guests.size(), 'Faculty plus the two offices. Guests=' + guests);
        Assert.isTrue(pushes[0].body.contains('Room 42'),
            'The pushed event must carry the change the user actually made. Body=' + pushes[0].body);
    }
}