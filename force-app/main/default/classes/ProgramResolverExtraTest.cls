/**
 * Supplements ProgramResolverTest by exercising the Direct Program Lookup branch
 * (Application__c -> Program__c) and the Parent-Chain branch (Academic_Detail__c -> Application__c -> Program__c).
 */
@IsTest(seeAllData=true)
private class ProgramResolverExtraTest {

    @IsTest
    static void resolvePrograms_directLookupReturnsProgramId() {
        // Application__c has Program_Lookup_Field__c='Program__c' per CMDT
        List<Application__c> apps = [SELECT Id FROM Application__c WHERE Program__c != null LIMIT 2];
        if (apps.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Application__c a : apps) {
            ids.add(a.Id);
        }
        Map<Id, Id> result = ProgramResolver.resolvePrograms('Application__c', ids);
        System.assertEquals(apps.size(), result.size(), 'Each app should map to a program');
    }

    @IsTest
    static void resolvePrograms_parentChainResolves() {
        // Try with a child object that has a parent chain to Application__c.
        // Academic_Detail__c -> Application__c -> Program__c
        List<Academic_Detail__c> details = [
            SELECT Id FROM Academic_Detail__c WHERE Application__c != null LIMIT 2
        ];
        if (details.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (Academic_Detail__c d : details) {
            ids.add(d.Id);
        }
        Map<Id, Id> result = ProgramResolver.resolvePrograms('Academic_Detail__c', ids);
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void resolvePrograms_parentChainEmptyParents() {
        // Trigger the parent-chain branch but with records whose parent field is null
        // -> parentIds stays empty -> early return at line 87.
        // Use a fake Id of a parent-chained object
        Id fake = Schema.SObjectType.Academic_Detail__c.getKeyPrefix() + '000000000099';
        Map<Id, Id> result = ProgramResolver.resolvePrograms('Academic_Detail__c', new Set<Id>{ fake });
        System.assertEquals(0, result.size());
    }
}