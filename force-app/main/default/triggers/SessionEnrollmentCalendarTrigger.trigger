/**
 * Google Calendar re-push for enrolment changes, kept in its OWN trigger rather than inside
 * sessionEnrollmentTrigger so that the calendar feature is portable across orgs.
 *
 * The shared sessionEnrollmentTrigger calls SessionEnrollmentTriggerHandler and
 * SPJIMR_ProgramCodeCopyHandler.syncSessionEnrollment, neither of which exists in devfeat, so
 * folding this hook into it would make the feature undeployable there. This trigger depends
 * only on SessionCalendarInviteHandler.
 *
 * Enrolments ARE the student guest list of the session's Google event
 * (SessionCalendarInviteQueueable.resolveStudentEmails reads them). A student enrolled AFTER
 * the session was published previously never received an invite at all.
 *
 * The handler is PATCH-only and skips Cancelled sessions, so cascade-deleting enrolments while
 * cancelling a session does not re-push anything. It also caps how much SOQL it will spend per
 * transaction, so a caller that inserts enrolments one-per-DML in a loop cannot exhaust its own
 * query budget here.
 */
trigger SessionEnrollmentCalendarTrigger on Session_Enrollment__c (after insert, after delete) {
    SessionCalendarInviteHandler.handleRelatedRecordChange(
        Trigger.isDelete ? Trigger.old : Trigger.new,
        'Session__c'
    );
}