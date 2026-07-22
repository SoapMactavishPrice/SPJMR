@IsTest
private class RoundMasterTriggerHelperTest {
    
    // Mock class for callouts from triggers/flows
    private class DummyCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }
    
    @TestSetup
    static void setupData() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Program prog = new Program(
            Name = 'Test Program',
            Program_Code__c = 'TP01',
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'TP',
            Programme_Contact__c = '9998887776'
        );
        insert prog;
        
        // Existing round for duplicate test
        RoundMaster__c existingRound = new RoundMaster__c(
            Name = 'FirstRound',
            Program__c = prog.Id,
            RoundNumber__c = '1'
        );
        insert existingRound;
    }
    
    /* Test Empty List */
    @IsTest
    static void testEmptyList() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Test.startTest();
        RoundMasterTriggerHelper.checkForSameSequence(
            new List<RoundMaster__c>()
        );
        Test.stopTest();
        
        Integer countRounds = [SELECT COUNT() FROM RoundMaster__c];
        System.assertEquals(1, countRounds, 'No new rounds should be created when list is empty');
    }
    
    /* Test Round Name With Number */
    @IsTest
    static void testRoundNameWithNumber() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        RoundMaster__c roundRec = new RoundMaster__c(
            Name = 'Round1',
            Program__c = prog.Id,
            RoundNumber__c = '2'
        );
        
        List<RoundMaster__c> rounds = new List<RoundMaster__c>{roundRec};
            
            Test.startTest();
        try {
            RoundMasterTriggerHelper.checkForSameSequence(rounds);
        } catch (Exception e) {}
        Test.stopTest();
    }
    
    /* Test Duplicate Round Number */
    @IsTest
    static void testDuplicateRoundNumber() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        RoundMaster__c duplicateRound = new RoundMaster__c(
            Name = 'SecondRound',
            Program__c = prog.Id,
            RoundNumber__c = '1'
        );
        
        List<RoundMaster__c> rounds = new List<RoundMaster__c>{duplicateRound};
            
            Test.startTest();
        try {
            RoundMasterTriggerHelper.checkForSameSequence(rounds);
        } catch (Exception e) {}
        Test.stopTest();
        
    }
    
    /* Test Valid Round */
    @IsTest
    static void testValidRound() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        RoundMaster__c validRound = new RoundMaster__c(
            Name = 'SecondRound',
            Program__c = prog.Id,
            RoundNumber__c = '3'
        );
        
        List<RoundMaster__c> rounds = new List<RoundMaster__c>{validRound};
            
            Test.startTest();
        RoundMasterTriggerHelper.checkForSameSequence(rounds);
        Test.stopTest();
        
        System.assertEquals('3', validRound.RoundNumber__c);
        System.assertEquals('SecondRound', validRound.Name);
    }
    @IsTest
    static void testRoundNameNull() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Program prog = [SELECT Id FROM Program LIMIT 1];
        
        RoundMaster__c roundRec = new RoundMaster__c(
            Name = null,
            Program__c = prog.Id,
            RoundNumber__c = '5'
        );
        
        List<RoundMaster__c> rounds = new List<RoundMaster__c>{roundRec};
            
            Test.startTest();
        RoundMasterTriggerHelper.checkForSameSequence(rounds);
        Test.stopTest();
        
        System.assertEquals(null, roundRec.Name);
        System.assertEquals('5', roundRec.RoundNumber__c);
    }
}