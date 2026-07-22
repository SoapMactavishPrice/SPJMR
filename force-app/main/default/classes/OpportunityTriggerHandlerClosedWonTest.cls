/**
 * Tests B2B Closed Won contract automation (OpportunityTriggerHandler) and legacy non-B2B close-won behavior.
 */
@IsTest
private class OpportunityTriggerHandlerClosedWonTest {
    private static Id b2bRecordTypeId() {
        Schema.RecordTypeInfo rti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2B_Opportunity');
        System.assertNotEquals(null, rti, 'Org must define Opportunity record type B2B_Opportunity.');
        return rti.getRecordTypeId();
    }

    private static Id b2cRecordTypeIdOrNull() {
        Schema.RecordTypeInfo rti = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity');
        return rti != null && rti.isAvailable() ? rti.getRecordTypeId() : null;
    }

    private static Account insertAccount() {
        Account a = new Account(Name = 'Closed Won Contract Test Account');
        insert a;
        return a;
    }

    private static Opportunity insertB2BOpportunity(Id accountId, Id pricebookId) {
        Opportunity opp = new Opportunity(
            Name = 'B2B Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId,
            RecordTypeId = b2bRecordTypeId()
        );
        insert opp;
        return opp;
    }

    private static Quote insertQuote(Id opportunityId, Id pricebookId) {
        Quote q = new Quote(Name = 'Test Quote', OpportunityId = opportunityId, Pricebook2Id = pricebookId);
        insert q;
        q.Status = 'Accepted';
        update q;
        return q;
    }

    @IsTest
    static void b2bClosedWon_syncedQuote_createsDraftContract_linksOppAndQuote() {
        Id pricebookId = Test.getStandardPricebookId();
        System.assertNotEquals(null, pricebookId, 'Standard Price Book required for Quote tests.');

        Account acc = insertAccount();
        Opportunity opp = insertB2BOpportunity(acc.Id, pricebookId);
        Quote q = insertQuote(opp.Id, pricebookId);

        Test.startTest();
        opp.SyncedQuoteId = q.Id;
        update opp;
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT Id, ContractId, AccountId, CloseDate
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
        System.assertNotEquals(null, updatedOpp.ContractId, 'Opportunity should reference new Contract.');

        Contract c = [
            SELECT Id, AccountId, Status, StartDate, ContractTerm, Description
            FROM Contract
            WHERE Id = :updatedOpp.ContractId
        ];
        System.assertEquals(acc.Id, c.AccountId);
        System.assertEquals(updatedOpp.CloseDate, c.StartDate);
        System.assertEquals(12, c.ContractTerm);
        System.assertEquals('Draft', c.Status);
        System.assertEquals(
            'Automatically generated from Closed Won Opportunity via Synced/Accepted Quote.',
            c.Description
        );

        if (Schema.SObjectType.Quote.fields.getMap().containsKey('contractid')) {
            Quote quoted = [SELECT ContractId FROM Quote WHERE Id = :q.Id];
            System.assertEquals(c.Id, quoted.ContractId);
        }
    }

    @IsTest
    static void b2bClosedWon_noSync_usesLatestAcceptedQuote() {
        Id pricebookId = Test.getStandardPricebookId();
        System.assertNotEquals(null, pricebookId);

        Account acc = insertAccount();
        Opportunity opp = insertB2BOpportunity(acc.Id, pricebookId);
        Quote q = insertQuote(opp.Id, pricebookId);

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [SELECT ContractId FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.ContractId);

        if (Schema.SObjectType.Quote.fields.getMap().containsKey('contractid')) {
            Quote quoted = [SELECT ContractId FROM Quote WHERE Id = :q.Id];
            System.assertEquals(updatedOpp.ContractId, quoted.ContractId);
        }
    }

    @IsTest
    static void b2bClosedWon_noQuote_stillCreatesContract() {
        Id pricebookId = Test.getStandardPricebookId();
        System.assertNotEquals(null, pricebookId);

        Account acc = insertAccount();
        Opportunity opp = insertB2BOpportunity(acc.Id, pricebookId);

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [SELECT ContractId FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.ContractId);

        Contract c = [
            SELECT Status, Description
            FROM Contract
            WHERE Id = :updatedOpp.ContractId
        ];
        System.assertEquals('Draft', c.Status);
    }

