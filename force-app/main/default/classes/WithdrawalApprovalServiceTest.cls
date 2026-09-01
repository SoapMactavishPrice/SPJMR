/**
 * Test class for WithdrawalApprovalService - the trigger-side auto-submit into
 * the standard 'Withdrawal_Request_Approval_Process' plus the shared
 * Programme -> approver resolver.
 *
 * The running (test) user is registered as the Programme Office team member so
 * that WithdrawalRequestTrigger -> submitForApproval routes to a real user and
 * the flow needs no User DML (no setup/non-setup mixed DML).
 */
@isTest
@SuppressWarnings('PMD.ApexCRUDViolation')
private class WithdrawalApprovalServiceTest {

    private static final String PROGRAMME_OFFICE_ROLE = 'Programme Office';

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

    private static Withdrawal_Request__c appliedRequest(Id studentId, Id programmeId) {
        return new Withdrawal_Request__c(
            Student__c = studentId,
            Programme_Master__c = programmeId,
            Status__c = 'Applied',
            Roll_Number__c = 'TEST-ROLL-1',
            Application_ID__c = 'TEST-APP-1'
        );
    }

    private static Integer processInstanceCount(Id reqId) {
        return [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :reqId];
    }

    private static String debugLog(Id reqId) {
        return [SELECT Notification_Debug__c FROM Withdrawal_Request__c WHERE Id = :reqId].Notification_Debug__c;
    }

    // ---------------------------------------------------------------

    @isTest
    static void testNullAndEmptyInputDoNothing() {
        Test.startTest();
        WithdrawalApprovalService.submitForApproval(null);
        WithdrawalApprovalService.submitForApproval(new List<Withdrawal_Request__c>());
        Test.stopTest();
        // No exception is the assertion.
    }

    @isTest
    static void testAutoSubmitCreatesApprovalInstance() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());

        Test.startTest();
        Withdrawal_Request__c req = appliedRequest(newStudentAccount().Id, programmeId);
        insert req;
        Test.stopTest();

        Withdrawal_Request__c after = [
            SELECT Current_Role__c, Current_Approver_User__c, Current_Approver_Ids__c
            FROM Withdrawal_Request__c WHERE Id = :req.Id
        ];
        System.assertEquals('Programme Office', after.Current_Role__c);
        System.assertEquals(UserInfo.getUserId(), after.Current_Approver_User__c);
        System.assert(after.Current_Approver_Ids__c.contains(String.valueOf(UserInfo.getUserId())));
        System.assertEquals(1, processInstanceCount(req.Id));
        System.assertEquals(1, [
            SELECT COUNT() FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :req.Id AND ProcessInstance.Status = 'Pending'
        ]);
    }

    @isTest
    static void testNoProgrammeIsNotSubmitted() {
        Test.startTest();
        Withdrawal_Request__c req = new Withdrawal_Request__c(
            Student__c = newStudentAccount().Id,
            Status__c = 'Applied'
        );
        insert req;
        Test.stopTest();

        System.assertEquals(0, processInstanceCount(req.Id), 'No Programme -> no approval instance.');
        String log = debugLog(req.Id);
        System.assert(log != null && log.contains('STOP'),
            'Expected a STOP line for a request with no Programme. Trace:\n' + log);
    }

    @isTest
    static void testNoProgrammeOfficeMemberIsNotSubmitted() {
        Id programmeId = newProgramme();
        // Programme exists but has no Programme Office team member.

        Test.startTest();
        Withdrawal_Request__c req = appliedRequest(newStudentAccount().Id, programmeId);
        insert req;
        Test.stopTest();

        System.assertEquals(0, processInstanceCount(req.Id));
        String log = debugLog(req.Id);
        System.assert(log != null && log.contains('STOP'),
            'Expected a STOP line when no Programme Office member exists. Trace:\n' + log);
    }

    @isTest
    static void testBulkAutoSubmit() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Id studentId = newStudentAccount().Id;

        List<Withdrawal_Request__c> requests = new List<Withdrawal_Request__c>();
        for (Integer i = 0; i < 5; i++) {
            Withdrawal_Request__c r = appliedRequest(studentId, programmeId);
            r.Roll_Number__c = 'TEST-ROLL-' + i;
            r.Application_ID__c = 'TEST-APP-' + i;
            requests.add(r);
        }

        Test.startTest();
        insert requests;
        Test.stopTest();

        for (Withdrawal_Request__c r : requests) {
            System.assertEquals(1, processInstanceCount(r.Id),
                'Every bulk-inserted request should get exactly one approval instance.');
        }
    }

    @isTest
    static void testAlreadySubmittedIsNotResubmitted() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        Withdrawal_Request__c req = appliedRequest(newStudentAccount().Id, programmeId);
        insert req; // trigger auto-submits once

        Test.startTest();
        WithdrawalApprovalService.submitForApproval(new List<Withdrawal_Request__c>{ req });
        Test.stopTest();

        System.assertEquals(1, processInstanceCount(req.Id),
            'An already-submitted request must not be submitted a second time.');
        String log = debugLog(req.Id);
        System.assert(log != null && log.contains('already has an open approval instance'),
            'Expected the duplicate-submit guard to log a SKIP. Trace:\n' + log);
    }

    @isTest
    static void testGetProgrammeApprovers() {
        Id programmeId = newProgramme();
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());
        // Same user on a second team of the same Programme - must de-dupe.
        addTeamMember(programmeId, PROGRAMME_OFFICE_ROLE, UserInfo.getUserId());

        Test.startTest();
        List<Id> approvers = WithdrawalApprovalService.getProgrammeApprovers(programmeId, PROGRAMME_OFFICE_ROLE);
        List<Id> none = WithdrawalApprovalService.getProgrammeApprovers(null, PROGRAMME_OFFICE_ROLE);
        List<Id> blankRole = WithdrawalApprovalService.getProgrammeApprovers(programmeId, '   ');
        Test.stopTest();

        System.assertEquals(1, approvers.size(), 'A user on two teams should resolve once.');
        System.assertEquals(UserInfo.getUserId(), approvers[0]);
        System.assertEquals(0, none.size());
        System.assertEquals(0, blankRole.size());
    }
}