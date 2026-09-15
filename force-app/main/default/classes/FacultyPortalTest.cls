@IsTest
private class FacultyPortalTest {

    @TestSetup
    static void setupData() {

        Profile sysAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        UserRole studentCounsellorRole = new UserRole(
            Name = 'Student_Counsellor',
            DeveloperName = 'StudentCounsellor'
        );
        insert studentCounsellorRole;

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'Admin',
            Alias = 'tadmin',
            Email = 'testadmin@example.com',
            Username = 'testadmin.@987example.com',
            ProfileId = sysAdminProfile.Id,
            UserRoleId = studentCounsellorRole.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        Map<String, Id> permissionSetIds = new Map<String, Id>();

        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('Admissions_Team', 'EducationCloudAccess')
        ]) {
            permissionSetIds.put(ps.Name, ps.Id);
        }

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetIds.get('Admissions_Team')
            ),
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetIds.get('EducationCloudAccess')
            )
        };

        System.runAs(testUser) {
            // Bypass org flow automation used in other tests.
            insert new Automation_Control__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Skip_Flows__c = true
            );

            Id personRtId = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Account' AND IsPersonType = true AND RecordType.Name = 'Interviewer Faculty'
                LIMIT 1
            ].Id;

            Account interviewerAcc = new Account(
                RecordTypeId = personRtId,
                FirstName = 'Portal',
                LastName = 'Interviewer',
                PersonEmail = UserInfo.getUserEmail()
            );
            insert interviewerAcc;

            Application__c app = new Application__c(
                Name = 'Portal Test Application',
                Applicant__c = interviewerAcc.Id,
                Applicant_State_Management__c = 'Profile Shortlisted'
            );
            insert app;

            RoundMaster__c round = new RoundMaster__c(
                Name = 'Round One',
                RoundNumber__c = '1'
            );
            insert round;

            SlotMaster__c slot = new SlotMaster__c(
                BookedCapacity__c = 0
            );
            insert slot;

            PanelMaster__c panel = new PanelMaster__c();
            insert panel;

            insert new PanelInterviewer__c(
                Account__c = interviewerAcc.Id,
                PanelMaster__c = panel.Id
            );

            ApplicationSlotBooking__c b1 = new ApplicationSlotBooking__c(
                Application__c = app.Id,
                RoundMaster__c = round.Id,
                SlotMaster__c = slot.Id,
                Panel_Master__c = panel.Id
            );

            ApplicationSlotBooking__c b2 = new ApplicationSlotBooking__c(
                Application__c = app.Id,
                RoundMaster__c = round.Id,
                SlotMaster__c = slot.Id,
                Panel_Master__c = panel.Id
            );

            insert new List<ApplicationSlotBooking__c>{ b1, b2 };

            insert new List<Evaluation__c>{
                new Evaluation__c(
                    Application_Slot_Booking__c = b1.Id,
                    Status__c = 'Complete'
                ),
                new Evaluation__c(
                    Application_Slot_Booking__c = b2.Id,
                    Status__c = 'In Progress'
                )
            };
        }
    }

    @IsTest
    static void testGetAssignedSlotBookings_NoAccountForUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User u = new User(
            FirstName = 'No',
            LastName = 'Account',
            Alias = 'noacc',
            Username = 'noacc' + System.currentTimeMillis() + '@test.com',
            Email = 'noacc@test.com',
            TimeZoneSidKey = 'GMT',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;

        System.runAs(u) {
            List<FacultyPortal.BookingWrapper> results = FacultyPortal.getAssignedSlotBookings();
            System.assertNotEquals(null, results);
            System.assertEquals(0, results.size());
        }
    }

    @IsTest
    static void testGetAssignedSlotBookings_WithBookings() {

        User testUser = [
                SELECT Id
                FROM User
                WHERE Username LIKE 'testadmin.@987example.com'
                LIMIT 1
            ];
        
        
        System.runAs(testUser) {
            Test.startTest();
            List<FacultyPortal.BookingWrapper> results = FacultyPortal.getAssignedSlotBookings();
            Test.stopTest();

            Boolean foundComplete = false;
            Boolean foundPending = false;

            for (FacultyPortal.BookingWrapper bw : results) {
                if (bw.evaluationStatus == 'Complete') {
                    foundComplete = true;
                }
                if (bw.evaluationStatus == 'In Progress') {
                    foundPending = true;
                }
            }
        }
    }

    @IsTest
    static void testGetSlotMasterList_WithData() {

        User testUser = [
                SELECT Id
                FROM User
                WHERE Username LIKE 'testadmin.@987example.com'
                LIMIT 1
            ];
        
        
        System.runAs(testUser) {
            Test.startTest();
            List<SlotMaster__c> results = FacultyPortal.getSlotMasterList();
            Test.stopTest();
            System.assertNotEquals(null, results);
        }
    }

    @IsTest
    static void testGetSlotMasterList_NoAccount() {
        
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];

        User u = new User(
            FirstName = 'No',
            LastName = 'Slot',
            Alias = 'noslot',
            Username = 'noslot' + System.currentTimeMillis() + '@test.com',
            Email = 'noslot@test.com',
            TimeZoneSidKey = 'GMT',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;

        System.runAs(u) {
            List<SlotMaster__c> results = FacultyPortal.getSlotMasterList();
            System.assertNotEquals(null, results);
            System.assertEquals(0, results.size());
        }
    }
}