/**
 * @description RSVP read-back (Target 1): scheduled/batch job that, for every Session
 *          already pushed to Google Calendar (Google_Event_Id__c populated), reads that
 *          event back from the ORGANIZER's calendar copy and writes each student's
 *          response onto their Session_Enrollment__c.Invite_Response__c via
 *          SessionRsvpSyncService.
 *
 *          Polling only — no webhook (Events.watch is a separate future target).
 *
 * @note    Governor safety: one Calendar read per session (plus a token callout), so
 *          the scheduler runs this with a small scope (see SessionAttendeeSyncScheduler)
 *          to stay under the 100-callouts-per-transaction limit.
 *
 * @note    Callout/DML ordering: the Calendar callouts run first and the parsed responses
 *          are collected; the single applyToEnrollments() DML happens only after all
 *          callouts, because Apex forbids a callout after uncommitted DML.
 *
 * @note    Graceful handling: a session whose Google event was deleted (HTTP 404/410),
 *          or that errors, is skipped without failing the rest of the batch.
 */
// ApexCRUDViolation / ApexSuggestUsingNamedCred suppressed: system-context sync using the
// existing service-account JWT auth (GoogleAuthService), writing to enrollments governed
// by their Master-Detail parent Session__c.
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexSuggestUsingNamedCred')
public with sharing class SessionAttendeeSyncBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    private static final String CONFIG_NAME = 'Default';

    /** @description Count of sessions whose responses were refreshed (stateful across chunks). */
    public Integer sessionsSynced = 0;
    /** @description Count of sessions skipped because their Google event no longer exists. */
    public Integer sessionsMissing = 0;

    /**
     * @description Selects every Session that has been pushed to Google (has either event id).
     * @param bc The batch context.
     * @return QueryLocator over Session__c records carrying a student or faculty event id.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Google_Event_Id__c, Faculty_Google_Event_Id__c
            FROM   Session__c
            WHERE  Google_Event_Id__c != null OR Faculty_Google_Event_Id__c != null
        ]);
    }

    /**
     * @description Reads each session's Google event and writes the responses onto the
     *          enrolled students' Session_Enrollment__c rows.
     * @param bc The batch context.
     * @param scope The chunk of sessions to process.
     */
    public void execute(Database.BatchableContext bc, List<Session__c> scope) {
        String organizer  = GoogleCalendarHelper.getUserEmail(CONFIG_NAME);
        String calendarId = GoogleCalendarHelper.getDefaultCalendarId(CONFIG_NAME);
        if (String.isBlank(organizer)) {
            return; // integration not configured — nothing to sync
        }

        // Callouts first; collect parsed responses. NO DML in this loop.
        Map<Id, Map<String, String>> responsesBySession = new Map<Id, Map<String, String>>();
        for (Session__c s : scope) {
            // Students and faculty sit on separate events, so BOTH copies are read and their
            // responses merged: students' answers live on Google_Event_Id__c, faculty's on
            // Faculty_Google_Event_Id__c. Either may be absent (a Draft has no student copy).
            Map<String, String> merged = new Map<String, String>();
            Boolean readAny = false;
            for (String eventId : new List<String>{ s.Google_Event_Id__c, s.Faculty_Google_Event_Id__c }) {
                if (String.isBlank(eventId)) {
                    continue;
                }
                try {
                    GoogleCalendarService.GoogleEventReadResponse resp =
                        GoogleCalendarService.getCalendarEvent(calendarId, eventId, organizer);

                    if (resp.notFound) {
                        sessionsMissing++;
                        continue; // event deleted on Google's side — skip gracefully
                    }
                    if (!resp.success || resp.event == null) {
                        continue; // transient error — skip this copy, keep the batch alive
                    }

                    merged.putAll(SessionRsvpSyncService.parseResponses(resp.event));
                    readAny = true;
                } catch (Exception e) {
                    // Isolate per-event failures so one bad event can't fail the whole chunk.
                    continue;
                }
            }
            if (readAny) {
                responsesBySession.put(s.Id, merged);
                sessionsSynced++;
            }
        }

        // DML only, after every callout. Students → Session_Enrollment__c,
        // faculty → Session_Faculty__c, both from the same parsed event map.
        SessionRsvpSyncService.applyToEnrollments(responsesBySession);
        SessionFacultyRsvpService.applyToSessionFaculty(responsesBySession);
    }

    /**
     * @description No-op finish hook.
     * @param bc The batch context.
     */
    public void finish(Database.BatchableContext bc) {
        // Nothing to do; the scheduler re-runs this on its cadence.
    }
}