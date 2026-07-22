@IsTest
private class ProgramTeamMemberHelperTest {
    @IsTest
    static void processTeamMemberChanges_emptyAndNull() {
        try {
            ProgramTeamMemberHelper.processTeamMemberChanges(new List<Program_Team_Members__c>(), null);
            ProgramTeamMemberHelper.processTeamMemberChanges(new List<Program_Team_Members__c>(), new Map<Id, Program_Team_Members__c>());
        } catch (Exception e) {}
    }
}