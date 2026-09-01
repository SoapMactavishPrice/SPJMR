/**
 * @description TEMPORARY test harness for UAT of the Student Deferment process
 *              (Step 4 - "Apply for Deferment on ERP").
 *
 *              Runs the real DefermentRequestController against the real org
 *              data as the real student portal user, because Step 4 can only be
 *              exercised by a user whose User record is linked to the student's
 *              Account. Nothing here is part of the deferment feature - delete
 *              this class once testing is finished.
 *
 *              SeeAllData is on deliberately: the point is to test against the
 *              live Programme Team routing, the live approval process and the
 *              live Deferment Request, not against a synthetic copy.
 */
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts,PMD.ApexAssertionsShouldIncludeMessage')
@IsTest(SeeAllData=true)
public class TempDefermentStep4Harness {

    /** Dannel George's student portal user. */
    private static final Id STUDENT_USER_ID = '005C1000006b293IAA';

    /** DR-00171 - the request opened for Dannel George at Step 3. */
    private static final Id REQUEST_ID = 'a4xC1000000C5yPIAS';

    private static final String DOC_SUPPORT = 'Documents to Support Request';
    private static final String DOC_APPROVAL = 'Approval Email';
    private static final String DOC_ACCEPT = 'Rejoining Condition Acceptance';
    private static final String DOC_TXN = 'Transaction Details';

    /**
     * @description Builds the JSON payload the portal screen sends on submit.
     * @param reason the Reason for Deferment typed by the student
     * @param docTypes the document types the student attached
     * @return the serialized request the controller expects
     */
    private static String payload(String reason, List<String> docTypes) {

        List<Map<String, Object>> files = new List<Map<String, Object>>();

        for (String docType : docTypes) {
            files.add(new Map<String, Object>{
                'documentType' => docType,
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('test file content')),
                'fileName' => docType + '.pdf'
            });
        }

