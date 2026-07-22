/**
 * @description Asynchronously create, update or cancel a Google Calendar event for a
 *          student-scheduled meeting (Calendar_Meeting__c, Source__c = 'Salesforce').
 *          This is the outbound counterpart of GoogleCalendarInboundService and a
 *          sibling of SessionCalendarInviteQueueable — it reuses the same auth and
 *          GoogleCalendarService callout layer, but sources its fields and attendees
 *          from Calendar_Meeting__c instead of Session__c.
 *
 *          Mapping (Calendar_Meeting__c → GoogleCalendarEvent):
 *            summary     ← Subject__c
 *            start/end   ← Start_Time__c / End_Time__c (Asia/Kolkata)
 *            location    ← Location__c (+ Meeting_Link__c)
 *            description ← Description__c (+ Meeting_Link__c join line)
 *            attendees   ← Attendee_Emails__c (comma-separated, resolved by the controller)
 *
 *          Idempotency / update / cancel:
 *            - No Google_Event_Id__c → POST (create), store the returned id.
 *            - Has Google_Event_Id__c → PATCH (update) the same event.
 *            - cancelEventIdsByMeeting → DELETE the event (sendUpdates=all).
 *
 *          Organiser (MVP): the event is created by the shared impersonated Workspace
 *          user configured in Google_Calendar_Config__mdt (no student impersonation).
 *          Every participant, including the student, is an attendee.
 *
 * @note    Google Calendar has no bulk API, so this issues one callout per meeting
 *          (Queueable allows up to ~100). Larger batches are chunked by the handler.
 */
