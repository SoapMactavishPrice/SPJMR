@IsTest
private class SlotSchedulerControllerTest {
    private static final String PROGRAM_CODE = 'SSP01';

    private class NoOpHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"ok":true}');
            return res;
        }
    }

    private class NoOpWebServiceMock implements WebServiceMock {
        public void doInvoke(
            Object stub,
            Object request,
            Map<String, Object> response,
            String endpoint,
            String soapAction,
            String requestName,
            String responseNS,
            String responseName,
            String responseType
        ) {
            // Intentionally empty: blocks org-level SOAP callouts during tests.
        }
    }

    private static void registerMocks() {
        Test.setMock(HttpCalloutMock.class, new NoOpHttpMock());
        Test.setMock(WebServiceMock.class, new NoOpWebServiceMock());
    }

    @TestSetup
    static void setupData() {
        registerMocks();

        insert new Automation_Control__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Skip_Flows__c = true
        );

        Program prog = new Program(
            Name = 'Slot Scheduler Program',
            Program_Code__c = PROGRAM_CODE,
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'SSP',
            Programme_Contact__c = '9999999999',
            StartDate = Date.today().addDays(-2),
            EndDate = Date.today().addDays(20)
        );
        insert prog;

        insert new RoundMaster__c(
            Name = 'Round One',
            Program__c = prog.Id,
            RoundNumber__c = '1'
        );

        LocationMaster__c loc = new LocationMaster__c(
            LocationName__c = 'Main Campus',
            Status__c = 'Available'
        );
        insert loc;

        Program_Team__c team = new Program_Team__c(
            Name = 'Interview Team',
            Program__c = prog.Id
        );
        insert team;

        insert new PanelMaster__c(ProgramTeam__c = team.Id);

        insert new SlotMaster__c(
            Program_Master__c = prog.Id,
            LocationMaster__c = loc.Id,
            SlotDate__c = Date.today().addDays(1),
            SlotStartTime__c = Time.newInstance(10, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(11, 0, 0, 0),
            Capacity__c = 3,
            BookedCapacity__c = 0
        );

        insert new SlotMaster__c(
            Program_Master__c = prog.Id,
            LocationMaster__c = loc.Id,
            SlotDate__c = Date.today().addDays(2),
            SlotStartTime__c = Time.newInstance(12, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(13, 0, 0, 0),
            Capacity__c = 3,
            BookedCapacity__c = 0
        );

        Id personRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsPersonType = true
            LIMIT 1
        ].Id;

        Account pa = new Account(
            RecordTypeId = personRtId,
            FirstName = 'Slot',
            LastName = 'Applicant',
            PersonEmail = UserInfo.getUserEmail()
        );
        insert pa;

        insert new Application__c(
            Name = 'APP-EMAIL-1',
            Applicant__c = pa.Id,
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Profile Shortlisted'
        );

        insert new Application__c(
            Name = 'APP-NULL-1',
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Profile Shortlisted'
        );

        insert new Application__c(
            Name = 'APP-NULL-2',
            Program__c = prog.Id,
            Applicant_State_Management__c = 'Profile Shortlisted'
        );
    }

    private static Program getProgram() {
        return [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c = :PROGRAM_CODE LIMIT 1];
    }

    private static RoundMaster__c getRound() {
        return [SELECT Id FROM RoundMaster__c WHERE Program__r.Program_Code__c = :PROGRAM_CODE LIMIT 1];
    }

    private static PanelMaster__c getPanel() {
        return [SELECT Id FROM PanelMaster__c WHERE ProgramTeam__r.Program__r.Program_Code__c = :PROGRAM_CODE LIMIT 1];
    }

    private static LocationMaster__c getLocation() {
        return [SELECT Id FROM LocationMaster__c WHERE Status__c = 'Available' LIMIT 1];
    }

    private static SlotMaster__c getFirstSlot() {
        return [
            SELECT Id, Capacity__c, BookedCapacity__c, LocationMaster__c
            FROM SlotMaster__c
            WHERE Program_Master__r.Program_Code__c = :PROGRAM_CODE
            ORDER BY SlotDate__c ASC, SlotStartTime__c ASC
            LIMIT 1
        ];
    }

    private static SlotMaster__c getSecondSlot() {
        return [
            SELECT Id
            FROM SlotMaster__c
            WHERE Program_Master__r.Program_Code__c = :PROGRAM_CODE
            ORDER BY SlotDate__c DESC, SlotStartTime__c DESC
            LIMIT 1
        ];
    }

    @IsTest
    static void testGetAvailableRoundsAndPanels() {
        registerMocks();
        Test.startTest();
        List<RoundMaster__c> rounds = SlotSchedulerController.getAvailableRounds(PROGRAM_CODE);
        List<RoundMaster__c> emptyRounds = SlotSchedulerController.getAvailableRounds('NO_CODE');

        List<PanelMaster__c> panels = SlotSchedulerController.getPanels(PROGRAM_CODE);
        List<PanelMaster__c> emptyPanels = SlotSchedulerController.getPanels('NO_CODE');
        Test.stopTest();

        System.assert(!rounds.isEmpty(), 'Expected rounds for known program.');
        System.assertEquals(0, emptyRounds.size(), 'Expected empty list for unknown program code.');
        System.assert(!panels.isEmpty(), 'Expected panels for known program.');
        System.assertEquals(0, emptyPanels.size(), 'Expected empty list for unknown program code.');
    }

    @IsTest
    static void testGetLocationsAndGetSlots() {
        registerMocks();
        LocationMaster__c loc = getLocation();

        insert new Program(
            Name = 'No Slot Program',
            Program_Code__c = 'NOSLOT',
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'NSP',
            Programme_Contact__c = '8888888888',
            StartDate = Date.today(),
            EndDate = Date.today().addDays(15)
        );

        Test.startTest();
        List<LocationMaster__c> locations = SlotSchedulerController.getLocations();
        List<SlotMaster__c> blankArgs = SlotSchedulerController.getSlots(null, null);
        List<SlotMaster__c> noSlots = SlotSchedulerController.getSlots('NOSLOT', loc.Id);
        List<SlotMaster__c> availableSlots = SlotSchedulerController.getSlots(PROGRAM_CODE, loc.Id);
        Test.stopTest();

        System.assert(locations.size() > 0, 'Expected available locations.');
        System.assertEquals(0, blankArgs.size(), 'Expected empty result on blank inputs.');
        System.assertEquals(0, noSlots.size(), 'Expected no upcoming slots.');
        System.assert(availableSlots.size() > 0, 'Expected slots in the rolling window.');
    }

    @IsTest
    static void testBookSlotsBulkSuccessAndErrors() {
        registerMocks();
        SlotMaster__c slot = getFirstSlot();
        RoundMaster__c round = getRound();
        PanelMaster__c panel = getPanel();
        List<Application__c> nullApplicantApps = [
            SELECT Id
            FROM Application__c
            WHERE Program__r.Program_Code__c = :PROGRAM_CODE
            AND Applicant__c = null
            LIMIT 2
        ];

        Boolean missingParamsThrown = false;
        try {
            SlotSchedulerController.bookSlotsBulk('', new List<Id>{ nullApplicantApps[0].Id });
        } catch (AuraHandledException e) {
            missingParamsThrown = true;
        }

        Boolean noAppsThrown = false;
        try {
            String goodParams = JSON.serialize(new Map<String, Object>{
                'slotId' => slot.Id,
                'roundId' => round.Id,
                'panelId' => panel.Id
            });
            SlotSchedulerController.bookSlotsBulk(goodParams, new List<Id>());
        } catch (AuraHandledException e) {
            noAppsThrown = true;
        }

        insert new ApplicationSlotBooking__c(
            Application__c = nullApplicantApps[0].Id,
            SlotMaster__c = slot.Id,
            RoundMaster__c = round.Id,
            Panel_Master__c = panel.Id,
            BookingState__c = 'Booked'
        );

        Boolean duplicateThrown = false;
        try {
            String paramsForDuplicate = JSON.serialize(new Map<String, Object>{
                'slotId' => slot.Id,
                'roundId' => round.Id,
                'panelId' => panel.Id
            });
            SlotSchedulerController.bookSlotsBulk(
                paramsForDuplicate,
                new List<Id>{ nullApplicantApps[0].Id }
            );
        } catch (AuraHandledException e) {
            duplicateThrown = true;
        }

        Boolean parseThrown = false;
        try {
            SlotSchedulerController.bookSlotsBulk('not-json', new List<Id>{ nullApplicantApps[1].Id });
        } catch (AuraHandledException e) {
            parseThrown = true;
        }

        String success = SlotSchedulerController.bookSlotsBulk(
            JSON.serialize(new Map<String, Object>{
                'slotId' => slot.Id,
                'roundId' => round.Id,
                'panelId' => panel.Id
            }),
            new List<Id>{ nullApplicantApps[1].Id }
        );

        Integer created = [
            SELECT COUNT()
            FROM ApplicationSlotBooking__c
            WHERE Application__c = :nullApplicantApps[1].Id
            AND SlotMaster__c = :slot.Id
        ];

        System.assertEquals(true, missingParamsThrown);
        System.assertEquals(true, noAppsThrown);
        System.assertEquals(true, duplicateThrown);
        System.assertEquals(true, parseThrown);
        System.assertEquals('Booking successful', success);
        System.assertEquals(1, created, 'Expected a booking row from success path.');
    }

    @IsTest
    static void testGetBookedSlotsTrueAndFalse() {
        registerMocks();
        Program prog = getProgram();
        SlotMaster__c slot1 = getFirstSlot();
        SlotMaster__c slot2 = getSecondSlot();
        RoundMaster__c round = getRound();
        PanelMaster__c panel = getPanel();

        Application__c emailMatchedApp = [
            SELECT Id
            FROM Application__c
            WHERE Program__c = :prog.Id
            AND Applicant__r.PersonEmail = :UserInfo.getUserEmail()
            LIMIT 1
        ];

        insert new ApplicationSlotBooking__c(
            Application__c = emailMatchedApp.Id,
            SlotMaster__c = slot1.Id,
            RoundMaster__c = round.Id,
            Panel_Master__c = panel.Id,
            BookingState__c = 'Booked'
        );

        Test.startTest();
        Boolean allowedWhenBooked = SlotSchedulerController.getBookedSlots(PROGRAM_CODE, slot1.Id);
        Boolean allowedWhenFree = SlotSchedulerController.getBookedSlots(PROGRAM_CODE, slot2.Id);
        Test.stopTest();

        System.assertEquals(false, allowedWhenBooked, 'Expected false when current user already has a booking for the slot.');
        System.assertEquals(true, allowedWhenFree, 'Expected true when no booking exists for current user.');
    }

    @IsTest
    static void testGetBookedSlotsMalformedId() {
        registerMocks();
        Boolean isBookable = SlotSchedulerController.getBookedSlots(PROGRAM_CODE, 'NOT_AN_ID');
        System.assertEquals(true, isBookable, 'Non-matching slot Id string should return true (no booking found).');
    }

    @IsTest
    static void testBookSlotBranches() {
        registerMocks();
        Program prog = getProgram();
        RoundMaster__c round = getRound();

        Application__c nullApplicantApp = [
            SELECT Id
            FROM Application__c
            WHERE Program__c = :prog.Id
            AND Applicant__c = null
            LIMIT 1
        ];
        System.assertNotEquals(null, nullApplicantApp.Id);

        Boolean missingParamThrown = false;
        try {
            SlotSchedulerController.bookSlot(null, PROGRAM_CODE);
        } catch (AuraHandledException e) {
            missingParamThrown = true;
        }

        Boolean appNotFoundThrown = false;
        try {
            SlotSchedulerController.bookSlot(getFirstSlot().Id, 'NO_APP_CODE');
        } catch (AuraHandledException e) {
            appNotFoundThrown = true;
        }

        SlotMaster__c deleteMe = new SlotMaster__c(
            Program_Master__c = prog.Id,
            LocationMaster__c = getLocation().Id,
            SlotDate__c = Date.today().addDays(3),
            SlotStartTime__c = Time.newInstance(14, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(15, 0, 0, 0),
            Capacity__c = 2,
            BookedCapacity__c = 0
        );
        insert deleteMe;
        Id deletedSlotId = deleteMe.Id;
        delete deleteMe;

        Boolean slotNotFoundThrown = false;
        try {
            SlotSchedulerController.bookSlot(deletedSlotId, PROGRAM_CODE);
        } catch (AuraHandledException e) {
            slotNotFoundThrown = true;
        }

        SlotMaster__c fullSlot = new SlotMaster__c(
            Program_Master__c = prog.Id,
            LocationMaster__c = getLocation().Id,
            SlotDate__c = Date.today().addDays(4),
            SlotStartTime__c = Time.newInstance(16, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(17, 0, 0, 0),
            Capacity__c = 1,
            BookedCapacity__c = 1
        );
        insert fullSlot;

        Boolean fullSlotThrown = false;
        try {
            SlotSchedulerController.bookSlot(fullSlot.Id, PROGRAM_CODE);
        } catch (AuraHandledException e) {
            fullSlotThrown = true;
        }

        SlotMaster__c openSlot = new SlotMaster__c(
            Program_Master__c = prog.Id,
            LocationMaster__c = getLocation().Id,
            SlotDate__c = Date.today().addDays(5),
            SlotStartTime__c = Time.newInstance(18, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(19, 0, 0, 0),
            Capacity__c = 5,
            BookedCapacity__c = 0
        );
        insert openSlot;

        Test.startTest();
        String success = SlotSchedulerController.bookSlot(openSlot.Id, PROGRAM_CODE);
        Test.stopTest();

        Integer bookingCount = [
            SELECT COUNT()
            FROM ApplicationSlotBooking__c
            WHERE SlotMaster__c = :openSlot.Id
            AND RoundMaster__c = :round.Id
        ];

        System.assertEquals(true, missingParamThrown);
        System.assertEquals(true, appNotFoundThrown);
        System.assertEquals(true, slotNotFoundThrown);
        System.assertEquals(true, fullSlotThrown);
        System.assertEquals('Booking successful', success);
        System.assertEquals(1, bookingCount, 'Expected one booking created in success path.');
    }
}