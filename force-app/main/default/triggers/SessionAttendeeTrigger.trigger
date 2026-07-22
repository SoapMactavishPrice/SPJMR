/**
 * @description Fires after Session_Attendee__c rows are written by the RSVP capture batch
 *              (SessionAttendeeSyncBatch) and mirrors each STUDENT attendee's response onto
 *              the matching Session_Enrollment__c record. Additive to the attendee-sync flow.
 */
trigger SessionAttendeeTrigger on Session_Attendee__c (after insert, after update) {
    SessionAttendeeMirrorHandler.mirrorResponsesToEnrollment(Trigger.new);
}