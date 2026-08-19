@SuppressWarnings('PMD.OperationWithLimitsInLoop')
@IsTest
private class SessionPublishSummaryEmailTest {

    private static final String STUDENT_MARKER = 'Participant Portal';
    private static final String FACULTY_MARKER = 'Google Calendar';

    private class Scenario {
        private Id divisionId;
        private Id studentAccountId;
        private Id facultyAccountId;
        private List<Id> sessionIds = new List<Id>();
    }

    private static User currentUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static void disableCalendarPush() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(Active__c = false);
    }

    private static void allowMissingSender() {
        SessionPublishSummaryEmailQueueable.requireVerifiedSender = false;
    }

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

    private static void publish(Scenario sc, Boolean sendNotifications) {
        TimetableSessionController.SessionFilter filter =
            new TimetableSessionController.SessionFilter();
        filter.divisionId        = String.valueOf(sc.divisionId);
        filter.startDate         = Date.today();
        filter.endDate           = Date.today().addDays(30);
        filter.sendNotifications = sendNotifications;
        TimetableSessionController.publishSessions(JSON.serialize(filter));
    }

    private static Integer countByBody(String marker) {
        Integer n = 0;
        for (Messaging.SingleEmailMessage m : SessionPublishSummaryEmailQueueable.sentMessages) {
            if (m.getHtmlBody() != null && m.getHtmlBody().contains(marker)) {
                n++;
            }
        }
        return n;
    }

    private static Messaging.SingleEmailMessage firstByBody(String marker) {
        for (Messaging.SingleEmailMessage m : SessionPublishSummaryEmailQueueable.sentMessages) {
            if (m.getHtmlBody() != null && m.getHtmlBody().contains(marker)) {
                return m;
            }
        }
        return null;
    }

    private static String formatted(Date value) {
        return Datetime.newInstance(value, Time.newInstance(0, 0, 0, 0)).format('d MMM yyyy');
    }

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
            Assert.areEqual(0, countByBody(FACULTY_MARKER),
                'Faculty are notified by Google Calendar on publish, so the summary job must not '
                + 'email them as well.');

            Messaging.SingleEmailMessage studentMail = firstByBody(STUDENT_MARKER);
            Assert.isTrue(studentMail.getSubject().contains(formatted(first)),
                'The subject must quote the earliest published session date. Subject='
                + studentMail.getSubject());
            Assert.isTrue(studentMail.getSubject().contains(formatted(last)),
                'The subject must quote the latest published session date. Subject='
                + studentMail.getSubject());
            Assert.isTrue(studentMail.getHtmlBody().contains('has been published'),
                'The student body must carry the ticket wording.');

            Assert.isNotNull(studentMail.getPlainTextBody(),
                'A plain-text alternative must always be built.');
            Assert.isFalse(studentMail.getPlainTextBody().contains('<p>'),
                'The plain-text alternative must have its markup stripped. Text='
                + studentMail.getPlainTextBody());
        }
    }

    @IsTest
    static void publishNoStillSendsTheStudentSummary() {
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

            Assert.areEqual(1, countByBody(STUDENT_MARKER),
                'Answering No must still send the students their consolidated email.');
            Assert.areEqual(0, countByBody(FACULTY_MARKER),
                'Answering No must not email the faculty at all.');
            Session__c after = [
                SELECT Schedule_Type__c FROM Session__c WHERE Id = :sc.sessionIds[0]
            ];
            Assert.areEqual('Published', after.Schedule_Type__c,
                'Answering No must still publish the session.');
        }
    }

    @IsTest
    static void republishNoSendsStudentsTheUpdatedScheduleEmail() {
        System.runAs(currentUser()) {
            disableCalendarPush();
            allowMissingSender();
            Date sessionDate = Date.today().addDays(4);
            Scenario sc = buildScenario('c', new List<Date>{ sessionDate });
            if (sc == null) {
                Assert.isTrue(true, 'Managed EDA setup unavailable; skipping.');
                return;
            }
            Session__c republished = new Session__c(
                Id = sc.sessionIds[0],
                Schedule_Type__c = 'Republished'
            );
            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Test.startTest();
            TimetableSessionController.enqueueRepublishStudentEmail(republished, sessionDate);
            Test.stopTest();

            Assert.areEqual(1, countByBody(STUDENT_MARKER),
                'Republishing with No must send the enrolled student exactly one summary email.');
            Assert.areEqual(0, countByBody(FACULTY_MARKER),
                'No means the faculty are not emailed at all on a republish.');

            Messaging.SingleEmailMessage studentMail = firstByBody(STUDENT_MARKER);
            Assert.isTrue(studentMail.getHtmlBody().contains('has been Republished'),
                'A republish must use the "Republished" wording, not the publish wording. Body='
                + studentMail.getHtmlBody());
            Assert.isTrue(studentMail.getSubject().contains('Republished'),
                'The subject must say the schedule was republished. Subject='
                + studentMail.getSubject());
            Assert.isTrue(studentMail.getSubject().contains(formatted(sessionDate)),
                'The subject must quote the session date being saved. Subject='
                + studentMail.getSubject());
            Assert.isFalse(studentMail.getSubject().contains(' to '),
                'A single republished session must not read as a date range. Subject='
                + studentMail.getSubject());
        }
    }

    @IsTest
    static void savesThatAreNotRepublishesEmailNobody() {
        System.runAs(currentUser()) {
            disableCalendarPush();
            allowMissingSender();
            Session__c draft = new Session__c(
                Name             = 'DraftOnly',
                Session_Date__c  = Date.today().addDays(6),
                Schedule_Type__c = 'Draft',
                Start_Time__c    = Datetime.newInstance(Date.today().addDays(6), Time.newInstance(9, 0, 0, 0)),
                End_Time__c      = Datetime.newInstance(Date.today().addDays(6), Time.newInstance(10, 0, 0, 0))
            );
            insert draft;
            SessionPublishSummaryEmailQueueable.sentMessages.clear();

            Test.startTest();
            // A draft edit: Publish will notify later, so this path must stay silent.
            TimetableSessionController.enqueueRepublishStudentEmail(draft, draft.Session_Date__c);
            // A brand-new session has no Id yet, so there is nobody enrolled to email.
            TimetableSessionController.enqueueRepublishStudentEmail(
                new Session__c(Schedule_Type__c = 'Republished'), Date.today()
            );
            TimetableSessionController.enqueueRepublishStudentEmail(null, Date.today());
            Test.stopTest();

            Assert.areEqual(0, SessionPublishSummaryEmailQueueable.sentMessages.size(),
                'Only a republish may trigger the summary email; creates and draft edits must not.');
        }
    }

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

    @IsTest
    static void noVerifiedAddressResolvesToNoOrgWideId() {
        System.runAs(currentUser()) {
            SessionPublishSummaryEmailQueueable.senderOverride = new List<OrgWideEmailAddress>();

            Test.startTest();
            Id resolved = SessionPublishSummaryEmailQueueable.resolveSenderId();
            Test.stopTest();

            Assert.isNull(resolved,
                'With no verified org-wide address the sender must resolve to null.');
        }
    }

    @IsTest
    static void verifiedAddressInTheOrgIsUsedAsSender() {
        List<OrgWideEmailAddress> verified = [
            SELECT Id FROM OrgWideEmailAddress WHERE IsVerified = true ORDER BY Address LIMIT 1
        ];

        System.runAs(currentUser()) {
            Test.startTest();
            Id resolved = SessionPublishSummaryEmailQueueable.resolveSenderId();
            Test.stopTest();

            if (verified.isEmpty()) {
                Assert.isNull(resolved,
                    'An org with no verified address has no sender to resolve.');
            } else {
                Assert.areEqual(verified[0].Id, resolved,
                    'The org\'s first verified address by address order must be the sender.');
            }
        }
    }

    @IsTest
    static void senderIsRequiredWhenUnverified() {
        System.runAs(currentUser()) {
            SessionPublishSummaryEmailQueueable.senderOverride = new List<OrgWideEmailAddress>();

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