public class OfferLetterGenerationDispatcher {
    private static Set<Id> pendingAdmissionDecisionIds = new Set<Id>();
    private static Boolean dispatchDeferred = false;

    public static void beginDeferredDispatch() {
        dispatchDeferred = true;
    }

    public static void requestGeneration(List<Id> admissionDecisionIds) {
        if (admissionDecisionIds != null) {
            pendingAdmissionDecisionIds.addAll(admissionDecisionIds);
        }

        if (!dispatchDeferred) {
            dispatchPendingRequests();
        }
    }

    public static void endDeferredDispatch() {
        dispatchDeferred = false;
        dispatchPendingRequests();
    }

    private static void dispatchPendingRequests() {
        if (pendingAdmissionDecisionIds.isEmpty()) {
            return;
        }

        List<Id> admissionDecisionIds = new List<Id>(
            pendingAdmissionDecisionIds
        );
        pendingAdmissionDecisionIds.clear();

        System.enqueueJob(
            new OfferLetterGeneratorBulk(admissionDecisionIds)
        );
    }
}