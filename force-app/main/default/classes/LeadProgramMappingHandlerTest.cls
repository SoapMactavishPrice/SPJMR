@IsTest
private class LeadProgramMappingHandlerTest {

    // Mock for callouts happening in triggers
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

        List<Program> progs = new List<Program>{
            new Program(
                Name = 'MBA',
                Program_Code__c = 'MBA01',
                Programme_Type__c = 'Full-Time',
                Programme_Sub_Type__c = 'Class Room',
                Short_Programme_Code__c = 'S01',
                Programme_Contact__c = '9998887776'
            ),
            new Program(
                Name = 'PGDM',
                Program_Code__c = 'PGDM01',
                Programme_Type__c = 'Full-Time',
                Programme_Sub_Type__c = 'Class Room',
                Short_Programme_Code__c = 'S02',
                Programme_Contact__c = '9998887775'
            )
        };

        insert progs;
    }

    private static Program getProgramByName(String name) {
        return [SELECT Id, Name FROM Program WHERE Name = :name LIMIT 1];
    }

    @IsTest
    static void testPicklistToLookup() {

        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Lead l = new Lead(
            LastName = 'Test Lead',
            Company = 'Acme',
            Program_Picklist__c = 'MBA'
        );

        Test.startTest();
        LeadProgramMappingHandler.syncProgramFields(new List<Lead>{ l });
        Test.stopTest();

        Program mba = getProgramByName('MBA');
        System.assertEquals(mba.Id, l.Program_Master__c);
    }

    @IsTest
    static void testLookupToPicklist() {

        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Program pgdm = getProgramByName('PGDM');

        Lead l = new Lead(
            LastName = 'Test Lead 2',
            Company = 'Acme',
            Program_Master__c = pgdm.Id
        );

        Test.startTest();
        LeadProgramMappingHandler.syncProgramFields(new List<Lead>{ l });
        Test.stopTest();

        System.assertEquals('PGDM', l.Program_Picklist__c);
    }

    @IsTest
    static void testNoMatch() {

        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Lead l = new Lead(
            LastName = 'Test Lead 3',
            Company = 'Acme',
            Program_Picklist__c = 'Unknown'
        );

        Test.startTest();
        LeadProgramMappingHandler.syncProgramFields(new List<Lead>{ l });
        Test.stopTest();

        System.assertEquals(null, l.Program_Master__c);
    }
}