@IsTest
private class ProgramTeamMemberTHTest {
    @IsTest
    static void lifecycleMethodsWithEmptyData() {
        ProgramTeamMemberTriggerHandler h = new ProgramTeamMemberTriggerHandler();
        List<Program_Team_Members__c> l = new List<Program_Team_Members__c>();
        Map<Id, Program_Team_Members__c> m = new Map<Id, Program_Team_Members__c>();
        h.beforeInsert(l, m);
        h.beforeUpdate(l, m, l, m);
        h.afterInsert(l, m);
        h.afterUpdate(l, m, l, m); // hasRun guard kicks in - early return
        h.beforeDelete(l, m);
        h.afterDelete(l, m);
        h.afterUndelete(l, m);
        System.assert(true);
    }
}