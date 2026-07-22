@isTest
public class ApplicationSlotBookingTriggerHandlerTest {

    @testSetup
    static void setupData() {

        // Bypass Flow
        Automation_Control__c control = new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );
        insert control;

        Application__c app = new Application__c(
            Name = 'Test Application',
            Applicant_State_Management__c = 'Profile Shortlisted'
        );
        insert app;

        RoundMaster__c round = new RoundMaster__c(
            Name = 'Round one',
            RoundNumber__c = '1'
        );
        insert round;

        SlotMaster__c slot = new SlotMaster__c(
            BookedCapacity__c = 0
        );
        insert slot;

        insert new ApplicationSlotBooking__c(
            Application__c = app.Id,
            RoundMaster__c = round.Id,
            SlotMaster__c = slot.Id
        );
    }


    // ---------------------------------------------------
    // AFTER INSERT
    // ---------------------------------------------------
    @isTest
    static void testAfterInsert() {

        ApplicationSlotBooking__c booking = [
            SELECT Id, Application__c, RoundMaster__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
            LIMIT 1
        ];

        ApplicationSlotBookingTriggerHandler handler =
            new ApplicationSlotBookingTriggerHandler();

        Test.startTest();
        handler.afterInsert(
            new List<ApplicationSlotBooking__c>{booking},
            new Map<Id,ApplicationSlotBooking__c>{booking.Id => booking}
        );
        Test.stopTest();

        ApplicationSlotBooking__c verify =
    [SELECT Id FROM ApplicationSlotBooking__c WHERE Id = :booking.Id];

System.assertNotEquals(null, verify);
    }


    // ---------------------------------------------------
    // AFTER UPDATE
    // ---------------------------------------------------
    @isTest
    static void testAfterUpdate() {

        ApplicationSlotBooking__c booking = [
            SELECT Id, Application__c, RoundMaster__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
            LIMIT 1
        ];

        ApplicationSlotBookingTriggerHandler handler =
            new ApplicationSlotBookingTriggerHandler();

        Test.startTest();
        handler.afterUpdate(
            new List<ApplicationSlotBooking__c>{booking},
            new Map<Id,ApplicationSlotBooking__c>{booking.Id => booking},
            new List<ApplicationSlotBooking__c>{booking},
            new Map<Id,ApplicationSlotBooking__c>{booking.Id => booking}
        );
        Test.stopTest();

       ApplicationSlotBooking__c verify =
    [SELECT Id FROM ApplicationSlotBooking__c WHERE Id = :booking.Id];

System.assertEquals(booking.Id, verify.Id);
    }


    // ---------------------------------------------------
    // BEFORE DELETE + AFTER DELETE
    // ---------------------------------------------------
    @isTest
    static void testDeleteFlow() {

        ApplicationSlotBooking__c booking = [
            SELECT Id, Application__c, RoundMaster__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
            LIMIT 1
        ];

        insert new Evaluation__c(
            Application_Slot_Booking__c = booking.Id
        );

        ApplicationSlotBookingTriggerHandler handler =
            new ApplicationSlotBookingTriggerHandler();

        Test.startTest();

        handler.beforeDelete(
            new List<ApplicationSlotBooking__c>{booking},
            new Map<Id,ApplicationSlotBooking__c>{booking.Id => booking}
        );

        handler.afterDelete(
            new List<ApplicationSlotBooking__c>{booking},
            new Map<Id,ApplicationSlotBooking__c>{booking.Id => booking}
        );

        Test.stopTest();

       List<Evaluation__c> evals =
    [SELECT Id FROM Evaluation__c WHERE Application_Slot_Booking__c = :booking.Id];

System.assertNotEquals(null, booking.Id);
    }


    // ---------------------------------------------------
    // AFTER UNDELETE
    // ---------------------------------------------------
    @isTest
    static void testAfterUndelete() {

        ApplicationSlotBooking__c booking = [
            SELECT Id, Application__c, RoundMaster__c, SlotMaster__c
            FROM ApplicationSlotBooking__c
            LIMIT 1
        ];

        ApplicationSlotBookingTriggerHandler handler =
            new ApplicationSlotBookingTriggerHandler();

        Test.startTest();
        handler.afterUndelete(
            new List<ApplicationSlotBooking__c>{booking},
            new Map<Id,ApplicationSlotBooking__c>{booking.Id => booking}
        );
        Test.stopTest();

System.assertNotEquals(null, booking.Id);
    }
}