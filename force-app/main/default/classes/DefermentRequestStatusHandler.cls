@SuppressWarnings('PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.QueueableWithoutFinalizer')
public with sharing class DefermentRequestStatusHandler {
    @TestVisible
    private static final String STATUS_PROCESS_COMPLETE =
        'Deferment Process Complete';

    @TestVisible
    private static final String STATUS_PENDING_REENROLLMENT =
        'Pending Re-enrollment';

    @TestVisible
    private static final String STATUS_WITHDRAWAL = 'Withdrawal';

    @TestVisible
    private static final String STATUS_REJOINING_COMPLETE = 'Rejoining Complete';

    @TestVisible
    private static final String STATUS_ALL_RIGHTS_REACTIVATED =
        'All Rights Reactivated';

    @TestVisible
    private static final String STATUS_PAYMENT_CONFIRMED = 'Payment Confirmed';

    private static final List<String> STATUS_ORDER = new List<String>{
        'Deferment Form Enabled',
        'Form Submitted',
        'Pending Chairperson\'s Approval',
        'Pending Dean\'s / AD\'s Approval',
        'Rejoining Details',
        'Rejoining Details Updated',
        'No Dues Process Initiated',
        'No Dues Process Complete',
        'Access Removal Complete',
        'Deferment Process Complete',
        'Pending Re-enrollment',
        'Return to Campus Notification Sent',
        'Rejoining Confirmation Received',
        'Programme Architecture Communicated',
        'Fees Updated on ERP',
        'Payment Received',
        'Payment Confirmed',
        'Stakeholders Notified',
        'Student Record Reactivated',
        'Credentials Activated',
        'All Rights Reactivated',
        'Rejoining Complete'
    };

    private static Map<String, Integer> positions;

    @TestVisible
    private static final String STATUS_RECORD_REACTIVATED =
        'Student Record Reactivated';

    @TestVisible
    private static final String STATUS_REJOINING_DETAILS = 'Rejoining Details';

    @TestVisible
    private static final String STATUS_REJOINING_DETAILS_UPDATED =
        'Rejoining Details Updated';

    @TestVisible
    private static final String ENROLLMENT_STATUS_PENDING_REENROLLMENT =
        'Pending Re Enrollment';

    @TestVisible
    private static final String ENROLLMENT_STATUS_ACTIVE_REJOINED =
        'Active - Rejoined';

    public static void applyPendingReEnrollment(
        List<Deferment_Request__c> requests
    ) {
        if (requests == null) {
            return;
        }

        for (Deferment_Request__c request : requests) {
            if (request.Status__c != STATUS_PROCESS_COMPLETE) {
                continue;
            }

            request.Status__c = STATUS_PENDING_REENROLLMENT;
        }
    }

    public static void applyRejoiningComplete(
        List<Deferment_Request__c> requests
    ) {
        if (requests == null) {
            return;
        }

        for (Deferment_Request__c request : requests) {
            if (request.Status__c != STATUS_ALL_RIGHTS_REACTIVATED) {
                continue;
            }

            request.Status__c = STATUS_REJOINING_COMPLETE;
        }
    }

    public static void markStudentDeferredOnPendingReEnrollment(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById
    ) {
        applyEnrollmentStatusForTransition(
            requests,
            oldById,
            STATUS_PENDING_REENROLLMENT,
            ENROLLMENT_STATUS_PENDING_REENROLLMENT,
            true
        );
    }

    public static void markEnrollmentActiveOnRejoiningComplete(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById
    ) {
        applyEnrollmentStatusForTransition(
            requests,
            oldById,
            STATUS_REJOINING_COMPLETE,
            ENROLLMENT_STATUS_ACTIVE_REJOINED,
            false
        );
    }

    private static void applyEnrollmentStatusForTransition(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById,
        String requestStatus,
        String enrollmentStatus,
        Boolean markDeferred
    ) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> memberIds = new Set<Id>();
        for (Deferment_Request__c request : requests) {
            if (!justBecameStatus(request, oldById, requestStatus)) {
                continue;
            }
            if (request.Program_Cohort_Member__c != null) {
                memberIds.add(request.Program_Cohort_Member__c);
            }
        }

        if (memberIds.isEmpty()) {
            return;
        }

        List<ProgramCohortMember> members = [
            SELECT Id, ProgramEnrollmentId
            FROM ProgramCohortMember
            WHERE Id IN :memberIds
            WITH SYSTEM_MODE
        ];

        Set<Id> enrollmentIds = new Set<Id>();
        for (ProgramCohortMember member : members) {
            if (member.ProgramEnrollmentId != null) {
                enrollmentIds.add(member.ProgramEnrollmentId);
            }
        }

        if (enrollmentIds.isEmpty()) {
            return;
        }

        List<ProgramEnrollment> enrollmentsToUpdate = new List<ProgramEnrollment>();
        for (ProgramEnrollment enrollment : [
            SELECT Id, Status, isDeferred__c
            FROM ProgramEnrollment
            WHERE Id IN :enrollmentIds
            WITH SYSTEM_MODE
        ]) {
            Boolean changed = false;
            if (enrollment.Status != enrollmentStatus) {
                enrollment.Status = enrollmentStatus;
                changed = true;
            }
            if (markDeferred != null && enrollment.isDeferred__c != markDeferred) {
                enrollment.isDeferred__c = markDeferred;
                changed = true;
            }
            if (changed) {
                enrollmentsToUpdate.add(enrollment);
            }
        }

        if (!enrollmentsToUpdate.isEmpty()) {
            Database.update(enrollmentsToUpdate, false);
        }
    }

    private static Boolean justBecameStatus(
        Deferment_Request__c request,
        Map<Id, Deferment_Request__c> oldById,
        String status
    ) {
        if (request == null || request.Status__c != status) {
            return false;
        }
        if (oldById == null || request.Id == null) {
            return true;
        }
        Deferment_Request__c oldRequest = oldById.get(request.Id);
        return oldRequest == null || oldRequest.Status__c != status;
    }

    public static void rejectNegativeFee(List<Deferment_Request__c> requests) {
        if (requests == null) {
            return;
        }

        for (Deferment_Request__c request : requests) {
            if (
                request.Deferment_Application_Fee__c == null ||
                request.Deferment_Application_Fee__c >= 0
            ) {
                continue;
            }

            request.Deferment_Application_Fee__c.addError(
                'The Deferment Application Fee cannot be a negative amount. ' +
                'Enter 0 if no fee applies to this programme.'
            );
        }
    }

    public static void advanceOnRejoiningDetails(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById
    ) {
        if (requests == null || oldById == null) {
            return;
        }

        for (Deferment_Request__c request : requests) {
            if (request.Status__c != STATUS_REJOINING_DETAILS) {
                continue;
            }

            if (!hasEveryRejoiningDetail(request)) {
                continue;
            }

            request.Status__c = STATUS_REJOINING_DETAILS_UPDATED;
        }
    }

    private static Boolean hasEveryRejoiningDetail(
        Deferment_Request__c request
    ) {
        return request.Rejoining_Date__c != null
            && request.Rejoining_Batch__c != null
            && request.Rejoining_Fee_Deadline__c != null;
    }

    public static void enforceStatusOrder(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById
    ) {
        if (requests == null || oldById == null) {
            return;
        }

        for (Deferment_Request__c request : requests) {
            Deferment_Request__c old = oldById.get(request.Id);

            if (old == null || old.Status__c == request.Status__c) {
                continue;
            }

            if (isAlwaysAllowed(request)) {
                continue;
            }

            checkOneMove(request, old);
        }
    }

    private static void checkOneMove(
        Deferment_Request__c request,
        Deferment_Request__c old
    ) {
        Integer wasAt = positionOf(old.Status__c);
        Integer goingTo = positionOf(request.Status__c);

        if (wasAt == null || goingTo == null) {
            return;
        }

        if (goingTo < wasAt) {
            request.addError(
                'A Deferment Request cannot be moved back to "' +
                request.Status__c + '" once it has reached "' +
                old.Status__c + '". Completed steps cannot be reopened.'
            );
            return;
        }

        if (
            request.Status__c == STATUS_REJOINING_COMPLETE &&
            wasAt < positionOf(STATUS_PAYMENT_CONFIRMED)
        ) {
            request.addError(
                'This student cannot be marked "Rejoining Complete" yet. ' +
                'The rejoining fee has not been confirmed by Finance - ' +
                'the request is still at "' + old.Status__c + '".'
            );
        }
    }

    private static Boolean isAlwaysAllowed(Deferment_Request__c request) {
        return request.Status__c == STATUS_WITHDRAWAL
            || request.Approval_Status__c == 'Rejected';
    }

    private static Integer positionOf(String status) {
        if (positions == null) {
            positions = new Map<String, Integer>();
            for (Integer i = 0; i < STATUS_ORDER.size(); i++) {
                positions.put(STATUS_ORDER[i], i);
            }
        }

        return positions.get(status);
    }

    public static void mapStudentToRejoiningBatch(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById
    ) {
        List<Deferment_Request__c> reactivated =
            justReactivated(requests, oldById);

        if (reactivated.isEmpty()) {
            return;
        }

        Map<Id, ProgramCohortMember> originalByRequest =
            originalEnrolments(reactivated);

        Set<Id> alreadyInBatch = existingMemberships(
            reactivated,
            originalByRequest
        );

        List<ProgramCohortMember> toCreate = new List<ProgramCohortMember>();

        for (Deferment_Request__c request : reactivated) {
            ProgramCohortMember original = originalByRequest.get(request.Id);

            if (original == null || original.ProgramEnrollmentId == null) {
                request.addError(
                    'This request has no original batch enrolment, so the ' +
                    'student cannot be placed in the rejoining batch. ' +
                    'Please contact your administrator.'
                );
                continue;
            }

            if (alreadyInBatch.contains(original.ProgramEnrollmentId)) {
                continue;
            }

            toCreate.add(new ProgramCohortMember(
                ProgramCohortId = request.Rejoining_Batch__c,
                ProgramEnrollmentId = original.ProgramEnrollmentId,
                Roll_Number__c = original.Roll_Number__c,
                Serial_Number__c = original.Serial_Number__c
            ));
        }

        if (toCreate.isEmpty()) {
            return;
        }

        System.enqueueJob(new RejoiningBatchEnroller(toCreate));
    }

    public class RejoiningBatchEnroller implements Queueable {
        private final List<ProgramCohortMember> enrolments;

        public RejoiningBatchEnroller(List<ProgramCohortMember> members) {
            this.enrolments = members;
        }

        public void execute(QueueableContext ctx) {
            List<Database.SaveResult> results =
                Database.insert(enrolments, false);

            List<String> problems = new List<String>();

            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    problems.add(
                        'Programme Enrolment ' +
                        enrolments[i].ProgramEnrollmentId + ': ' +
                        results[i].getErrors()[0].getMessage()
                    );
                }
            }

            if (!problems.isEmpty()) {
                warnOwners(problems);
            }
        }

        private void warnOwners(List<String> problems) {
            Set<Id> batchIds = new Set<Id>();
            for (ProgramCohortMember m : enrolments) {
                batchIds.add(m.ProgramCohortId);
            }

            Set<String> addresses = new Set<String>();
            for (Deferment_Request__c request : [
                SELECT Owner.Email
                FROM Deferment_Request__c
                WHERE Rejoining_Batch__c IN :batchIds
                WITH SYSTEM_MODE
            ]) {
                if (String.isNotBlank(request.Owner.Email)) {
                    addresses.add(request.Owner.Email);
                }
            }

            if (addresses.isEmpty()) {
                return;
            }

            Messaging.SingleEmailMessage mail =
                new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>(addresses));
            mail.setSubject('Action needed: student not placed in rejoining batch');
            mail.setPlainTextBody(
                'A student was marked "Student Record Reactivated", but could ' +
                'not be placed in their rejoining batch:\n\n' +
                String.join(problems, '\n') +
                '\n\nPlease check the Rejoining Batch on the Deferment Request ' +
                'and set the status again.\n\n' +
                'This is an automated notification.'
            );
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail },
                false
            );
        }
    }

    private static List<Deferment_Request__c> justReactivated(
        List<Deferment_Request__c> requests,
        Map<Id, Deferment_Request__c> oldById
    ) {
        List<Deferment_Request__c> reactivated =
            new List<Deferment_Request__c>();

        if (requests == null) {
            return reactivated;
        }

        for (Deferment_Request__c request : requests) {
            if (request.Status__c != STATUS_RECORD_REACTIVATED) {
                continue;
            }

            Deferment_Request__c old = oldById == null
                ? null
                : oldById.get(request.Id);

            if (old != null && old.Status__c == STATUS_RECORD_REACTIVATED) {
                continue;
            }

            if (request.Rejoining_Batch__c == null) {
                request.addError(
                    'Please choose a Rejoining Batch before marking the ' +
                    'student record reactivated. Without it the student ' +
                    'cannot be placed in the batch they are returning to.'
                );
                continue;
            }

            reactivated.add(request);
        }

        return reactivated;
    }

    private static Map<Id, ProgramCohortMember> originalEnrolments(
        List<Deferment_Request__c> reactivated
    ) {
        Map<Id, Id> memberIdByRequest = new Map<Id, Id>();

        for (Deferment_Request__c request : reactivated) {
            if (request.Program_Cohort_Member__c != null) {
                memberIdByRequest.put(
                    request.Id,
                    request.Program_Cohort_Member__c
                );
            }
        }

        Map<Id, ProgramCohortMember> membersById =
            new Map<Id, ProgramCohortMember>([
                SELECT Id, ProgramEnrollmentId, Roll_Number__c,
                       Serial_Number__c
                FROM ProgramCohortMember
                WHERE Id IN :memberIdByRequest.values()
                WITH SYSTEM_MODE
            ]);

        Map<Id, ProgramCohortMember> byRequest =
            new Map<Id, ProgramCohortMember>();

        for (Id requestId : memberIdByRequest.keySet()) {
            byRequest.put(
                requestId,
                membersById.get(memberIdByRequest.get(requestId))
            );
        }

        return byRequest;
    }

    private static Set<Id> existingMemberships(
        List<Deferment_Request__c> reactivated,
        Map<Id, ProgramCohortMember> originalByRequest
    ) {
        Set<Id> batchIds = new Set<Id>();
        Set<Id> enrolmentIds = new Set<Id>();

        for (Deferment_Request__c request : reactivated) {
            ProgramCohortMember original = originalByRequest.get(request.Id);

            if (original == null || original.ProgramEnrollmentId == null) {
                continue;
            }

            batchIds.add(request.Rejoining_Batch__c);
            enrolmentIds.add(original.ProgramEnrollmentId);
        }

        Set<Id> already = new Set<Id>();

        if (batchIds.isEmpty() || enrolmentIds.isEmpty()) {
            return already;
        }

        for (ProgramCohortMember member : [
            SELECT ProgramEnrollmentId
            FROM ProgramCohortMember
            WHERE ProgramCohortId IN :batchIds
            AND ProgramEnrollmentId IN :enrolmentIds
            WITH SYSTEM_MODE
        ]) {
            already.add(member.ProgramEnrollmentId);
        }

        return already;
    }
}