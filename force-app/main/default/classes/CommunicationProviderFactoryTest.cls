@IsTest
private class CommunicationProviderFactoryTest {
    private static Integer sequence = 0;

    private static Program createProgram(String programCode) {
        sequence++;
        Program programRecord = new Program(
            Name = 'Provider Factory Test Program ' + sequence,
            Program_Code__c = programCode,
            Short_Programme_Code__c = 'P' + sequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert programRecord;
        return programRecord;
    }

    private static Application__c createApplication(Id programId) {
        Id applicantId;
        Id batchId;
        if (programId != null) {
            sequence++;
            Account applicant = new Account(
                RecordTypeId = Schema.SObjectType.Account
                    .getRecordTypeInfosByDeveloperName()
                    .get('Applicant')
                    .getRecordTypeId(),
                FirstName = 'Test',
                LastName = 'Applicant ' + sequence,
                PersonEmail = 'provider.factory.' + sequence + '@example.com'
            );
            insert applicant;
            applicantId = applicant.Id;

            ProgramCohort batchRecord = new ProgramCohort(
                Name = 'Provider Factory Batch ' + sequence,
                ProgramId = programId,
                Batch_Code__c = 'PFB' + sequence,
                Batch_Sub_Type__c = 'Class Room',
                Batch_Base_Currency__c = 'INR',
                StartDate = Date.today().addDays(30),
                EndDate = Date.today().addYears(1)
            );
            insert batchRecord;
            batchId = batchRecord.Id;
        }

        Application__c application = new Application__c(
            Program__c = programId,
            Applicant__c = applicantId,
            Batch__c = batchId
        );
        insert application;
        return application;
    }

    private static Admission_Decision__c eligibleDecision(Id applicationId) {
        return new Admission_Decision__c(
            Application__c = applicationId,
            Result__c = 'Eligible for Admission',
            Offer_Letter_Date__c = Date.newInstance(2027, 1, 10),
            LastDateOfAcceptance__c = Date.newInstance(2027, 1, 11),
            SignedLetterOfAcceptanceEta__c = Date.newInstance(2027, 1, 12),
            PaymentOfTheAcceptanceFeeEta__c = Date.newInstance(2027, 1, 13),
            PaymentOfTheFirstInstallmentEta__c = Date.newInstance(2027, 1, 14),
            BalanceFeePaymentETA__c = Date.newInstance(2027, 1, 15)
        );
    }

    // ---------------------------------------------------------------
    // getProvider / normalizeProviderType routing
    // ---------------------------------------------------------------

    @IsTest
    static void getProviderReturnsApplicationSlotBookingProviderForCanonicalAndClassNameValues() {
        System.assert(
            CommunicationProviderFactory.getProvider('APPLICATION_SLOT_BOOKING')
                instanceof CommunicationProviderFactory.ApplicationSlotBookingProvider
        );
        System.assert(
            CommunicationProviderFactory.getProvider(' ApplicationSlotBookingProvider ')
                instanceof CommunicationProviderFactory.ApplicationSlotBookingProvider
        );
    }

    @IsTest
    static void getProviderReturnsAdmissionDecisionProviderForCanonicalAndClassNameValues() {
        System.assert(
            CommunicationProviderFactory.getProvider('ADMISSION_DECISION')
                instanceof CommunicationProviderFactory.AdmissionDecisionProvider
        );
        System.assert(
            CommunicationProviderFactory.getProvider(' AdmissionDecisionProvider ')
                instanceof CommunicationProviderFactory.AdmissionDecisionProvider
        );
    }

    @IsTest
    static void getProviderThrowsForUnknownAndBlankProviderType() {
        Boolean unknownThrew = false;
        try {
            CommunicationProviderFactory.getProvider('SOME_UNKNOWN_TYPE');
        } catch (CommunicationProviderFactory.CommunicationException e) {
            unknownThrew = true;
            System.assert(e.getMessage().contains('SOME_UNKNOWN_TYPE'));
        }
        System.assert(unknownThrew);

        Boolean blankThrew = false;
        try {
            CommunicationProviderFactory.getProvider(null);
        } catch (CommunicationProviderFactory.CommunicationException e) {
            blankThrew = true;
        }
        System.assert(blankThrew);
    }

    // ---------------------------------------------------------------
    // formatTime utility
    // ---------------------------------------------------------------

    @IsTest
    static void formatTimeReturnsEmptyStringForNullAndFormattedStringOtherwise() {
        System.assertEquals(
            '',
            CommunicationProviderFactory.formatTime(null)
        );
        System.assertEquals(
            '09:30 AM',
            CommunicationProviderFactory.formatTime(Time.newInstance(9, 30, 0, 0))
        );
    }

    // ---------------------------------------------------------------
    // AdmissionDecisionProvider.getData
    // ---------------------------------------------------------------

    @IsTest
    static void admissionDecisionProviderGetDataThrowsWhenRequestOrApplicationIdMissing() {
        CommunicationProviderFactory.AdmissionDecisionProvider provider =
            new CommunicationProviderFactory.AdmissionDecisionProvider();

        Boolean nullRequestThrew = false;
        try {
            provider.getData(null);
        } catch (CommunicationProviderFactory.CommunicationException e) {
            nullRequestThrew = true;
        }
        System.assert(nullRequestThrew);

        Boolean nullApplicationIdThrew = false;
        try {
            provider.getData(new CommunicationsController.CommunicationRequest());
        } catch (CommunicationProviderFactory.CommunicationException e) {
            nullApplicationIdThrew = true;
        }
        System.assert(nullApplicationIdThrew);
    }

    @IsTest
    static void admissionDecisionProviderGetDataThrowsWhenNoDecisionFound() {
        Application__c application = createApplication(null);

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.applicationId = application.Id;

        CommunicationProviderFactory.AdmissionDecisionProvider provider =
            new CommunicationProviderFactory.AdmissionDecisionProvider();

        Boolean threw = false;
        Test.startTest();
        try {
            provider.getData(request);
        } catch (CommunicationProviderFactory.CommunicationException e) {
            threw = true;
            System.assert(e.getMessage().contains('No admission decision found.'));
        }
        Test.stopTest();

        System.assert(threw);
    }

    @IsTest
    static void admissionDecisionProviderGetDataReturnsMergedDataForSingleApplication() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id);
        Admission_Decision__c decision = eligibleDecision(application.Id);
        insert decision;

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.applicationId = application.Id;

