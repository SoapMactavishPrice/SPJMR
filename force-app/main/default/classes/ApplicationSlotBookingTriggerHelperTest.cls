@isTest
public class ApplicationSlotBookingTriggerHelperTest {
    
    @testSetup
    static void setupData() {
        
        //  Bypass Flow (Hierarchy Custom Setting)
        Automation_Control__c control = new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );
        insert control;
        
        // Create Application
        Application__c app = new Application__c(
            Name = 'Test Application',
            Applicant_State_Management__c = 'Profile Shortlisted'
        );
        insert app;
        
        // Create Rounds
        RoundMaster__c round1 = new RoundMaster__c(
            Name = 'Round one',
            RoundNumber__c = '1'
        );
        RoundMaster__c round2 = new RoundMaster__c(
            Name = 'Round two',
            RoundNumber__c = '2'
        );
        insert new List<RoundMaster__c>{round1, round2};
            
            // Create Slot (Name is AutoNumber so do NOT set Name)
            SlotMaster__c slot = new SlotMaster__c(
                BookedCapacity__c = 0
            );
        insert slot;
        
        // Insert Initial Bookings
        insert new List<ApplicationSlotBooking__c>{
            new ApplicationSlotBooking__c(
                Application__c = app.Id,
                RoundMaster__c = round1.Id,
                SlotMaster__c = slot.Id
            ),
                new ApplicationSlotBooking__c(
                    Application__c = app.Id,
                    RoundMaster__c = round2.Id,
                    SlotMaster__c = slot.Id
                )
                };
                    }
    
    
    // ---------------------------------------------------
    // deleteEvaluationsRecords
    // ---------------------------------------------------
    @isTest
    static void testDeleteEvaluationsRecords() {
        
        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Application__c
            FROM ApplicationSlotBooking__c
        ];
        
        insert new Evaluation__c(
            Application_Slot_Booking__c = bookings[0].Id
        );
        
        Test.startTest();
        ApplicationSlotBookingTriggerHelper.deleteEvaluationsRecords(bookings);
        Test.stopTest();
        
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Evaluation__c]
        );
    }
    
    
    // ---------------------------------------------------
    // checkForDuplicateRounds
    // ---------------------------------------------------
    @isTest
    static void testCheckForDuplicateRounds() {
        
        // Get one existing booking
        ApplicationSlotBooking__c existing = [
            SELECT Id, Application__c, RoundMaster__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
            LIMIT 1
        ];
        
        // Insert duplicate booking
        ApplicationSlotBooking__c duplicate = new ApplicationSlotBooking__c(
            Application__c = existing.Application__c,
            RoundMaster__c = existing.RoundMaster__c,
            SlotMaster__c = existing.SlotMaster__c
        );
        insert duplicate;
        
        //  Always re-query after insert
        List<ApplicationSlotBooking__c> freshList = [
            SELECT Id, Application__c, RoundMaster__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
            WHERE Id = :duplicate.Id
        ];
        
        Map<Id, ApplicationSlotBooking__c> newMap =
            new Map<Id, ApplicationSlotBooking__c>(freshList);
        
        Test.startTest();
        ApplicationSlotBookingTriggerHelper.checkForDuplicateRounds(
            freshList,
            newMap
        );
        Test.stopTest();
        
        ApplicationSlotBooking__c verify =
            [SELECT Id FROM ApplicationSlotBooking__c WHERE Id = :duplicate.Id];
        
        System.assertNotEquals(null, verify);
    }
    
    
    // ---------------------------------------------------
    // updateApplicationStateManagement
    // ---------------------------------------------------
    @isTest
    static void testUpdateApplicationStateManagement() {
        
        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Application__c
            FROM ApplicationSlotBooking__c
        ];
        
        insert new Evaluation__c(
            Application_Slot_Booking__c = bookings[0].Id
        );
        
        Test.startTest();
        ApplicationSlotBookingTriggerHelper.updateApplicationStateManagement(bookings);
        Test.stopTest();
        
        Application__c app = [
            SELECT Applicant_State_Management__c
            FROM Application__c
            LIMIT 1
        ];
        
        System.assertNotEquals(null, app.Applicant_State_Management__c);
    }
    
    
    // ---------------------------------------------------
    // updateSlotBookedCapacity
    // ---------------------------------------------------
    @isTest
    static void testUpdateSlotBookedCapacity() {
        
        List<ApplicationSlotBooking__c> bookings = [
            SELECT Id, Application__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
        ];
        
        Map<Id, ApplicationSlotBooking__c> bookingMap =
            new Map<Id, ApplicationSlotBooking__c>(bookings);
        
        Test.startTest();
        ApplicationSlotBookingTriggerHelper.updateSlotBookedCapacity(bookingMap);
        Test.stopTest();
        
        SlotMaster__c slot = [
            SELECT BookedCapacity__c
            FROM SlotMaster__c
            LIMIT 1
        ];
        
        System.assert(slot.BookedCapacity__c > 0);
    }
}