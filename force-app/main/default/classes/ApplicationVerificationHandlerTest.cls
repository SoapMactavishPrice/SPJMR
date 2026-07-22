@IsTest
public class ApplicationVerificationHandlerTest {
    
    private class DummyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true}');
            return res;
        }
    }
    
    @TestSetup
    static void setupData() {
        
        Test.setMock(HttpCalloutMock.class, new DummyMock());
        
        Program prog = new Program(
            Name = 'Test Program',
            Program_Code__c = 'TP01',
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'TP',
            Programme_Contact__c = '9900887766'
        );
        insert prog;
        
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User u = new User(
            FirstName = 'Test',
            LastName = 'Verifier',
            Email = 'verifier@test.com',
            Username = 'verifier' + System.currentTimeMillis() + '@test.com',
            Alias = 'ver1',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert u;
        
        Program_Team__c team = new Program_Team__c(
            Name = 'Dual Team',
            Program__c = prog.Id,
            Type__c = 'Verifier',
            IsApplicationVerifier__c = true,
            IsDocumentVerifier__c = true
        );
        insert team;
        
        Program_Team_Members__c ptm = new Program_Team_Members__c(
            Program_Team__c = team.Id,
            User__c = u.Id
        );
        insert ptm;
        
        Application__c app = new Application__c(
            Name = 'Test App',
            Program__c = prog.Id,
            Assignment_Status__c = 'Assigned'
        );
        insert app;
        
        Application_Verification__c av = new Application_Verification__c(
            Application__c = app.Id,
            Program_Team_Members__c = ptm.Id,
            Verifier__c = u.Id,
            OwnerId = u.Id,
            Application_Verification_Status__c = 'Assigned',
            Status__c = 'Assigned'
        );
        insert av;
    }
    
    @IsTest
    static void testApplicationVerificationCompleted() {
        
        Test.setMock(HttpCalloutMock.class, new DummyMock());
        
        Application_Verification__c av =
            [SELECT Id, Application_Verification_Status__c
             FROM Application_Verification__c LIMIT 1];
        
        Test.startTest();
        av.Application_Verification_Status__c = 'Completed';
        update av;
        Test.stopTest();
        
        Application__c app =
            [SELECT Assignment_Status__c FROM Application__c LIMIT 1];
        
        System.assertEquals('Application Verified', app.Assignment_Status__c);
    }
    
    @IsTest
    static void testDocumentVerificationCompleted() {
        
        Test.setMock(HttpCalloutMock.class, new DummyMock());
        
        Application_Verification__c av =
            [SELECT Id, Status__c FROM Application_Verification__c LIMIT 1];
        
        Test.startTest();
        av.Status__c = 'Completed';
        update av;
        Test.stopTest();
        
        Application__c app =
            [SELECT Assignment_Status__c FROM Application__c LIMIT 1];
        
        System.assertEquals('Document Verified', app.Assignment_Status__c);
    }
    
    @IsTest
    static void testNoStatusChange() {
        
        Test.setMock(HttpCalloutMock.class, new DummyMock());
        
        Application_Verification__c av =
            [SELECT Id FROM Application_Verification__c LIMIT 1];
        
        Test.startTest();
        update av;
        Test.stopTest();
        
        Application__c app =
            [SELECT Assignment_Status__c FROM Application__c LIMIT 1];
        
        System.assertEquals('Assigned', app.Assignment_Status__c);
    }
}