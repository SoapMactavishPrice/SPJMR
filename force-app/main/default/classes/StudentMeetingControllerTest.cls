/**
 * @description Tests for StudentMeetingController — the student-facing scheduling entry
 *          point. These assert controller logic only (search, validation, email
 *          resolution, persistence); the outbound Google push is covered by
 *          CalendarMeetingInviteTest.
 *
 * @note    This org provisions a portal User (and chains queueables) whenever a Person
 *          Account is INSERTED, which trips a pre-existing queueable-chaining limit in
 *          the org's UserTrigger inside a test transaction. So these tests never insert
 *          Person Accounts: validation paths use fabricated ids, and the happy paths
 *          read an EXISTING Person Account (SeeAllData) — hence the suppressed rule.
 *          The integration is also seeded INACTIVE so CalendarMeetingTrigger never
 *          enqueues a callout job here.
 */
// SeeAllData justified: inserting Person Accounts is impossible in this org's test
// context (see class note), so the happy-path methods must read an existing one.
@SuppressWarnings('PMD.ApexUnitTestClassShouldNotUseSeeAllDataTrue')
@IsTest
private class StudentMeetingControllerTest {

    private static final Id FAKE_ACCOUNT_ID = '001000000000001AAA';

    private static User thisUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static void integrationOff() {
        GoogleCalendarHelper.configOverride = new Google_Calendar_Config__mdt(Active__c = false);
    }

