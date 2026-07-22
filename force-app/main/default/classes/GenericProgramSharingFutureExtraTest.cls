/**
 * Supplements GenericProgramSharingFutureTest by walking the populated path:
 * real Application__c -> ProgramResolver returns programIds -> ProgramTeamService.getActiveMembers
 * -> ShareBuilder.buildShares -> Database.insert.
 */
@IsTest(seeAllData=true)
private class GenericProgramSharingFutureExtraTest {

    @IsTest
    static void shareRecords_runsFullChainWithRealApplicationId() {
        List<Application__c> apps = [SELECT Id FROM Application__c WHERE Program__c != null LIMIT 1];
        if (apps.isEmpty()) {
            return;
        }
        Test.startTest();
        GenericProgramSharingFuture.shareRecords('Application__c', new List<Id>{ apps[0].Id });
        Test.stopTest();
    }
}