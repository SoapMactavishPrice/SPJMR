/**
 * @description Unit tests for SessionFacultyRsvpService. The pure seams (matchResponses,
 *              extractEmail) are tested with in-memory records — the faculty Account
 *              relationship path is fabricated via JSON to avoid inserting Person Accounts.
 *              The DML branch is covered with a well-formed non-existent Id under
 *              allOrNone=false, and the query path with a real Session that has no faculty.
 */
@IsTest
private class SessionFacultyRsvpServiceTest {

    private static Integer idCounter = 1;
    private static final Id FAKE_SESSION = fakeId(Session__c.SObjectType);
    private static final Id FAKE_FACULTY = fakeId(Session_Faculty__c.SObjectType);

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
     * @description Fabricates an in-memory Session_Faculty__c with the faculty email path populated.
     * @param facId Optional record Id (null to omit).
     * @param sessionId The session lookup value.
     * @param email The faculty PersonEmail (null to omit the faculty Account relationship).
     * @return A Session_Faculty__c with the relationship path set (read-only via JSON).
     */
    private static Session_Faculty__c fabricateFaculty(Id facId, Id sessionId, String email) {
        String body = '{"attributes":{"type":"Session_Faculty__c"}';
        if (facId != null) {
            body += ',"Id":"' + facId + '"';
        }
        body += ',"Session__c":"' + sessionId + '"';
        if (email != null) {
            body += ',"Session_Faculty__r":{"attributes":{"type":"Account"},"PersonEmail":"' + email + '"}';
        }
        body += '}';
        return (Session_Faculty__c) JSON.deserialize(body, Session_Faculty__c.class);
    }

    @IsTest
    static void testMatchResponsesChangesMatching() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Faculty__c fac = fabricateFaculty(FAKE_FACULTY, FAKE_SESSION, 'Prof@X.com');
            Map<Id, Map<String, String>> bySession = new Map<Id, Map<String, String>>{
                FAKE_SESSION => new Map<String, String>{ 'prof@x.com' => 'Declined' }
            };
            List<Session_Faculty__c> changed = SessionFacultyRsvpService.matchResponses(
                new List<Session_Faculty__c>{ fac }, bySession);
            Assert.areEqual(1, changed.size(), 'The matching faculty row is flagged for update');
            Assert.areEqual('Declined', changed[0].Invite_Response__c, 'Response is copied onto the faculty row');
            Assert.isNotNull(changed[0].Invite_Response_Checked__c, 'Checked timestamp is stamped on change');
        }
    }

    @IsTest
    static void testMatchResponsesSkipsUnchangedAndUnmatched() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Faculty__c already = fabricateFaculty(FAKE_FACULTY, FAKE_SESSION, 'same@x.com');
            already.Invite_Response__c = 'Accepted';
            Session_Faculty__c noEmail = fabricateFaculty(FAKE_FACULTY, FAKE_SESSION, null);
            Map<Id, Map<String, String>> bySession = new Map<Id, Map<String, String>>{
                FAKE_SESSION => new Map<String, String>{ 'same@x.com' => 'Accepted' }
            };
            List<Session_Faculty__c> changed = SessionFacultyRsvpService.matchResponses(
                new List<Session_Faculty__c>{ already, noEmail }, bySession);
            Assert.areEqual(0, changed.size(), 'Unchanged value and missing-email rows produce no updates');
            Assert.isTrue(SessionFacultyRsvpService.matchResponses(null, bySession).isEmpty(),
                'Null faculty list yields no updates');
        }
    }

    @IsTest
    static void testExtractEmailNullSafe() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Faculty__c withEmail = fabricateFaculty(null, FAKE_SESSION, 'lead@x.com');
            Session_Faculty__c noAccount = fabricateFaculty(null, FAKE_SESSION, null);
            Assert.areEqual('lead@x.com', SessionFacultyRsvpService.extractEmail(withEmail),
                'Email is read from the faculty Account relationship');
            Assert.isNull(SessionFacultyRsvpService.extractEmail(noAccount),
                'Missing faculty Account returns null, not an exception');
        }
    }

    @IsTest
    static void testPersistToleratesBadId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Faculty__c fac = fabricateFaculty(FAKE_FACULTY, FAKE_SESSION, 'ghost@x.com');
            fac.Invite_Response__c = 'Tentative';
            Test.startTest();
            SessionFacultyRsvpService.persist(new List<Session_Faculty__c>{ fac });
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Session_Faculty__c WHERE Id = :FAKE_FACULTY],
                'The non-existent-Id update fails silently under allOrNone=false (no rows, no exception)');
        }
    }

    @IsTest
    static void testApplyToSessionFacultyQueryAndNoOp() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session__c s = new Session__c(
                Schedule_Type__c = 'Scheduled',
                Start_Time__c    = Datetime.now().addDays(1),
                End_Time__c      = Datetime.now().addDays(1).addHours(1)
            );
            insert s;
            Test.startTest();
            // Empty/null inputs are no-ops; a real session with no faculty exercises the query.
            SessionFacultyRsvpService.applyToSessionFaculty(null);
            SessionFacultyRsvpService.applyToSessionFaculty(new Map<Id, Map<String, String>>());
            SessionFacultyRsvpService.applyToSessionFaculty(new Map<Id, Map<String, String>>{
                s.Id => new Map<String, String>{ 'nobody@x.com' => 'Accepted' }
            });
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Session_Faculty__c WHERE Session__c = :s.Id],
                'No faculty exist for the session, so nothing is updated');
        }
    }
}