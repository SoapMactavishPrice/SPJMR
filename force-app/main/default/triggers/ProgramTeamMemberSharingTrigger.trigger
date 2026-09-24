trigger ProgramTeamMemberSharingTrigger on Program_Team_Members__c (after insert, after delete) {
if (Trigger.isAfter && Trigger.isInsert) {
        ProgramTeamMemberTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter) {

        if (Trigger.isInsert) {
            ProgramTeamMemberSharingHandler.shareAccess(Trigger.new);
        }

        if (Trigger.isDelete) {
            ProgramTeamMemberSharingHandler.removeAccess(Trigger.old);
        }
    }
}