    @IsTest
    static void b2bClosedWon_missingAccount_throwsAndRollsBack() {
        Id pricebookId = Test.getStandardPricebookId();
        if (pricebookId == null) {
            return;
        }

        Id b2bRt = b2bRecordTypeId();
        Opportunity opp = new Opportunity(
            Name = 'No Account Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId,
            RecordTypeId = b2bRt
        );
        try {
            insert opp;
        } catch (DmlException e) {
            return;
        }

        Boolean sawException = false;
        Test.startTest();
        try {
            opp.StageName = 'Closed Won';
            update opp;
        } catch (Exception expected) {
            sawException = true;
        }
        Test.stopTest();

        System.assertEquals(true, sawException, 'Expected failure when Account is missing.');

        Opportunity reloaded = [SELECT StageName FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals('Closed Won', reloaded.StageName);
    }

    @IsTest
    static void b2bClosedWon_skipsWhenContractAlreadySet() {
        Id pricebookId = Test.getStandardPricebookId();
        System.assertNotEquals(null, pricebookId);

        Account acc = insertAccount();
        Opportunity opp = insertB2BOpportunity(acc.Id, pricebookId);
        insertQuote(opp.Id, pricebookId);

        Contract existing = new Contract(
            AccountId = acc.Id,
            StartDate = Date.today(),
            ContractTerm = 6,
            Status = 'Draft'
        );
        insert existing;

        opp.ContractId = existing.Id;
        update opp;

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        System.assertEquals(
            existing.Id,
            [SELECT ContractId FROM Opportunity WHERE Id = :opp.Id].ContractId,
            'Existing Contract should be preserved.'
        );
        System.assertEquals(
            1,
            [SELECT Id FROM Contract WHERE AccountId = :acc.Id].size(),
            'No second Contract should be inserted.'
        );
    }

    @IsTest
    static void bulkB2BClosedWon_createsContracts() {
        Id pricebookId = Test.getStandardPricebookId();
        System.assertNotEquals(null, pricebookId);

        Account acc = insertAccount();
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            opps.add(
                new Opportunity(
                    Name = 'Bulk B2B ' + i,
                    AccountId = acc.Id,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Pricebook2Id = pricebookId,
                    RecordTypeId = b2bRecordTypeId()
                )
            );
        }
        insert opps;

        for (Opportunity o : opps) {
            insertQuote(o.Id, pricebookId);
        }

        Test.startTest();
        for (Opportunity o : opps) {
            o.StageName = 'Closed Won';
        }
        update opps;
        Test.stopTest();

        List<Opportunity> reloaded = [SELECT ContractId FROM Opportunity WHERE Id IN :opps];
        for (Opportunity o : reloaded) {
            System.assertNotEquals(null, o.ContractId);
        }
    }

    @IsTest
    static void legacyNonB2B_closedWon_stillRunsWhenB2CRecordTypeExists() {
        Id b2cRt = b2cRecordTypeIdOrNull();
        if (b2cRt == null) {
            return;
        }

        Id pricebookId = Test.getStandardPricebookId();
        System.assertNotEquals(null, pricebookId);

        Account acc = insertAccount();
        Opportunity opp = new Opportunity(
            Name = 'B2C Legacy Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId,
            RecordTypeId = b2cRt
        );
        insert opp;

        Quote q = new Quote(Name = 'Legacy Q', OpportunityId = opp.Id, Pricebook2Id = pricebookId);
        insert q;
        q.Status = 'Accepted';
        update q;

        Test.startTest();
        opp.SyncedQuoteId = q.Id;
        update opp;
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        Opportunity updatedOpp = [SELECT ContractId FROM Opportunity WHERE Id = :opp.Id];
        System.assertNotEquals(null, updatedOpp.ContractId);

        Contract c = [SELECT Status FROM Contract WHERE Id = :updatedOpp.ContractId];
        System.assertEquals('Activated', c.Status);
    }
}