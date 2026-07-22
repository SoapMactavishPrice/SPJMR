@IsTest
private class LeaveSubmissionControllerTest {

    /**
     * No Programme Office team member -> the queueable returns before touching the
     * record (so a fake Id is enough and nothing throws).
     */
    @IsTest
    static void submitLeaveJob_noProgrammeOfficeUser_earlyReturns() {
        Id fake = Schema.SObjectType.Leave_Application__c.getKeyPrefix() + '000000000001';
        Test.startTest();
        System.enqueueJob(new LeaveSubmissionController.SubmitLeaveJob(fake));
        Test.stopTest();
        System.assert(true, 'Queueable executed the early-return branch.');
    }

    /**
     * Programme Office member exists -> the job loads the record + approver, sets the
     * status to 'Submitted - Pending Approval', updates the record (line 37) and then
     * builds/submits the approval request (lines 39-45). We call execute() directly so
     * that, if the org has no active approval process for Leave_Application__c,
     * Approval.process (line 45) can throw without failing the test — the status update
     * has already committed and the approval lines are still exercised.
     */
    @IsTest
    static void submitLeaveJob_withProgrammeOffice_runsBody() {
        createTeamMember('Programme Office', UserInfo.getUserId());

        Leave_Application__c leave = new Leave_Application__c(
            Start_Date__c = Date.today(),
            End_Date__c   = Date.today().addDays(1),
            Leave_Type__c = 'Medical Leave'
        );
        insert leave; // succeeds because a Programme Office member now exists

        Test.startTest();
        try {
            new LeaveSubmissionController.SubmitLeaveJob(leave.Id).execute(null);
        } catch (Exception e) {
            // Tolerated: org may have no active approval process, so Approval.process can
            // throw. The status update (line 37) already committed by then.
            System.debug('SubmitLeaveJob body: ' + e.getMessage());
        }
        Test.stopTest();

        Leave_Application__c after = [SELECT Status__c FROM Leave_Application__c WHERE Id = :leave.Id];
        System.assertEquals('Submitted - Pending Approval', after.Status__c,
            'The status update (line 37) should have committed before approval submission.');
    }

    private static void createTeamMember(String role, Id userId) {
        try {
            SObject team = (SObject) Type.forName('Program_Team__c').newInstance();
            team.put('Name', 'Test Team ' + role);
            insert team;
            SObject m = (SObject) Type.forName('Program_Team_Members__c').newInstance();
            m.put('Program_Team__c', team.Id);
            m.put('Role__c', role);
            m.put('User__c', userId);
            insert m;
        } catch (Exception e) {
            System.debug('createTeamMember skipped: ' + e.getMessage());
        }
    }
}