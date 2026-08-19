/**
 * @description RSVP read-back (Target 1): Scheduled Apex entry point that kicks off the
 *          SessionAttendeeSyncBatch on a cadence (recommended every 10-15 minutes) to
 *          poll Google Calendar for attendee response updates.
 *
 *          Scope is kept small (one Calendar read + token callout per session) so each
 *          batch chunk stays under the 100-callouts-per-transaction limit.
 *
 * @example Schedule four jobs, 15 minutes apart, from anonymous Apex:
 *          System.schedule('Session Attendee RSVP Sync 00', '0 0 * * * ?',  new SessionAttendeeSyncScheduler());
 *          System.schedule('Session Attendee RSVP Sync 15', '0 15 * * * ?', new SessionAttendeeSyncScheduler());
 *          System.schedule('Session Attendee RSVP Sync 30', '0 30 * * * ?', new SessionAttendeeSyncScheduler());
 *          System.schedule('Session Attendee RSVP Sync 45', '0 45 * * * ?', new SessionAttendeeSyncScheduler());
 */
global class SessionAttendeeSyncScheduler implements Schedulable {

    /**
     * @description Batch scope: sessions per chunk. Kept low for callout limits — each session now
     *          costs up to TWO callouts, because faculty and students sit on separate Google events
     *          and both are read, so 30 sessions is a worst case of 60 of the 100 allowed.
     */
    @TestVisible
    private static final Integer BATCH_SCOPE = 30;

    /**
     * @description Scheduled entry point — launches the RSVP read-back batch.
     * @param sc The Schedulable context.
     */
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new SessionAttendeeSyncBatch(), BATCH_SCOPE);
    }
}