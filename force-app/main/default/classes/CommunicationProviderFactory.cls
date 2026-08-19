public class CommunicationProviderFactory {

    public static ICommunicationProvider getProvider(String providerType) {
        String normalizedProviderType = normalizeProviderType(providerType);

        switch on normalizedProviderType {
            when 'APPLICATION_SLOT_BOOKING' {
                return new ApplicationSlotBookingProvider();
            }
            when 'ADMISSION_DECISION' {
                return new AdmissionDecisionProvider();
            }
            when else {
                throw new CommunicationException(
                    'Unknown provider type: ' + providerType
                );
            }
        }
    }

    private static String normalizeProviderType(String providerType) {
        if (String.isBlank(providerType)) {
            return providerType;
        }

        String trimmedProviderType = providerType.trim();

        switch on trimmedProviderType {
            when 'APPLICATION_SLOT_BOOKING', 'ApplicationSlotBookingProvider' {
                return 'APPLICATION_SLOT_BOOKING';
            }
            when 'ADMISSION_DECISION', 'AdmissionDecisionProvider' {
                return 'ADMISSION_DECISION';
            }
            when else {
                return trimmedProviderType;
            }
        }
    }

    public class CommunicationException extends Exception {}

    public interface ICommunicationProvider {
        Map<String, Object> getData(
            CommunicationsController.CommunicationRequest request
        );

        Map<Id, Map<String, Object>> getDataByApplicationIds(
            List<Id> applicationIds
        );

        Map<Id, Map<String, Object>> getDataByApplicationIds(
            CommunicationsController.CommunicationRequest request,
            List<Id> applicationIds
        );
    }

    public class AdmissionDecisionProvider implements ICommunicationProvider {

        public Map<String, Object> getData(
            CommunicationsController.CommunicationRequest request
        ) {
            validateRequest(request);

            Map<Id, Map<String, Object>> dataByApplicationId =
                getDataByApplicationIds(
                    request,
                    new List<Id>{ request.applicationId }
                );

            if (!dataByApplicationId.containsKey(request.applicationId)) {
                throw new CommunicationProviderFactory.CommunicationException(
                    'No admission decision found.'
                );
            }

            return dataByApplicationId.get(request.applicationId);
        }

        public Map<Id, Map<String, Object>> getDataByApplicationIds(
            List<Id> applicationIds
        ) {
            return getDataByApplicationIds(
                null,
                applicationIds
            );
        }

        public Map<Id, Map<String, Object>> getDataByApplicationIds(
            CommunicationsController.CommunicationRequest request,
            List<Id> applicationIds
        ) {
            Map<Id, Map<String, Object>> dataByApplicationId =
                new Map<Id, Map<String, Object>>();

            if (applicationIds == null || applicationIds.isEmpty()) {
                return dataByApplicationId;
            }

            for (
                Application__c application :
                [
                    SELECT
                        Id,
                        Name,
                        Application_Number__c,
                        Applicant_State_Management__c,
                        Applicant__r.Name,
                        Applicant__r.PersonEmail,
                        Program__r.Id,
                        Program__r.Name,
                        Program__r.Program_Code__c,
                        Batch__r.Name,
                        (
                            SELECT
                                Id,
                                Result__c,
                                Offer_Letter_Date__c,
                                WaitlistNumber__c,
                                Offer_Accepted__c,
                                Offer_Declined__c,
                                CreatedDate
                            FROM Admission_Decisions__r
                            ORDER BY CreatedDate DESC
                            LIMIT 1
                        )
                    FROM Application__c
                    WHERE Id IN :applicationIds
                ]
            ) {
                if (application.Admission_Decisions__r.isEmpty()) {
                    continue;
                }

                Admission_Decision__c decision =
                    application.Admission_Decisions__r[0];

                Map<String, Object> data = new Map<String, Object>();

                data.put('ApplicationId', application.Id);
                data.put('ApplicationNumber', application.Name);

                data.put('ApplicantName', application.Applicant__r.Name);
                data.put('ApplicantEmail', application.Applicant__r.PersonEmail);
                data.put(
                    'ApplicantStateManagement',
                    application.Applicant_State_Management__c
                );

                data.put('ProgramId', application.Program__r.Id);
                data.put('ProgramName', application.Program__r.Name);
                data.put('ProgramCode', application.Program__r.Program_Code__c);
                data.put('BatchName', application.Batch__r.Name);

                data.put('AdmissionDecisionId', decision.Id);
                data.put('AdmissionResult', decision.Result__c);
                data.put('OfferDate', decision.Offer_Letter_Date__c);
                data.put('WaitlistNumber', decision.WaitlistNumber__c);
                data.put('OfferAccepted', decision.Offer_Accepted__c);
                data.put('OfferDeclined', decision.Offer_Declined__c);
                data.put('OfferLink', buildOfferLink(decision.Id));

                dataByApplicationId.put(application.Id, data);
            }

            return dataByApplicationId;
        }

        private void validateRequest(
            CommunicationsController.CommunicationRequest request
        ) {
            if (request == null || request.applicationId == null) {
                throw new CommunicationProviderFactory.CommunicationException(
                    'Application Id is required.'
                );
            }
        }

        private String buildOfferLink(Id admissionDecisionId) {
            if (admissionDecisionId == null) {
                return '';
            }

            return URL.getOrgDomainUrl().toExternalForm()
                + '/lightning/r/Admission_Decision__c/'
                + admissionDecisionId
                + '/view';
        }
    }

    public class ApplicationSlotBookingProvider implements ICommunicationProvider {

        public Map<String, Object> getData(
            CommunicationsController.CommunicationRequest request
        ) {
            validateRequest(request);

            Map<Id, Map<String, Object>> dataByApplicationId =
                getDataByApplicationIds(
                    request,
                    new List<Id>{ request.applicationId }
                );

            if (!dataByApplicationId.containsKey(request.applicationId)) {
                throw new CommunicationProviderFactory.CommunicationException(
                    'No interview booking found.'
                );
            }

            return dataByApplicationId.get(request.applicationId);
        }

        public Map<Id, Map<String, Object>> getDataByApplicationIds(
            List<Id> applicationIds
        ) {
            return getDataByApplicationIds(
                null,
                applicationIds
            );
        }

        public Map<Id, Map<String, Object>> getDataByApplicationIds(
            CommunicationsController.CommunicationRequest request,
            List<Id> applicationIds
        ) {
            Map<Id, Id> applicationIdToBookingId =
                getRequestedBookingIdsByApplicationId(
                    request,
                    applicationIds
                );

            if (!applicationIdToBookingId.isEmpty()) {
                return getDataByApplicationIdsFromBookings(
                    applicationIds,
                    applicationIdToBookingId
                );
            }

            return getDataByApplicationIdsUsingFallback(applicationIds);
        }

        private void validateRequest(
            CommunicationsController.CommunicationRequest request
        ) {
            if (request == null || request.applicationId == null) {
                throw new CommunicationProviderFactory.CommunicationException(
                    'Application Id is required.'
                );
            }
        }

        private Map<Id, Id> getRequestedBookingIdsByApplicationId(
            CommunicationsController.CommunicationRequest request,
            List<Id> applicationIds
        ) {
            Map<Id, Id> applicationIdToBookingId = new Map<Id, Id>();

            if (request == null || applicationIds == null || applicationIds.isEmpty()) {
                return applicationIdToBookingId;
            }

            if (
                request.applicationIdToReferenceRecordId != null &&
                !request.applicationIdToReferenceRecordId.isEmpty()
            ) {
                for (Id applicationId : applicationIds) {
                    Id bookingId =
                        request.applicationIdToReferenceRecordId.get(applicationId);
                    if (bookingId != null) {
                        applicationIdToBookingId.put(applicationId, bookingId);
                    }
                }
                return applicationIdToBookingId;
            }

            if (
                applicationIds.size() == 1 &&
                request.referenceRecordId != null
            ) {
                applicationIdToBookingId.put(
                    applicationIds[0],
                    request.referenceRecordId
                );
            }

            return applicationIdToBookingId;
        }

        private Map<Id, Map<String, Object>> getDataByApplicationIdsFromBookings(
            List<Id> applicationIds,
            Map<Id, Id> applicationIdToBookingId
        ) {
            Map<Id, Map<String, Object>> dataByApplicationId =
                new Map<Id, Map<String, Object>>();

            if (
                applicationIds == null ||
                applicationIds.isEmpty() ||
                applicationIdToBookingId == null ||
                applicationIdToBookingId.isEmpty()
            ) {
                return dataByApplicationId;
            }

            Map<Id, ApplicationSlotBooking__c> bookingsById =
                new Map<Id, ApplicationSlotBooking__c>();

            for (
                ApplicationSlotBooking__c booking :
                [
                    SELECT
                        Id,
                        Application__c,
                        BookingState__c,
                        RoundMaster__r.Name,
                        Panel_Master__r.Name,
                        SlotMaster__r.SlotDate__c,
                        SlotMaster__r.SlotStartTime__c,
                        SlotMaster__r.SlotEndTime__c,
                        SlotMaster__r.LocationMaster__r.AddressInformation__c,
                        Application__r.Id,
                        Application__r.Name,
                        Application__r.Batch__r.Name,
                        Application__r.Application_Number__c,
                        Application__r.Applicant__r.Name,
                        Application__r.Applicant__r.PersonEmail,
                        Application__r.Program__r.Id,
                        Application__r.Program__r.Name,
                        Application__r.Program__r.Program_Code__c
                    FROM ApplicationSlotBooking__c
                    WHERE Id IN :applicationIdToBookingId.values()
                    AND Application__c IN :applicationIds
                ]
            ) {
                bookingsById.put(booking.Id, booking);
            }

            for (Id applicationId : applicationIds) {
                Id requestedBookingId = applicationIdToBookingId.get(applicationId);
                ApplicationSlotBooking__c booking =
                    requestedBookingId == null
                        ? null
                        : bookingsById.get(requestedBookingId);

                if (booking == null || booking.Application__c != applicationId) {
                    continue;
                }

                dataByApplicationId.put(
                    applicationId,
                    buildApplicationSlotBookingData(booking)
                );
            }

            return dataByApplicationId;
        }

        private Map<Id, Map<String, Object>> getDataByApplicationIdsUsingFallback(
            List<Id> applicationIds
        ) {
            Map<Id, Map<String, Object>> dataByApplicationId =
                new Map<Id, Map<String, Object>>();

            if (applicationIds == null || applicationIds.isEmpty()) {
                return dataByApplicationId;
            }

            for (
                Application__c application :
                [
                    SELECT
                        Id,
                        Name,
                        Application_Number__c,
                        Applicant__r.Name,
                        Applicant__r.PersonEmail,
                        Program__r.Id,
                        Program__r.Name,
                        Program__r.Program_Code__c,
                        Batch__r.Name,
                        (
                            SELECT
                                Id,
                                BookingState__c,
                                RoundMaster__r.Name,
                                Panel_Master__r.Name,
                                SlotMaster__r.SlotDate__c,
                                SlotMaster__r.SlotStartTime__c,
                                SlotMaster__r.SlotEndTime__c,
                                SlotMaster__r.LocationMaster__r.AddressInformation__c
                            FROM ApplicationSlotBookings__r
                            WHERE BookingState__c != 'Cancelled'
                            ORDER BY Slot_Date__c ASC
                            LIMIT 1
                        )
                    FROM Application__c
                    WHERE Id IN :applicationIds
                ]
            ) {
                if (application.ApplicationSlotBookings__r.isEmpty()) {
                    continue;
                }

                dataByApplicationId.put(
                    application.Id,
                    buildApplicationSlotBookingData(
                        application,
                        application.ApplicationSlotBookings__r[0]
                    )
                );
            }

            return dataByApplicationId;
        }

        private Map<String, Object> buildApplicationSlotBookingData(
            Application__c application,
            ApplicationSlotBooking__c booking
        ) {
            if (application == null || booking == null) {
                return null;
            }

            Map<String, Object> data = new Map<String, Object>();

            data.put('ApplicationId', application.Id);
            data.put('ApplicationNumber', application.Name);

            data.put('ApplicantName', application.Applicant__r.Name);
            data.put('ApplicantEmail', application.Applicant__r.PersonEmail);

            data.put('ProgramId', application.Program__r.Id);
            data.put('ProgramName', application.Program__r.Name);
            data.put('ProgramCode', application.Program__r.Program_Code__c);
            data.put('BatchName', application.Batch__r.Name);

            data.put('BookingId', booking.Id);
            data.put('BookingState', booking.BookingState__c);
            data.put('InterviewDate', booking.SlotMaster__r.SlotDate__c);
            data.put(
                'InterviewTime',
                formatTime(booking.SlotMaster__r.SlotStartTime__c)
            );
            data.put(
                'InterviewEndTime',
                formatTime(booking.SlotMaster__r.SlotEndTime__c)
            );
            data.put(
                'InterviewVenue',
                booking.SlotMaster__r.LocationMaster__r?.AddressInformation__c
            );
            data.put('RoundName', booking.RoundMaster__r?.Name);
            data.put('PanelName', booking.Panel_Master__r?.Name);

            return data;
        }

        private Map<String, Object> buildApplicationSlotBookingData(
            ApplicationSlotBooking__c booking
        ) {
            return buildApplicationSlotBookingData(
                booking == null ? null : booking.Application__r,
                booking
            );
        }
    }

    public static String formatTime(Time val) {
        if (val == null) {
            return '';
        }

        DateTime dt = DateTime.newInstance(
            Date.newInstance(2000, 1, 1),
            val
        );

        return dt.format('hh:mm a');
    }

}