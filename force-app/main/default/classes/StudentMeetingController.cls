/**
 * @description Student-facing controller for scheduling a meeting with faculty and/or
 *          other students. Backs the studentMeetingScheduler LWC.
 *
 *          Flow: the student picks a title, time and a set of people (Person Accounts);
 *          this controller validates the request, resolves the chosen people to their
 *          emails SERVER-SIDE (emails are never sent to the browser), and writes a
 *          Calendar_Meeting__c (Source__c='Salesforce'). The CalendarMeetingTrigger then
 *          pushes it to Google Calendar asynchronously (CalendarMeetingInviteQueueable).
 *
 *          Scope (per product decision, 10 Jul 2026): a student may invite ANYONE in the
 *          organisation — getInvitableParticipants() searches all Person Accounts that
 *          have an email. Emails are resolved only at save time from the selected ids,
 *          so a tampered client cannot inject arbitrary invitees.
 *
 *          Security: all SOQL/DML runs in USER_MODE so object/field/sharing permissions
 *          are enforced against the running user (the student).
 */
// CyclomaticComplexity suppressed at class level: no method exceeds a complexity of 8 —
// the aggregate is breadth (five entry points plus three small DTO wrapper classes), not
// any single complex method.
@SuppressWarnings('PMD.CyclomaticComplexity,PMD.StdCyclomaticComplexity')
public with sharing class StudentMeetingController {

    private static final String SOURCE_SALESFORCE = 'Salesforce';
    private static final String STATUS_SCHEDULED  = 'Scheduled';
    private static final String STATUS_CANCELLED  = 'Cancelled';
    private static final String SYNC_PENDING      = 'Pending';
    private static final Integer SEARCH_LIMIT      = 50;
    private static final Integer MAX_ATTENDEES      = 50;

    /**
     * @description People this student may invite. Returns id/name/role only — never
     *          emails. Matches Person Accounts (any record type) whose name contains the
     *          search term and that have a populated email.
     * @param searchTerm The partial name typed by the student (min 2 chars enforced client-side).
     * @return Up to SEARCH_LIMIT matching participants.
     */
    @AuraEnabled(cacheable=true)
    public static List<ParticipantDTO> getInvitableParticipants(String searchTerm) {
        List<ParticipantDTO> results = new List<ParticipantDTO>();
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            return results;
        }
        String searchLike = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        if (searchLike == null) {
            return results; // defensive: guarantees a non-null SOQL bind
        }
        for (Account a : [
            SELECT Id, Name, PersonEmail, RecordType.Name
            FROM   Account
            WHERE  IsPersonAccount = true
              AND  PersonEmail != null
              AND  Name LIKE :searchLike
            WITH USER_MODE
            ORDER BY Name
            LIMIT :SEARCH_LIMIT
        ]) {
            results.add(new ParticipantDTO(a.Id, a.Name, roleFor(a)));
        }
        return results;
    }

    /**
     * @description Creates a new student-scheduled meeting and lets the trigger push it.
     * @param req The meeting details and selected attendee account ids.
     * @return The id of the created Calendar_Meeting__c.
     */
    @AuraEnabled
    public static Id scheduleMeeting(MeetingRequest req) {
        validateRequest(req);
        Map<Id, String> emailsById = resolveEmails(req.attendeeAccountIds);
        if (emailsById.isEmpty()) {
            throw error('None of the selected people have an email address to invite.');
        }
        Calendar_Meeting__c m = new Calendar_Meeting__c(
            Subject__c        = req.subject,
            Start_Time__c     = req.startTime,
            End_Time__c       = req.endTime,
            Location__c       = req.location,
            Meeting_Link__c   = req.meetingLink,
            Description__c    = req.description,
            Attendee_Emails__c = String.join(new List<String>(emailsById.values()), ', '),
            Organizer_Email__c = UserInfo.getUserEmail(),
            Source__c         = SOURCE_SALESFORCE,
            Meeting_Status__c = STATUS_SCHEDULED,
            Sync_Status__c    = SYNC_PENDING
        );
        insertMeeting(m);
        return m.Id;
    }

    /**
     * @description Updates an existing meeting the student owns; the trigger re-sends
     *          (PATCH) the Google event with the new details/attendees.
     * @param req The meeting details, including meetingId, and selected attendee account ids.
     */
    @AuraEnabled
    public static void updateMeeting(MeetingRequest req) {
        if (req == null || req.meetingId == null) {
            throw error('meetingId is required to update a meeting.');
        }
        validateRequest(req);
        Map<Id, String> emailsById = resolveEmails(req.attendeeAccountIds);
        if (emailsById.isEmpty()) {
            throw error('None of the selected people have an email address to invite.');
        }
        Calendar_Meeting__c m = new Calendar_Meeting__c(
            Id                = req.meetingId,
            Subject__c        = req.subject,
            Start_Time__c     = req.startTime,
            End_Time__c       = req.endTime,
            Location__c       = req.location,
            Meeting_Link__c   = req.meetingLink,
            Description__c    = req.description,
            Attendee_Emails__c = String.join(new List<String>(emailsById.values()), ', '),
            Meeting_Status__c = STATUS_SCHEDULED
        );
        updateMeetingRecord(m);
    }

    /**
     * @description Cancels a meeting the student owns; the trigger deletes the Google
     *          event and notifies attendees.
     * @param meetingId The Calendar_Meeting__c id to cancel.
     */
    @AuraEnabled
    public static void cancelMeeting(Id meetingId) {
        if (meetingId == null) {
            throw error('meetingId is required to cancel a meeting.');
        }
        updateMeetingRecord(new Calendar_Meeting__c(
            Id = meetingId,
            Meeting_Status__c = STATUS_CANCELLED
        ));
    }

    /**
     * @description The meetings the running user has scheduled, most recent first.
     * @return The current user's Salesforce-originated meetings (up to 200).
     */
    @AuraEnabled(cacheable=true)
    public static List<MeetingDTO> getMyMeetings() {
        List<MeetingDTO> results = new List<MeetingDTO>();
        for (Calendar_Meeting__c m : [
            SELECT Id, Name, Subject__c, Start_Time__c, End_Time__c, Location__c,
                   Meeting_Link__c, Description__c, Attendee_Emails__c,
                   Meeting_Status__c, Sync_Status__c, Sync_Error__c
            FROM   Calendar_Meeting__c
            WHERE  Source__c = :SOURCE_SALESFORCE
              AND  CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Start_Time__c DESC
            LIMIT 200
        ]) {
            results.add(new MeetingDTO(m));
        }
        return results;
    }

    /**
     * @description Resolves selected Person Account ids to their emails (server-side only).
     * @param accountIds The chosen attendee account ids.
     * @return Map of account id to email for those that have one.
     */
    private static Map<Id, String> resolveEmails(List<Id> accountIds) {
        Map<Id, String> emailsById = new Map<Id, String>();
        if (accountIds == null || accountIds.isEmpty()) {
            return emailsById;
        }
        for (Account a : [
            SELECT Id, PersonEmail
            FROM   Account
            WHERE  Id IN :accountIds
              AND  PersonEmail != null
            WITH USER_MODE
        ]) {
            emailsById.put(a.Id, a.PersonEmail);
        }
        return emailsById;
    }

    /**
     * @description Validates common meeting-request rules; throws on the first violation.
     * @param req The meeting request to validate.
     */
    private static void validateRequest(MeetingRequest req) {
        if (req == null) {
            throw error('No meeting details were provided.');
        }
        if (String.isBlank(req.subject)) {
            throw error('Please enter a title for the meeting.');
        }
        validateTiming(req);
        validateAttendees(req);
    }

    /**
     * @description Validates the start/end times of a meeting request.
     * @param req The meeting request to validate.
     */
    private static void validateTiming(MeetingRequest req) {
        if (req.startTime == null || req.endTime == null) {
            throw error('Please provide both a start and an end time.');
        }
        if (req.endTime <= req.startTime) {
            throw error('The end time must be after the start time.');
        }
        if (req.startTime < Datetime.now()) {
            throw error('The meeting cannot start in the past.');
        }
    }

    /**
     * @description Validates the attendee selection of a meeting request.
     * @param req The meeting request to validate.
     */
    private static void validateAttendees(MeetingRequest req) {
        if (req.attendeeAccountIds == null || req.attendeeAccountIds.isEmpty()) {
            throw error('Please select at least one person to invite.');
        }
        if (req.attendeeAccountIds.size() > MAX_ATTENDEES) {
            throw error('You can invite at most ' + MAX_ATTENDEES + ' people per meeting.');
        }
    }

    /**
     * @description Inserts a meeting in user mode.
     * @param m The meeting to insert.
     */
    private static void insertMeeting(Calendar_Meeting__c m) {
        // sfge does not recognise AccessLevel.USER_MODE as FLS enforcement, but it
        // enforces object/field permissions at runtime — this is the intended check.
        /* sfge-disable-next-line ApexFlsViolation */
        Database.insert(m, AccessLevel.USER_MODE);
    }

    /**
     * @description Updates a meeting in user mode.
     * @param m The meeting to update.
     */
    private static void updateMeetingRecord(Calendar_Meeting__c m) {
        // See insertMeeting: USER_MODE enforces FLS at runtime; sfge cannot see it.
        /* sfge-disable-next-line ApexFlsViolation */
        Database.update(m, AccessLevel.USER_MODE);
    }

    /**
     * @description Maps a Person Account to a coarse role label for display.
     * @param a The account.
     * @return 'Student' for the Student record type, otherwise 'Faculty / Staff'.
     */
    private static String roleFor(Account a) {
        String rt = (a.RecordType != null) ? a.RecordType.Name : null;
        return 'Student'.equalsIgnoreCase(rt) ? 'Student' : 'Faculty / Staff';
    }

    /**
     * @description Builds an AuraHandledException with a user-facing message.
     * @param message The message to show the user.
     * @return The exception to throw.
     */
    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    /**
     * @description Read-only participant projection sent to the LWC (no email).
     */
    public class ParticipantDTO {
        /** @description Person Account id. */
        @AuraEnabled public Id id { get; set; }
        /** @description Display name. */
        @AuraEnabled public String name { get; set; }
        /** @description Coarse role label ('Student' / 'Faculty / Staff'). */
        @AuraEnabled public String role { get; set; }

        /**
         * @description Constructs a participant projection.
         * @param id Person Account id.
         * @param name Display name.
         * @param role Coarse role label.
         */
        public ParticipantDTO(Id id, String name, String role) {
            this.id = id;
            this.name = name;
            this.role = role;
        }
    }

    /**
     * @description Inbound request from the LWC describing a meeting to create or update.
     */
    public class MeetingRequest {
        /** @description Existing meeting id (null for create). */
        @AuraEnabled public Id meetingId { get; set; }
        /** @description Meeting title. */
        @AuraEnabled public String subject { get; set; }
        /** @description Start time. */
        @AuraEnabled public Datetime startTime { get; set; }
        /** @description End time. */
        @AuraEnabled public Datetime endTime { get; set; }
        /** @description Optional physical location. */
        @AuraEnabled public String location { get; set; }
        /** @description Optional video/meeting link. */
        @AuraEnabled public String meetingLink { get; set; }
        /** @description Optional agenda/notes. */
        @AuraEnabled public String description { get; set; }
        /** @description Selected attendee Person Account ids. */
        @AuraEnabled public List<Id> attendeeAccountIds { get; set; }
    }

    /**
     * @description Outbound projection of a meeting for the "my meetings" list.
     */
    public class MeetingDTO {
        /** @description Record id. */
        @AuraEnabled public Id id { get; set; }
        /** @description Meeting number (Name). */
        @AuraEnabled public String name { get; set; }
        /** @description Title. */
        @AuraEnabled public String subject { get; set; }
        /** @description Start time. */
        @AuraEnabled public Datetime startTime { get; set; }
        /** @description End time. */
        @AuraEnabled public Datetime endTime { get; set; }
        /** @description Location. */
        @AuraEnabled public String location { get; set; }
        /** @description Video/meeting link. */
        @AuraEnabled public String meetingLink { get; set; }
        /** @description Comma-separated invitee emails. */
        @AuraEnabled public String attendeeEmails { get; set; }
        /** @description Lifecycle status (Scheduled/Cancelled). */
        @AuraEnabled public String meetingStatus { get; set; }
        /** @description Sync status (Pending/Synced/Failed). */
        @AuraEnabled public String syncStatus { get; set; }
        /** @description Last sync error, when any. */
        @AuraEnabled public String syncError { get; set; }

        /**
         * @description Projects a Calendar_Meeting__c into the DTO.
         * @param m The source record.
         */
        public MeetingDTO(Calendar_Meeting__c m) {
            this.id = m.Id;
            this.name = m.Name;
            this.subject = m.Subject__c;
            this.startTime = m.Start_Time__c;
            this.endTime = m.End_Time__c;
            this.location = m.Location__c;
            this.meetingLink = m.Meeting_Link__c;
            this.attendeeEmails = m.Attendee_Emails__c;
            this.meetingStatus = m.Meeting_Status__c;
            this.syncStatus = m.Sync_Status__c;
            this.syncError = m.Sync_Error__c;
        }
    }
}