/**
 * @description Fires the outbound Google Calendar push for student-scheduled meetings
 *          (Calendar_Meeting__c, Source__c = 'Salesforce'). Create/update on insert &
 *          update; cancel on cancel-status or delete. All decisioning lives in
 *          CalendarMeetingInviteHandler; the actual callouts run async in
 *          CalendarMeetingInviteQueueable.
 */
trigger CalendarMeetingTrigger on Calendar_Meeting__c (after insert, after update, after delete) { // NOPMD: thin delegate to handler (handler pattern)
    if (Trigger.isAfter && Trigger.isInsert) {
        CalendarMeetingInviteHandler.handleCalendarMeetingInvites(Trigger.newMap, null);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        CalendarMeetingInviteHandler.handleCalendarMeetingInvites(Trigger.newMap, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isDelete) {
        CalendarMeetingInviteHandler.handleCalendarMeetingDeletes(Trigger.oldMap);
    }
}