/**
 * @description Unit tests for SessionRsvpSyncService. The pure seams (parseResponses,
 *              matchResponses, mapResponse, extractEmail) are tested with in-memory records
 *              — the enrollment relationship path is fabricated via JSON to avoid inserting
 *              Person Accounts / enrollment chains. The DML branch is covered with a
 *              well-formed non-existent Id under allOrNone=false, and the query path with a
 *              real Session that has no enrollments.
 */
@IsTest
private class SessionRsvpSyncServiceTest {

    private static Integer idCounter = 1;
    private static final Id FAKE_SESSION = fakeId(Session__c.SObjectType);
    private static final Id FAKE_ENROLL  = fakeId(Session_Enrollment__c.SObjectType);

    /**
     * @description Generates a well-formed but non-existent Id for the given SObject type.
     * @param sot The SObject type whose key prefix to use.
     * @return A unique 15-char Id with that type's key prefix.
     */
    private static Id fakeId(Schema.SObjectType sot) {
        String base = '000000000000' + idCounter++;
        return Id.valueOf(sot.getDescribe().getKeyPrefix() + base.right(12));
    }

    /**
     * @description Fabricates an in-memory enrollment with the student email path populated.
     * @param enrId Optional record Id (null to omit).
     * @param sessionId The session lookup value.
     * @param email The student PersonEmail (null to omit the whole relationship path).
     * @return A Session_Enrollment__c with the relationship path set (read-only via JSON).
     */
    private static Session_Enrollment__c fabricateEnrollment(Id enrId, Id sessionId, String email) {
        String body = '{"attributes":{"type":"Session_Enrollment__c"}';
        if (enrId != null) {
            body += ',"Id":"' + enrId + '"';
        }
        body += ',"Session__c":"' + sessionId + '"';
        if (email != null) {
            body += ',"Division_Enrollment__r":{"attributes":{"type":"Division_Enrollment__c"},'
                 +  '"Academic_Term_Enrollment__r":{"attributes":{"type":"AcademicTermEnrollment"},'
                 +  '"LearnerAccount":{"attributes":{"type":"Account"},"PersonEmail":"' + email + '"}}}';
        }
        body += '}';
        return (Session_Enrollment__c) JSON.deserialize(body, Session_Enrollment__c.class);
    }

    /**
     * @description Builds the parsed Google event map used by parseResponses.
     * @param attendeesJson The attendees array literal.
     * @return The event as an untyped map.
     */
    @SuppressWarnings('PMD.ApexDoc')
    private static Map<String, Object> event(String attendeesJson) {
        return (Map<String, Object>) JSON.deserializeUntyped(
            '{"id":"evt","attendees":' + attendeesJson + '}');
    }

