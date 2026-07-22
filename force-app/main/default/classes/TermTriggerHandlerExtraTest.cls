/**
 * Supplements TermTriggerHandlerTest by exercising the full sequential-naming path:
 * Division_Group__c name = "Fundamental", Term__c set, and the for-loop that assigns
 * A, B, C... names based on existing count.
 */
@IsTest(seeAllData=true)
private class TermTriggerHandlerExtraTest {

    @IsTest
    static void assignSequentialNames_assignsLettersToFundamentalDivisions() {
        Division_Group__c fundamental;
        for (Division_Group__c dg : [SELECT Id, Name FROM Division_Group__c WHERE Name = 'Fundamental' LIMIT 1]) {
            fundamental = dg;
        }
        if (fundamental == null) {
            return;
        }
        // Find a Term__c reference value via an existing Division__c
        Id termId;
        for (Division__c d : [SELECT Term__c FROM Division__c WHERE Term__c != null LIMIT 1]) {
            termId = d.Term__c;
        }
        if (termId == null) {
            return;
        }

        // Construct in-memory Division__c records (no DML — handler just stamps Division_Name__c)
        Division__c d1 = new Division__c(Division_Group__c = fundamental.Id, Term__c = termId);
        Division__c d2 = new Division__c(Division_Group__c = fundamental.Id, Term__c = termId);
        TermTriggerHandler.assignSequentialNames(new List<Division__c>{ d1, d2 });

        // Each got a non-blank Division_Name__c assigned (A/B... or AA/AB depending on existing count)
        System.assertNotEquals(null, d1.Division_Name__c);
        System.assertNotEquals(null, d2.Division_Name__c);
        System.assertNotEquals(d1.Division_Name__c, d2.Division_Name__c);
    }

    @IsTest
    static void assignSequentialNames_nonFundamentalGroupNoOp() {
        // Find a non-Fundamental group to skip the inner branch
        Division_Group__c other;
        for (Division_Group__c dg : [SELECT Id, Name FROM Division_Group__c WHERE Name != 'Fundamental' LIMIT 1]) {
            other = dg;
        }
        if (other == null) {
            return;
        }
        Id termId;
        for (Division__c d : [SELECT Term__c FROM Division__c WHERE Term__c != null LIMIT 1]) {
            termId = d.Term__c;
        }
        if (termId == null) {
            return;
        }
        Division__c d = new Division__c(Division_Group__c = other.Id, Term__c = termId);
        TermTriggerHandler.assignSequentialNames(new List<Division__c>{ d });
        // Skipped: Division_Name__c stays null
        System.assertEquals(null, d.Division_Name__c);
    }
}