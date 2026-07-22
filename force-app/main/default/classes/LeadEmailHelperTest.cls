@IsTest(seeAllData=true)
private class LeadEmailHelperTest {

    @IsTest
    static void sendWelcomeEmail_emptyInputsReturnEarly() {
        Test.startTest();
        LeadEmailHelper.sendWelcomeEmail(new List<Id>());
        LeadEmailHelper.sendWelcomeEmail(new List<Lead>());
        Test.stopTest();
    }

    @IsTest
    static void sendWelcomeEmail_idsOverloadSendsForLeadsWithEmail() {
        Lead l1 = new Lead(FirstName = 'Email', LastName = 'Test1', Email = 'lead1@test.com', Company = 'Co');
        Lead l2 = new Lead(FirstName = 'Em<ail>', LastName = 'Test"2', Email = 'lead2@test.com', Company = 'Co');
        insert new List<Lead>{ l1, l2 };

        Test.startTest();
        LeadEmailHelper.sendWelcomeEmail(new List<Id>{ l1.Id, l2.Id });
        Test.stopTest();
    }

    @IsTest
    static void sendWelcomeEmail_listOverloadDelegatesToIdsOverload() {
        Lead l = new Lead(FirstName = 'Delegate', LastName = 'Test', Email = 'del@test.com', Company = 'Co');
        insert l;
        Test.startTest();
        LeadEmailHelper.sendWelcomeEmail(new List<Lead>{ l });
        Test.stopTest();
    }
}