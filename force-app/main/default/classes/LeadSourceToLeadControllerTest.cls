@IsTest
private class LeadSourceToLeadControllerTest {
    
    // Mock for possible callouts from triggers
    public class DummyCalloutMock implements HttpCalloutMock {
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
        
        
        
        //Create original Lead
        Lead originalLead = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Company = 'Test Company',
            Status = 'Open' // Use valid status
        );
        insert originalLead;
        
        //Create Lead Source record
        Lead_Sources__c ls = new Lead_Sources__c(
            
            Email__c = 'new@test.com',
            Phone__c = '8888888888',
            Lead__c = originalLead.Id
            
        );
        insert ls;
    }
    
    @IsTest
    static void testConvertLead_Success() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Lead_Sources__c ls = [SELECT Id FROM Lead_Sources__c LIMIT 1];
        
        Test.startTest();
        String newLeadId = LeadSourceToLeadController.convertLead(ls.Id);
        Test.stopTest();
        
        // Verify new Lead created
        Lead createdLead = [
            SELECT Id, Email, Phone, Converted_From__c
            FROM Lead
            WHERE Id = :newLeadId
        ];
        
        System.assertEquals('new@test.com', createdLead.Email);
        System.assertEquals('8888888888', createdLead.Phone);
        System.assertEquals(ls.Id, createdLead.Converted_From__c);
    }
    
    @IsTest
    static void testConvertLead_Exception() {
        
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());
        
        Test.startTest();
        try {
            LeadSourceToLeadController.convertLead(null);
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}