public with sharing class BulkCommunicationBatch
    implements Queueable {

    private CommunicationsController.CommunicationRequest requestTemplate;
    private List<Id> remainingApplicationIds;
    private Integer scopeSize;

    public BulkCommunicationBatch(
        CommunicationsController.CommunicationRequest requestTemplate
    ) {
        this(
            requestTemplate,
            normalizeApplicationIds(requestTemplate),
            50
        );
    }

    public BulkCommunicationBatch(
        CommunicationsController.CommunicationRequest requestTemplate,
        List<Id> applicationIds,
        Integer scopeSize
    ) {
        this.requestTemplate = requestTemplate;
        this.remainingApplicationIds =
            applicationIds == null
                ? new List<Id>()
                : new List<Id>(applicationIds);
        this.scopeSize =
            scopeSize == null || scopeSize <= 0
                ? 50
                : scopeSize;
    }

    public void execute(QueueableContext context) {
        if (remainingApplicationIds == null || remainingApplicationIds.isEmpty()) {
            return;
        }

        Integer currentScopeSize = Math.min(
            scopeSize,
            remainingApplicationIds.size()
        );
        List<Id> scopeApplicationIds = new List<Id>();
        for (Integer index = 0; index < currentScopeSize; index++) {
            scopeApplicationIds.add(remainingApplicationIds[index]);
        }

        CommunicationService.processAsyncScope(
            requestTemplate,
            scopeApplicationIds
        );

        if (remainingApplicationIds.size() > currentScopeSize) {
            List<Id> nextApplicationIds = new List<Id>();
            for (
                Integer index = currentScopeSize;
                index < remainingApplicationIds.size();
                index++
            ) {
                nextApplicationIds.add(remainingApplicationIds[index]);
            }
            System.enqueueJob(
                new BulkCommunicationBatch(
                    requestTemplate,
                    nextApplicationIds,
                    scopeSize
                )
            );
        }
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
                if (
                    applicationId != null &&
                    !applicationIds.contains(applicationId)
                ) {
                    applicationIds.add(applicationId);
                }
            }
        }

        if (request.applicationIds != null) {
            for (Id applicationId : request.applicationIds) {
                if (
                    applicationId != null &&
                    !applicationIds.contains(applicationId)
                ) {
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