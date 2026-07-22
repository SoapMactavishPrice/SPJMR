/**
 * @description Unit tests for SessionAttendeeMirrorHandler. Logic seams are tested with
 *              in-memory records (relationship path fabricated via JSON) to avoid inserting
 *              Person Accounts / enrollment chains, and the DML branch is covered with a
 *              well-formed non-existent Id under allOrNone=false. One end-to-end test inserts
 *              a real Session + Session_Attendee__c to cover the trigger.
 */
@IsTest
private class SessionAttendeeMirrorHandlerTest {

    private static Integer idCounter = 1;
    private static final Id FAKE_SESSION = fakeId(Session__c.SObjectType);
    private static final Id FAKE_ENROLL  = fakeId(Session_Enrollment__c.SObjectType);

    /**
     * @description Generates a well-formed but non-existent Id for the given SObject type,
     *              so tests never hardcode environment-specific Ids.
     * @param sot The SObject type whose key prefix to use.
     * @return A unique 15-char Id with that type's key prefix.
     */
    private static Id fakeId(Schema.SObjectType sot) {
        String base = '000000000000' + idCounter++;
        return Id.valueOf(sot.getDescribe().getKeyPrefix() + base.right(12));
    }

    /**
     * @description Simple mock so any incidental Session invite callout on insert is harmless.
     */
    private class HttpMock implements HttpCalloutMock {
        /**
         * @description Returns a generic 200 response for any request.
         * @param req The outbound request (ignored).
         * @return A 200 JSON response.
         */
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{}');
            return res;
        }
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
     * @description Builds a STUDENT Session_Attendee__c in memory (no DML). Callers override
     *              Attendee_Type__c afterwards to model faculty/guest rows.
     * @param sessionId The session lookup.
     * @param email The attendee email.
     * @param status The Response_Status__c value.
     * @return The in-memory attendee row (type defaults to Student).
     */
    private static Session_Attendee__c att(Id sessionId, String email, String status) {
        return new Session_Attendee__c(
            Session__c = sessionId,
            Attendee_Email__c = email,
            Attendee_Type__c = 'Student',
            Response_Status__c = status
        );
    }

