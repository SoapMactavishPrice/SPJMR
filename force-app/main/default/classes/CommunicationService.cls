public with sharing class CommunicationService {

    private static final Integer DEFAULT_BULK_BATCH_SIZE = 50;

    public static void communicate(
        CommunicationsController.CommunicationRequest request
    ) {
        List<Id> targetApplicationIds = normalizeApplicationIds(request);

        if (targetApplicationIds.isEmpty()) {
            throw new CommunicationServiceException(
                'At least one Application Id is required.'
            );
        }

        if (targetApplicationIds.size() > 1) {
            communicateAsync(request);
            return;
        }

        processScope(
            request,
            targetApplicationIds
        );
    }

    public static Id communicateAsync(
        CommunicationsController.CommunicationRequest request
    ) {
        List<Id> targetApplicationIds = normalizeApplicationIds(request);

        if (targetApplicationIds.isEmpty()) {
            throw new CommunicationServiceException(
                'At least one Application Id is required.'
            );
        }

        CommunicationsController.CommunicationRequest asyncRequest =
            cloneRequest(request);
        asyncRequest.applicationIds = targetApplicationIds;

        return Database.executeBatch(
            new BulkCommunicationBatch(asyncRequest),
            DEFAULT_BULK_BATCH_SIZE
        );
    }

    public static void processAsyncScope(
        CommunicationsController.CommunicationRequest request,
        List<Id> applicationIds
    ) {
        processScope(request, applicationIds);
    }

    private static void processScope(
        CommunicationsController.CommunicationRequest request,
        List<Id> applicationIds
    ) {
        validateBulkRequest(request, applicationIds);

        Map<Id, Application__c> applicationsById =
            getApplicationsById(applicationIds);
        validateApplicationsForProgram(
            request.programId,
            applicationsById,
            applicationIds
        );

        CommunicationConfiguration__mdt configuration =
            getConfigurationForRequest(
                request,
                applicationsById
            );
        CommunicationsController.CommunicationOptions options =
            resolveOptions(
                request.options,
                configuration
            );

        CommunicationProviderFactory.ICommunicationProvider provider =
            CommunicationProviderFactory.getProvider(
                configuration.ProviderType__c
            );
        Map<Id, Map<String, Object>> providerDataByApplicationId =
            provider.getDataByApplicationIds(applicationIds);

        List<CustomNotification__c> notificationsToInsert =
            new List<CustomNotification__c>();

        for (Id applicationId : applicationIds) {
            if (!applicationsById.containsKey(applicationId)) {
                continue;
            }

            Map<String, Object> providerData =
                providerDataByApplicationId.get(applicationId);

            if (providerData == null) {
                continue;
            }

            Application__c application = applicationsById.get(applicationId);

            if (options.sendEmail == true) {
                sendEmail(
                    request,
                    application,
                    configuration,
                    providerData,
                    options
                );
            }

            if (options.sendNotification == true) {
                CustomNotification__c notification =
                    buildNotification(
                        request,
                        application,
                        configuration,
                        providerData,
                        options
                    );

                if (notification != null) {
                    notificationsToInsert.add(notification);
                }
            }
        }

        if (!notificationsToInsert.isEmpty()) {
            insert notificationsToInsert;
        }
    }

    private static void validateBulkRequest(
        CommunicationsController.CommunicationRequest request,
        List<Id> applicationIds
    ) {
        if (request == null) {
            throw new CommunicationServiceException(
                'Communication request cannot be null.'
            );
        }

        if (request.programId == null) {
            throw new CommunicationServiceException(
                'Program Id is required.'
            );
        }

        if (request.scenario == null) {
            throw new CommunicationServiceException(
                'Communication Scenario is required.'
            );
        }

        if (applicationIds == null || applicationIds.isEmpty()) {
            throw new CommunicationServiceException(
                'At least one Application Id is required.'
            );
        }
    }

    private static List<Id> normalizeApplicationIds(
        CommunicationsController.CommunicationRequest request
    ) {
        List<Id> normalizedApplicationIds = new List<Id>();

        if (request == null) {
            return normalizedApplicationIds;
        }

        if (request.applicationIds != null) {
            for (Id applicationId : request.applicationIds) {
                if (
                    applicationId != null &&
                    !normalizedApplicationIds.contains(applicationId)
                ) {
                    normalizedApplicationIds.add(applicationId);
                }
            }
        }

        if (
            request.applicationId != null &&
            !normalizedApplicationIds.contains(request.applicationId)
        ) {
            normalizedApplicationIds.add(request.applicationId);
        }

        return normalizedApplicationIds;
    }

    private static CommunicationsController.CommunicationRequest cloneRequest(
        CommunicationsController.CommunicationRequest request
    ) {
        CommunicationsController.CommunicationRequest clonedRequest =
            new CommunicationsController.CommunicationRequest();

        if (request == null) {
            return clonedRequest;
        }

        clonedRequest.scenario = request.scenario;
        clonedRequest.programId = request.programId;
        clonedRequest.applicationId = request.applicationId;
        clonedRequest.referenceRecordId = request.referenceRecordId;
        clonedRequest.options = cloneOptions(request.options);

        if (request.applicationIds != null) {
            clonedRequest.applicationIds = new List<Id>();
            clonedRequest.applicationIds.addAll(request.applicationIds);
        }

        return clonedRequest;
    }

    private static CommunicationsController.CommunicationOptions cloneOptions(
        CommunicationsController.CommunicationOptions options
    ) {
        if (options == null) {
            return null;
        }

        CommunicationsController.CommunicationOptions clonedOptions =
            new CommunicationsController.CommunicationOptions();
        clonedOptions.sendEmail = options.sendEmail;
        clonedOptions.sendNotification = options.sendNotification;
        clonedOptions.documentIdentifier = options.documentIdentifier;

        return clonedOptions;
    }

    private static Map<Id, Application__c> getApplicationsById(
        List<Id> applicationIds
    ) {
        Map<Id, Application__c> applicationsById =
            new Map<Id, Application__c>();

        for (
            Application__c application :
            [
                SELECT
                    Id,
                    Program__c,
                    Program__r.Program_Code__c,
                    Applicant__r.PersonEmail
                FROM Application__c
                WHERE Id IN :applicationIds
            ]
        ) {
            applicationsById.put(application.Id, application);
        }

        return applicationsById;
    }

    private static void validateApplicationsForProgram(
        Id programId,
        Map<Id, Application__c> applicationsById,
        List<Id> applicationIds
    ) {
        for (Id applicationId : applicationIds) {
            Application__c application = applicationsById.get(applicationId);

            if (application == null) {
                throw new CommunicationServiceException(
                    'Application not found for Id ' + applicationId + '.'
                );
            }

            if (application.Program__c != programId) {
                throw new CommunicationServiceException(
                    'All applications in a communication request must belong to Program Id '
                    + programId
                    + '.'
                );
            }
        }
    }

    private static CommunicationConfiguration__mdt getConfigurationForRequest(
        CommunicationsController.CommunicationRequest request,
        Map<Id, Application__c> applicationsById
    ) {
        Application__c sampleApplication =
            applicationsById.values().isEmpty()
                ? null
                : applicationsById.values()[0];

        if (
            sampleApplication == null ||
            sampleApplication.Program__r == null ||
            String.isBlank(sampleApplication.Program__r.Program_Code__c)
        ) {
            throw new CommunicationServiceException(
                'Program Code is required to resolve communication configuration.'
            );
        }

        return CommunicationConfigurationService.getConfiguration(
            sampleApplication.Program__r.Program_Code__c,
            request.scenario
        );
    }

    private static CommunicationsController.CommunicationOptions resolveOptions(
        CommunicationsController.CommunicationOptions requestOptions,
        CommunicationConfiguration__mdt configuration
    ) {
        if (requestOptions != null) {
            return requestOptions;
        }

        CommunicationsController.CommunicationOptions options =
            new CommunicationsController.CommunicationOptions();
        options.sendEmail = configuration.DefaultSendEmail__c;
        options.sendNotification = configuration.DefaultSendNotification__c;

        return options;
    }

    private static void sendEmail(
        CommunicationsController.CommunicationRequest request,
        Application__c application,
        CommunicationConfiguration__mdt configuration,
        Map<String, Object> providerData,
        CommunicationsController.CommunicationOptions options
    ) {
        if (String.isBlank(configuration.EmailFlowName__c)) {
            throw new CommunicationServiceException(
                'Email flow is not configured for scenario '
                + request.scenario
                + '.'
            );
        }

        Map<String, Object> flowInputs = buildMergedData(
            request,
            application.Id,
            providerData
        );

        if (
            options != null &&
            !String.isBlank(options.documentIdentifier)
        ) {
            flowInputs.put('documentIdentifier', options.documentIdentifier);
            flowInputs.put('DocumentIdentifier', options.documentIdentifier);
        }

        Flow.Interview emailFlow = Flow.Interview.createInterview(
            configuration.EmailFlowName__c,
            flowInputs
        );
        emailFlow.start();
    }

    private static CustomNotification__c buildNotification(
        CommunicationsController.CommunicationRequest request,
        Application__c application,
        CommunicationConfiguration__mdt configuration,
        Map<String, Object> providerData,
        CommunicationsController.CommunicationOptions options
    ) {
        if (String.isBlank(configuration.NotificationTemplate__c)) {
            throw new CommunicationServiceException(
                'Notification template is not configured for scenario '
                + request.scenario
                + '.'
            );
        }

        Map<String, Object> templateData = buildMergedData(
            request,
            application.Id,
            providerData
        );

        if (
            options != null &&
            !String.isBlank(options.documentIdentifier)
        ) {
            templateData.put('DocumentIdentifier', options.documentIdentifier);
        }

        RenderedNotification renderedNotification =
            renderNotificationTemplate(
                configuration.NotificationTemplate__c,
                templateData,
                request.scenario
            );

        String recipientEmail = resolveRecipientEmail(
            templateData,
            application
        );

        if (String.isBlank(recipientEmail)) {
            return null;
        }

        return new CustomNotification__c(
            IsRead__c = false,
            Title__c = renderedNotification.title,
            Message__c = renderedNotification.message,
            Recipient_Email__c = recipientEmail
        );
    }

    private static Map<String, Object> buildMergedData(
        CommunicationsController.CommunicationRequest request,
        Id applicationId,
        Map<String, Object> providerData
    ) {
        Map<String, Object> mergedData = new Map<String, Object>();

        if (providerData != null) {
            mergedData.putAll(providerData);
        }

        mergedData.put('Scenario', String.valueOf(request.scenario));
        mergedData.put('ProgramId', request.programId);
        mergedData.put('ApplicationId', applicationId);
        mergedData.put('ReferenceRecordId', request.referenceRecordId);

        return mergedData;
    }

    private static RenderedNotification renderNotificationTemplate(
        String template,
        Map<String, Object> templateData,
        CommunicationsController.CommunicationScenario scenario
    ) {
        String renderedTemplate = CommunicationsController.renderTemplate(
            template,
            templateData
        );

        RenderedNotification renderedNotification =
            new RenderedNotification();
        renderedNotification.title = humanizeScenario(scenario);
        renderedNotification.message = renderedTemplate;

        List<String> templateLines = renderedTemplate.split('\\r?\\n', 2);
        if (
            !templateLines.isEmpty() &&
            templateLines[0] != null &&
            templateLines[0].toLowerCase().startsWith('subject:')
        ) {
            renderedNotification.title =
                templateLines[0].substring('Subject:'.length()).trim();
            renderedNotification.message =
                templateLines.size() > 1
                    ? templateLines[1].trim()
                    : '';
        }

        return renderedNotification;
    }

    private static String resolveRecipientEmail(
        Map<String, Object> templateData,
        Application__c application
    ) {
        if (
            templateData != null &&
            templateData.containsKey('ApplicantEmail') &&
            templateData.get('ApplicantEmail') != null
        ) {
            return String.valueOf(templateData.get('ApplicantEmail'));
        }

        return application?.Applicant__r?.PersonEmail;
    }

    private static String humanizeScenario(
        CommunicationsController.CommunicationScenario scenario
    ) {
        if (scenario == null) {
            return 'Notification';
        }

        String scenarioLabel = String.valueOf(scenario)
            .replace('_', ' ')
            .toLowerCase();

        List<String> words = scenarioLabel.split(' ');
        for (Integer index = 0; index < words.size(); index++) {
            if (String.isBlank(words[index])) {
                continue;
            }

            words[index] =
                words[index].substring(0, 1).toUpperCase()
                + words[index].substring(1);
        }

        return String.join(words, ' ');
    }

    private class RenderedNotification {
        private String title;
        private String message;
    }

    public class CommunicationServiceException extends Exception {}
}