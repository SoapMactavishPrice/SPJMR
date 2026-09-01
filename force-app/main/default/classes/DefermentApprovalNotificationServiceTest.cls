@isTest
private class DefermentApprovalNotificationServiceTest {

    private static Account testAccount;
    private static Contact testContact;
    private static User approverUser1;
    private static User approverUser2;
    private static User managerUser;
    private static User studentPortalUser;
    private static Deferment_Request__c testRequest;

    @testSetup
    static void setupBaseData() {
        Id studentAccountRecordTypeId = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND Name = 'Student'
            LIMIT 1
        ].Id;

        Account acc = new Account(
            FirstName = 'Test',
            LastName = 'Student',
            RecordTypeId = studentAccountRecordTypeId
        );
        insert acc;

        Account insertedAcc = [
            SELECT Id, PersonContactId
            FROM Account
            WHERE Id = :acc.Id
            LIMIT 1
        ];
        Id studentContactId = insertedAcc.PersonContactId;

        Profile stdProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        List<User> internalUsers = new List<User>();
        internalUsers.add(buildInternalUser(stdProfile.Id, 'Approver', 'One'));
        internalUsers.add(buildInternalUser(stdProfile.Id, 'Approver', 'Two'));
        internalUsers.add(buildInternalUser(stdProfile.Id, 'Manager', 'One'));
        insert internalUsers;

        Deferment_Request__c req = new Deferment_Request__c(
            Account__c = acc.Id,
            Status__c = 'Deferment Form Enabled'
        );
        insert req;

