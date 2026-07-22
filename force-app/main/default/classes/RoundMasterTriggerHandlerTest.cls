@IsTest
private class RoundMasterTriggerHandlerTest {
    
    private class DummyCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }
    
    @TestSetup
    static void setupData(){
        
        Test.setMock(HttpCalloutMock.class,new DummyCalloutMock());
        
        Program prog1 = new Program(
            Name='Program One',
            Program_Code__c='TP01',
            Programme_Type__c='Full-Time',
            Programme_Sub_Type__c='Class Room',
            Short_Programme_Code__c='TP',
            Programme_Contact__c='9998887776'
        );
        
        Program prog2 = new Program(
            Name='Program Two',
            Program_Code__c='TP02',
            Programme_Type__c='Full-Time',
            Programme_Sub_Type__c='Class Room',
            Short_Programme_Code__c='TP2',
            Programme_Contact__c='9998887777'
        );
        
        insert new List<Program>{prog1,prog2};
            
            RoundMaster__c r1 = new RoundMaster__c(
                Name='RoundOne',
                Program__c=prog1.Id,
                RoundNumber__c='1'
            );
        
        insert r1;
    }
    
    /* INSERT TEST */
    @IsTest
    static void testInsert(){
        
        Test.setMock(HttpCalloutMock.class,new DummyCalloutMock());
        
        Program prog=[SELECT Id FROM Program WHERE Name='Program One' LIMIT 1];
        
        RoundMaster__c r=new RoundMaster__c(
            Name='RoundTwo',
            Program__c=prog.Id,
            RoundNumber__c='2'
        );
        
        Test.startTest();
        insert r;
        Test.stopTest();
        
        System.assertNotEquals(null,r.Id);
    }
    
    /* UPDATE TEST (Different Program prevents duplicate) */
    @IsTest
    static void testUpdate(){
        
        Test.setMock(HttpCalloutMock.class,new DummyCalloutMock());
        
        Program prog2=[SELECT Id FROM Program WHERE Name='Program Two' LIMIT 1];
        
        RoundMaster__c r=new RoundMaster__c(
            Name='RoundThree',
            Program__c=prog2.Id,
            RoundNumber__c='1'
        );
        
        insert r;
        
        Test.startTest();
        
        r.Name='UpdatedRound';
        update r;
        
        Test.stopTest();
        
        System.assertEquals('UpdatedRound',r.Name);
    }
    
    /* DUPLICATE VALIDATION TEST */
    @IsTest
    static void testDuplicate(){
        
        Test.setMock(HttpCalloutMock.class,new DummyCalloutMock());
        
        Program prog=[SELECT Id FROM Program WHERE Name='Program One' LIMIT 1];
        
        RoundMaster__c dup=new RoundMaster__c(
            Name='DuplicateRound',
            Program__c=prog.Id,
            RoundNumber__c='1'
        );
        
        Test.startTest();
        
        try{
            insert dup;
            System.assert(false);
        }catch(DmlException e){
            System.assert(e.getMessage().contains('already exists'));
        }
        
        Test.stopTest();
    }
    
    /* DELETE TEST */
    @IsTest
    static void testDelete(){
        
        Test.setMock(HttpCalloutMock.class,new DummyCalloutMock());
        
        Program prog=[SELECT Id FROM Program WHERE Name='Program Two' LIMIT 1];
        
        RoundMaster__c r=new RoundMaster__c(
            Name='DeleteRound',
            Program__c=prog.Id,
            RoundNumber__c='3'
        );
        
        insert r;
        
        Test.startTest();
        delete r;
        Test.stopTest();
        
        RoundMaster__c deletedRound = [SELECT Id, IsDeleted FROM RoundMaster__c WHERE Id = :r.Id ALL ROWS];
        System.assertEquals(true, deletedRound.IsDeleted);
    }
    
    /* UNDELETE TEST */
    @IsTest
    static void testUndelete(){
        
        Test.setMock(HttpCalloutMock.class,new DummyCalloutMock());
        
        Program prog=[SELECT Id FROM Program WHERE Name='Program Two' LIMIT 1];
        
        RoundMaster__c r=new RoundMaster__c(
            Name='RestoreRound',
            Program__c=prog.Id,
            RoundNumber__c='3'
        );
        
        insert r;
        delete r;
        
        Test.startTest();
        undelete r;
        Test.stopTest();
        
        System.assertNotEquals(null,r.Id);
    }
}