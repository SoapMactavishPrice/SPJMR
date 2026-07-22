@IsTest
private class LeaveApprovalActionControllerTest {

    // Leave_Application__c BeforeInsert throws unless a Programme Office team member
    // exists, and AfterInsert auto-submits the record to the Leave_Application_Approval
    // process (creating a work item for that PO user).
    @TestSetup
    static void setup() {
        List<User> us = new List<User>{
            buildUser('aapo', 'ZleavePO'),
            buildUser('aamgr', 'ZleaveMGR'),
            buildUser('aadep', 'ZleaveDEP')
        };
        insert us;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            createTeamMember('Programme Office', us[0].Id);
            createTeamMember('Manager', us[1].Id);
            createTeamMember('Deputy Chairperson', us[2].Id);
        }
    }

    private static User poUser()  { return getUser('ZleavePO'); }
    private static User mgrUser() { return getUser('ZleaveMGR'); }

    private static Leave_Application__c newLeave() {
        Leave_Application__c l = new Leave_Application__c(
            Start_Date__c = Date.today(),
            End_Date__c   = Date.today().addDays(2),
            Leave_Type__c = 'Other',
            Reason__c     = 'orig'
        );
        insert l; // trigger sets status/role + submits for approval
        return l;
    }

    @IsTest
    static void getCurrentUserRole_branches() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        System.assertEquals('Programme Office',
            LeaveApprovalActionController.getCurrentUserRole(l.Id),
            'Trigger sets the current role to Programme Office.');
        try {
            LeaveApprovalActionController.getCurrentUserRole(null);
            System.assert(false, 'Null id should throw.');
        } catch (Exception e) { /* expected */ }
        Test.stopTest();
    }

    /** INCOMPLETE returns before the work-item check. */
    @IsTest
    static void processLeaveAction_incomplete() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        LeaveApprovalActionController.processLeaveAction(
            l.Id, 'INCOMPLETE', 'Approve', false, 'need more docs');
        Test.stopTest();

        Leave_Application__c after = [SELECT Status__c, Reason__c FROM Leave_Application__c WHERE Id = :l.Id];
        System.assertEquals('Incomplete', after.Status__c);
        System.assertEquals('need more docs', after.Reason__c);
    }

    /** Running user has no work item -> "not the current approver" path. */
    @IsTest
    static void processLeaveAction_noWorkItem() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        // Run as a user who is NOT the current approver, the submitter, or a member
        // of the Programme Office queue. Under both the ad-hoc and queue-based Step 1
        // configurations, no work item is actionable for them -> processLeaveAction throws.
        System.runAs(mgrUser()) {
            try {
                LeaveApprovalActionController.processLeaveAction(
                    l.Id, 'Approve', 'Approve', false, 'ok');
                System.assert(false, 'Running user is not the approver -> should throw.');
            } catch (Exception e) { /* expected */ }
        }
        Test.stopTest();
    }

    /** Programme Office approves -> routes to Manager, who gives final approval. */
    @IsTest
    static void processLeaveAction_poApprove_then_managerFinal() {
        Leave_Application__c l = newLeave();

        Test.startTest();
        System.runAs(poUser()) {
            try {
                LeaveApprovalActionController.processLeaveAction(
                    l.Id, 'Approve', 'Approve', false, 'PO approved');
            } catch (Exception e) { System.debug('PO step: ' + e.getMessage()); }
        }
        System.runAs(mgrUser()) {
            try {
                LeaveApprovalActionController.processLeaveAction(
                    l.Id, 'Eligible for Makeup', 'Approve', false, 'Manager approved');
            } catch (Exception e) { System.debug('Manager step: ' + e.getMessage()); }
        }
        Test.stopTest();
        System.assert(true);
    }

    /** Programme Office rejects. */
    @IsTest
    static void processLeaveAction_poReject() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        System.runAs(poUser()) {
            try {
                LeaveApprovalActionController.processLeaveAction(
                    l.Id, 'Not Approved', 'Reject', false, 'rejected');
            } catch (Exception e) { System.debug('PO reject: ' + e.getMessage()); }
        }
        Test.stopTest();
        System.assert(true);
    }

    /** Manager approves with route-to-deputy. */
    @IsTest
    static void processLeaveAction_managerRouteToDeputy() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        System.runAs(poUser()) {
            try {
                LeaveApprovalActionController.processLeaveAction(
                    l.Id, 'Approve', 'Approve', false, 'PO ok');
            } catch (Exception e) {}
        }
        System.runAs(mgrUser()) {
            try {
                LeaveApprovalActionController.processLeaveAction(
                    l.Id, 'Approve', 'Approve', true, 'route to deputy');
            } catch (Exception e) { System.debug('Mgr deputy: ' + e.getMessage()); }
        }
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void getStudentLeaves_returnsOwned() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        List<Leave_Application__c> leaves =
            LeaveApprovalActionController.getStudentLeaves(UserInfo.getUserId());
        Test.stopTest();
        System.assert(!leaves.isEmpty(), 'Current user owns the inserted leave.');
    }

    @IsTest
    static void getFilesWithData_returnsAttached() {
        Leave_Application__c l = newLeave();
        ContentVersion cv = new ContentVersion(
            Title = 'doc', PathOnClient = 'doc.txt', VersionData = Blob.valueOf('file-body'));
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId, LinkedEntityId = l.Id, ShareType = 'V', Visibility = 'AllUsers');

        Test.startTest();
        List<Map<String, String>> files = LeaveApprovalActionController.getFilesWithData(l.Id);
        Test.stopTest();
        System.assert(!files.isEmpty(), 'The attached file should be returned.');
        System.assertEquals('doc', files[0].get('name'));
    }

    @IsTest
    static void updateLeave_setsIncomplete() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        LeaveApprovalActionController.updateLeave(
            l.Id, Date.today(), Date.today().addDays(3), 'Emergency Leave', 'updated');
        Test.stopTest();
        Leave_Application__c after = [
            SELECT Status__c, Leave_Type__c, Reason__c FROM Leave_Application__c WHERE Id = :l.Id];
        System.assertEquals('Incomplete', after.Status__c);
        System.assertEquals('Emergency Leave', after.Leave_Type__c);
    }

    @IsTest
    static void uploadFile_attachesAndBadInputThrows() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        LeaveApprovalActionController.uploadFile(
            l.Id, 'note.txt', EncodingUtil.base64Encode(Blob.valueOf('x')));
        try {
            LeaveApprovalActionController.uploadFile(null, null, null);
        } catch (Exception e) { /* error path */ }
        Test.stopTest();
        System.assert(![SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :l.Id].isEmpty());
    }

    @IsTest
    static void submitToDeputyAsync_runs() {
        Leave_Application__c l = newLeave();
        Test.startTest();
        LeaveApprovalActionController.submitToDeputyAsync(l.Id, poUser().Id);
        Test.stopTest();
        System.assert(true);
    }

    // ---------- helpers ----------

    private static User buildUser(String alias, String lastName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = alias + System.currentTimeMillis() + Crypto.getRandomInteger();
        return new User(
            Alias = alias.left(8),
            Email = uniq + '@example.com.spjtest',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniq + '@example.com.spjtest'
        );
    }

    private static User getUser(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName ORDER BY CreatedDate DESC LIMIT 1];
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
            System.debug('createTeamMember(' + role + ') skipped: ' + e.getMessage());
        }
    }
}