        tryCreateStudentPortalUser(studentContactId);
    }

    private static User buildInternalUser(Id profileId, String firstName, String lastName) {
        String uniqueKey = String.valueOf(Crypto.getRandomInteger()).right(8);
        return new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = (firstName.substring(0, 1) + lastName).left(8),
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueKey + '@example.invalid',
            Username = firstName.toLowerCase() + '.' + lastName.toLowerCase() + uniqueKey + '@example.invalid.test',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
    }

    private static User tryCreateStudentPortalUser(Id contactId) {
        try {
            List<Profile> portalProfiles = [
                SELECT Id
                FROM Profile
                WHERE UserLicense.Name IN ('Customer Community', 'Customer Community Plus', 'Partner Community')
                LIMIT 1
            ];
            if (portalProfiles.isEmpty()) {
                return null;
            }

            String uniqueKey = String.valueOf(Crypto.getRandomInteger()).right(8);
            User u = new User(
                FirstName = 'Portal',
                LastName = 'Student',
                Alias = 'pstud' + uniqueKey.left(3),
                Email = 'portal.student.' + uniqueKey + '@example.invalid',
                Username = 'portal.student.' + uniqueKey + '@example.invalid.test',
                ProfileId = portalProfiles[0].Id,
                ContactId = contactId,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                IsActive = true
            );
            insert u;
            return u;
        } catch (Exception e) {
            return null;
        }
    }

    private static void loadCommonData() {
        testAccount = null;
        testContact = null;
        testRequest = null;
        approverUser1 = null;
        approverUser2 = null;
        managerUser = null;
        studentPortalUser = null;

        List<Account> matchingAccounts = [
            SELECT Id, Name
            FROM Account
            WHERE FirstName = 'Test'
            AND LastName = 'Student'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(!matchingAccounts.isEmpty(), 'Expected @testSetup to have created a Test Student Account.');
        testAccount = matchingAccounts[0];

        testContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE AccountId = :testAccount.Id
            LIMIT 1
        ];
        testRequest = [
            SELECT Id, Account__c, Status__c
            FROM Deferment_Request__c
            WHERE Account__c = :testAccount.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        List<User> approvers = [
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE LastName IN ('One', 'Two')
            AND FirstName = 'Approver'
            ORDER BY CreatedDate DESC
            LIMIT 2
        ];
        for (User u : approvers) {
            if (approverUser1 == null) {
                approverUser1 = u;
            } else {
                approverUser2 = u;
            }
        }

        List<User> managers = [
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE FirstName = 'Manager'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!managers.isEmpty()) {
            managerUser = managers[0];
        }

        List<User> portalUsers = [
            SELECT Id, Name, Email, IsActive
            FROM User
            WHERE ContactId = :testContact.Id
            AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        studentPortalUser = portalUsers.isEmpty() ? null : portalUsers[0];
    }

    // =====================================================================
    // notifyApprovers()
    // =====================================================================

    @isTest
    static void testNotifyApprovers_NullRecordId_NoOp() {
        loadCommonData();

        Test.startTest();

        Integer emailsBefore = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyApprovers(
            null,
            new List<Id>{ approverUser1.Id },
            'Chairperson'
        );

        Integer emailsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            emailsAfter - emailsBefore,
            'notifyApprovers should not send an email when recordId is null.'
        );
    }

    @isTest
    static void testNotifyApprovers_EmptyApproverIds_NoOp() {
        loadCommonData();

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyApprovers(
            testRequest.Id,
            new List<Id>(),
            'Chairperson'
        );

        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(
            0,
            emailsAfter - emailsBefore,
            'No email should be sent for empty approverIds.'
        );
    }

    @isTest
    static void testNotifyApprovers_HappyPath_Chairperson() {
        loadCommonData();

        Test.startTest();
        DefermentApprovalNotificationService.notifyApprovers(
            testRequest.Id,
            new List<Id>{ approverUser1.Id, approverUser2.Id },
            'Chairperson'
        );
        Test.stopTest();

        System.assertEquals(
            1,
            Limits.getEmailInvocations(),
            'Expected a single batched sendEmail() call for all approvers.'
        );
    }

    @isTest
    static void testNotifyApprovers_HappyPath_AssociateDean() {
        loadCommonData();

        Test.startTest();
        DefermentApprovalNotificationService.notifyApprovers(
            testRequest.Id,
            new List<Id>{ approverUser1.Id },
            'AssociateDean'
        );
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations(), 'Expected one email for the single approver.');
    }

    @isTest
    static void testNotifyApprovers_InactiveApprover_SkippedSilently() {
        loadCommonData();

        approverUser1.IsActive = false;
        update approverUser1;

        Test.startTest();

        DefermentApprovalNotificationService.notifyApprovers(
            testRequest.Id,
            new List<Id>{ approverUser1.Id },
            'Chairperson'
        );

        System.assertEquals(
            0,
            Limits.getEmailInvocations(),
            'Inactive approver should not receive an email.'
        );
        Test.stopTest();
    }

    @isTest
    static void testNotifyApprovers_UnknownRecordId_HandledGracefully() {
        loadCommonData();

        Id fakeId = Deferment_Request__c.sObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';

        Test.startTest();
        try {
            DefermentApprovalNotificationService.notifyApprovers(
                fakeId,
                new List<Id>{ approverUser1.Id },
                'Chairperson'
            );
        } catch (Exception e) {
            System.assert(false, 'Service must never throw back to the caller: ' + e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations(), 'Email should still be attempted with fallback merge data.');
    }

    // =====================================================================
    // notifyProgrammeManagersAfterL2Approval()
    // =====================================================================

    @isTest
    static void testNotifyProgrammeManagersAfterL2Approval_HappyPath() {
        loadCommonData();
        System.assert(managerUser != null, 'Expected a Manager test user to exist.');

        Test.startTest();
        DefermentApprovalNotificationService.notifyProgrammeManagersAfterL2Approval(
            testRequest.Id,
            new List<Id>{ managerUser.Id }
        );
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations(), 'Expected one email to the Programme Manager.');
    }

    @isTest
    static void testNotifyProgrammeManagersAfterL2Approval_NullInputs_NoOp() {
        loadCommonData();

        Test.startTest();

        Integer beforeNullRecord = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyProgrammeManagersAfterL2Approval(
            null,
            new List<Id>{ managerUser.Id }
        );

        Integer afterNullRecord = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyProgrammeManagersAfterL2Approval(
            testRequest.Id,
            new List<Id>()
        );

        Integer afterEmptyList = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            afterNullRecord - beforeNullRecord,
            'Null recordId should not send an email.'
        );

        System.assertEquals(
            0,
            afterEmptyList - afterNullRecord,
            'Empty managerIds should not send an email.'
        );
    }

    @isTest
    static void testNotifyProgrammeManagersAfterL2Approval_InactiveManager_NoOp() {
        loadCommonData();
        managerUser.IsActive = false;
        update managerUser;

        Test.startTest();

        Integer emailsBefore = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyProgrammeManagersAfterL2Approval(
            testRequest.Id, new List<Id>{ managerUser.Id }
        );

        Integer emailsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            emailsAfter - emailsBefore,
            'notifyProgrammeManagersAfterL2Approval should not send an email for an inactive manager.'
        );
    }

    // =====================================================================
    // notifyStudentOfRejection()
    // =====================================================================

    @isTest
    static void testNotifyStudentOfRejection_CreatesPortalNotification() {
        loadCommonData();

        Test.startTest();
        DefermentApprovalNotificationService.notifyStudentOfRejection(
            testRequest.Id,
            testAccount.Id,
            'Chairperson',
            'Please provide supporting documents.'
        );
        Test.stopTest();

        List<Portal_Notification__c> notifications = [
            SELECT Id, Title__c, Body__c, Is_Read__c
            FROM Portal_Notification__c
            WHERE Recipient_Account__c = :testAccount.Id
            WITH SYSTEM_MODE
        ];
        if (studentPortalUser != null) {
            System.assertEquals(
                1,
                notifications.size(),
                'Expected one Portal_Notification__c record when Portal User is available.'
            );

            System.assertEquals(
                'Deferment Application Rejected',
                notifications[0].Title__c
            );

            System.assertEquals(
                false,
                notifications[0].Is_Read__c
            );

            System.assert(
                notifications[0].Body__c.contains('Please provide supporting documents.'),
                'Body should include the rejection comments.'
            );
        } else {
            System.assertEquals(
                0,
                notifications.size(),
                'No Portal_Notification__c expected because no Portal User is available.'
            );
        }
    }

    @isTest
    static void testNotifyStudentOfRejection_BlankComments_UsesDash() {
        loadCommonData();

        Test.startTest();

        DefermentApprovalNotificationService.notifyStudentOfRejection(
            testRequest.Id,
            testAccount.Id,
            'AssociateDean',
            null
        );

        Test.stopTest();

        List<Portal_Notification__c> notifications = [
            SELECT Id, Title__c, Body__c, Is_Read__c
            FROM Portal_Notification__c
            WHERE Recipient_Account__c = :testAccount.Id
            WITH SYSTEM_MODE
        ];

        if (studentPortalUser != null) {
            System.assertEquals(
                1,
                notifications.size(),
                'Expected one Portal_Notification__c record when Portal User is available.'
            );

            System.assertEquals(
                'Deferment Application Rejected',
                notifications[0].Title__c
            );

            System.assertEquals(
                false,
                notifications[0].Is_Read__c
            );

            System.assert(
                notifications[0].Body__c.contains('-'),
                'Blank comments should use "-" as the rejection remarks.'
            );
        } else {
            System.assertEquals(
                0,
                notifications.size(),
                'No Portal_Notification__c expected because no Portal User is available.'
            );
        }
    }

    @isTest
    static void testNotifyStudentOfRejection_NullIds_NoOp() {
        loadCommonData();

        Test.startTest();
        DefermentApprovalNotificationService.notifyStudentOfRejection(null, testAccount.Id, 'Chairperson', 'x');
        DefermentApprovalNotificationService.notifyStudentOfRejection(testRequest.Id, null, 'Chairperson', 'x');
        Test.stopTest();

        List<Portal_Notification__c> notifications = [SELECT Id FROM Portal_Notification__c WITH SYSTEM_MODE];
        System.assertEquals(0, notifications.size(), 'No Portal_Notification__c should be created for null ids.');
    }

    @isTest
    static void testNotifyStudentOfRejection_NoPortalUserFound_DoesNotThrow() {
        loadCommonData();

        Account orphanAccount = new Account(Name = 'Orphan Account - No Portal User');
        insert orphanAccount;

        Test.startTest();
        try {
            DefermentApprovalNotificationService.notifyStudentOfRejection(
                testRequest.Id,
                orphanAccount.Id,
                'Chairperson',
                'No portal user exists for this account.'
            );
        } catch (Exception e) {
            System.assert(false, 'Service must never throw: ' + e.getMessage());
        }
        Test.stopTest();

        List<Portal_Notification__c> notifications = [
            SELECT Id
            FROM Portal_Notification__c
            WHERE Recipient_Account__c = :orphanAccount.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals(0, notifications.size());
    }

    // =====================================================================
    // notifyStudentOfFinalApproval()
    // =====================================================================

    @isTest
    static void testNotifyStudentOfFinalApproval_NullIds_NoOp() {
        loadCommonData();

        Test.startTest();

        Integer beforeFirstCall = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyStudentOfFinalApproval(
            null,
            testAccount.Id
        );

        Integer afterFirstCall = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyStudentOfFinalApproval(
            testRequest.Id,
            null
        );

        Integer afterSecondCall = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            afterFirstCall - beforeFirstCall,
            'Null requestId should not send an email.'
        );

        System.assertEquals(
            0,
            afterSecondCall - afterFirstCall,
            'Null accountId should not send an email.'
        );
    }

    @isTest
    static void testNotifyStudentOfFinalApproval_NoPortalUser_NoEmailSent() {
        loadCommonData();

        Account orphanAccount = new Account(
            Name = 'Orphan Account - Final Approval'
        );
        insert orphanAccount;

        Test.startTest();

        Integer emailsBefore = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyStudentOfFinalApproval(
            testRequest.Id,
            orphanAccount.Id
        );

        Integer emailsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            emailsAfter - emailsBefore,
            'No email should be sent when no portal User resolves.'
        );
    }

    @isTest
    static void testNotifyStudentOfFinalApproval_HappyPath_IfPortalUserAvailable() {
        loadCommonData();

        Test.startTest();

        DefermentApprovalNotificationService.notifyStudentOfFinalApproval(
            testRequest.Id,
            testAccount.Id
        );

        Integer emailInvocations = Limits.getEmailInvocations();

        Test.stopTest();

        if (studentPortalUser != null) {
            System.assertEquals(
                1,
                emailInvocations,
                'Expected one final-approval email when a portal User is resolvable.'
            );
        } else {
            System.assertEquals(
                0,
                emailInvocations,
                'No email is expected because the test org could not create a portal User.'
            );
        }
    }

    // =====================================================================
    // Bulk / multiple recipients sanity check
    // =====================================================================

    @isTest
    static void testNotifyApprovers_BulkApprovers() {
        loadCommonData();

        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> bulkUsers = new List<User>();
        for (Integer i = 0; i < 5; i++) {
            bulkUsers.add(buildInternalUser(stdProfile.Id, 'Bulk', 'Approver' + i));
        }
        insert bulkUsers;

        List<Id> approverIds = new List<Id>();
        for (User u : bulkUsers) {
            approverIds.add(u.Id);
        }

        Test.startTest();
        DefermentApprovalNotificationService.notifyApprovers(testRequest.Id, approverIds, 'Chairperson');
        Test.stopTest();

        System.assertEquals(
            1,
            Limits.getEmailInvocations(),
            'Expected a single batched sendEmail() call for all bulk approvers.'
        );
    }

    // =====================================================================
    // notifyStudentOfDefermentProcessComplete()
    // =====================================================================

    @isTest
    static void testNotifyStudentOfDefermentProcessComplete_NullIds_NoOp() {
        loadCommonData();

        Test.startTest();

        Integer beforeFirstCall = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyStudentOfDefermentProcessComplete(
            null,
            testAccount.Id
        );

        Integer afterFirstCall = Limits.getEmailInvocations();

        DefermentApprovalNotificationService.notifyStudentOfDefermentProcessComplete(
            testRequest.Id,
            null
        );

        Integer afterSecondCall = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            afterFirstCall - beforeFirstCall,
            'Null recordId should not send an email.'
        );

        System.assertEquals(
            0,
            afterSecondCall - afterFirstCall,
            'Null accountId should not send an email.'
        );
    }

    @isTest
    static void testNotifyStudentOfDefermentProcessComplete_HappyPath_IfPortalUserAvailable() {
        loadCommonData();

        Test.startTest();

        try {
            DefermentApprovalNotificationService.notifyStudentOfDefermentProcessComplete(
                testRequest.Id,
                testAccount.Id
            );
        } catch (Exception e) {
            System.assert(false, 'Service must never throw back to the caller: ' + e.getMessage());
        }

        Integer emailInvocations = Limits.getEmailInvocations();

        Test.stopTest();

        if (studentPortalUser != null) {
            System.assertEquals(
                1,
                emailInvocations,
                'Expected one deferment-process-complete email when a portal User is resolvable.'
            );
        } else {
            System.assertEquals(
                0,
                emailInvocations,
                'No email is expected because the test org could not create a portal User.'
            );
        }
    }

    @isTest
    static void testNotifyStudentOfDefermentProcessComplete_NoPortalUser_DoesNotThrow_NoEmailSent() {
        loadCommonData();

        Account orphanAccount = new Account(Name = 'Orphan Account - Deferment Complete');
        insert orphanAccount;

        Test.startTest();

        Integer emailsBefore = Limits.getEmailInvocations();

        try {
            DefermentApprovalNotificationService.notifyStudentOfDefermentProcessComplete(
                testRequest.Id,
                orphanAccount.Id
            );
        } catch (Exception e) {
            System.assert(false, 'Service must never throw: ' + e.getMessage());
        }

        Integer emailsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        System.assertEquals(
            0,
            emailsAfter - emailsBefore,
            'No email should be sent when no portal User resolves for the account.'
        );
    }

    @isTest
    static void testNotifyStudentOfDefermentProcessComplete_UnknownRecordId_HandledGracefully() {
        loadCommonData();

        Id fakeId = Deferment_Request__c.sObjectType.getDescribe().getKeyPrefix() + '000000000000AAA';

        Test.startTest();

        try {
            DefermentApprovalNotificationService.notifyStudentOfDefermentProcessComplete(
                fakeId,
                testAccount.Id
            );
        } catch (Exception e) {
            System.assert(false, 'Service must never throw back to the caller: ' + e.getMessage());
        }

        Integer emailInvocations = Limits.getEmailInvocations();

        Test.stopTest();

        if (studentPortalUser != null) {
            System.assertEquals(
                1,
                emailInvocations,
                'Email should still be attempted with fallback merge data when a portal User is resolvable.'
            );
        } else {
            System.assertEquals(
                0,
                emailInvocations,
                'No email is expected because the test org could not create a portal User.'
            );
        }
    }

    @isTest
    static void testGetMergeData_PopulatedLookups_UsedInEmail() {
        loadCommonData();

        Program programme = new Program(
            Name                    = 'Test Programme ' + String.valueOf(DateTime.now().getTime()),
            Program_Code__c         = 'TP' + String.valueOf(DateTime.now().getTime()).right(6),
            Programme_Type__c       = 'Part-time',
            Programme_Sub_Type__c   = 'Class Room',
            Short_Programme_Code__c = 'TP1'
        );
        insert programme;

        testRequest.Programme__c = programme.Id;
        update testRequest;

        Test.startTest();
        DefermentApprovalNotificationService.notifyApprovers(
            testRequest.Id,
            new List<Id>{ approverUser1.Id },
            'Chairperson'
        );
        Test.stopTest();

        System.assertEquals(1, Limits.getEmailInvocations());
    }

    @isTest
    static void testStudentNotificationBuilders() {
        loadCommonData();

        DefermentApprovalNotificationService.MergeData data =
            new DefermentApprovalNotificationService.MergeData();
        data.studentName = 'Test Student';
        data.studentRollNumber = 'ROLL-001';
        data.programmeName = 'Test Programme';
        data.referenceNumber = 'DR-001';
        data.status = 'Pending Chairperson Approval';

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();
        List<User> recipients = new List<User>{ approverUser1 };

        DefermentApprovalNotificationService.sendStudentFinalApprovalEmail(
            recipients, data, null
        );
        DefermentApprovalNotificationService.sendStudentRejectionEmail(
            recipients, data, 'Programme Chairperson', 'Please resubmit.', null
        );
        DefermentApprovalNotificationService.sendStudentDefermentProcessCompleteEmail(
            recipients, data, null
        );
        DefermentApprovalNotificationService.createStudentPortalRejectionNotification(
            testAccount.Id, data, 'Programme Chairperson', 'Please resubmit.', testRequest.Id
        );
        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(3, emailsAfter - emailsBefore);
        Portal_Notification__c notification = [
            SELECT Title__c, Body__c, Is_Read__c
            FROM Portal_Notification__c
            WHERE Recipient_Account__c = :testAccount.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        System.assertEquals('Deferment Application Rejected', notification.Title__c);
        System.assertEquals(false, notification.Is_Read__c);
        System.assert(notification.Body__c.contains('Please resubmit.'));
    }

}