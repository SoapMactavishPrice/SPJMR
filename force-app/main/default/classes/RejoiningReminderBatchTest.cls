/**
 * @description Tests for RejoiningReminderBatch and RejoiningReminderScheduler.
 *              Covers the 30-day reminder, the nightly missing-date chaser,
 *              requests that must be ignored, a student with no alternate
 *              e-mail and a programme with no Programme Office member.
 *
 *              Stored templates are created inside the test transaction and the
 *              batch is pointed at them, so the tests never depend on org data.
 */
@IsTest
private class RejoiningReminderBatchTest {

    private static final Integer REMINDER_DAYS = 30;
    private static final String TPL_STUDENT = 'Test_Rejoining_Student';
    private static final String TPL_OFFICE = 'Test_Rejoining_Office';
    private static final String TPL_NOTICE = 'Test_Return_To_Campus';

    /**
     * @description Creates the three stored templates the batch renders and
     *              points the batch at them. EmailTemplate is a setup object,
     *              so the insert is isolated inside System.runAs to avoid a
     *              mixed-DML error alongside the Account and Programme inserts.
     */
    private static void createTemplates() {

        User runner = new User(Id = UserInfo.getUserId());

        System.runAs(runner) {

            List<EmailTemplate> templates = new List<EmailTemplate>();

            for (String developerName : new List<String>{
                TPL_STUDENT,
                TPL_OFFICE,
                TPL_NOTICE
            }) {
                templates.add(new EmailTemplate(
                    DeveloperName = developerName,
                    Name = developerName,
                    FolderId = UserInfo.getUserId(),
                    TemplateType = 'text',
                    Subject = 'Rejoining - {!Deferment_Request__c.Name}',
                    Body = 'Rejoining Date: {!Deferment_Request__c.Rejoining_Date__c}',
                    IsActive = true
                ));
            }

            insert templates;
        }

        RejoiningReminderBatch.tplStudent = TPL_STUDENT;
        RejoiningReminderBatch.tplOffice = TPL_OFFICE;
        RejoiningReminderBatch.tplNotice = TPL_NOTICE;
    }

    /**
     * @description Builds a programme, optionally with a Programme Office member.
     * @param suffix unique suffix for the programme's required codes
     * @param withOffice true to attach a Programme Office team member
     * @return the inserted Program
     */
    private static Program buildProgramme(String suffix, Boolean withOffice) {

        Program programme = new Program(
            Name = 'Test Programme ' + suffix,
            Program_Code__c = 'TP' + suffix,
            Short_Programme_Code__c = 'T' + suffix,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room'
        );
        insert programme;

        if (!withOffice) {
            return programme;
        }

        Program_Team__c team = new Program_Team__c(Program__c = programme.Id);
        insert team;

        insert new Program_Team_Members__c(
            Program_Team__c = team.Id,
            User__c = UserInfo.getUserId(),
            Role__c = 'Programme Office'
        );

        return programme;
    }

    /**
     * @description Builds a student person account via the org's shared factory,
     *              then stamps the alternate e-mail this batch reads.
     * @param tag unique suffix so each account's duplicate-check keys differ
     * @param alternateEmail the alternate e-mail, or null to leave it blank
     * @return the inserted Account
     */
    private static Account buildStudent(String tag, String alternateEmail) {

        Account student =
            SpjimrPortalTestDataFactory.buildLearnerPersonAccount(tag);

        student.Alternate_E_mail__c = alternateEmail;
        update student;

        return student;
    }

    /**
     * @description Builds a Deferment Request.
     * @param student the student account
     * @param programme the programme
     * @param rejoiningDate the rejoining date, or null
     * @param approvalStatus the Approval_Status__c value
     * @return the inserted record
     */
    private static Deferment_Request__c buildRequest(
        Account student,
        Program programme,
        Date rejoiningDate,
        String approvalStatus
    ) {
        return buildRequest(
            student,
            programme,
            rejoiningDate,
            approvalStatus,
            null
        );
    }

    /**
     * @description Builds a Deferment Request at a given tracker status.
     * @param student the student account
     * @param programme the programme
     * @param rejoiningDate the rejoining date, or null
     * @param approvalStatus the Approval_Status__c value
     * @param status the Status__c value, or null to leave it blank
     * @return the inserted record
     */
    private static Deferment_Request__c buildRequest(
        Account student,
        Program programme,
        Date rejoiningDate,
        String approvalStatus,
        String status
    ) {
        Deferment_Request__c request = new Deferment_Request__c(
            Account__c = student.Id,
            Programme__c = programme.Id,
            Rejoining_Date__c = rejoiningDate,
            Approval_Status__c = approvalStatus,
            Status__c = status
        );
        insert request;

        return request;
    }

    /**
     * @description Re-reads one request's stored status.
     * @param requestId the record to re-read
     * @return the stored Status__c value
     */
    private static String storedStatus(Id requestId) {

        return [
            SELECT Status__c
            FROM Deferment_Request__c
            WHERE Id = :requestId
        ].Status__c;
    }

