/**
 * @description Tests the consolidated publish notification: publishing a date range of sessions
 *          must send ONE email to each enrolled student and each assigned faculty member for the
 *          whole publication, instead of Google sending one calendar invitation per session.
 *
 *          The Google Calendar push is deliberately switched off in these tests
 *          (GoogleCalendarHelper.configOverride with Active__c = false) so no HTTP mock is needed
 *          and the assertions isolate the email behaviour. That the publish path itself uses
 *          sendUpdates=none is asserted separately in SessionCalendarInviteHandlerTest.
 *
 *          Emails are never delivered in a test context, so assertions read
 *          SessionPublishSummaryEmailQueueable.sentMessages, which records what was handed to
 *          Messaging.sendEmail. Both audiences share one subject line, so the audiences are told
 *          apart by their body text: students are pointed at the Participant Portal, faculty at
 *          their Google Calendar.
 */
// OperationWithLimitsInLoop suppressed: buildScenario inserts each Session__c and its junction rows
// one per iteration on purpose. The Session trigger stamps and re-reads a session on insert, so a
// bulk insert would not produce the per-session graph these tests need, and the loop is bounded by
// the handful of sessions each scenario asks for.
@SuppressWarnings('PMD.OperationWithLimitsInLoop')
@IsTest
private class SessionPublishSummaryEmailTest {

    private static final String STUDENT_MARKER = 'Participant Portal';
    private static final String FACULTY_MARKER = 'Google Calendar';

    /** @description Graph of ids a publish scenario needs. */
    private class Scenario {
        private Id divisionId;
        private Id studentAccountId;
        private Id facultyAccountId;
        private List<Id> sessionIds = new List<Id>();
    }

    private static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

