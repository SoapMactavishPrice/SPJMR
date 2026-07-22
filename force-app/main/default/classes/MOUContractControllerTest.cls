@IsTest
private class MOUContractControllerTest {

    /* ------------------------------------------
       Dummy Callout Mock (for hidden automations)
    ------------------------------------------ */
    private class DummyCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":"success"}');
            return res;
        }
    }

    /* ------------------------------------------
       Test Data Setup
    ------------------------------------------ */
    @TestSetup
    static void setupData() {

        Test.setMock(HttpCalloutMock.class, new DummyCalloutMock());

        Program prog = new Program(
            Name = 'MBA Program',
            Program_Code__c = 'TP01',
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'TP',
            Programme_Contact__c = '9998887776'
        );
        insert prog;

        Slab__c slab = new Slab__c(
            Name = 'Slab 1',
            Program_Master__c = prog.Id,
            Start_Range__c = 1,
            End_Range__c = 100
        );
        insert slab;

        Company_Master__c comp =
            new Company_Master__c(Name='Test Company');
        insert comp;

        Lead ld = new Lead(
            LastName='Test Lead',
            Company='ABC',
            Company_Master__c = comp.Id
        );
        insert ld;

        Company_Contacts__c contact =
            new Company_Contacts__c(
                Name='Primary Contact',
                Email__c='test@mail.com',
                Company_Master__c = comp.Id,
                Primary_Contact__c = true
            );
        insert contact;
    }

    /* ------------------------------------------
       getProgramOptions
    ------------------------------------------ */
    @IsTest
    static void testGetProgramOptions() {
        List<Map<String,String>> result =
            MOUContractController.getProgramOptions();
        System.assert(result.size() > 0);
    }

    /* ------------------------------------------
       resolveSlab (All branches)
    ------------------------------------------ */
    @IsTest
    static void testResolveSlab() {

        Program prog = [SELECT Id FROM Program LIMIT 1];

        // Null input
        System.assertEquals(null,
            MOUContractController.resolveSlab(null, null));

        // Slab found
        Map<String,Object> slabMap =
            MOUContractController.resolveSlab(prog.Id, 10);
        System.assertNotEquals(null, slabMap);

        // Slab not found
        System.assertEquals(null,
            MOUContractController.resolveSlab(prog.Id, 9999));
    }

    /* ------------------------------------------
       getPrimaryContacts (All branches)
    ------------------------------------------ */
    @IsTest
    static void testGetPrimaryContacts() {

        Lead ld = [SELECT Id FROM Lead LIMIT 1];

        // Null lead
        Map<String,Object> nullResult =
            MOUContractController.getPrimaryContacts(null,5,1);
        System.assertEquals(0,
            (Integer)nullResult.get('total'));

        // Lead without company
        Lead newLead = new Lead(
            LastName='NoCompany',
            Company='Test'
        );
        insert newLead;

        Map<String,Object> noCompanyResult =
            MOUContractController.getPrimaryContacts(newLead.Id,5,1);
        System.assertEquals(0,
            (Integer)noCompanyResult.get('total'));

        // Valid case
        Map<String,Object> result =
            MOUContractController.getPrimaryContacts(ld.Id,5,1);
        System.assertNotEquals(null, result);

        // Pagination branch
        Map<String,Object> page2 =
            MOUContractController.getPrimaryContacts(ld.Id,1,2);
        System.assertNotEquals(null, page2);
    }

    /* ------------------------------------------
       saveMOUContract SUCCESS (with contacts)
    ------------------------------------------ */
    @IsTest
    static void testSaveMOUContractSuccess() {

        Lead ld = [SELECT Id FROM Lead LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];
        Slab__c slab = [SELECT Id FROM Slab__c LIMIT 1];
        Company_Contacts__c contact =
            [SELECT Id FROM Company_Contacts__c LIMIT 1];

        MOU_Contract__c mou = new MOU_Contract__c();

        List<Map<String,Object>> rows =
            new List<Map<String,Object>>{
                new Map<String,Object>{
                    'programId'=>prog.Id,
                    'participants'=>10,
                    'slabId'=>slab.Id
                }
            };

        List<Id> contactIds = new List<Id>{contact.Id};

        String result =
            MOUContractController.saveMOUContract(
                mou,
                rows,
                contactIds,
                ld.Id
            );

        System.assert(result.contains('SUCCESS'));
    }

    /* ------------------------------------------
       saveMOUContract SUCCESS (without contacts)
    ------------------------------------------ */
    @IsTest
    static void testSaveWithoutContacts() {

        Lead ld = [SELECT Id FROM Lead LIMIT 1];
        Program prog = [SELECT Id FROM Program LIMIT 1];

        MOU_Contract__c mou = new MOU_Contract__c();

        List<Map<String,Object>> rows =
            new List<Map<String,Object>>{
                new Map<String,Object>{
                    'programId'=>prog.Id,
                    'participants'=>5,
                    'slabId'=>null
                }
            };

        String result =
            MOUContractController.saveMOUContract(
                mou,
                rows,
                null,
                ld.Id
            );

        System.assert(result.contains('SUCCESS'));
    }

    /* ------------------------------------------
       Validation Branches
    ------------------------------------------ */
    @IsTest
static void testSaveMOUContractValidations() {

    Lead ld = [SELECT Id FROM Lead LIMIT 1];
    Program prog = [SELECT Id FROM Program LIMIT 1];

    // Missing leadId
    Boolean exceptionThrown = false;
    try {
        MOUContractController.saveMOUContract(
            new MOU_Contract__c(),
            new List<Map<String,Object>>(),
            null,
            null
        );
    } catch(Exception e) {
        exceptionThrown = true;
    }
    System.assertEquals(true, exceptionThrown, 'Exception expected for missing leadId');


    // Null mou
    exceptionThrown = false;
    try {
        MOUContractController.saveMOUContract(
            null,
            new List<Map<String,Object>>(),
            null,
            ld.Id
        );
    } catch(Exception e) {
        exceptionThrown = true;
    }
    System.assertEquals(true, exceptionThrown, 'Exception expected for null MOU');


    // programRows null
    exceptionThrown = false;
    try {
        MOUContractController.saveMOUContract(
            new MOU_Contract__c(),
            null,
            null,
            ld.Id
        );
    } catch(Exception e) {
        exceptionThrown = true;
    }
    System.assertEquals(true, exceptionThrown, 'Exception expected for null programRows');


    // Missing programId
    exceptionThrown = false;
    try {
        List<Map<String,Object>> rows =
            new List<Map<String,Object>>{
                new Map<String,Object>{
                    'participants' => 5
                }
            };

        MOUContractController.saveMOUContract(
            new MOU_Contract__c(),
            rows,
            null,
            ld.Id
        );
    } catch(Exception e) {
        exceptionThrown = true;
    }
    System.assertEquals(true, exceptionThrown, 'Exception expected for missing programId');


    // Invalid participants
    exceptionThrown = false;
    try {
        List<Map<String,Object>> rows =
            new List<Map<String,Object>>{
                new Map<String,Object>{
                    'programId' => prog.Id,
                    'participants' => 0
                }
            };

        MOUContractController.saveMOUContract(
            new MOU_Contract__c(),
            rows,
            null,
            ld.Id
        );
    } catch(Exception e) {
        exceptionThrown = true;
    }
    System.assertEquals(true, exceptionThrown, 'Exception expected for invalid participants');
}    

}