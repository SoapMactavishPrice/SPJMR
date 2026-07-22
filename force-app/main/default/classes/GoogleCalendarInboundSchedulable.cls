/**
 * @description Scheduled poller for the inbound Google Calendar → Salesforce sync
 *          (Requirement 3): pulls events that FACULTY create on their own
 *          @spjimr.org calendars into Salesforce as Calendar_Meeting__c records.
 *
 *          Watched calendars = every faculty assigned to a session (Session_Faculty__c
 *          → Account.PersonEmail). A faculty-created event lives on that faculty's own
 *          calendar, so reading faculty calendars catches it. Events that Salesforce
 *          itself pushed out (Session invites, SF-originated meetings) are skipped by
 *          the echo-guard in GoogleCalendarInboundService.
 *
 *          Scale: callouts are one per calendar, so the faculty set is chunked into
 *          groups of ≤ MAX_CALENDARS_PER_JOB and each chunk runs in its own queueable
 *          to stay under the 100-callouts-per-transaction limit.
 *
 *          Schedule (every 15 min) from Execute Anonymous — 4 jobs, 15 min apart:
 *            System.schedule('GCal Faculty Inbound 00', '0 0 * * * ?',  new GoogleCalendarInboundSchedulable());
 *            System.schedule('GCal Faculty Inbound 15', '0 15 * * * ?', new GoogleCalendarInboundSchedulable());
 *            System.schedule('GCal Faculty Inbound 30', '0 30 * * * ?', new GoogleCalendarInboundSchedulable());
 *            System.schedule('GCal Faculty Inbound 45', '0 45 * * * ?', new GoogleCalendarInboundSchedulable());
 */
// ApexCRUDViolation suppressed: system-context scheduled read of faculty emails from
// Session_Faculty__c to decide which calendars to poll (no user data is modified here).
// OperationWithLimitsInLoop suppressed: the enqueue loop is DELIBERATE chunking of the
// faculty set across queueables, each of which caps its own callouts.
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.OperationWithLimitsInLoop')
public with sharing class GoogleCalendarInboundSchedulable implements Schedulable {

    /** Overlap window so we don't miss events created between polls. */
    private static final Integer LOOKBACK_HOURS = 24;

    /** Google Calendar allows ~100 callouts per queueable (one per calendar); chunk below that. */
    private static final Integer MAX_CALENDARS_PER_JOB = 90;

    /**
     * @description Scheduler entry point: resolve the faculty calendars and enqueue the
     *          sync in ≤MAX_CALENDARS_PER_JOB chunks.
     * @param sc The Schedulable execution context.
     */
    public void execute(SchedulableContext sc) {
        if (!GoogleCalendarHelper.isActive()) {
            return;
        }
        List<String> calendars = new List<String>(watchedCalendars());
        if (calendars.isEmpty()) {
            return;
        }
        Datetime since = Datetime.now().addHours(-LOOKBACK_HOURS);
        for (Integer i = 0; i < calendars.size(); i += MAX_CALENDARS_PER_JOB) {
            Set<String> chunk = new Set<String>();
            for (Integer j = i; j < Math.min(i + MAX_CALENDARS_PER_JOB, calendars.size()); j++) {
                chunk.add(calendars[j]);
            }
            System.enqueueJob(new GoogleCalendarInboundQueueable(chunk, since));
        }
    }

    /**
     * @description The faculty calendars to poll: distinct, non-blank PersonEmails of
     *          faculty assigned to any session (Session_Faculty__c).
     * @return A set of faculty calendar emails to read (may be empty).
     */
    @TestVisible
    private Set<String> watchedCalendars() {
        Set<String> calendars = new Set<String>();
        for (Session_Faculty__c sf : [
            SELECT Session_Faculty__r.PersonEmail
            FROM   Session_Faculty__c
            WHERE  Session_Faculty__r.PersonEmail != NULL
        ]) {
            String email = (sf.Session_Faculty__r != null) ? sf.Session_Faculty__r.PersonEmail : null;
            if (String.isNotBlank(email)) {
                calendars.add(email);
            }
        }
        return calendars;
    }
}