@IsTest
private class FacultyPortalTest {

    @TestSetup
    static void setupData() {
        // Bypass org flow automation used in other tests.
        insert new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );

        Id personRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND IsPersonType = true
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
                Status__c = 'Pending'
            )
        };
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
        Test.startTest();
        List<FacultyPortal.BookingWrapper> results = FacultyPortal.getAssignedSlotBookings();
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() > 0, 'Expected slot bookings for current user email-linked account.');

        Boolean foundComplete = false;
        Boolean foundPending = false;

        for (FacultyPortal.BookingWrapper bw : results) {
            if (bw.evaluationStatus == 'Complete') {
                foundComplete = true;
            }
            if (bw.evaluationStatus == 'Pending') {
                foundPending = true;
            }
        }

        System.assert(foundComplete, 'Expected at least one Complete evaluation status.');
        System.assert(foundPending, 'Expected at least one Pending evaluation status.');
    }
}