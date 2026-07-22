trigger ProgramTeamTrigger on Program_Team__c (after insert) {
    
    if (Trigger.isAfter && Trigger.isInsert) {
        ProgramTeamHandler.shareProgramWithOfficeUser(Trigger.new);
    }
}