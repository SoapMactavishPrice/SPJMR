public with sharing class CommunicationDispatchQueueable
    implements Queueable {

    private static final Integer DEFAULT_SCOPE_SIZE = 50;

    private String serializedRequests;
    private Integer scopeSize;

    public CommunicationDispatchQueueable(
        List<CommunicationsController.CommunicationRequest> requests
    ) {
        this(requests, DEFAULT_SCOPE_SIZE);
    }

    public CommunicationDispatchQueueable(
        List<CommunicationsController.CommunicationRequest> requests,
        Integer scopeSize
    ) {
        this.serializedRequests = JSON.serialize(
            requests == null
                ? new List<CommunicationsController.CommunicationRequest>()
                : requests
        );
        this.scopeSize =
            scopeSize == null || scopeSize <= 0
                ? DEFAULT_SCOPE_SIZE
                : scopeSize;
    }

    public void execute(QueueableContext context) {
        List<CommunicationsController.CommunicationRequest> requests =
            deserializeRequests(serializedRequests);

        if (requests.isEmpty()) {
            return;
        }

        CommunicationsController.CommunicationRequest currentRequest =
            requests.remove(0);
        List<Id> applicationIds = normalizeApplicationIds(currentRequest);

        if (applicationIds.isEmpty()) {
            enqueueRemainingIfNeeded(requests);
            return;
        }

        Integer currentScopeSize = Math.min(scopeSize, applicationIds.size());
        List<Id> scopeApplicationIds = new List<Id>();
        for (Integer index = 0; index < currentScopeSize; index++) {
            scopeApplicationIds.add(applicationIds[index]);
        }

        CommunicationService.processAsyncScope(
            currentRequest,
            scopeApplicationIds
        );

        if (applicationIds.size() > currentScopeSize) {
            requests.add(
                0,
                buildContinuationRequest(
                    currentRequest,
                    applicationIds,
                    currentScopeSize
                )
            );
        }

        enqueueRemainingIfNeeded(requests);
    }

    private void enqueueRemainingIfNeeded(
        List<CommunicationsController.CommunicationRequest> requests
    ) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        System.enqueueJob(
            new CommunicationDispatchQueueable(
                requests,
                scopeSize
            )
        );
    }

    private static List<CommunicationsController.CommunicationRequest> deserializeRequests(
        String serializedRequests
    ) {
        if (String.isBlank(serializedRequests)) {
            return new List<CommunicationsController.CommunicationRequest>();
        }

        return (List<CommunicationsController.CommunicationRequest>) JSON.deserialize(
            serializedRequests,
            List<CommunicationsController.CommunicationRequest>.class
        );
    }

    private static CommunicationsController.CommunicationRequest buildContinuationRequest(
        CommunicationsController.CommunicationRequest sourceRequest,
        List<Id> applicationIds,
        Integer processedCount
    ) {
        CommunicationsController.CommunicationRequest continuationRequest =
            cloneRequest(sourceRequest);

        continuationRequest.applicationId = null;
        continuationRequest.referenceRecordId = null;
        continuationRequest.applicationIds = new List<Id>();
        continuationRequest.applicationIdToReferenceRecordId = null;

        for (Integer index = processedCount; index < applicationIds.size(); index++) {
            continuationRequest.applicationIds.add(applicationIds[index]);
        }

        if (
            sourceRequest != null &&
            sourceRequest.applicationIdToReferenceRecordId != null &&
            !sourceRequest.applicationIdToReferenceRecordId.isEmpty()
        ) {
            continuationRequest.applicationIdToReferenceRecordId =
                new Map<Id, Id>();
            for (Id applicationId : continuationRequest.applicationIds) {
                if (sourceRequest.applicationIdToReferenceRecordId.containsKey(applicationId)) {
                    continuationRequest.applicationIdToReferenceRecordId.put(
                        applicationId,
                        sourceRequest.applicationIdToReferenceRecordId.get(applicationId)
                    );
                }
            }
        }

        return continuationRequest;
    }

    private static CommunicationsController.CommunicationRequest cloneRequest(
        CommunicationsController.CommunicationRequest sourceRequest
    ) {
        CommunicationsController.CommunicationRequest clonedRequest =
            new CommunicationsController.CommunicationRequest();

        if (sourceRequest == null) {
            return clonedRequest;
        }

        clonedRequest.scenario = sourceRequest.scenario;
        clonedRequest.programId = sourceRequest.programId;
        clonedRequest.applicationId = sourceRequest.applicationId;
        clonedRequest.referenceRecordId = sourceRequest.referenceRecordId;

        if (sourceRequest.options != null) {
            clonedRequest.options = new CommunicationsController.CommunicationOptions();
            clonedRequest.options.sendEmail = sourceRequest.options.sendEmail;
            clonedRequest.options.sendNotification = sourceRequest.options.sendNotification;
            clonedRequest.options.documentIdentifier =
                sourceRequest.options.documentIdentifier;
        }

        if (sourceRequest.applicationIds != null) {
            clonedRequest.applicationIds = new List<Id>();
            clonedRequest.applicationIds.addAll(sourceRequest.applicationIds);
        }

        if (sourceRequest.applicationIdToReferenceRecordId != null) {
            clonedRequest.applicationIdToReferenceRecordId = new Map<Id, Id>();
            clonedRequest.applicationIdToReferenceRecordId.putAll(
                sourceRequest.applicationIdToReferenceRecordId
            );
        }

        return clonedRequest;
    }

    private static List<Id> normalizeApplicationIds(
        CommunicationsController.CommunicationRequest request
    ) {
        List<Id> applicationIds = new List<Id>();

        if (request == null) {
            return applicationIds;
        }

        if (request.applicationIdToReferenceRecordId != null) {
            for (Id applicationId : request.applicationIdToReferenceRecordId.keySet()) {
                if (applicationId != null && !applicationIds.contains(applicationId)) {
                    applicationIds.add(applicationId);
                }
            }
        }

        if (request.applicationIds != null) {
            for (Id applicationId : request.applicationIds) {
                if (applicationId != null && !applicationIds.contains(applicationId)) {
                    applicationIds.add(applicationId);
                }
            }
        }

        if (
            request.applicationId != null &&
            !applicationIds.contains(request.applicationId)
        ) {
            applicationIds.add(request.applicationId);
        }

        return applicationIds;
    }
}