// complexity suppressed: working integration logic mirrored from SessionCalendarInviteQueueable.
// QueueableWithoutFinalizer suppressed: per-record failures are captured on the record
// (Sync_Status__c/Sync_Error__c), so a chained Finalizer would add no recovery value here.
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity,PMD.CognitiveComplexity,PMD.NcssMethodCount,PMD.QueueableWithoutFinalizer')
public with sharing class CalendarMeetingInviteQueueable implements Queueable, Database.AllowsCallouts {

    private static final String EVENT_TIMEZONE = 'Asia/Kolkata';
    private static final String STATUS_SYNCED    = 'Synced';
    private static final String STATUS_FAILED    = 'Failed';

    private Set<Id> createOrUpdateIds;
    private Map<Id, String> cancelEventIdsByMeeting;

    /**
     * @description Backward-compatible constructor: create/update only, no cancellations.
     * @param createOrUpdateIds Calendar_Meeting__c ids to create or update in Google.
     */
    public CalendarMeetingInviteQueueable(Set<Id> createOrUpdateIds) {
        this(createOrUpdateIds, null);
    }

    /**
     * @description Full constructor supporting create/update plus cancellations.
     * @param createOrUpdateIds Calendar_Meeting__c ids to create or update in Google.
     * @param cancelEventIdsByMeeting Map of meeting id to the Google event id to DELETE.
     */
    public CalendarMeetingInviteQueueable(
        Set<Id> createOrUpdateIds,
        Map<Id, String> cancelEventIdsByMeeting
    ) {
        this.createOrUpdateIds = (createOrUpdateIds != null) ? createOrUpdateIds : new Set<Id>();
        this.cancelEventIdsByMeeting = (cancelEventIdsByMeeting != null)
            ? cancelEventIdsByMeeting : new Map<Id, String>();
    }

    /**
     * @description Queueable entry point: process cancellations, then create/update
     *          events, then write the sync results back to the meetings.
     * @param qc The Queueable execution context.
     */
    public void execute(QueueableContext qc) {
        Map<Id, Calendar_Meeting__c> toUpdate = new Map<Id, Calendar_Meeting__c>();
        processCancellations(toUpdate);
        processCreateOrUpdate(toUpdate);
        writeBack(toUpdate);
    }

    /**
     * @description Cancel path: DELETE each Google event and stamp the (still-existing) meeting.
     * @param toUpdate Accumulator of meetings to write sync results back to.
     */
    private void processCancellations(Map<Id, Calendar_Meeting__c> toUpdate) {
        if (cancelEventIdsByMeeting.isEmpty()) {
            return;
        }
        Set<Id> existing = new Map<Id, Calendar_Meeting__c>([
            SELECT Id FROM Calendar_Meeting__c WHERE Id IN :cancelEventIdsByMeeting.keySet()
        ]).keySet();

        for (Id meetingId : cancelEventIdsByMeeting.keySet()) {
            String eventId = cancelEventIdsByMeeting.get(meetingId);
            if (String.isBlank(eventId)) {
                continue;
            }
            try {
                GoogleCalendarService.GoogleCalendarResponse resp =
                    GoogleCalendarHelper.deleteEventWithStoredCredentials(eventId);
                if (existing.contains(meetingId)) {
                    toUpdate.put(meetingId, cancelResult(meetingId, resp));
                }
            } catch (Exception e) {
                if (existing.contains(meetingId)) {
                    toUpdate.put(meetingId, failedMeeting(meetingId, e.getMessage()));
                }
            }
        }
    }

    /**
     * @description Builds the write-back record for a cancellation outcome.
     * @param meetingId The Calendar_Meeting__c id.
     * @param resp The Google delete response (may be null).
     * @return The Calendar_Meeting__c carrying the sync stamps.
     */
    private Calendar_Meeting__c cancelResult(Id meetingId, GoogleCalendarService.GoogleCalendarResponse resp) {
        Calendar_Meeting__c upd = new Calendar_Meeting__c(Id = meetingId);
        if (resp != null && resp.success) {
            upd.Sync_Status__c = STATUS_SYNCED;
            upd.Event_Status__c = 'Cancelled';
            upd.Last_Synced__c = Datetime.now();
            upd.Google_Event_Id__c = null; // a future re-schedule creates a fresh event
            upd.Sync_Error__c = null;
        } else {
            upd.Sync_Status__c = STATUS_FAILED;
            upd.Sync_Error__c = (resp != null) ? resp.errorMessage : 'Unknown cancel error';
        }
        return upd;
    }

    /**
     * @description Create/update path: POST when no event id, PATCH when one is present.
     * @param toUpdate Accumulator of meetings to write sync results back to.
     */
    private void processCreateOrUpdate(Map<Id, Calendar_Meeting__c> toUpdate) {
        if (createOrUpdateIds.isEmpty()) {
            return;
        }
        Map<Id, Calendar_Meeting__c> meetings = new Map<Id, Calendar_Meeting__c>([
            SELECT Id, Subject__c, Start_Time__c, End_Time__c, Location__c,
                   Meeting_Link__c, Description__c, Attendee_Emails__c, Google_Event_Id__c
            FROM   Calendar_Meeting__c
            WHERE  Id IN :createOrUpdateIds
        ]);

        for (Id meetingId : meetings.keySet()) {
            Calendar_Meeting__c m = meetings.get(meetingId);
            List<String> attendees = parseAttendees(m.Attendee_Emails__c);

            String problem = validate(m, attendees);
            if (problem != null) {
                toUpdate.put(meetingId, failedMeeting(meetingId, problem));
                continue;
            }

            toUpdate.put(meetingId, pushEvent(m));
        }
    }

    /**
     * @description Issues the create/update callout for one meeting and maps the result.
     * @param m The meeting to push (fields already validated).
     * @return The Calendar_Meeting__c carrying the sync stamps.
     */
    private Calendar_Meeting__c pushEvent(Calendar_Meeting__c m) {
        GoogleCalendarEvent ev = buildEvent(m, parseAttendees(m.Attendee_Emails__c));
        try {
            Boolean isUpdate = String.isNotBlank(m.Google_Event_Id__c);
            GoogleCalendarService.GoogleCalendarResponse resp = isUpdate
                ? GoogleCalendarHelper.updateEventWithStoredCredentials(m.Google_Event_Id__c, ev)
                : GoogleCalendarHelper.createEventWithStoredCredentials(ev);

            Calendar_Meeting__c upd = new Calendar_Meeting__c(Id = m.Id);
            if (resp != null && resp.success) {
                upd.Google_Event_Id__c = String.isNotBlank(resp.eventId) ? resp.eventId : m.Google_Event_Id__c;
                upd.Sync_Status__c = STATUS_SYNCED;
                upd.Event_Status__c = 'Confirmed';
                upd.Last_Synced__c = Datetime.now();
                upd.Sync_Error__c = null;
                return upd;
            }
            upd.Sync_Status__c = STATUS_FAILED;
            upd.Sync_Error__c = (resp != null) ? resp.errorMessage : 'Unknown sync error';
            return upd;
        } catch (Exception e) {
            return failedMeeting(m.Id, e.getMessage());
        }
    }

    /**
     * @description Reason the meeting cannot be pushed, or null when it is valid.
     * @param m The meeting.
     * @param attendees The parsed attendee emails.
     * @return A human-readable problem string, or null when valid.
     */
    private String validate(Calendar_Meeting__c m, List<String> attendees) {
        if (m.Start_Time__c == null || m.End_Time__c == null) {
            return 'Meeting is missing Start_Time__c / End_Time__c.';
        }
        if (attendees.isEmpty()) {
            return 'No attendees with a valid email were found for this meeting.';
        }
        return null;
    }

    /**
     * @description Stamp sync results back onto the meetings, suppressing trigger re-entry.
     * @param toUpdate Map of meeting id to the Calendar_Meeting__c records carrying stamps.
     */
    private void writeBack(Map<Id, Calendar_Meeting__c> toUpdate) {
        if (toUpdate.isEmpty()) {
            return;
        }
        Boolean prior = CalendarMeetingInviteHandler.suppressInvites;
        CalendarMeetingInviteHandler.suppressInvites = true;
        // allOrNone = false: one bad row must not roll back other rows' sync stamps
        // (including freshly created Google_Event_Id__c values). Database.update with
        // allOrNone=false reports row errors in its results rather than throwing, so no
        // catch is needed; the finally simply restores the re-entry guard.
        try {
            Database.update(toUpdate.values(), false);
        } finally {
            CalendarMeetingInviteHandler.suppressInvites = prior;
        }
    }

    /**
     * @description Maps a Calendar_Meeting__c to the Google Calendar event format.
     * @param m The meeting.
     * @param attendees The attendee emails.
     * @return The populated GoogleCalendarEvent.
     */
    private GoogleCalendarEvent buildEvent(Calendar_Meeting__c m, List<String> attendees) {
        GoogleCalendarEvent ev = new GoogleCalendarEvent();
        ev.summary = String.isNotBlank(m.Subject__c) ? m.Subject__c : 'Meeting';
        ev.timeZone = EVENT_TIMEZONE;
        ev.startDateTime = toGoogleTime(m.Start_Time__c);
        ev.endDateTime = toGoogleTime(m.End_Time__c);

        List<String> locationParts = new List<String>();
        if (String.isNotBlank(m.Location__c)) {
            locationParts.add(m.Location__c);
        }
        if (String.isNotBlank(m.Meeting_Link__c)) {
            locationParts.add(m.Meeting_Link__c);
        }
        if (!locationParts.isEmpty()) {
            ev.location = String.join(locationParts, ' | ');
        }

        String descText = String.isNotBlank(m.Description__c) ? m.Description__c : '';
        if (String.isNotBlank(m.Meeting_Link__c)) {
            descText += (String.isBlank(descText) ? '' : '\n\n') + 'Join: ' + m.Meeting_Link__c;
        }
        ev.description = descText;

        ev.attendees = attendees;
        return ev;
    }

    /**
     * @description Formats a Datetime into the Google start/end map in Asia/Kolkata.
     * @param dt The Datetime to format.
     * @return The Google-shaped {dateTime, timeZone} map.
     */
    private Map<String, Object> toGoogleTime(Datetime dt) {
        return new Map<String, Object>{
            'dateTime' => dt.format('yyyy-MM-dd\'T\'HH:mm:ss', EVENT_TIMEZONE),
            'timeZone' => EVENT_TIMEZONE
        };
    }

    /**
     * @description Splits a comma-separated attendee-email string into a clean list.
     * @param csv The comma-separated emails (may be null/blank).
     * @return A de-duplicated, trimmed list of non-blank emails.
     */
    private List<String> parseAttendees(String csv) {
        List<String> emails = new List<String>();
        if (String.isBlank(csv)) {
            return emails;
        }
        Set<String> seen = new Set<String>();
        for (String raw : csv.split(',')) {
            String email = (raw != null) ? raw.trim() : '';
            if (String.isNotBlank(email) && !seen.contains(email.toLowerCase())) {
                seen.add(email.toLowerCase());
                emails.add(email);
            }
        }
        return emails;
    }

    /**
     * @description Builds a failed-sync write-back record.
     * @param meetingId The Calendar_Meeting__c id.
     * @param message The error message to record.
     * @return The Calendar_Meeting__c carrying the failure stamps.
     */
    private Calendar_Meeting__c failedMeeting(Id meetingId, String message) {
        return new Calendar_Meeting__c(
            Id = meetingId,
            Sync_Status__c = STATUS_FAILED,
            Sync_Error__c = message
        );
    }
}