    /**
     * @description Runs the batch and returns the messages it built.
     * @return the outbox from the last execute(), never null
     */
    private static List<Messaging.SingleEmailMessage> runBatch() {

        Test.startTest();
        Database.executeBatch(new RejoiningReminderBatch(), 50);
        Test.stopTest();

        return RejoiningReminderBatch.lastOutbox == null
            ? new List<Messaging.SingleEmailMessage>()
            : RejoiningReminderBatch.lastOutbox;
    }

    @IsTest
    static void sendsStudentAndOfficeMailThirtyDaysOut() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('01', true);
            Account student = buildStudent('rj01', 'due.student@example.com');
            buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS),
                'Approved'
            );

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                2,
                outbox.size(),
                'Student and Programme Office should each receive one e-mail.'
            );

            Set<String> recipients = new Set<String>();

            for (Messaging.SingleEmailMessage mail : outbox) {
                recipients.addAll(mail.getToAddresses());
            }

            System.assertEquals(
                true,
                recipients.contains('due.student@example.com'),
                'The student alternate e-mail should be addressed.'
            );

            System.assertEquals(
                true,
                recipients.contains(UserInfo.getUserEmail()),
                'The Programme Office member should be addressed.'
            );
        }
    }

    @IsTest
    static void raisesBellAndNoEmailWhenRejoiningDateMissing() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('02', true);
            Account student = buildStudent('rj02', 'nodate@example.com');
            buildRequest(student, programme, null, 'Approved');

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                0,
                outbox.size(),
                'A missing Rejoining Date raises a bell, never an e-mail.'
            );
        }
    }

    @IsTest
    static void countsMissingDatesPerProgrammeForOneBellEach() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('07', true);
            Account student = buildStudent('rj07', 'multi@example.com');

            for (Integer i = 0; i < 3; i++) {
                buildRequest(student, programme, null, 'Approved');
            }

            Test.startTest();
            Database.executeBatch(new RejoiningReminderBatch(), 50);
            Test.stopTest();

            System.assertEquals(
                0,
                RejoiningReminderBatch.lastOutbox == null
                    ? 0
                    : RejoiningReminderBatch.lastOutbox.size(),
                'Three undated requests should produce no e-mail at all.'
            );
        }
    }

    @IsTest
    static void bellIsSkippedWhenNotificationTypeIsAbsent() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            RejoiningReminderBatch.notificationTypeName = 'No_Such_Notification_Type';

            Program programme = buildProgramme('08', true);
            Account student = buildStudent('rj08', 'notype@example.com');
            buildRequest(student, programme, null, 'Approved');

            System.assertEquals(
                0,
                runBatch().size(),
                'A missing notification type should not raise an error or an e-mail.'
            );
        }
    }

    @IsTest
    static void sendsReturnToCampusNoticeThreeMonthsOut() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('09', true);
            Account student = buildStudent('rj09', 'notice@example.com');
            buildRequest(
                student,
                programme,
                Date.today().addMonths(3),
                'Approved'
            );

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                1,
                outbox.size(),
                'The three-month notice goes to the student only.'
            );

            System.assertEquals(
                'notice@example.com',
                outbox[0].getToAddresses()[0],
                'The Return to Campus notice is addressed to the student.'
            );
        }
    }

    @IsTest
    static void ignoresRequestBetweenTheTwoWindows() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('10', true);
            Account student = buildStudent('rj10', 'between@example.com');
            buildRequest(
                student,
                programme,
                Date.today().addDays(60),
                'Approved'
            );

            System.assertEquals(
                0,
                runBatch().size(),
                'A request 60 days out falls between both windows.'
            );
        }
    }

    @IsTest
    static void ignoresRequestOutsideTheWindow() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('03', true);
            Account student = buildStudent('rj03', 'far@example.com');
            buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS + 1),
                'Approved'
            );

            System.assertEquals(
                0,
                runBatch().size(),
                'A request 31 days out should not be mailed.'
            );
        }
    }

    @IsTest
    static void ignoresUnapprovedRequestWithNoDate() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('04', true);
            Account student = buildStudent('rj04', 'pending@example.com');
            buildRequest(student, programme, null, 'Pending');

            System.assertEquals(
                0,
                runBatch().size(),
                'Only approved requests should be chased for a missing date.'
            );
        }
    }

    @IsTest
    static void skipsStudentWithNoAlternateEmail() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('05', true);
            Account student = buildStudent('rj05', null);
            buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS),
                'Approved'
            );

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                1,
                outbox.size(),
                'Programme Office is still mailed when the student has no address.'
            );

            System.assertEquals(
                UserInfo.getUserEmail(),
                outbox[0].getToAddresses()[0],
                'The surviving message should be the Programme Office one.'
            );
        }
    }

    @IsTest
    static void skipsProgrammeWithNoOfficeMember() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('06', false);
            Account student = buildStudent('rj06', 'orphan@example.com');
            buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS),
                'Approved'
            );

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                1,
                outbox.size(),
                'Only the student is mailed when no Programme Office member exists.'
            );

            System.assertEquals(
                'orphan@example.com',
                outbox[0].getToAddresses()[0],
                'The surviving message should be the student one.'
            );
        }
    }

    @IsTest
    static void schedulerRegistersAndAbortsNightlyJob() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            Test.startTest();
            RejoiningReminderScheduler.scheduleAll();
            Test.stopTest();

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM CronTrigger
                    WHERE CronJobDetail.Name = 'Rejoining_Reminder_Nightly'
                ],
                'The nightly reminder job should be registered exactly once.'
            );

            RejoiningReminderScheduler.abortAll();

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM CronTrigger
                    WHERE CronJobDetail.Name = 'Rejoining_Reminder_Nightly'
                ],
                'abortAll should clear the scheduled job.'
            );
        }
    }

    @IsTest
    static void skipsWithdrawnRequestWithNoRejoiningDate() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('09', true);
            Account student = buildStudent('rj09', 'gone@example.com');

            buildRequest(student, programme, null, 'Approved', 'Withdrawal');

            Test.startTest();
            Database.executeBatch(new RejoiningReminderBatch(), 50);
            Test.stopTest();

            System.assertEquals(
                0,
                RejoiningReminderBatch.lastOutbox == null
                    ? 0
                    : RejoiningReminderBatch.lastOutbox.size(),
                'A withdrawn student must not generate any mail.'
            );

            System.assertEquals(
                0,
                [
                    SELECT COUNT()
                    FROM Deferment_Request__c
                    WHERE Programme__c = :programme.Id
                    AND Status__c != 'Withdrawal'
                ],
                'The withdrawn request is the only one on this programme, so the batch has nothing to chase.'
            );
        }
    }

    @IsTest
    static void skipsWithdrawnRequestThatIsOtherwiseDueAReminder() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('10', true);
            Account student = buildStudent('rj10', 'quit@example.com');

            buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS),
                'Approved',
                'Withdrawal'
            );

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                0,
                outbox.size(),
                'A withdrawn student due a 30-day reminder must still be skipped.'
            );
        }
    }

    @IsTest
    static void stillChasesRequestsThatAreNotWithdrawn() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            Program programme = buildProgramme('11', true);
            Account student = buildStudent('rj11', 'staying@example.com');

            buildRequest(student, programme, null, 'Approved', 'Pending Re-enrollment');
            buildRequest(student, programme, null, 'Approved', 'Withdrawal');

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                0,
                outbox.size(),
                'Missing dates raise a bell, never an e-mail.'
            );

            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM Deferment_Request__c
                    WHERE Programme__c = :programme.Id
                    AND Status__c != 'Withdrawal'
                    AND Rejoining_Date__c = null
                    AND Approval_Status__c = 'Approved'
                ],
                'Exactly one of the two requests should still be in scope for the bell.'
            );
        }
    }

    @IsTest
    static void stampsStatusWhenThirtyDayReminderIsSent() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            RejoiningReminderBatch.assumeSendSucceeded = true;
            Program programme = buildProgramme('12', true);
            Account student = buildStudent('rj12', 'stamped@example.com');

            Deferment_Request__c request = buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS),
                'Approved',
                'Pending Re-enrollment'
            );

            runBatch();

            System.assertEquals(
                'Return to Campus Notification Sent',
                storedStatus(request.Id),
                'Sending the 30-day reminder should stamp the tracker.'
            );
        }
    }

    @IsTest
    static void leavesStatusAloneWhenStudentHasNoAddress() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            RejoiningReminderBatch.assumeSendSucceeded = true;
            Program programme = buildProgramme('13', true);
            Account student = buildStudent('rj13', null);

            Deferment_Request__c request = buildRequest(
                student,
                programme,
                Date.today().addDays(REMINDER_DAYS),
                'Approved',
                'Pending Re-enrollment'
            );

            runBatch();

            System.assertEquals(
                'Pending Re-enrollment',
                storedStatus(request.Id),
                'No student e-mail means no notification, so no stamp.'
            );
        }
    }

    @IsTest
    static void doesNotStampOnTheThreeMonthNotice() {

        System.runAs(new User(Id = UserInfo.getUserId())) {

            createTemplates();
            RejoiningReminderBatch.assumeSendSucceeded = true;
            Program programme = buildProgramme('14', true);
            Account student = buildStudent('rj14', 'notice@example.com');

            Deferment_Request__c request = buildRequest(
                student,
                programme,
                Date.today().addMonths(3),
                'Approved',
                'Pending Re-enrollment'
            );

            List<Messaging.SingleEmailMessage> outbox = runBatch();

            System.assertEquals(
                1,
                outbox.size(),
                'The three-month notice goes to the student only.'
            );

            System.assertEquals(
                'Pending Re-enrollment',
                storedStatus(request.Id),
                'Only the 30-day reminder stamps the tracker.'
            );
        }
    }
}