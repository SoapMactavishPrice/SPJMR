/**
 * @description Status automation for Deferment_Request__c. Two jobs:
 *
 *              1. Advances a request from "Deferment Process Complete" to
 *                 "Pending Re-enrollment" so the student is held in the stage
 *                 that the rejoining reminders and the Programme Office alert
 *                 both read from. Runs in a before context, so the corrected
 *                 status is saved with the record itself and costs no DML.
 *
 *              2. Places the student in their rejoining batch the moment the
 *                 Programme Office marks the request "Student Record
 *                 Reactivated". The process document defines that status as
 *                 "Student mapped to rejoining batch; Roll No. and Email ID
 *                 retained", and nothing was doing it, so a student could reach
 *                 "Rejoining Complete" with no membership of the batch they
 *                 were returning to. Runs in an after context because it
 *                 inserts a record.
 *
 *              Deliberately does NOT choose the term, division or courses:
 *              section 8.4 of the process document makes term placement "a
 *              manual decision made by the Programme Manager... no automated
 *              placement rule applies".
 */
public with sharing class DefermentRequestStatusHandler {

    /** Stage reached once every exit formality of the deferment is done. */
    @TestVisible
    private static final String STATUS_PROCESS_COMPLETE =
        'Deferment Process Complete';

    /** Stage the student waits in until they return to campus. */
    @TestVisible
    private static final String STATUS_PENDING_REENROLLMENT =
        'Pending Re-enrollment';

    /** Terminal stage for a student who has said they are not coming back. */
    @TestVisible
    private static final String STATUS_WITHDRAWAL = 'Withdrawal';

    /** Stage that closes the rejoining process. */
    @TestVisible
    private static final String STATUS_REJOINING_COMPLETE = 'Rejoining Complete';

    /** Stage by which Finance has recorded the student's payment. */
    @TestVisible
    private static final String STATUS_PAYMENT_CONFIRMED = 'Payment Confirmed';

    /**
     * The order of the tracker, exactly as sections 5 and 7 of the process
     * document set it out. Withdrawal is deliberately absent: it is a terminal
     * status reachable from any point, not a step in the sequence.
     */
    private static final List<String> STATUS_ORDER = new List<String>{
        'Deferment Form Enabled',
        'Form Submitted',
        'Pending Chairperson\'s Approval',
        'Pending Dean\'s / AD\'s Approval',
        'Rejoining Details',
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

    /** Position of each status in STATUS_ORDER, built once per transaction. */
    private static Map<String, Integer> positions;

    /** Stage at which the student is mapped to the batch they rejoin. */
    @TestVisible
    private static final String STATUS_RECORD_REACTIVATED =
        'Student Record Reactivated';

    /**
     * @description Rewrites "Deferment Process Complete" to
     *              "Pending Re-enrollment" before the record is saved.
     *
     *              Because the rewrite happens in a before context, the
     *              completed status is never stored, so "is currently
     *              Deferment Process Complete" and "has just been changed to
     *              Deferment Process Complete" are the same test and no
     *              Trigger.oldMap comparison is needed.
     * @param requests the records being inserted or updated (Trigger.new)
     */
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

    /**
     * @description Refuses a negative Deferment Application Fee, whichever way
     *              it is entered - the Break in Study button, a direct edit on
     *              the record, or the API.
     *
     *              A negative fee used to save. It showed the student a
     *              negative amount on their form and, because the form only
     *              treats a fee above zero as payable, quietly waived the
     *              Transaction Details screenshot as well. Section 8.2 allows a
     *              fee or zero, never less than zero.
     * @param requests the records being inserted or updated (Trigger.new)
     */
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

    /**
     * @description Keeps the tracker honest. Section 5 of the process document
     *              makes status transitions linear and says no completed step
     *              "can be reopened once finalised", but the Status field is an
     *              ordinary picklist and nothing was checking it - a request
     *              could be dragged backwards into a finished approval, or sent
     *              straight to "Rejoining Complete" from anywhere, skipping the
     *              fees and the payment entirely.
     *
     *              Two rules, deliberately no more:
     *                1. a request cannot move backwards;
     *                2. it cannot reach "Rejoining Complete" from before
     *                   "Payment Confirmed".
     *
     *              Forward movement in between is left alone on purpose.
     *              "Return to Campus Notification Sent" is stamped by the
     *              nightly job rather than a person, so insisting on one step at
     *              a time would strand the Programme Office whenever that mail
     *              could not be sent.
     *
     *              Three documented moves stay open: a rejection sending the
     *              request back to the student (8.1), Withdrawal from any point
     *              (8.4), and the automatic hop from "Deferment Process
     *              Complete" to "Pending Re-enrollment".
     * @param requests the records being updated (Trigger.new)
     * @param oldById the records as they were before this save (Trigger.oldMap)
     */
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

            Integer wasAt = positionOf(old.Status__c);
            Integer goingTo = positionOf(request.Status__c);

            if (wasAt == null || goingTo == null) {
                continue;
            }

            if (goingTo < wasAt) {
                request.addError(
                    'A Deferment Request cannot be moved back to "' +
                    request.Status__c + '" once it has reached "' +
                    old.Status__c + '". Completed steps cannot be reopened.'
                );
                continue;
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
    }

    /**
     * @description The moves the process document allows outside the sequence:
     *              marking a student Withdrawal, and an approver rejecting the
     *              request back to the student.
     * @param request the record being updated
     * @return true when this change must not be order-checked
     */
    private static Boolean isAlwaysAllowed(Deferment_Request__c request) {
        return request.Status__c == STATUS_WITHDRAWAL
            || request.Approval_Status__c == 'Rejected';
    }

    /**
     * @description Where a status sits in the documented sequence.
     * @param status the Status__c value to place
     * @return its position, or null for a value outside the sequence
     */
    private static Integer positionOf(String status) {

        if (positions == null) {
            positions = new Map<String, Integer>();
            for (Integer i = 0; i < STATUS_ORDER.size(); i++) {
                positions.put(STATUS_ORDER[i], i);
            }
        }

        return positions.get(status);
    }

    /**
     * @description Creates the student's membership of their rejoining batch
     *              when a request reaches "Student Record Reactivated",
     *              carrying the existing Roll Number across unchanged.
     *
     *              Refuses the save, with a message the Programme Office can
     *              act on, when the request has no Rejoining Batch or no
     *              original batch enrolment to copy the Roll Number from -
     *              silently doing nothing is what let a student be marked
     *              rejoined with nowhere to go.
     *
     *              Safe to run more than once: a student who already belongs to
     *              the rejoining batch is skipped rather than duplicated.
     * @param requests the records just saved (Trigger.new)
     * @param oldById the records as they were before this save (Trigger.oldMap)
     */
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

        /*
         * Handed to a queued job rather than inserted here.
         *
         * Creating the enrolment inside this after-update trigger puts it at
         * the second level of a chain that keeps going: the org's own
         * ProgramCohortMemberTrigger fires, updates the Programme Enrolment's
         * batch, and that cascades into the Programme Cohort triggers. In
         * devfeat the platform gives up at that depth and throws a bare
         * "Internal Salesforce.com Error" - the identical insert run on its own
         * succeeds every time.
         *
         * A Queueable runs a moment later in a fresh transaction, so the org's
         * automation gets a clean stack to work in. Everything that can be
         * checked without DML has already been checked above, so the Programme
         * Office still gets an immediate, readable message for the mistakes
         * they can actually make.
         */
        System.enqueueJob(new RejoiningBatchEnroller(toCreate));
    }

    /**
     * @description Inserts the rejoining batch enrolments a moment after the
     *              Deferment Request is saved, in its own transaction.
     *
     *              If the insert still fails - the chosen batch is full, or has
     *              no intake set - the Programme Manager who owns the request is
     *              e-mailed. A batch enrolment that quietly never happened is
     *              exactly the failure this whole change exists to prevent, so
     *              it must not fail silently now that nobody is watching the
     *              screen.
     */
    public class RejoiningBatchEnroller implements Queueable {

        private final List<ProgramCohortMember> enrolments;

        /**
         * @description Holds the enrolments until the job runs.
         * @param members the batch enrolments to create
         */
        public RejoiningBatchEnroller(List<ProgramCohortMember> members) {
            this.enrolments = members;
        }

        /**
         * @description Creates the enrolments and reports anything that failed.
         * @param ctx the queueable context
         */
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

        /**
         * @description E-mails whoever owns the Deferment Requests for the
         *              rejoining batches that could not be filled.
         * @param problems one line per failed enrolment
         */
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

    /**
     * @description Picks out the requests that have just moved into "Student
     *              Record Reactivated", and stops any that have no Rejoining
     *              Batch chosen.
     * @param requests the records just saved (Trigger.new)
     * @param oldById the records as they were before this save (Trigger.oldMap)
     * @return the requests that should be mapped to a rejoining batch
     */
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

    /**
     * @description Loads the batch enrolment each request was raised against,
     *              which is where the Roll Number that must be retained lives.
     * @param reactivated the requests being mapped to a rejoining batch
     * @return the original batch enrolment, by Deferment Request Id
     */
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

    /**
     * @description Finds the students who already belong to the rejoining batch
     *              they are being mapped to, so running twice cannot duplicate
     *              a membership.
     * @param reactivated the requests being mapped to a rejoining batch
     * @param originalByRequest the original batch enrolment, by request Id
     * @return the Programme Enrolment Ids that are already in their batch
     */
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