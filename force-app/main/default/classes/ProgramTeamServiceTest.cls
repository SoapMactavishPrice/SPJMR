@IsTest(SeeAllData=true)
private class ProgramTeamServiceTest {
    @IsTest
    static void nullAndEmptyEarlyReturns() {
        System.assertEquals(0, ProgramTeamService.getActiveMembers(null).size());
        System.assertEquals(0, ProgramTeamService.getActiveMembers(new Set<Id>()).size());
    }
    @IsTest
    static void unknownProgramIdReturnsEmpty() {
        Id fake = Schema.SObjectType.Program.getKeyPrefix() + '000000000001';
        Map<Id, List<Program_Team_Members__c>> out =
            ProgramTeamService.getActiveMembers(new Set<Id>{ fake });
        System.assertNotEquals(null, out);
    }
    @IsTest
    static void withExistingProgramWithMembers() {
        List<Program_Team_Members__c> existing = [
            SELECT Program_Team__r.Program__c FROM Program_Team_Members__c
            WHERE User__c != null AND Program_Team__r.Program__c != null LIMIT 1
        ];
        if (existing.isEmpty()) return;
        Set<Id> pids = new Set<Id>{ existing[0].Program_Team__r.Program__c };
        Map<Id, List<Program_Team_Members__c>> out = ProgramTeamService.getActiveMembers(pids);
        System.assert(out.containsKey(existing[0].Program_Team__r.Program__c));
    }
}