    /**
     * @description Silences the Google Calendar integration so publishing performs no callout.
     */
    private static void disableCalendarPush() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(Active__c = false);
    }

    /**
     * @description Apex cannot create an OrgWideEmailAddress and a test run has no verified sender
     *          to point at, so the org-wide-sender requirement is switched off for the tests that
     *          assert audience and copy. senderIsRequiredWhenUnverified covers the enforcing path.
     */
    private static void allowMissingSender() {
        SessionPublishSummaryEmailQueueable.requireVerifiedSender = false;
    }

    /**
     * @description Builds the faculty Person Account directly rather than through
     *          SpjimrPortalTestDataFactory.buildLearnerPersonAccount, which stamps the Student
     *          record type plus a shared Date_Of_Birth__c and PersonMobilePhone — a second learner
     *          in the same transaction therefore trips AccountTriggerHandler's "Duplicate Student
     *          found!" check. The Faculty record type is outside that check and is what a faculty
     *          member should be anyway.
     * @param tag Uniqueness suffix.
     * @return The inserted faculty account, or null when the Faculty person record type is absent.
     */
    private static Account buildFacultyPersonAccount(String tag) {
        Schema.RecordTypeInfo rt = Account.SObjectType
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('Faculty');
        if (rt == null || !rt.isAvailable()) {
            return null;
        }
        Account faculty = new Account(
            FirstName    = 'FacF' + tag,
            LastName     = 'FacL' + tag,
            PersonEmail  = ('faculty' + tag + '@example.com').toLowerCase(),
            RecordTypeId = rt.getRecordTypeId()
        );
        insert faculty;
        return faculty;
    }

    /**
     * @description Builds a division with one enrolled student, one faculty member and the
     *          requested number of Draft sessions, each linked to the division and to the student.
     * @param tag Uniqueness suffix.
     * @param sessionDates Dates of the Draft sessions to create.
     * @return The populated scenario, or null when the managed EDA graph is unavailable.
     */
    private static Scenario buildScenario(String tag, List<Date> sessionDates) {
        Scenario sc = new Scenario();

        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('stu' + tag);
        sc.studentAccountId = learner.Id;

        Id termId = SpjimrPortalTestDataFactory.insertAcademicTerm();
        Id ateId  = SpjimrPortalTestDataFactory.insertAcademicTermEnrollment(learner.Id, termId);
        Id groupId = SpjimrPortalTestDataFactory.insertDivisionGroup();
        sc.divisionId = SpjimrPortalTestDataFactory.insertDivision(groupId, termId);
        Id deId = SpjimrPortalTestDataFactory.insertDivisionEnrollment(sc.divisionId, ateId);
        if (sc.divisionId == null || deId == null) {
            return null;
        }

        Account faculty = buildFacultyPersonAccount(tag);
        sc.facultyAccountId = (faculty != null) ? faculty.Id : null;

        for (Integer i = 0; i < sessionDates.size(); i++) {
            Session__c s = new Session__c(Name = 'Pub' + tag + i);
            s.Session_Date__c  = sessionDates[i];
            s.Schedule_Type__c = 'Draft';
            s.Start_Time__c    = Datetime.newInstance(sessionDates[i], Time.newInstance(9, 0, 0, 0));
            s.End_Time__c      = Datetime.newInstance(sessionDates[i], Time.newInstance(10, 0, 0, 0));
            insert s;
            sc.sessionIds.add(s.Id);

            insert new Session_Division__c(Session__c = s.Id, Division__c = sc.divisionId);
            SpjimrPortalTestDataFactory.insertSessionEnrollment(s.Id, deId, ateId);
            if (sc.facultyAccountId != null) {
                SpjimrPortalTestDataFactory.insertSessionFaculty(s.Id, sc.facultyAccountId);
            }
        }
        return sc;
    }

    /**
     * @description Runs the publish action over the scenario's division and date window.
     * @param sc The scenario.
     * @param sendNotifications The Yes/No answer from the modal.
     */
    private static void publish(Scenario sc, Boolean sendNotifications) {
        TimetableSessionController.SessionFilter filter =
            new TimetableSessionController.SessionFilter();
        filter.divisionId        = String.valueOf(sc.divisionId);
        filter.startDate         = Date.today();
        filter.endDate           = Date.today().addDays(30);
        filter.sendNotifications = sendNotifications;
        TimetableSessionController.publishSessions(JSON.serialize(filter));
    }

    /**
     * @description Counts messages whose body identifies the given audience.
     * @param marker Body text unique to that audience.
     * @return How many messages matched.
     */
    private static Integer countByBody(String marker) {
        Integer n = 0;
        for (Messaging.SingleEmailMessage m : SessionPublishSummaryEmailQueueable.sentMessages) {
            if (m.getHtmlBody() != null && m.getHtmlBody().contains(marker)) {
                n++;
            }
        }
        return n;
    }

    /**
     * @description Returns the first message for an audience.
     * @param marker Body text unique to that audience.
     * @return The message, or null when none was sent.
     */
    private static Messaging.SingleEmailMessage firstByBody(String marker) {
        for (Messaging.SingleEmailMessage m : SessionPublishSummaryEmailQueueable.sentMessages) {
            if (m.getHtmlBody() != null && m.getHtmlBody().contains(marker)) {
                return m;
            }
        }
        return null;
    }

    /**
     * @description Formats a date the way the queueable does, for subject assertions.
     * @param value The date.
     * @return The formatted date.
     */
    private static String formatted(Date value) {
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('d MMM yyyy');
    }

    /**
     * @description Yes must send exactly one email to the student and one to the faculty member for
     *          the whole publication, even though both are attached to three separate sessions —
     *          that deduplication is the entire point of the ticket. The quoted range must be the
     *          min/max Session_Date__c of the sessions actually published.
     */
    @IsTest
    static void publishYesSendsOneEmailPerRecipientForTheWholeRange() {
        System.runAs(currentUser()) {
            disableCalendarPush();
            allowMissingSender();
            Date first = Date.today().addDays(2);
            Date last  = Date.today().addDays(9);
            Scenario sc = buildScenario('a', new List<Date>{ first, Date.today().addDays(5), last });
            if (sc == null) {
                Assert.isTrue(true, 'Managed EDA setup unavailable; skipping.');
                return;
            }
            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Test.startTest();
            publish(sc, true);
            Test.stopTest();

            Assert.areEqual(1, countByBody(STUDENT_MARKER),
                'Three published sessions must still produce exactly ONE student email.');
            Assert.areEqual(1, countByBody(FACULTY_MARKER),
                'Three published sessions must still produce exactly ONE faculty email.');

            Messaging.SingleEmailMessage studentMail = firstByBody(STUDENT_MARKER);
            Assert.isTrue(studentMail.getSubject().contains(formatted(first)),
                'The subject must quote the earliest published session date. Subject='
                + studentMail.getSubject());
            Assert.isTrue(studentMail.getSubject().contains(formatted(last)),
                'The subject must quote the latest published session date. Subject='
                + studentMail.getSubject());
            Assert.isTrue(studentMail.getHtmlBody().contains('has been published'),
                'The student body must carry the ticket wording.');

            Messaging.SingleEmailMessage facultyMail = firstByBody(FACULTY_MARKER);
            Assert.isNotNull(facultyMail.getPlainTextBody(),
                'A plain-text alternative must always be built.');
            Assert.isFalse(facultyMail.getPlainTextBody().contains('<p>'),
                'The plain-text alternative must have its markup stripped. Text='
                + facultyMail.getPlainTextBody());
        }
    }

    /**
     * @description No must publish the sessions and email nobody. This is also the Programme
     *          Office's off switch, which is why the copy needs no separate active flag.
     */
    @IsTest
    static void publishNoSendsNothingButStillPublishes() {
        System.runAs(currentUser()) {
            disableCalendarPush();
            allowMissingSender();
            Scenario sc = buildScenario('b', new List<Date>{ Date.today().addDays(3) });
            if (sc == null) {
                Assert.isTrue(true, 'Managed EDA setup unavailable; skipping.');
                return;
            }
            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Test.startTest();
            publish(sc, false);
            Test.stopTest();

            Assert.areEqual(0, SessionPublishSummaryEmailQueueable.sentMessages.size(),
                'Answering No must not send any email.');
            Session__c after = [
                SELECT Schedule_Type__c FROM Session__c WHERE Id = :sc.sessionIds[0]
            ];
            Assert.areEqual('Published', after.Schedule_Type__c,
                'Answering No must still publish the session.');
        }
    }

    /**
     * @description A recipient with no contact behind the Person Account falls back to a direct
     *          to-address, and a recipient with no name falls back to the generic greeting. Also
     *          covers null dates merging to an empty string rather than throwing.
     */
    @IsTest
    static void fallbackGreetingAddressAndNullDatesAreHandled() {
        System.runAs(currentUser()) {
            allowMissingSender();
            SessionPublishSummaryEmailQueueable.Recipient anonymous =
                new SessionPublishSummaryEmailQueueable.Recipient();
            anonymous.email = 'anonymous@example.com';

            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Test.startTest();
            SessionPublishSummaryEmailQueueable job = new SessionPublishSummaryEmailQueueable(
                new List<SessionPublishSummaryEmailQueueable.Recipient>{ anonymous },
                new List<SessionPublishSummaryEmailQueueable.Recipient>(),
                null,
                null
            );
            job.execute(null);
            Test.stopTest();

            Assert.areEqual(1, SessionPublishSummaryEmailQueueable.sentMessages.size(),
                'The continuation job must send the recipient it was handed.');
            Messaging.SingleEmailMessage mail = SessionPublishSummaryEmailQueueable.sentMessages[0];
            Assert.areEqual(new List<String>{ 'anonymous@example.com' }, mail.getToAddresses(),
                'With no contact id the message must fall back to a direct to-address.');
            Assert.isTrue(mail.getHtmlBody().contains('Dear Student,'),
                'A nameless student must get the generic greeting. Body=' + mail.getHtmlBody());
            Assert.areEqual('Session Schedule Published:  to ', mail.getSubject(),
                'Null dates must merge to an empty string rather than throwing.');
        }
    }

    /**
     * @description An empty publication must not send anything, and must not throw.
     */
    @IsTest
    static void emptyPublicationSendsNothing() {
        System.runAs(currentUser()) {
            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Test.startTest();
            SessionPublishSummaryEmailQueueable job = new SessionPublishSummaryEmailQueueable(
                new Set<Id>(), Date.today(), Date.today().addDays(1)
            );
            job.execute(null);
            Test.stopTest();

            Assert.areEqual(0, SessionPublishSummaryEmailQueueable.sentMessages.size(),
                'A publication with no sessions has no audience and must send nothing.');
        }
    }

    /**
     * @description An address matching no verified Organization-Wide Email Address must resolve to
     *          no sender id, rather than throwing at the lookup itself.
     */
    @IsTest
    static void unknownSenderAddressResolvesToNoOrgWideId() {
        System.runAs(currentUser()) {
            Test.startTest();
            Id resolved = SessionPublishSummaryEmailQueueable.resolveSenderId(
                'not-a-real-owa@example.invalid'
            );
            Test.stopTest();

            Assert.isNull(resolved,
                'An unverified or unknown sender address must resolve to null.');
        }
    }

    /**
     * @description These emails may come ONLY from the Programme Office org-wide address — never
     *          from whichever staff member happened to click Publish. With no verified sender
     *          available the job must fail loudly rather than send from a person, so the failure is
     *          visible under Setup > Apex Jobs and nothing misleading reaches students or faculty.
     */
    @IsTest
    static void senderIsRequiredWhenUnverified() {
        System.runAs(currentUser()) {
            SessionPublishSummaryEmailQueueable.Recipient r =
                new SessionPublishSummaryEmailQueueable.Recipient();
            r.email    = 'someone@example.com';
            r.greeting = 'Someone';

            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Boolean threw = false;
            String message = '';
            Test.startTest();
            try {
                new SessionPublishSummaryEmailQueueable(
                    new List<SessionPublishSummaryEmailQueueable.Recipient>{ r },
                    new List<SessionPublishSummaryEmailQueueable.Recipient>(),
                    Date.today(),
                    Date.today().addDays(1)
                ).execute(null);
            } catch (SessionPublishSummaryEmailQueueable.SenderNotConfiguredException e) {
                threw = true;
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.isTrue(threw,
                'With no verified org-wide sender the job must throw, not fall back to the user.');
            Assert.isTrue(message.contains('Organization-Wide Email Address'),
                'The failure must tell an admin exactly what to create. Message=' + message);
            Assert.areEqual(0, SessionPublishSummaryEmailQueueable.sentMessages.size(),
                'Nothing may be sent when there is no valid sender.');
        }
    }
}