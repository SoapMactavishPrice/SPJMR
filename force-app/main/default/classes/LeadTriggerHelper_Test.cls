@isTest
public class LeadTriggerHelper_Test {
    
    // ✅ Callout Mock
    public class DummyCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }
    
    @TestSetup
    static void setupData(){

        // ✅ Set mock BEFORE any DML
        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Id recordTypeId_B2B = Schema.SobjectType.Lead
            .getRecordTypeInfosByName()
            .get('B2B')
            .getRecordTypeId();

        Lead l1 = new Lead(
            FirstName = 'test',
            LastName = 'testHydra',
            Email = 'b2b@test.com',
            RecordTypeId = recordTypeId_B2B,
            Company = 'SJ Corp'
        );
        insert l1;

        Insert new Program(
            Name = 'Test Program',
            IsActive = true,
            StartDate = System.Today().addDays(-15),
            EndDate = System.Today().addDays(18),
            Program_Code__c = 'TP01',
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'TP',
            Programme_Contact__c = '9998887776'
        );

        Insert new Lead_Contact__c(
            Lead__c = l1.Id,
            Name = 'Test',
            Email__c = 'leadcontact@test.com'
        );
    }
    
    @isTest
    static void convertB2BLead_test(){

        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Lead l1 = [SELECT Id FROM Lead LIMIT 1];

        LeadStatus convertStatus = [
            SELECT MasterLabel 
            FROM LeadStatus 
            WHERE IsConverted = true 
            LIMIT 1
        ];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l1.Id);
        lc.setConvertedStatus(convertStatus.MasterLabel);
        lc.setDoNotCreateOpportunity(true); 

        Database.LeadConvertResult lcr = Database.convertLead(lc);

        System.assert(lcr.isSuccess());
    }
    
    @isTest
    static void insertGradesTest(){

        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Id recordTypeId_B2C = Schema.SobjectType.Lead
            .getRecordTypeInfosByName()
            .get('B2C')
            .getRecordTypeId();

        Id programId = [SELECT Id FROM Program LIMIT 1].Id;

        Lead l1 = new Lead(
            LastName = 'testHydra',
            Email = 'b2c@test.com',
            RecordTypeId = recordTypeId_B2C,
            Is_Verified__c = true,
            Company = 'Test Company',
            Program_Master__c = programId
        );
        insert l1;

        LeadStatus convertStatus = [
            SELECT MasterLabel 
            FROM LeadStatus 
            WHERE IsConverted = true 
            LIMIT 1
        ];

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(l1.Id);
        lc.setConvertedStatus(convertStatus.MasterLabel);
        lc.setDoNotCreateOpportunity(true); 

        Database.LeadConvertResult lcr = Database.convertLead(lc);

        System.assert(lcr.isSuccess());

        Lead l2 = new Lead(
            LastName = 'testHydra2',
            Email = 'b2c2@test.com',
            RecordTypeId = recordTypeId_B2C,
            Company = 'Test Company',
            Program_Master__c = programId
        );
        insert l2;
    }
}