        return JSON.serialize(new Map<String, Object>{
            'defermentRequestId' => REQUEST_ID,
            'reason' => reason,
            'files' => files
        });
    }

    /**
     * @description Runs one submission as the student and reports the outcome.
     * @param label the scenario name shown in the log
     * @param reason the Reason for Deferment
     * @param docTypes the document types attached
     */
    private static void submitAs(String label, String reason, List<String> docTypes) {

        User student = [SELECT Id FROM User WHERE Id = :STUDENT_USER_ID];

        Boolean accepted = false;
        String failedAt = '';

        System.runAs(student) {
            try {
                DefermentRequestController.submitDefermentRequest(
                    payload(reason, docTypes)
                );
                accepted = true;
            } catch (Exception ex) {
                failedAt = ex.getMessage() + ' @@ ' +
                    ex.getStackTraceString().split('\n')[0];
            }
        }

        if (accepted) {
            Deferment_Request__c after = [
                SELECT Status__c, Current_Role__c, Approval_Status__c,
                       Student_Submission_Date__c
                FROM Deferment_Request__c
                WHERE Id = :REQUEST_ID
            ];
            System.debug(LoggingLevel.ERROR,
                'HARNESS|' + label + '|ACCEPTED|status=' + after.Status__c +
                '|role=' + after.Current_Role__c +
                '|approval=' + after.Approval_Status__c);
        } else {
            System.debug(LoggingLevel.ERROR,
                'HARNESS|' + label + '|REJECTED|' + failedAt);
        }
    }

    /** @description What the student sees when the window is open. */
    @IsTest
    static void a1WindowVisibleToStudent() {

        User student = [SELECT Id FROM User WHERE Id = :STUDENT_USER_ID];

        System.runAs(student) {
            DefermentRequestController.DefermentRequestWrapper w =
                DefermentRequestController.getActiveDefermentRequest();

            System.debug(LoggingLevel.ERROR,
                'HARNESS|A1 window shown to student|' + w.requestNumber +
                '|windowStatus=' + w.windowStatus +
                '|fee=' + w.fee +
                '|message=' + w.windowMessage);
        }
    }

    /** @description Happy path - all mandatory documents, fee is zero. */
    @IsTest
    static void a2HappyPath() {
        submitAs('A2 happy path (3 docs, fee 0)', 'Medical treatment requiring a year away.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description Reason left blank. */
    @IsTest
    static void a3BlankReason() {
        submitAs('A3 blank reason', '',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description Supporting documents not attached. */
    @IsTest
    static void a4MissingSupportingDocs() {
        submitAs('A4 no supporting documents', 'Medical treatment.',
            new List<String>{ DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description Approval email screenshot not attached. */
    @IsTest
    static void a5MissingApprovalEmail() {
        submitAs('A5 no approval email screenshot', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_ACCEPT });
    }

    /** @description Rejoining condition acceptance not attached. */
    @IsTest
    static void a6MissingAcceptance() {
        submitAs('A6 no rejoining acceptance screenshot', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL });
    }

    /**
     * @description Fee is zero, so Transaction Details must be treated as Not
     *              Applicable - submitting without it must still be accepted.
     */
    @IsTest
    static void a7ZeroFeeNeedsNoTransaction() {
        submitAs('A7 fee zero, no transaction screenshot', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /**
     * @description Fee is payable, but the student attaches no transaction
     *              screenshot. Must be refused.
     */
    @IsTest
    static void a8FeePayableNoTransaction() {

        Deferment_Request__c req = [
            SELECT Id, Deferment_Application_Fee__c
            FROM Deferment_Request__c WHERE Id = :REQUEST_ID
        ];
        req.Deferment_Application_Fee__c = 25000;
        update req;

        submitAs('A8 fee 25000, no transaction screenshot', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description The same student submits a second time straight away. */
    @IsTest
    static void a9DoubleSubmission() {
        submitAs('A9 first submission', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
        submitAs('A9 second submission (duplicate)', 'Medical treatment, edited.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description The application window has already closed. */
    @IsTest
    static void b1WindowExpired() {

        Deferment_Request__c req = [
            SELECT Id, Break_Start_Date_Time__c, Break_End_Date_Time__c
            FROM Deferment_Request__c WHERE Id = :REQUEST_ID
        ];
        req.Break_Start_Date_Time__c = Datetime.now().addDays(-10);
        req.Break_End_Date_Time__c = Datetime.now().addDays(-1);
        update req;

        User student = [SELECT Id FROM User WHERE Id = :STUDENT_USER_ID];
        System.runAs(student) {
            DefermentRequestController.DefermentRequestWrapper w =
                DefermentRequestController.getActiveDefermentRequest();
            System.debug(LoggingLevel.ERROR,
                'HARNESS|B1 expired window shown as|' + w.windowStatus +
                '|' + w.windowMessage);
        }

        submitAs('B1 submit after window closed', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description The window has not opened yet. */
    @IsTest
    static void b2WindowNotStarted() {

        Deferment_Request__c req = [
            SELECT Id, Break_Start_Date_Time__c, Break_End_Date_Time__c
            FROM Deferment_Request__c WHERE Id = :REQUEST_ID
        ];
        req.Break_Start_Date_Time__c = Datetime.now().addDays(5);
        req.Break_End_Date_Time__c = Datetime.now().addDays(7);
        update req;

        User student = [SELECT Id FROM User WHERE Id = :STUDENT_USER_ID];
        System.runAs(student) {
            DefermentRequestController.DefermentRequestWrapper w =
                DefermentRequestController.getActiveDefermentRequest();
            System.debug(LoggingLevel.ERROR,
                'HARNESS|B2 not-yet-open window shown as|' + w.windowStatus +
                '|' + w.windowMessage);
        }

        submitAs('B2 submit before window opens', 'Medical treatment.',
            new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT });
    }

    /** @description A different student tries to submit this student's request. */
    @IsTest
    static void b3WrongStudent() {

        List<User> others = [
            SELECT Id FROM User
            WHERE IsActive = true
            AND AccountId != null
            AND Id != :STUDENT_USER_ID
            AND Profile.Name = 'SPJIMR Student Portal User'
            LIMIT 1
        ];

        if (others.isEmpty()) {
            System.debug(LoggingLevel.ERROR,
                'HARNESS|B3 wrong student|SKIPPED - no second portal user');
            return;
        }

        System.runAs(others[0]) {
            try {
                DefermentRequestController.submitDefermentRequest(
                    payload('Trying to hijack another student request.',
                        new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT })
                );
                System.debug(LoggingLevel.ERROR,
                    'HARNESS|B3 wrong student|ACCEPTED - SECURITY HOLE');
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'HARNESS|B3 wrong student|REJECTED|' +
                    ex.getStackTraceString().split('\n')[0]);
            }
        }
    }

    /**
     * @description Step 7 - can a real (non-admin) Programme Manager still fill
     *              in the Rejoining Date after the request has been finally
     *              approved, given the approval process locks the record?
     */
    @IsTest
    static void c1ProgrammeManagerEditsAfterApproval() {

        for (Id pmId : new List<Id>{ '005C1000007ySmzIAE', '005C1000005ZvYPIA0' }) {

            User pm = [SELECT Id, Name, Profile.Name FROM User WHERE Id = :pmId];

            System.runAs(pm) {
                try {
                    update new Deferment_Request__c(
                        Id = 'a4xC1000000C6PpIAK',
                        Rejoining_Date__c = Date.today().addMonths(12),
                        Current_Batch_Fee__c = 1800000,
                        Next_Batch_Fee__c = 1950000
                    );
                    System.debug(LoggingLevel.ERROR,
                        'HARNESS|C1 Step 7 as ' + pm.Name + ' (' + pm.Profile.Name +
                        ')|ALLOWED - rejoining date saved');
                } catch (Exception ex) {
                    System.debug(LoggingLevel.ERROR,
                        'HARNESS|C1 Step 7 as ' + pm.Name + ' (' + pm.Profile.Name +
                        ')|BLOCKED|' + ex.getMessage());
                }
            }
        }
    }

    /**
     * @description Runs the nightly rejoining job over the 30-day reminder case
     *              and reports exactly what it put in the outbox, using the
     *              batch's own test hooks.
     */
    @IsTest
    static void d1ThirtyDayReminderOutbox() {

        update new Deferment_Request__c(
            Id = 'a4xC1000000C5yPIAS',
            Rejoining_Date__c = Date.today().addDays(30),
            Status__c = 'Pending Re-enrollment'
        );

        List<Deferment_Request__c> scope = [
            SELECT Id, Name, Status__c, Rejoining_Date__c, Programme__c, Account__c,
                   Account__r.Alternate_E_mail__c, Account__r.PersonContactId
            FROM Deferment_Request__c
            WHERE Id = 'a4xC1000000C5yPIAS'
        ];

        RejoiningReminderBatch.assumeSendSucceeded = true;
        RejoiningReminderBatch job = new RejoiningReminderBatch();

        Test.startTest();
        job.execute(null, scope);
        Test.stopTest();

        Integer queued = RejoiningReminderBatch.lastOutbox == null
            ? -1 : RejoiningReminderBatch.lastOutbox.size();

        System.debug(LoggingLevel.ERROR,
            'HARNESS|D1 30-day outbox|messages queued=' + queued);

        if (queued > 0) {
            for (Messaging.SingleEmailMessage m : RejoiningReminderBatch.lastOutbox) {
                System.debug(LoggingLevel.ERROR,
                    'HARNESS|D1 message|to=' + m.getToAddresses() +
                    '|subject=' + m.getSubject());
            }
        }

        System.debug(LoggingLevel.ERROR,
            'HARNESS|D1 status after|' +
            [SELECT Status__c FROM Deferment_Request__c
             WHERE Id = 'a4xC1000000C5yPIAS'].Status__c);
    }

    /**
     * @description Does a student's resubmission after a Level 2 (Dean/AD)
     *              rejection go back to Level 1, as section 8.1 of the process
     *              document requires, or straight back to Level 2?
     */
    @IsTest
    static void e1ResubmitAfterDeanRejection() {

        Id drId = 'a4xC1000000C6T3IAK';          // DR-00180 Ayush parashar
        Id studentUserId = '005C1000006xeE6IAI'; // Ayush's portal login

        Deferment_Request__c before = [
            SELECT Status__c, Current_Role__c, Approval_Status__c
            FROM Deferment_Request__c WHERE Id = :drId
        ];
        System.debug(LoggingLevel.ERROR, 'HARNESS|E1 before resubmit|status=' +
            before.Status__c + '|role=' + before.Current_Role__c +
            '|approval=' + before.Approval_Status__c);

        List<Map<String, Object>> files = new List<Map<String, Object>>();
        for (String docType : new List<String>{
                'Documents to Support Request', 'Approval Email',
                'Rejoining Condition Acceptance' }) {
            files.add(new Map<String, Object>{
                'documentType' => docType,
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('revised')),
                'fileName' => docType + '.pdf'
            });
        }
        String payload = JSON.serialize(new Map<String, Object>{
            'defermentRequestId' => drId,
            'reason' => 'Revised after the Dean rejected it. Resubmitting.',
            'files' => files
        });

        Boolean accepted = false;
        String failure = '';
        User student = [SELECT Id FROM User WHERE Id = :studentUserId];

        System.runAs(student) {
            try {
                DefermentRequestController.submitDefermentRequest(payload);
                accepted = true;
            } catch (Exception ex) {
                failure = ex.getStackTraceString().split('\n')[0];
            }
        }

        if (!accepted) {
            System.debug(LoggingLevel.ERROR,
                'HARNESS|E1 resubmit REFUSED|' + failure);
            return;
        }

        Deferment_Request__c after = [
            SELECT Status__c, Current_Role__c, Current_Approver_User__r.Name
            FROM Deferment_Request__c WHERE Id = :drId
        ];
        System.debug(LoggingLevel.ERROR, 'HARNESS|E1 after resubmit|status=' +
            after.Status__c + '|role=' + after.Current_Role__c +
            '|sitting with=' + after.Current_Approver_User__r.Name);

        // Asserted rather than logged, so the verdict comes back in the test
        // result even when debug logs are not being retained.
        Assert.areEqual(
            'Chairperson',
            after.Current_Role__c,
            'VERDICT: resubmission after a Dean rejection went to "' +
            after.Current_Role__c + '" (status "' + after.Status__c +
            '", sitting with ' + after.Current_Approver_User__r.Name +
            ') instead of restarting at Level 1 with the Chairperson'
        );
    }

    /**
     * @description Can the student still submit before their window opens?
     *              The portal says "not open yet"; this checks that the server
     *              agrees.
     */
    @IsTest
    static void f1WindowNotYetOpen() {

        // window opens in five days
        update new Deferment_Request__c(
            Id = REQUEST_ID,
            Break_Start_Date_Time__c = Datetime.now().addDays(5),
            Break_End_Date_Time__c = Datetime.now().addDays(7)
        );

        Boolean accepted = false;
        String failure = '';
        User student = [SELECT Id FROM User WHERE Id = :STUDENT_USER_ID];

        System.runAs(student) {
            try {
                DefermentRequestController.submitDefermentRequest(
                    payload('Trying to submit before the window opens.',
                        new List<String>{ DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT })
                );
                accepted = true;
            } catch (Exception ex) {
                failure = ex.getStackTraceString().split('\n')[0];
            }
        }

        Assert.isFalse(
            accepted,
            'VERDICT: a submission made BEFORE the window opened was accepted'
        );
        System.debug(LoggingLevel.ERROR,
            'HARNESS|F1 before window opens|REFUSED|' + failure);
    }

    /**
     * @description The same submission must still be accepted once the window
     *              is open, so the new check has not closed the door entirely.
     */
    @IsTest
    static void f2WindowOpen() {

        // DR-00180 (Ayush parashar), sitting at "Form Submitted" after a
        // rejection - a state a resubmission legitimately starts from. Only
        // the window is widened; the status is left alone, because moving it
        // backwards is exactly what the order rules now prevent.
        Id openRequestId = 'a4xC1000000C6T3IAK';
        update new Deferment_Request__c(
            Id = openRequestId,
            Break_Start_Date_Time__c = Datetime.now().addDays(-1),
            Break_End_Date_Time__c = Datetime.now().addDays(2)
        );

        Boolean accepted = false;
        String failure = '';
        User student = [SELECT Id FROM User WHERE Id = '005C1000006xeE6IAI'];

        System.runAs(student) {
            try {
                List<Map<String, Object>> files = new List<Map<String, Object>>();
                for (String docType : new List<String>{
                        DOC_SUPPORT, DOC_APPROVAL, DOC_ACCEPT }) {
                    files.add(new Map<String, Object>{
                        'documentType' => docType,
                        'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('x')),
                        'fileName' => docType + '.pdf'
                    });
                }
                DefermentRequestController.submitDefermentRequest(
                    JSON.serialize(new Map<String, Object>{
                        'defermentRequestId' => openRequestId,
                        'reason' => 'Submitting while the window is open.',
                        'files' => files
                    })
                );
                accepted = true;
            } catch (Exception ex) {
                failure = ex.getStackTraceString().split('\n')[0];
            }
        }

        Assert.isTrue(
            accepted,
            'VERDICT: a submission made while the window WAS open was refused - ' + failure
        );
    }
}