    @IsTest
    static void testParseResponsesMapsStatuses() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Map<String, Object> ev = event('['
                + '{"email":"A@spjimr.org","responseStatus":"accepted"},'
                + '{"email":"b@spjimr.org","responseStatus":"declined"},'
                + '{"email":"c@spjimr.org","responseStatus":"tentative"},'
                + '{"email":"d@spjimr.org","responseStatus":"needsAction"}]');
            Map<String, String> result = SessionRsvpSyncService.parseResponses(ev);
            Assert.areEqual(4, result.size(), 'All four attendees are parsed');
            Assert.areEqual('Accepted', result.get('a@spjimr.org'), 'Email lower-cased, accepted maps through');
            Assert.areEqual('Declined', result.get('b@spjimr.org'), 'declined maps through');
            Assert.areEqual('Tentative', result.get('c@spjimr.org'), 'tentative maps through');
            Assert.areEqual('No Response', result.get('d@spjimr.org'), 'needsAction -> No Response');
        }
    }

    @IsTest
    static void testParseResponsesSkipsBlankAndResources() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Map<String, Object> ev = event('['
                + '{"email":"","responseStatus":"accepted"},'
                + '{"email":"room@spjimr.org","responseStatus":"accepted","resource":true},'
                + '{"email":"real@spjimr.org","responseStatus":"accepted"}]');
            Map<String, String> result = SessionRsvpSyncService.parseResponses(ev);
            Assert.areEqual(1, result.size(), 'Blank email and resource rows are skipped');
            Assert.areEqual('Accepted', result.get('real@spjimr.org'), 'Only the real attendee remains');
        }
    }

    @IsTest
    static void testParseResponsesHandlesMissingAttendees() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Assert.isTrue(SessionRsvpSyncService.parseResponses(null).isEmpty(),
                'Null event yields an empty map');
            Map<String, Object> noList = (Map<String, Object>) JSON.deserializeUntyped('{"id":"evt"}');
            Assert.isTrue(SessionRsvpSyncService.parseResponses(noList).isEmpty(),
                'Event without an attendees array yields an empty map');
        }
    }

    @IsTest
    static void testMatchResponsesChangesMatching() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c enr = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, 'Stud@X.com');
            Map<Id, Map<String, String>> bySession = new Map<Id, Map<String, String>>{
                FAKE_SESSION => new Map<String, String>{ 'stud@x.com' => 'Accepted' }
            };
            List<Session_Enrollment__c> changed = SessionRsvpSyncService.matchResponses(
                new List<Session_Enrollment__c>{ enr }, bySession);
            Assert.areEqual(1, changed.size(), 'The matching enrollment is flagged for update');
            Assert.areEqual('Accepted', changed[0].Invite_Response__c, 'Response is copied onto the enrollment');
            Assert.isNotNull(changed[0].Invite_Response_Checked__c, 'Checked timestamp is stamped on change');
        }
    }

    @IsTest
    static void testMatchResponsesSkipsUnchangedAndUnmatched() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c already = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, 'same@x.com');
            already.Invite_Response__c = 'Accepted';
            Session_Enrollment__c noEmail = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, null);
            Map<Id, Map<String, String>> bySession = new Map<Id, Map<String, String>>{
                FAKE_SESSION => new Map<String, String>{ 'same@x.com' => 'Accepted' }
            };
            List<Session_Enrollment__c> changed = SessionRsvpSyncService.matchResponses(
                new List<Session_Enrollment__c>{ already, noEmail }, bySession);
            Assert.areEqual(0, changed.size(), 'Unchanged value and missing-email rows produce no updates');
            Assert.isTrue(SessionRsvpSyncService.matchResponses(null, bySession).isEmpty(),
                'Null enrollment list yields no updates');
        }
    }

    @IsTest
    static void testExtractEmailNullSafe() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c withEmail = fabricateEnrollment(null, FAKE_SESSION, 'here@x.com');
            Session_Enrollment__c noPath = fabricateEnrollment(null, FAKE_SESSION, null);
            Assert.areEqual('here@x.com', SessionRsvpSyncService.extractEmail(withEmail),
                'Email is read from the relationship path');
            Assert.isNull(SessionRsvpSyncService.extractEmail(noPath),
                'Missing relationship path returns null, not an exception');
        }
    }

    @IsTest
    static void testPersistToleratesBadId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c enr = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, 'ghost@x.com');
            enr.Invite_Response__c = 'Declined';
            Test.startTest();
            SessionRsvpSyncService.persist(new List<Session_Enrollment__c>{ enr });
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Session_Enrollment__c WHERE Id = :FAKE_ENROLL],
                'The non-existent-Id update fails silently under allOrNone=false (no rows, no exception)');
        }
    }

    @IsTest
    static void testApplyToEnrollmentsQueryAndNoOp() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = new Session__c(
                Schedule_Type__c = 'Scheduled',
                Start_Time__c    = Datetime.now().addDays(1),
                End_Time__c      = Datetime.now().addDays(1).addHours(1)
            );
            insert s;
            Test.startTest();
            // Empty/null inputs are no-ops; a real session with no enrollments exercises the query.
            SessionRsvpSyncService.applyToEnrollments(null);
            SessionRsvpSyncService.applyToEnrollments(new Map<Id, Map<String, String>>());
            SessionRsvpSyncService.applyToEnrollments(new Map<Id, Map<String, String>>{
                s.Id => new Map<String, String>{ 'nobody@x.com' => 'Accepted' }
            });
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Session_Enrollment__c WHERE Session__c = :s.Id],
                'No enrollments exist for the session, so nothing is updated');
        }
    }
}