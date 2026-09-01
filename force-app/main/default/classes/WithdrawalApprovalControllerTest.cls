/**
 * Test class for WithdrawalApprovalController.processApproval, which now drives
 * the standard 'Withdrawal_Request_Approval_Process' via Approval.process.
 *
 * HOW THE TESTS ARE WIRED
 *   - The running (test) user is registered as the Programme Office team member
 *     for the test Programme, so WithdrawalRequestTrigger ->
 *     WithdrawalApprovalService.submitForApproval auto-submits each inserted
 *     'Applied' request and assigns the step-1 work item to the running user.
 *     That keeps the whole flow free of setup/non-setup mixed DML (no User
 *     inserts) and lets the running user act on the work items.
 *   - Tests never call Approval.process submit themselves - the trigger does it
 *     once on insert (calling it again is the "duplicate approval submission"
 *     failure noted in LeaveSubmissionControllerTest).
 *   - Escalation tests also register the running user as the Deputy Chairperson
 *     team member so the same user can approve step 2.
 *
 * SCHEMA NOTES (verified against the org):
 *   - Programme_Master__c is a lookup to the standard "Program" object; use
 *     SpjimrPortalTestDataFactory.insertProgram().
 *   - Current_Role__c picklist includes 'Programme Office' and 'Chairperson'.
 *   - Chairperson approvers come from Program_Team_Members__c
 *     Role__c = 'Deputy Chairperson' (the org has no 'Chairperson' role value).
 */
@isTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class WithdrawalApprovalControllerTest {

    private static final String PROGRAMME_OFFICE_ROLE = 'Programme Office';
    private static final String CHAIRPERSON_TEAM_ROLE = 'Deputy Chairperson';

    // ---------------------------------------------------------------
    // Builders
    // ---------------------------------------------------------------

    private static Id newProgramme() {
        Id programmeId = SpjimrPortalTestDataFactory.insertProgram();
        System.assertNotEquals(null, programmeId,
            'Program could not be created via SpjimrPortalTestDataFactory.insertProgram().');
        return programmeId;
    }

    private static void addTeamMember(Id programmeId, String role, Id userId) {
        Program_Team__c team = new Program_Team__c(
            Name = 'WD ' + role,
            Program__c = programmeId,
            Type__c = 'Office User'
        );
        insert team;
        insert new Program_Team_Members__c(
            Program_Team__c = team.Id,
            User__c = userId,
            Role__c = role
        );
    }

    private static Account newStudentAccount() {
        Account acc = new Account(Name = 'Test Student Account');
        insert acc;
        return acc;
    }

    /** Inserts an 'Applied' request; the trigger auto-submits it into the process. */
    private static Withdrawal_Request__c newSubmittedRequest(Id studentId, Id programmeId) {
        Withdrawal_Request__c req = new Withdrawal_Request__c(
            Student__c = studentId,
            Programme_Master__c = programmeId,
            Status__c = 'Applied',
            Roll_Number__c = 'TEST-ROLL-1',
            Application_ID__c = 'TEST-APP-1'
        );
        insert req;
        return req;
    }

    private static Withdrawal_Request__c reload(Id reqId) {
        return [
            SELECT Id, Name, Status__c, Remarks__c, Approved_By__c, Approval_Date__c,
                   Current_Role__c, Current_Approver_User__c, Current_Approver_Ids__c,
                   Escalate_To_Chairperson__c, Notification_Debug__c
            FROM Withdrawal_Request__c
            WHERE Id = :reqId
        ];
    }

    private static String processInstanceStatus(Id reqId) {
        List<ProcessInstance> pis = [
            SELECT Status FROM ProcessInstance
            WHERE TargetObjectId = :reqId ORDER BY CreatedDate DESC LIMIT 1
        ];
        return pis.isEmpty() ? null : pis[0].Status;
    }

    private static Integer pendingWorkItemCount(Id reqId) {
        return [
            SELECT COUNT() FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :reqId
            AND ProcessInstance.Status = 'Pending'
        ];
    }

    // ---------------------------------------------------------------
    // Input validation
    // ---------------------------------------------------------------

    @isTest
    static void testNullRecordIdThrows() {
        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(null, 'APPROVE', 'Looks fine', false);
            System.assert(false, 'A null record Id should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @isTest
    static void testInvalidActionThrows() {
        Withdrawal_Request__c req = new Withdrawal_Request__c(Status__c = 'Applied');
        insert req; // no Programme -> not submitted

        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(req.Id, 'SUBMIT', 'Some comments', false);
            System.assert(false, 'An action other than APPROVE/REJECT should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @isTest
    static void testBlankCommentsThrows() {
        Withdrawal_Request__c req = new Withdrawal_Request__c(Status__c = 'Applied');
        insert req;

        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', '   ', false);
            System.assert(false, 'Blank comments should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @isTest
    static void testRecordNotFoundThrows() {
        Withdrawal_Request__c req = new Withdrawal_Request__c(Status__c = 'Applied');
        insert req;
        Id ghostId = req.Id;
        delete req;

        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(ghostId, 'APPROVE', 'Some comments', false);
            System.assert(false, 'A missing Withdrawal Request should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @isTest
    static void testNonApproverThrows() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        List<User> others = [
            SELECT Id FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND Id != :UserInfo.getUserId()
            LIMIT 1
        ];
        if (others.isEmpty()) {
            return; // org has only one usable user - cannot exercise this path
        }

        Test.startTest();
        System.runAs(others[0]) {
            try {
                WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Some comments', false);
                System.assert(false, 'A user absent from Current_Approver_Ids__c must be rejected.');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();

        System.assertEquals('Applied', reload(req.Id).Status__c, 'Status must be unchanged.');
    }

    @isTest
    static void testNoPendingWorkItemThrows() {
        // Stamped as an approver but never submitted (no Programme) -> auth
        // passes, then findPendingWorkItemId finds nothing.
        Withdrawal_Request__c req = new Withdrawal_Request__c(Status__c = 'Applied');
        insert req;
        update new Withdrawal_Request__c(
            Id = req.Id,
            Current_Role__c = 'Programme Office',
            Current_Approver_Ids__c = String.valueOf(UserInfo.getUserId())
        );

        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Some comments', false);
            System.assert(false, 'A request with no pending approval step should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------------
    // Decisions through the standard engine
    // ---------------------------------------------------------------

    @isTest
    static void testAutoSubmitAssignsProgrammeOfficeApprover() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());

        Test.startTest();
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Programme Office', after.Current_Role__c);
        System.assert(after.Current_Approver_Ids__c != null
            && after.Current_Approver_Ids__c.contains(String.valueOf(UserInfo.getUserId())),
            'The running user should be stamped as the approver.');
        System.assertEquals('Pending', processInstanceStatus(req.Id));
        System.assertEquals(1, pendingWorkItemCount(req.Id));
    }

    @isTest
    static void testRejectMovesToRejectedAndAudits() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'REJECT', 'Not eligible', false);
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Rejected', after.Status__c);
        System.assertEquals('Not eligible', after.Remarks__c);
        System.assertEquals(UserInfo.getUserId(), after.Approved_By__c);
        System.assertNotEquals(null, after.Approval_Date__c);
        System.assertEquals(null, after.Current_Approver_Ids__c);
        System.assertEquals('Rejected', processInstanceStatus(req.Id));
        System.assert(after.Notification_Debug__c != null
            && after.Notification_Debug__c.contains('Approval notifyStudent'),
            'Student decision diagnostics should be appended. Trace:\n' + after.Notification_Debug__c);
    }

    @isTest
    static void testRecallMovesToRecalledAndAudits() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'RECALL', 'Please resubmit with documents', false);
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Recalled', after.Status__c);
        System.assertEquals('Please resubmit with documents', after.Remarks__c);
        System.assertEquals(UserInfo.getUserId(), after.Approved_By__c);
        System.assertNotEquals(null, after.Approval_Date__c);
        System.assertEquals(null, after.Current_Approver_Ids__c);
        System.assertEquals('Rejected', processInstanceStatus(req.Id));
    }

    @isTest
    static void testProgrammeOfficeApproveFinalizes() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Approved by PO', false);
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Approved', after.Status__c);
        System.assertEquals(UserInfo.getUserId(), after.Approved_By__c);
        System.assertNotEquals(null, after.Approval_Date__c);
        System.assertEquals('Approved', processInstanceStatus(req.Id));
        System.assertEquals(0, pendingWorkItemCount(req.Id));
    }

    @isTest
    static void testEscalateRoutesToChairpersonStep() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        addTeamMember(programmeId, CHAIRPERSON_TEAM_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Please escalate', true);
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Accepted (PO Review)', after.Status__c);
        System.assertEquals('Chairperson', after.Current_Role__c);
        System.assertEquals(true, after.Escalate_To_Chairperson__c);
        System.assertEquals('Pending', processInstanceStatus(req.Id));
        System.assertEquals(1, pendingWorkItemCount(req.Id), 'A step-2 work item should be pending.');
    }

    @isTest
    static void testEscalateThenChairpersonApproves() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        addTeamMember(programmeId, CHAIRPERSON_TEAM_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'PO escalates', true);
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Chairperson approves', false);
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Approved', after.Status__c);
        System.assertEquals('Approved', processInstanceStatus(req.Id));
        System.assertEquals(0, pendingWorkItemCount(req.Id));
    }

    @isTest
    static void testUnknownCurrentRoleThrows() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);
        // Force a role the controller does not route (still a valid picklist value).
        update new Withdrawal_Request__c(Id = req.Id, Current_Role__c = 'Placement Officer');

        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Approve please', false);
            System.assert(false, 'A role the controller does not route should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();

        System.assertEquals(1, pendingWorkItemCount(req.Id), 'The work item must be untouched.');
    }

    @isTest
    static void testStudentNotificationDeliveredToPortalUser() {
        Account learner = SpjimrPortalTestDataFactory.buildLearnerPersonAccount('wac');
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(learner.Id, programmeId);
        User portalUser = PortalUserProvisioner.forAccount(learner.Id);

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Approved by PO', false);
            Test.stopTest();
        }

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Approved', after.Status__c);
        System.assert(after.Notification_Debug__c != null
            && after.Notification_Debug__c.contains('Approval notifyStudent'),
            'Student diagnostics should be appended. Trace:\n' + after.Notification_Debug__c);
        System.assert(!after.Notification_Debug__c.contains('UNCAUGHT EXCEPTION'),
            'notifyStudent must not raise. Trace:\n' + after.Notification_Debug__c);
        if (portalUser != null) {
            System.assert(
                after.Notification_Debug__c.contains('Email sent successfully')
                || after.Notification_Debug__c.contains('Custom notification sent'),
                'Expected a delivery line for the resolved portal user. Trace:\n' + after.Notification_Debug__c
            );
        } else {
            System.assert(after.Notification_Debug__c.contains('STOP'),
                'No community profile - expected the no-portal-user STOP. Trace:\n' + after.Notification_Debug__c);
        }
    }

    @isTest
    static void testEscalateWithoutChairpersonConfiguredThrows() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        // No Deputy Chairperson team member for this Programme.
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        try {
            WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'Please escalate', true);
            System.assert(false, 'Escalation with no Chairperson configured should throw.');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();

        Withdrawal_Request__c after = reload(req.Id);
        System.assertEquals('Applied', after.Status__c, 'A failed escalation must leave the request untouched.');
        System.assertEquals(1, pendingWorkItemCount(req.Id), 'The step-1 work item must still be pending.');
    }

    // ---------------------------------------------------------------
    // Approval history (record-page LWC feed)
    // ---------------------------------------------------------------

    private static WithdrawalApprovalController.ApprovalHistoryRow rowFor(
        List<WithdrawalApprovalController.ApprovalHistoryRow> rows, String stepNameContains
    ) {
        for (WithdrawalApprovalController.ApprovalHistoryRow r : rows) {
            if (r.stepName != null && r.stepName.containsIgnoreCase(stepNameContains)) {
                return r;
            }
        }
        return null;
    }

    @isTest
    static void testApprovalHistoryNullReturnsEmpty() {
        Test.startTest();
        List<WithdrawalApprovalController.ApprovalHistoryRow> rows =
            WithdrawalApprovalController.getApprovalHistory(null);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @isTest
    static void testApprovalHistoryShowsSubmittedAndPending() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        List<WithdrawalApprovalController.ApprovalHistoryRow> rows =
            WithdrawalApprovalController.getApprovalHistory(req.Id);
        Test.stopTest();

        System.assert(rows.size() >= 2, 'Expected a Submitted row plus a pending step.');
        System.assertEquals('Approval Request Submitted', rows[0].stepName);
        System.assertEquals('Submitted', rows[0].status);
        WithdrawalApprovalController.ApprovalHistoryRow po = rowFor(rows, 'Programme Office');
        System.assertNotEquals(null, po, 'A Programme Office step row should be present.');
        System.assertEquals('Pending', po.status);
        System.assert(po.assignedTo != null && po.assignedTo != '', 'Assigned-to names should be populated.');
    }

    @isTest
    static void testApprovalHistoryAfterProgrammeOfficeApproval() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'ok', false);
        Test.stopTest();

        List<WithdrawalApprovalController.ApprovalHistoryRow> rows =
            WithdrawalApprovalController.getApprovalHistory(req.Id);
        WithdrawalApprovalController.ApprovalHistoryRow po = rowFor(rows, 'Programme Office');
        System.assertNotEquals(null, po);
        System.assertEquals('Approved', po.status);
        System.assertEquals('ok', po.remarks);
        for (WithdrawalApprovalController.ApprovalHistoryRow r : rows) {
            System.assertNotEquals('Pending', r.status, 'A finalised request should have no pending row.');
        }
    }

    @isTest
    static void testApprovalHistoryAfterEscalation() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        addTeamMember(programmeId, CHAIRPERSON_TEAM_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'escalate', true);
        Test.stopTest();

        List<WithdrawalApprovalController.ApprovalHistoryRow> rows =
            WithdrawalApprovalController.getApprovalHistory(req.Id);
        System.assertEquals('Approved', rowFor(rows, 'Programme Office').status);
        WithdrawalApprovalController.ApprovalHistoryRow chair = rowFor(rows, 'Chairperson');
        System.assertNotEquals(null, chair, 'A Chairperson step row should be present after escalation.');
        System.assertEquals('Pending', chair.status);
    }

    @isTest
    static void testApprovalHistoryAfterRecall() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.processApproval(req.Id, 'RECALL', 'Please resubmit', false);
        Test.stopTest();

        List<WithdrawalApprovalController.ApprovalHistoryRow> rows =
            WithdrawalApprovalController.getApprovalHistory(req.Id);
        WithdrawalApprovalController.ApprovalHistoryRow po = rowFor(rows, 'Programme Office');
        System.assertNotEquals(null, po);
        System.assertEquals('Recalled', po.status);
        System.assertEquals('Please resubmit', po.remarks);
    }

    @isTest
    static void testGetApproverActionVisibilityForCurrentApprover() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        WithdrawalApprovalController.ApproverActionVisibility vis =
            WithdrawalApprovalController.getApproverActionVisibility(req.Id);
        Test.stopTest();

        System.assertEquals(true, vis.isApprover);
        System.assertEquals(true, vis.showApprove);
        System.assertEquals(true, vis.showReject);
        System.assertEquals(true, vis.showRecall);
        System.assertEquals(true, vis.showEscalateOption);
    }

    @isTest
    static void testGetApproverActionVisibilityHiddenAfterFinalApproval() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);
        WithdrawalApprovalController.processApproval(req.Id, 'APPROVE', 'done', false);

        Test.startTest();
        WithdrawalApprovalController.ApproverActionVisibility vis =
            WithdrawalApprovalController.getApproverActionVisibility(req.Id);
        Test.stopTest();

        System.assertEquals(false, vis.isApprover);
        System.assertEquals(false, vis.showApprove);
        System.assertEquals(false, vis.showReject);
        System.assertEquals(false, vis.showRecall);
    }

    @isTest
    static void testIsCurrentUserApproverMatchesMultipleIds() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = newSubmittedRequest(newStudentAccount().Id, programmeId);

        Test.startTest();
        Boolean allowed = WithdrawalApprovalController.isCurrentUserApprover(req.Id);
        Test.stopTest();

        System.assertEquals(true, allowed);
    }
}