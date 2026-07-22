trigger ProgramTeamMemberSharingTrigger on Program_Team_Members__c (after insert, after delete) {

    if (Trigger.isAfter) {

        if (Trigger.isInsert) {
            ProgramTeamMemberSharingHandler.shareAccess(Trigger.new);
        }

        if (Trigger.isDelete) {
            ProgramTeamMemberSharingHandler.removeAccess(Trigger.old);
        }
    }
}