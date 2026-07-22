/**
 * @description POC — async driver for the inbound Google Calendar → Salesforce sync.
 *          Runs the callouts for one or more calendars, then a single DML upsert.
 *
 *          Ordering matters: Apex forbids a callout after uncommitted DML, so we
 *          fetch every calendar first (HTTP GETs) and only then persist() once.
 *          Used both by the scheduled poller (GoogleCalendarInboundSchedulable) and
 *          the push webhook (GoogleCalendarInboundRest).
 */
// QueueableWithoutFinalizer suppressed: per-calendar fetch errors are collected and one
// bad calendar doesn't abort the rest, so a chained Finalizer adds no recovery value.
@SuppressWarnings('PMD.QueueableWithoutFinalizer')
public with sharing class GoogleCalendarInboundQueueable implements Queueable, Database.AllowsCallouts {

    private Set<String> calendarEmails;
    private Datetime sinceUtc;
    /** Per-calendar fetch failures, collected so one bad calendar doesn't abort the rest. */
    private List<String> errors = new List<String>();

    /**
     * @description Builds the job for a set of calendars and a lower time bound.
     * @param calendarEmails Workspace calendars (and impersonation subjects) to read.
     * @param sinceUtc Lower bound for the event window (null → service default).
     */
    public GoogleCalendarInboundQueueable(Set<String> calendarEmails, Datetime sinceUtc) {
        this.calendarEmails = (calendarEmails != null) ? calendarEmails : new Set<String>();
        this.sinceUtc = sinceUtc;
    }

    /**
     * @description Queueable entry point: fetch all calendars, then upsert once.
     * @param qc The Queueable execution context.
     */
    public void execute(QueueableContext qc) {
        if (calendarEmails.isEmpty() || !GoogleCalendarHelper.isActive()) {
            return;
        }
        List<Calendar_Meeting__c> all = new List<Calendar_Meeting__c>();
        for (String calendarEmail : calendarEmails) {
            try {
                all.addAll(GoogleCalendarInboundService.fetchMeetings(calendarEmail, sinceUtc));
            } catch (Exception e) {
                // One bad calendar must not abort the others; capture and continue.
                errors.add(calendarEmail + ': ' + e.getMessage());
            }
        }
        GoogleCalendarInboundService.persist(all);
    }
}