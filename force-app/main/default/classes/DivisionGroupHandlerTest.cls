@IsTest(SeeAllData=true)
private class DivisionGroupHandlerTest {
    @IsTest
    static void emptyListIsHandled() {
        DivisionGroupHandler.beforeDelete(new List<Division_Group__c>());
    }
    @IsTest
    static void existingGroupWithDivisions_isBlocked() {
        List<AggregateResult> ar = [
            SELECT Division_Group__c dgId
            FROM Division__c
            WHERE Division_Group__c != null
            GROUP BY Division_Group__c
            LIMIT 1
        ];
        if (ar.isEmpty()) return;
        Id dgId = (Id) ar[0].get('dgId');
        Division_Group__c dg = [SELECT Id FROM Division_Group__c WHERE Id = :dgId LIMIT 1];

        DivisionGroupHandler.beforeDelete(new List<Division_Group__c>{ dg });
        System.assert(dg.hasErrors(), 'Expected addError to be applied');
    }
}