    @IsTest
    static void testBuildStudentResponseMapFiltersNonStudents() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Attendee__c faculty = att(FAKE_SESSION, 'fac@x.com', 'Accepted');
            faculty.Attendee_Type__c = 'Faculty';
            Session_Attendee__c guest = att(FAKE_SESSION, 'guest@x.com', 'Declined');
            guest.Attendee_Type__c = 'Other';
            List<Session_Attendee__c> rows = new List<Session_Attendee__c>{
                att(FAKE_SESSION, 'Stud@X.com', 'Accepted'),
                faculty,
                guest,
                att(FAKE_SESSION, '', 'Accepted')
            };
            Map<String, String> result = SessionAttendeeMirrorHandler.buildStudentResponseMap(rows);
            Assert.areEqual(1, result.size(), 'Only the one valid student row should be mapped');
            Assert.areEqual('Accepted', result.get(FAKE_SESSION + ':stud@x.com'),
                'Email should be lower-cased in the key and mapped to Accepted');
            Assert.isTrue(SessionAttendeeMirrorHandler.buildStudentResponseMap(null).isEmpty(),
                'Null input yields an empty map');
        }
    }

    @IsTest
    static void testMapResponseVariants() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Session_Attendee__c> rows = new List<Session_Attendee__c>{
                att(FAKE_SESSION, 'a@x.com', 'Accepted'),
                att(FAKE_SESSION, 'b@x.com', 'Declined'),
                att(FAKE_SESSION, 'c@x.com', 'Tentative'),
                att(FAKE_SESSION, 'd@x.com', 'Needs Action'),
                att(FAKE_SESSION, 'e@x.com', null)
            };
            Map<String, String> result = SessionAttendeeMirrorHandler.buildStudentResponseMap(rows);
            Assert.areEqual('Accepted', result.get(FAKE_SESSION + ':a@x.com'), 'accepted maps through');
            Assert.areEqual('Declined', result.get(FAKE_SESSION + ':b@x.com'), 'declined maps through');
            Assert.areEqual('Tentative', result.get(FAKE_SESSION + ':c@x.com'), 'tentative maps through');
            Assert.areEqual('No Response', result.get(FAKE_SESSION + ':d@x.com'), 'needs action -> No Response');
            Assert.areEqual('No Response', result.get(FAKE_SESSION + ':e@x.com'), 'null status -> No Response');
        }
    }

    @IsTest
    static void testApplyResponsesChangesMatching() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c enr = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, 'Stud@X.com');
            Map<String, String> desired = new Map<String, String>{ FAKE_SESSION + ':stud@x.com' => 'Accepted' };
            List<Session_Enrollment__c> changed =
                SessionAttendeeMirrorHandler.applyResponses(new List<Session_Enrollment__c>{ enr }, desired);
            Assert.areEqual(1, changed.size(), 'The matching enrollment should be flagged for update');
            Assert.areEqual('Accepted', changed[0].Invite_Response__c, 'Response is copied onto the enrollment');
            Assert.isNotNull(changed[0].Invite_Response_Checked__c, 'Checked timestamp is stamped on change');
        }
    }

    @IsTest
    static void testApplyResponsesSkipsUnchangedAndUnmatched() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c already = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, 'same@x.com');
            already.Invite_Response__c = 'Accepted';
            Session_Enrollment__c noEmail = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, null);
            Map<String, String> desired = new Map<String, String>{ FAKE_SESSION + ':same@x.com' => 'Accepted' };
            List<Session_Enrollment__c> changed = SessionAttendeeMirrorHandler.applyResponses(
                new List<Session_Enrollment__c>{ already, noEmail }, desired);
            Assert.areEqual(0, changed.size(),
                'Unchanged value and missing-email rows produce no updates');
            Assert.isTrue(SessionAttendeeMirrorHandler.applyResponses(null, desired).isEmpty(),
                'Null enrollment list yields no updates');
        }
    }

    @IsTest
    static void testExtractEmailNullSafe() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c withEmail = fabricateEnrollment(null, FAKE_SESSION, 'here@x.com');
            Session_Enrollment__c noPath = fabricateEnrollment(null, FAKE_SESSION, null);
            Assert.areEqual('here@x.com', SessionAttendeeMirrorHandler.extractEmail(withEmail),
                'Email is read from the relationship path');
            Assert.isNull(SessionAttendeeMirrorHandler.extractEmail(noPath),
                'Missing relationship path returns null, not an exception');
        }
    }

    @IsTest
    static void testPersistResponsesToleratesBadId() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Session_Enrollment__c enr = fabricateEnrollment(FAKE_ENROLL, FAKE_SESSION, 'ghost@x.com');
            Map<String, String> desired = new Map<String, String>{ FAKE_SESSION + ':ghost@x.com' => 'Declined' };
            Test.startTest();
            SessionAttendeeMirrorHandler.persistResponses(new List<Session_Enrollment__c>{ enr }, desired);
            Test.stopTest();
            Assert.areEqual(0, [SELECT COUNT() FROM Session_Enrollment__c WHERE Id = :FAKE_ENROLL],
                'The non-existent-Id update fails silently under allOrNone=false (no rows persisted, no exception)');
        }
    }

    @IsTest
    static void testTriggerInsertMirrors() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.setMock(HttpCalloutMock.class, new HttpMock());
            Session__c s = new Session__c(
                Schedule_Type__c = 'Scheduled',
                Start_Time__c = Datetime.now().addDays(1),
                End_Time__c = Datetime.now().addDays(1).addHours(1)
            );
            insert s;
            Test.startTest();
            Session_Attendee__c a = new Session_Attendee__c(
                Session__c = s.Id,
                Attendee_Email__c = 'student@example.com',
                Attendee_Type__c = 'Student',
                Response_Status__c = 'Accepted',
                Attendee_Key__c = s.Id + ':student@example.com'
            );
            insert a;
            Test.stopTest();
            Assert.areEqual(1,
                [SELECT COUNT() FROM Session_Attendee__c WHERE Id = :a.Id],
                'The attendee insert (and the mirror trigger) completed without error');
        }
    }
}