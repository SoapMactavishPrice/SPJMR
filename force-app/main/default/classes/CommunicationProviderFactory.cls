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
    }

    public class AdmissionDecisionProvider implements ICommunicationProvider {

        public Map<String, Object> getData(
            CommunicationsController.CommunicationRequest request
        ) {
            validateRequest(request);

            Map<Id, Map<String, Object>> dataByApplicationId =
                getDataByApplicationIds(
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
                data.put('ApplicationNumber', application.Application_Number__c);
                data.put('ApplicationName', application.Name);

                data.put('ApplicantName', application.Applicant__r.Name);
                data.put('ApplicantEmail', application.Applicant__r.PersonEmail);
                data.put(
                    'ApplicantStateManagement',
                    application.Applicant_State_Management__c
                );

                data.put('ProgramId', application.Program__r.Id);
                data.put('ProgramName', application.Program__r.Name);
                data.put('ProgramCode', application.Program__r.Program_Code__c);

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

                ApplicationSlotBooking__c booking =
                    application.ApplicationSlotBookings__r[0];

                Map<String, Object> data = new Map<String, Object>();

                data.put('ApplicationId', application.Id);
                data.put('ApplicationNumber', application.Application_Number__c);
                data.put('ApplicationName', application.Name);

                data.put('ApplicantName', application.Applicant__r.Name);
                data.put('ApplicantEmail', application.Applicant__r.PersonEmail);

                data.put('ProgramId', application.Program__r.Id);
                data.put('ProgramName', application.Program__r.Name);
                data.put('ProgramCode', application.Program__r.Program_Code__c);

                data.put('BookingId', booking.Id);
                data.put('BookingState', booking.BookingState__c);
                data.put('InterviewDate', booking.SlotMaster__r.SlotDate__c);
                data.put('InterviewTime', booking.SlotMaster__r.SlotStartTime__c);
                data.put('InterviewEndTime', booking.SlotMaster__r.SlotEndTime__c);
                data.put(
                    'InterviewVenue',
                    booking.SlotMaster__r.LocationMaster__r?.AddressInformation__c
                );
                data.put('RoundName', booking.RoundMaster__r?.Name);
                data.put('PanelName', booking.Panel_Master__r?.Name);

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
    }

}