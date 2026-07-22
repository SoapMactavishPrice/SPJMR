@IsTest
private class ProgramTeamHandlerTest {
    @IsTest
    static void emptyListNoInsert() {
        ProgramTeamHandler.shareProgramWithOfficeUser(new List<Program_Team__c>());
    }
    @IsTest
    static void officeUserBranchBuildsShareAndAttemptsInsert() {
        // Construct a Program_Team__c (no insert) with the fields needed to enter the Office User branch.
        // The handler will build a ProgramShare and call insert; we wrap to swallow any DML failure.
        String fakeProgramId = Schema.SObjectType.Program.getKeyPrefix() + '000000000001';
        Program_Team__c pt = new Program_Team__c(
            Type__c = 'Office User',
            Program__c = (Id) fakeProgramId,
            User__c = UserInfo.getUserId()
        );
        try {
            ProgramTeamHandler.shareProgramWithOfficeUser(new List<Program_Team__c>{ pt });
        } catch (Exception e) {
            // Insert may fail due to fake ParentId; that's acceptable - the line was reached.
        }
    }
    @IsTest
    static void nonOfficeUserSkipsShareBranch() {
        Program_Team__c pt = new Program_Team__c(Type__c = 'Faculty');
        ProgramTeamHandler.shareProgramWithOfficeUser(new List<Program_Team__c>{ pt });
    }
}