        CommunicationProviderFactory.AdmissionDecisionProvider provider =
            new CommunicationProviderFactory.AdmissionDecisionProvider();

        Test.startTest();
        Map<String, Object> data = provider.getData(request);
        Test.stopTest();

        System.assertEquals(application.Id, data.get('ApplicationId'));
        System.assertEquals('Eligible for Admission', data.get('AdmissionResult'));
        System.assertEquals('10/01/2027', data.get('offerDateFormatted'));
        System.assertEquals('11/01/2027', data.get('OfferExpiryDate'));
        System.assert(
            String.valueOf(data.get('OfferLink')).contains(
                '/lightning/r/Admission_Decision__c/' + decision.Id + '/view'
            )
        );
    }

    @IsTest
    static void admissionDecisionProviderGetDataByApplicationIdsSkipsApplicationsWithoutDecisions() {
        Program programRecord = createProgram('PGPM');
        Application__c withDecision = createApplication(programRecord.Id);
        Application__c withoutDecision = createApplication(programRecord.Id);
        insert eligibleDecision(withDecision.Id);

        CommunicationProviderFactory.AdmissionDecisionProvider provider =
            new CommunicationProviderFactory.AdmissionDecisionProvider();

        Test.startTest();
        Map<Id, Map<String, Object>> dataByApplicationId =
            provider.getDataByApplicationIds(
                new List<Id>{ withDecision.Id, withoutDecision.Id }
            );
        Test.stopTest();

        System.assert(dataByApplicationId.containsKey(withDecision.Id));
        System.assert(!dataByApplicationId.containsKey(withoutDecision.Id));
    }

    @IsTest
    static void admissionDecisionProviderGetDataByApplicationIdsReturnsEmptyMapForNullOrEmptyIds() {
        CommunicationProviderFactory.AdmissionDecisionProvider provider =
            new CommunicationProviderFactory.AdmissionDecisionProvider();

        System.assert(provider.getDataByApplicationIds((List<Id>) null).isEmpty());
        System.assert(provider.getDataByApplicationIds(new List<Id>()).isEmpty());
    }

        // ---------------------------------------------------------------
    // Shared slot-booking test data helpers
    // (ASSUMED field/API names — verify against actual schema)
    // ---------------------------------------------------------------

    private static LocationMaster__c createLocationMaster() {
        sequence++;
        LocationMaster__c location = new LocationMaster__c(
            AddressInformation__c = 'Test Address ' + sequence
        );
        insert location;
        return location;
    }

    private static SlotMaster__c createSlotMaster(Id locationId) {
        sequence++;
        SlotMaster__c slot = new SlotMaster__c(
            Name = 'Provider Factory Slot ' + sequence,
            SlotDate__c = Date.newInstance(2027, 5, 20),
            SlotStartTime__c = Time.newInstance(9, 0, 0, 0),
            SlotEndTime__c = Time.newInstance(9, 30, 0, 0),
            LocationMaster__c = locationId
        );
        insert slot;
        return slot;
    }

    private static RoundMaster__c createRoundMaster() {
        sequence++;
        String uniqueName = 'Provider Factory Round ' +
            String.fromCharArray(new List<Integer>{65 + Math.mod(sequence, 26)});

        RoundMaster__c round = new RoundMaster__c(
            Name = uniqueName,
            RoundNumber__c = '1'
        );

        insert round;

        return round;
    }

    private static PanelMaster__c createPanelMaster() {
        sequence++;
        PanelMaster__c panel = new PanelMaster__c(
        );
        insert panel;
        return panel;
    }

    private static ApplicationSlotBooking__c createSlotBooking(
        Id applicationId,
        Id slotId,
        Id roundId,
        Id panelId,
        String bookingState
    ) {
        ApplicationSlotBooking__c booking = new ApplicationSlotBooking__c(
            Application__c = applicationId,
            SlotMaster__c = slotId,
            RoundMaster__c = roundId,
            Panel_Master__c = panelId
        );
        insert booking;
        return booking;
    }

    // ---------------------------------------------------------------
    // ApplicationSlotBookingProvider.getData
    // ---------------------------------------------------------------

    @IsTest
    static void slotBookingProviderGetDataThrowsWhenRequestOrApplicationIdMissing() {
        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Boolean nullRequestThrew = false;
        try {
            provider.getData(null);
        } catch (CommunicationProviderFactory.CommunicationException e) {
            nullRequestThrew = true;
        }
        System.assert(nullRequestThrew);

        Boolean nullApplicationIdThrew = false;
        try {
            provider.getData(new CommunicationsController.CommunicationRequest());
        } catch (CommunicationProviderFactory.CommunicationException e) {
            nullApplicationIdThrew = true;
        }
        System.assert(nullApplicationIdThrew);
    }

    @IsTest
    static void slotBookingProviderGetDataThrowsWhenNoBookingFound() {
        Application__c application = createApplication(null);

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.applicationId = application.Id;

        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Boolean threw = false;
        Test.startTest();
        try {
            provider.getData(request);
        } catch (CommunicationProviderFactory.CommunicationException e) {
            threw = true;
            System.assert(e.getMessage().contains('No interview booking found.'));
        }
        Test.stopTest();

        System.assert(threw);
    }

    @IsTest
    static void slotBookingProviderGetDataReturnsDataUsingReferenceRecordId() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id);
        LocationMaster__c location = createLocationMaster();
        SlotMaster__c slot = createSlotMaster(location.Id);
        RoundMaster__c round = createRoundMaster();
        PanelMaster__c panel = createPanelMaster();
        ApplicationSlotBooking__c booking = createSlotBooking(
            application.Id, slot.Id, round.Id, panel.Id, 'Scheduled'
        );

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.applicationId = application.Id;
        request.referenceRecordId = booking.Id;

        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Test.startTest();
        Map<String, Object> data = provider.getData(request);
        Test.stopTest();

        System.assertEquals(application.Id, data.get('ApplicationId'));
        System.assertEquals(booking.Id, data.get('BookingId'));
        System.assertEquals('20/05/2027', data.get('InterviewDate'));
        System.assertEquals('09:00 AM', data.get('InterviewTime'));
        System.assertEquals('09:30 AM', data.get('InterviewEndTime'));
    }

    // ---------------------------------------------------------------
    // getDataByApplicationIds — requested booking via map, single-id
    // referenceRecordId path, and fallback path
    // ---------------------------------------------------------------

    @IsTest
    static void slotBookingProviderGetDataByApplicationIdsUsesReferenceRecordIdMap() {
        Program programRecord = createProgram('PGPM');
        Application__c firstApplication = createApplication(programRecord.Id);
        Application__c secondApplication = createApplication(programRecord.Id);
        LocationMaster__c location = createLocationMaster();
        SlotMaster__c firstSlot = createSlotMaster(location.Id);
        SlotMaster__c secondSlot = createSlotMaster(location.Id);
        RoundMaster__c round = createRoundMaster();
        PanelMaster__c panel = createPanelMaster();

        ApplicationSlotBooking__c firstBooking = createSlotBooking(
            firstApplication.Id, firstSlot.Id, round.Id, panel.Id, 'Scheduled'
        );
        ApplicationSlotBooking__c secondBooking = createSlotBooking(
            secondApplication.Id, secondSlot.Id, round.Id, panel.Id, 'Scheduled'
        );

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            firstApplication.Id => firstBooking.Id,
            secondApplication.Id => secondBooking.Id
        };

        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Test.startTest();
        Map<Id, Map<String, Object>> dataByApplicationId =
            provider.getDataByApplicationIds(
                request,
                new List<Id>{ firstApplication.Id, secondApplication.Id }
            );
        Test.stopTest();

        System.assertEquals(2, dataByApplicationId.size());
        System.assertEquals(
            firstBooking.Id,
            dataByApplicationId.get(firstApplication.Id).get('BookingId')
        );
        System.assertEquals(
            secondBooking.Id,
            dataByApplicationId.get(secondApplication.Id).get('BookingId')
        );
    }

    @IsTest
    static void slotBookingProviderGetDataByApplicationIdsSkipsBookingBelongingToDifferentApplication() {
        Program programRecord = createProgram('PGPM');
        Application__c targetApplication = createApplication(programRecord.Id);
        Application__c otherApplication = createApplication(programRecord.Id);
        LocationMaster__c location = createLocationMaster();
        SlotMaster__c slot = createSlotMaster(location.Id);
        RoundMaster__c round = createRoundMaster();
        PanelMaster__c panel = createPanelMaster();

        // Booking actually belongs to otherApplication, but the map
        // claims it belongs to targetApplication.
        ApplicationSlotBooking__c mismatchedBooking = createSlotBooking(
            otherApplication.Id, slot.Id, round.Id, panel.Id, 'Scheduled'
        );

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.applicationIdToReferenceRecordId = new Map<Id, Id>{
            targetApplication.Id => mismatchedBooking.Id
        };

        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Test.startTest();
        Map<Id, Map<String, Object>> dataByApplicationId =
            provider.getDataByApplicationIds(
                request,
                new List<Id>{ targetApplication.Id }
            );
        Test.stopTest();

        System.assert(dataByApplicationId.isEmpty());
    }

    @IsTest
    static void slotBookingProviderGetDataByApplicationIdsFallsBackWhenNoReferenceProvided() {
        Program programRecord = createProgram('PGPM');
        Application__c application = createApplication(programRecord.Id);
        LocationMaster__c location = createLocationMaster();
        SlotMaster__c slot = createSlotMaster(location.Id);
        RoundMaster__c round = createRoundMaster();
        PanelMaster__c panel = createPanelMaster();

        // Not scheduled via request.referenceRecordId or the map, so the
        // provider must fall back to querying the application's own
        // non-cancelled ApplicationSlotBookings__r.
        createSlotBooking(application.Id, slot.Id, round.Id, panel.Id, 'Cancelled');
        ApplicationSlotBooking__c activeBooking = createSlotBooking(
            application.Id, slot.Id, round.Id, panel.Id, 'Scheduled'
        );

        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Test.startTest();
        Map<Id, Map<String, Object>> dataByApplicationId =
            provider.getDataByApplicationIds(
                new List<Id>{ application.Id }
            );
        Test.stopTest();

        System.assert(dataByApplicationId.containsKey(application.Id));
    }

    @IsTest
    static void slotBookingProviderGetDataByApplicationIdsFallbackSkipsApplicationsWithNoActiveBooking() {
        Program programRecord = createProgram('PGPM');
        Application__c applicationWithNoBooking = createApplication(programRecord.Id);

        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        Test.startTest();
        Map<Id, Map<String, Object>> dataByApplicationId =
            provider.getDataByApplicationIds(
                new List<Id>{ applicationWithNoBooking.Id }
            );
        Test.stopTest();

        System.assert(dataByApplicationId.isEmpty());
    }

    @IsTest
    static void slotBookingProviderGetDataByApplicationIdsReturnsEmptyMapForNullOrEmptyIds() {
        CommunicationProviderFactory.ApplicationSlotBookingProvider provider =
            new CommunicationProviderFactory.ApplicationSlotBookingProvider();

        System.assert(provider.getDataByApplicationIds((List<Id>) null).isEmpty());
        System.assert(provider.getDataByApplicationIds(new List<Id>()).isEmpty());
    }
}