    /**
     * @description Grants the running user the feature's permission set so USER_MODE DML
     *          in the controller can access the newly-created fields. Callers must then
     *          run the controller inside a fresh System.runAs so the grant takes effect.
     */
    private static void grantFeatureAccess() {
        List<PermissionSet> ps = [SELECT Id FROM PermissionSet WHERE Name = 'Student_Meeting_Scheduler' LIMIT 1];
        if (ps.isEmpty()) {
            return;
        }
        List<PermissionSetAssignment> existing = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :ps[0].Id
        ];
        if (existing.isEmpty()) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps[0].Id);
        }
    }

    private static Account anyPerson() {
        List<Account> people = [
            SELECT Id, Name FROM Account
            WHERE IsPersonAccount = true AND PersonEmail != null
            LIMIT 1
        ];
        return people.isEmpty() ? null : people[0];
    }

    private static StudentMeetingController.MeetingRequest buildRequest(List<Id> attendeeIds) {
        StudentMeetingController.MeetingRequest req = new StudentMeetingController.MeetingRequest();
        req.subject = 'Study group';
        req.startTime = Datetime.now().addDays(1);
        req.endTime = Datetime.now().addDays(1).addHours(1);
        req.location = 'Library';
        req.meetingLink = 'https://meet.example.com/x';
        req.description = 'Prep for exam';
        req.attendeeAccountIds = attendeeIds;
        return req;
    }

    private static Calendar_Meeting__c directMeeting(String subject) {
        return new Calendar_Meeting__c(
            Subject__c = subject,
            Start_Time__c = Datetime.now().addDays(1),
            End_Time__c = Datetime.now().addDays(1).addHours(1),
            Attendee_Emails__c = 'a@b.com',
            Source__c = 'Salesforce',
            Meeting_Status__c = 'Scheduled',
            Sync_Status__c = 'Pending'
        );
    }

    @IsTest
    static void shortSearchReturnsEmpty() {
        System.runAs(thisUser()) {
            List<StudentMeetingController.ParticipantDTO> hits =
                StudentMeetingController.getInvitableParticipants('a');
            System.assertEquals(0, hits.size(), 'A 1-char term must return nothing');
        }
    }

    @IsTest
    static void scheduleMeetingRejectsNoAttendees() {
        System.runAs(thisUser()) {
            integrationOff();
            Boolean threw = false;
            try {
                StudentMeetingController.scheduleMeeting(buildRequest(new List<Id>()));
            } catch (Exception e) {
                threw = true;
                System.assert(e.getMessage().containsIgnoreCase('at least one'), 'Expected attendee error: ' + e.getMessage());
            }
            System.assert(threw, 'Empty attendee list must be rejected');
        }
    }

    @IsTest
    static void scheduleMeetingRejectsEndBeforeStart() {
        System.runAs(thisUser()) {
            integrationOff();
            StudentMeetingController.MeetingRequest req = buildRequest(new List<Id>{ FAKE_ACCOUNT_ID });
            req.endTime = req.startTime.addHours(-2);
            Boolean threw = false;
            try {
                StudentMeetingController.scheduleMeeting(req);
            } catch (Exception e) {
                threw = true;
                System.assert(e.getMessage().containsIgnoreCase('end time'), 'Expected end-time error: ' + e.getMessage());
            }
            System.assert(threw, 'End-before-start must be rejected');
        }
    }

    @IsTest
    static void scheduleMeetingRejectsUnresolvableAttendees() {
        System.runAs(thisUser()) {
            integrationOff();
            // A non-existent account id resolves to no invitable email.
            Boolean threw = false;
            try {
                StudentMeetingController.scheduleMeeting(buildRequest(new List<Id>{ FAKE_ACCOUNT_ID }));
            } catch (Exception e) {
                threw = true;
                System.assert(e.getMessage().containsIgnoreCase('email'), 'Expected no-email error: ' + e.getMessage());
            }
            System.assert(threw, 'Attendees with no email must be rejected');
        }
    }

    @IsTest
    static void cancelMeetingSetsCancelledStatus() {
        grantFeatureAccess();
        System.runAs(thisUser()) {
            integrationOff();
            CalendarMeetingInviteHandler.suppressInvites = true;
            Calendar_Meeting__c m = directMeeting('X');
            insert m;
            CalendarMeetingInviteHandler.suppressInvites = false;

            StudentMeetingController.cancelMeeting(m.Id);
            Calendar_Meeting__c after = [SELECT Meeting_Status__c FROM Calendar_Meeting__c WHERE Id = :m.Id];
            System.assertEquals('Cancelled', after.Meeting_Status__c, 'Cancel must flip Meeting_Status__c');
        }
    }

    @IsTest
    static void updateWithNullIdThrows() {
        System.runAs(thisUser()) {
            integrationOff();
            Boolean threw = false;
            try {
                StudentMeetingController.updateMeeting(buildRequest(new List<Id>()));
            } catch (Exception e) {
                threw = true;
                System.assert(e.getMessage().containsIgnoreCase('meetingid'), 'Expected meetingId error: ' + e.getMessage());
            }
            System.assert(threw, 'Update without a meeting id must be rejected');
        }
    }

    @IsTest
    static void getMyMeetingsReturnsCreatorMeetings() {
        grantFeatureAccess();
        System.runAs(thisUser()) {
            integrationOff();
            CalendarMeetingInviteHandler.suppressInvites = true;
            insert directMeeting('Study group');
            CalendarMeetingInviteHandler.suppressInvites = false;

            List<StudentMeetingController.MeetingDTO> mine = StudentMeetingController.getMyMeetings();
            System.assert(mine.size() >= 1, 'Creator should see their own meeting');
            System.assertEquals('Study group', mine[0].subject, 'DTO should carry the subject');
        }
    }

    @IsTest
    static void cancelWithNullIdThrows() {
        System.runAs(thisUser()) {
            Boolean threw = false;
            try {
                StudentMeetingController.cancelMeeting(null);
            } catch (Exception e) {
                threw = true;
                System.assert(e.getMessage().containsIgnoreCase('required'), 'Expected required-id error: ' + e.getMessage());
            }
            System.assert(threw, 'Null meeting id must be rejected');
        }
    }

    @IsTest(SeeAllData=true)
    static void searchReturnsExistingPeople() {
        Account person = anyPerson();
        if (person == null) {
            return; // no Person Account to read in this org
        }
        System.runAs(thisUser()) {
            String term = person.Name.length() >= 2 ? person.Name.substring(0, 2) : person.Name;
            List<StudentMeetingController.ParticipantDTO> hits =
                StudentMeetingController.getInvitableParticipants(term);
            System.assert(hits.size() >= 1, 'Search should return at least the matching person');
            System.assertNotEquals(null, hits[0].role, 'Role should be populated');
        }
    }

    @IsTest(SeeAllData=true)
    static void scheduleThenUpdateSucceeds() {
        Account person = anyPerson();
        if (person == null) {
            return; // no Person Account to read in this org
        }
        grantFeatureAccess();
        System.runAs(thisUser()) {
            integrationOff();
            Id meetingId = StudentMeetingController.scheduleMeeting(buildRequest(new List<Id>{ person.Id }));
            Calendar_Meeting__c created = [
                SELECT Attendee_Emails__c, Source__c, Meeting_Status__c
                FROM Calendar_Meeting__c WHERE Id = :meetingId
            ];
            System.assertEquals('Salesforce', created.Source__c, 'Student meeting is Salesforce-sourced');
            System.assertNotEquals(null, created.Attendee_Emails__c, 'Resolved attendee email must be stored');

            StudentMeetingController.MeetingRequest upd = buildRequest(new List<Id>{ person.Id });
            upd.meetingId = meetingId;
            upd.subject = 'Renamed meeting';
            StudentMeetingController.updateMeeting(upd);
            Calendar_Meeting__c after = [SELECT Subject__c FROM Calendar_Meeting__c WHERE Id = :meetingId];
            System.assertEquals('Renamed meeting', after.Subject__c, 'Update must change the subject');
        }
    }
}