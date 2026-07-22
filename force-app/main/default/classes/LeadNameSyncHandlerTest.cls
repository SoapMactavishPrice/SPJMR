@IsTest
private class LeadNameSyncHandlerTest {

    @IsTest
    static void testProcess_AllBranches() {
        Lead customFnOnly = new Lead(
            First_Name__c = 'CustomFN',
            Last_Name__c = null,
            FirstName = 'OldStdFN',
            LastName = 'OldStdLN'
        );

        Lead customFnAndLn = new Lead(
            First_Name__c = 'CustomFirst',
            Last_Name__c = 'CustomLast',
            FirstName = 'OldStdFirst',
            LastName = 'OldStdLast'
        );

        Lead stdFnAndLn = new Lead(
            FirstName = 'StdFirst',
            LastName = 'StdLast'
        );

        Lead stdFnNoLn = new Lead(
            FirstName = 'OnlyStdFirst',
            LastName = null
        );

        Lead noData = new Lead(
            FirstName = null,
            LastName = null,
            First_Name__c = null,
            Last_Name__c = null
        );

        List<Lead> leads = new List<Lead>{
            customFnOnly, customFnAndLn, stdFnAndLn, stdFnNoLn, noData
        };

        LeadNameSyncHandler.process(leads);

        // CASE A: custom first present, custom last blank -> last name = custom first
        System.assertEquals('CustomFN', customFnOnly.FirstName);
        System.assertEquals('CustomFN', customFnOnly.LastName);

        // CASE A: custom first + custom last -> standard names follow custom values
        System.assertEquals('CustomFirst', customFnAndLn.FirstName);
        System.assertEquals('CustomLast', customFnAndLn.LastName);

        // CASE B: standard first + last -> copy both into custom fields
        System.assertEquals('StdFirst', stdFnAndLn.First_Name__c);
        System.assertEquals('StdLast', stdFnAndLn.Last_Name__c);

        // CASE B: standard first but no standard last -> set dot fallback
        System.assertEquals('OnlyStdFirst', stdFnNoLn.First_Name__c);
        System.assertEquals('.', stdFnNoLn.LastName);
        System.assertEquals('.', stdFnNoLn.Last_Name__c);

        // No data case -> should remain untouched
        System.assertEquals(null, noData.FirstName);
        System.assertEquals(null, noData.LastName);
        System.assertEquals(null, noData.First_Name__c);
        System.assertEquals(null, noData.Last_Name__c);
    }

    @IsTest
    static void testProcess_EmptyList() {
        LeadNameSyncHandler.process(new List<Lead>());
        System.assert(true, 'Empty list should be handled safely.');
    }
}