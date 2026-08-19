public with sharing class DashboardAnnouncementService {

    private static final Set<String> INTERVIEW_STATES = new Set<String>{
        'Interview Round 1',
        'Interview Round 2'
    };

    private static final Set<String> OFFER_STATES = new Set<String>{
        'Offer Issued',
        'Offer Accepted',
        'Withdrawn'
    };

    private static final Set<String> NOT_ELIGIBLE_STATES = new Set<String>{
        'Disqualified', 'Reject Round 1', 'Reject Round 2'
    };

    private static final Set<String> WAITLISTED_STATES = new Set<String>{
        'Waitlisted'
    };

    public static List<CommunicationsController.DashboardAnnouncement> getAnnouncements(
        Id applicationId
    ) {
        if (applicationId == null) {
            return new List<CommunicationsController.DashboardAnnouncement>();
        }

        Application__c application = getApplicationForDashboard(applicationId);

        if (application == null) {
            return new List<CommunicationsController.DashboardAnnouncement>();
        }

        return sortAnnouncementsByPriority(
            buildAnnouncementsForApplication(application)
        );
    }

    public static List<CommunicationsController.DashboardAnnouncement> getAnnouncements(
        List<Id> applicationIds
    ) {
        List<CommunicationsController.DashboardAnnouncement> announcements =
            new List<CommunicationsController.DashboardAnnouncement>();

        if (applicationIds == null || applicationIds.isEmpty()) {
            return announcements;
        }

        List<Application__c> applications = getApplicationsForDashboard(
            applicationIds
        );

        for (Application__c application : applications) {
            announcements.addAll(
                buildAnnouncementsForApplication(application)
            );
        }

        return sortAnnouncementsByPriority(announcements);
    }

    private static Application__c getApplicationForDashboard(
        Id applicationId
    ) {
        List<Application__c> applications = getApplicationsForDashboard(
            new List<Id>{ applicationId }
        );

        return applications.isEmpty()
            ? null
            : applications[0];
    }

    private static List<Application__c> getApplicationsForDashboard(
        List<Id> applicationIds
    ) {
        if (applicationIds == null || applicationIds.isEmpty()) {
            return new List<Application__c>();
        }

        return [
            SELECT
                Id,
                Name,
                Applicant_State_Management__c,
                Program__c,
                Program__r.Id,
                Program__r.Name,
                Program__r.Program_Code__c,
                (
                    SELECT
                        Id,
                        BookingState__c,
                        Slot_Date__c,
                        CreatedDate
                    FROM ApplicationSlotBookings__r
                    WHERE BookingState__c != 'Cancelled'
                    ORDER BY Slot_Date__c ASC, CreatedDate DESC
                    LIMIT 1
                ),
                (
                    SELECT
                        Id,
                        Result__c,
                        Offer_Accepted__c,
                        Offer_Declined__c,
                        CreatedDate
                    FROM Admission_Decisions__r
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                )
            FROM Application__c
            WHERE Id IN :applicationIds
        ];
    }

    private static List<CommunicationsController.DashboardAnnouncement> buildAnnouncementsForApplication(
        Application__c application
    ) {
        List<CommunicationsController.DashboardAnnouncement> announcements =
            new List<CommunicationsController.DashboardAnnouncement>();

        if (application == null || application.Program__r == null) {
            return announcements;
        }

        List<CommunicationsController.CommunicationScenario> scenarios =
            evaluateScenarios(application);

        for (CommunicationsController.CommunicationScenario scenario : scenarios) {
            CommunicationsController.DashboardAnnouncement announcement =
                buildAnnouncement(
                    application,
                    scenario
                );

            if (announcement != null) {
                announcements.add(announcement);
            }
        }

        return announcements;
    }

    private static List<CommunicationsController.CommunicationScenario> evaluateScenarios(
        Application__c application
    ) {
        List<CommunicationsController.CommunicationScenario> scenarios =
            new List<CommunicationsController.CommunicationScenario>();

        if (hasInterviewAnnouncement(application)) {
            scenarios.add(
                CommunicationsController.CommunicationScenario.INTERVIEW_SCHEDULED
            );
        }

        if (hasOfferAnnouncement(application)) {
            scenarios.add(
                CommunicationsController.CommunicationScenario.OFFER_AVAILABLE
            );
        }

        if (hasOfferWaitlisted(application)) {
            scenarios.add(
                CommunicationsController.CommunicationScenario.OFFER_WAITLISTED
            );
        }

        if (hasOfferNotEligible(application)) {
            scenarios.add(
                CommunicationsController.CommunicationScenario.OFFER_NOT_ELIGIBLE
            );
        }

        return scenarios;
    }

    private static Boolean hasInterviewAnnouncement(
        Application__c application
    ) {
        if (application == null) {
            return false;
        }

        if (!INTERVIEW_STATES.contains(application.Applicant_State_Management__c)) {
            return false;
        }

        return application.ApplicationSlotBookings__r != null
            && !application.ApplicationSlotBookings__r.isEmpty();
    }

    private static Boolean hasOfferAnnouncement(
        Application__c application
    ) {
        if (application == null) {
            return false;
        }

        if (!OFFER_STATES.contains(application.Applicant_State_Management__c)) {
            return false;
        }

        if (
            application.Admission_Decisions__r == null ||
            application.Admission_Decisions__r.isEmpty()
        ) {
            return false;
        }

        Admission_Decision__c decision =
            application.Admission_Decisions__r[0];

        return decision != null
            && decision.Result__c == 'Eligible for Admission';
    }

    private static Boolean hasOfferWaitlisted(
        Application__c application
    ) {
        if (application == null) {
            return false;
        }

        if (!WAITLISTED_STATES.contains(application.Applicant_State_Management__c)) {
            return false;
        }

        if (
            application.Admission_Decisions__r == null ||
            application.Admission_Decisions__r.isEmpty()
        ) {
            return false;
        }

        Admission_Decision__c decision =
            application.Admission_Decisions__r[0];

        return decision != null
            && decision.Result__c == 'Waitlisted';
    }

    private static Boolean hasOfferNotEligible(
        Application__c application
    ) {
        if (application == null) {
            return false;
        }

        if (!NOT_ELIGIBLE_STATES.contains(application.Applicant_State_Management__c)) {
            return false;
        }

        if (
            application.Admission_Decisions__r == null ||
            application.Admission_Decisions__r.isEmpty()
        ) {
            return false;
        }

        Admission_Decision__c decision =
            application.Admission_Decisions__r[0];

        return decision != null
            && decision.Result__c == 'Not Eligible';
    }

    private static CommunicationsController.DashboardAnnouncement buildAnnouncement(
        Application__c application,
        CommunicationsController.CommunicationScenario scenario
    ) {
        CommunicationConfiguration__mdt configuration =
            getConfigurationOrNull(
                application.Program__r.Program_Code__c,
                scenario
            );

        if (!isDashboardEnabled(configuration)) {
            return null;
        }

        CommunicationsController.CommunicationRequest request =
            new CommunicationsController.CommunicationRequest();
        request.scenario = scenario;
        request.programId = application.Program__c;
        request.applicationId = application.Id;
        request.referenceRecordId =
            resolveReferenceRecordId(application, scenario);

        CommunicationProviderFactory.ICommunicationProvider provider =
            CommunicationProviderFactory.getProvider(
                configuration.ProviderType__c
            );

        Map<String, Object> templateData =
            buildTemplateData(
                request,
                provider.getData(request)
            );

        String renderedHtml = CommunicationsController.renderTemplate(
            configuration.DashboardTemplate__c,
            templateData
        );

        if (String.isBlank(renderedHtml)) {
            return null;
        }

        CommunicationsController.DashboardAnnouncement announcement =
            new CommunicationsController.DashboardAnnouncement();
        announcement.scenario = scenario;
        announcement.htmlContent = renderedHtml;
        announcement.priority =
            configuration.Priority__c == null
                ? 0
                : configuration.Priority__c.intValue();
        announcement.applicationId = application.Id;
        announcement.programId = application.Program__c;

        return announcement;
    }

    private static Boolean isDashboardEnabled(
        CommunicationConfiguration__mdt configuration
    ) {
        return configuration != null
            && configuration.DashboardAnnouncementEnabled__c == true
            && !String.isBlank(configuration.DashboardTemplate__c)
            && !String.isBlank(configuration.ProviderType__c);
    }

    private static Id resolveReferenceRecordId(
        Application__c application,
        CommunicationsController.CommunicationScenario scenario
    ) {
        if (
            scenario ==
                CommunicationsController.CommunicationScenario.INTERVIEW_SCHEDULED &&
            application.ApplicationSlotBookings__r != null &&
            !application.ApplicationSlotBookings__r.isEmpty()
        ) {
            return application.ApplicationSlotBookings__r[0].Id;
        }

        if (
            scenario ==
                CommunicationsController.CommunicationScenario.OFFER_AVAILABLE &&
            application.Admission_Decisions__r != null &&
            !application.Admission_Decisions__r.isEmpty()
        ) {
            return application.Admission_Decisions__r[0].Id;
        }

        return application.Id;
    }

    private static CommunicationConfiguration__mdt getConfigurationOrNull(
        String programCode,
        CommunicationsController.CommunicationScenario scenario
    ) {
        try {
            return CommunicationConfigurationService.getConfiguration(
                programCode,
                scenario
            );
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> buildTemplateData(
        CommunicationsController.CommunicationRequest request,
        Map<String, Object> providerData
    ) {
        Map<String, Object> mergedData = new Map<String, Object>();

        if (providerData != null) {
            mergedData.putAll(providerData);
        }

        mergedData.put('Scenario', String.valueOf(request.scenario));
        mergedData.put('ProgramId', request.programId);
        mergedData.put('ApplicationId', request.applicationId);
        mergedData.put('ReferenceRecordId', request.referenceRecordId);

        return mergedData;
    }

    private static List<CommunicationsController.DashboardAnnouncement> sortAnnouncementsByPriority(
        List<CommunicationsController.DashboardAnnouncement> announcements
    ) {
        List<CommunicationsController.DashboardAnnouncement> sortedAnnouncements =
            new List<CommunicationsController.DashboardAnnouncement>();

        for (CommunicationsController.DashboardAnnouncement announcement : announcements) {
            Integer insertAt = sortedAnnouncements.size();
            Integer currentPriority = getPriorityValue(announcement);

            for (Integer index = 0; index < sortedAnnouncements.size(); index++) {
                if (
                    currentPriority <
                    getPriorityValue(sortedAnnouncements[index])
                ) {
                    insertAt = index;
                    break;
                }
            }

            if (insertAt == sortedAnnouncements.size()) {
                sortedAnnouncements.add(announcement);
            } else {
                sortedAnnouncements.add(insertAt, announcement);
            }
        }

        return sortedAnnouncements;
    }

    private static Integer getPriorityValue(
        CommunicationsController.DashboardAnnouncement announcement
    ) {
        return announcement == null || announcement.priority == null
            ? 0
            : announcement.priority;
    }

    public class DashboardAnnouncementException extends Exception {}
}