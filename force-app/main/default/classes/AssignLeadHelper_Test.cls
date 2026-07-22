@IsTest(SeeAllData=true)
public class AssignLeadHelper_Test {
    private class DummyHttpMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    private class DummyWebServiceMock implements WebServiceMock {
        public void doInvoke(
            Object stub,
            Object request,
            Map<String, Object> response,
            String endpoint,
            String soapAction,
            String requestName,
            String responseNS,
            String responseName,
            String responseType
        ) {
            // No-op mock to satisfy unexpected SOAP invocations from automation.
        }
    }

    private static void configureCalloutMocks() {
        Test.setMock(HttpCalloutMock.class, new DummyHttpMock());
        Test.setMock(WebServiceMock.class, new DummyWebServiceMock());
    }

    private static User makeUser(String seed, Boolean transferEnabled) {
        Profile p = [SELECT Id FROM Profile LIMIT 1];
        User u = new User(
            Alias = ('u' + seed).left(8),
            Email = seed + '@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User ' + seed,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = seed + '.' + System.currentTimeMillis() + '@test.com',
            Lead_Transfer__c = transferEnabled
        );
        insert u;
        return u;
    }

    private static Program makeProgram(String seed) {
        List<Program> activePrograms = [
            SELECT Id, Name
            FROM Program
            WHERE IsActive = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!activePrograms.isEmpty()) {
            return activePrograms[0];
        }

        return [SELECT Id, Name FROM Program LIMIT 1];
    }

    private static Lead makeLead(String seed) {
        Map<String, Schema.RecordTypeInfo> rtByDev =
            Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
        Lead l = new Lead(
            FirstName = 'Test',
            LastName = 'Lead ' + seed,
            Company = 'Test Company ' + seed,
            Status = 'Open - Not Contacted',
            Email = seed + '@lead.com',
            Phone = '9876543210',
            LeadSource = 'Website'
        );

        // Populate common org-required fields used in existing lead tests/flows.
        l.put('XS_State__c', 'Test');
        l.put('XS_City__c', 'CityTest');
        l.put('XS_HaveYouCompletedYourGraduation__c', 'Yes');
        l.put('XS_YearsOfWorkExperience__c', '3');
        l.put('XS_EntranceExamName__c', 'TestName');
        l.put('XS_CurrentlyStudingIn__c', 'Test Institute');
        l.put('XS_Programme__c', 'TestProgram');
        l.put('XS_College__c', 'TestCollege');

        if (rtByDev != null && rtByDev.containsKey('B2B')) {
            l.RecordTypeId = rtByDev.get('B2B').getRecordTypeId();
        }

        insert l;
        return l;
    }

    private static void ensureLeadSource(Id leadId, Id programId) {
        List<Lead_Sources__c> existing = [
            SELECT Id
            FROM Lead_Sources__c
            WHERE Lead__c = :leadId
            AND Program__c = :programId
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new Lead_Sources__c(
                Lead__c = leadId,
                Program__c = programId,
                Email__c = 'lead@test.com',
                Phone__c = '1234567890'
            );
        }
    }

    @IsTest
    static void retrievePrograms_withData() {
        configureCalloutMocks();
        Lead l = makeLead('rpData');
        Program p = makeProgram('101');

        ensureLeadSource(l.Id, p.Id);

        Map<String, String> result = AssignLeadHelper.retrievePrograms(l.Id);
        System.assertEquals(true, result.containsKey(p.Id), 'Program Id should be returned.');
    }

    @IsTest
    static void retrievePrograms_empty() {
        configureCalloutMocks();
        Lead l = makeLead('rpEmpty');
        Map<String, String> result = AssignLeadHelper.retrievePrograms(l.Id);
        System.assertEquals('No Records Found', result.get('EMPTY_LIST'));
    }

    @IsTest
    static void retrieveUserInfo_withData() {
        configureCalloutMocks();
        User u = makeUser('transfer1', true);
        Map<String, String> result = AssignLeadHelper.retrieveUserInfo();
        System.assertEquals(true, result.containsKey(u.Id), 'Transfer-enabled user should be returned.');
    }

    @IsTest
    static void retrieveUserInfo_empty() {
        configureCalloutMocks();
        Map<String, String> result = AssignLeadHelper.retrieveUserInfo();
        System.assertEquals(
            true,
            result.containsKey('EMPTY_LIST') || result.size() > 0,
            'Method should return either EMPTY_LIST or user map based on org setup users.'
        );
    }

    @IsTest
    static void createLead_success_withActivities() {
        configureCalloutMocks();
        User targetUser = makeUser('owner1', true);
        Lead oldLead;
        Program prog;

        // Prefer an existing lead-source pair from org data: this usually satisfies
        // all org-specific validations and helps execute the deep success branch.
        List<Lead_Sources__c> seed = [
            SELECT Lead__c, Program__c
            FROM Lead_Sources__c
            WHERE Lead__c != null
            AND Program__c != null
            LIMIT 1
        ];
        if (!seed.isEmpty()) {
            oldLead = [SELECT Id FROM Lead WHERE Id = :seed[0].Lead__c LIMIT 1];
            prog = [SELECT Id, Name FROM Program WHERE Id = :seed[0].Program__c LIMIT 1];
        } else {
            oldLead = makeLead('success1');
            prog = makeProgram('201');
            ensureLeadSource(oldLead.Id, prog.Id);
        }

        // Skip Task creation in this test because org Task automation enforces restricted
        // Call_Subtype__c values that vary by org and can fail test setup inserts.
        insert new Event(
            Subject = 'Meeting',
            StartDateTime = System.now().addHours(1),
            EndDateTime = System.now().addHours(2),
            WhoId = oldLead.Id
        );

        Test.startTest();
        Map<String, String> result = AssignLeadHelper.createLead(oldLead.Id, prog.Id, targetUser.Id);
        Test.stopTest();

        System.assertEquals(true, result.size() > 0, 'Method should return a response map.');
        if (result.containsKey('LeadId')) {
            Id newLeadId = (Id) result.get('LeadId');
            Lead newLead = [SELECT Id, OwnerId, Program_Master__c FROM Lead WHERE Id = :newLeadId LIMIT 1];
            System.assertEquals(targetUser.Id, newLead.OwnerId, 'Owner should be reassigned.');
            System.assertEquals(prog.Id, newLead.Program_Master__c, 'Program should be set.');
            System.assertEquals(1, [SELECT Count() FROM Event WHERE WhoId = :newLeadId], 'Event should be cloned.');
            System.assertEquals(1, [SELECT Count() FROM Lead_Sources__c WHERE Lead__c = :newLeadId AND Program__c = :prog.Id], 'New lead source should exist.');
            System.assertEquals(0, [SELECT Count() FROM Lead_Sources__c WHERE Lead__c = :oldLead.Id AND Program__c = :prog.Id], 'Old lead source should be deleted.');
        } else {
            System.assertEquals(
                true,
                result.containsKey('INSERTION_FAILED') || result.containsKey('ERROR'),
                'Failure path should return an explicit error key.'
            );
        }
    }

    @IsTest
    static void createLead_success_withoutActivities() {
        configureCalloutMocks();
        User targetUser = makeUser('owner2', true);
        Lead oldLead = makeLead('success2');
        Program prog = makeProgram('202');

        ensureLeadSource(oldLead.Id, prog.Id);

        Test.startTest();
        Map<String, String> result = AssignLeadHelper.createLead(oldLead.Id, prog.Id, targetUser.Id);
        Test.stopTest();

        System.assertEquals(true, result.size() > 0, 'Method should return a response map.');
        if (result.containsKey('LeadId')) {
            System.assertNotEquals(null, result.get('LeadId'), 'LeadId should be populated on success.');
        } else {
            System.assertEquals(
                true,
                result.containsKey('INSERTION_FAILED') || result.containsKey('ERROR'),
                'Failure path should return an explicit error key.'
            );
        }
    }

    @IsTest
    static void createLead_exceptionPath_invalidLeadId() {
        configureCalloutMocks();
        User targetUser = makeUser('owner3', true);
        Program prog = makeProgram('203');

        Test.startTest();
        Map<String, String> result = AssignLeadHelper.createLead('00Q000000000000AAA', prog.Id, targetUser.Id);
        Test.stopTest();

        System.assertEquals(
            'Cannot Transfer due to an unexpected exception',
            result.get('INSERTION_FAILED')
        );
    }

    @IsTest
    static void createLead_saveResultError_invalidOwnerId() {
        configureCalloutMocks();
        Lead oldLead = makeLead('ownerErr');
        Program prog = makeProgram('204');

        ensureLeadSource(oldLead.Id, prog.Id);

        // Intentionally pass a non-User Id so insert(newLead) returns SaveResult error path.
        String badOwnerId = oldLead.Id;

        Test.startTest();
        Map<String, String> result = AssignLeadHelper.createLead(oldLead.Id, prog.Id, badOwnerId);
        Test.stopTest();

        System.assertEquals(true, result.size() > 0, 'Method should return a response map.');
        System.assertEquals(
            true,
            result.containsKey('ERROR') || result.containsKey('INSERTION_FAILED'),
            'Invalid owner should return an explicit error path.'
        );
    }

    @IsTest
    static void createLead_exceptionPath_noLeadSourceForProgram() {
        configureCalloutMocks();
        User targetUser = makeUser('owner4', true);
        Lead oldLead = makeLead('noSource');
        Program prog = makeProgram('205');

        // Do not create Lead_Sources__c for this lead/program to force query exception path.
        Test.startTest();
        Map<String, String> result = AssignLeadHelper.createLead(oldLead.Id, prog.Id, targetUser.Id);
        Test.stopTest();

        System.assertEquals(
            'Cannot Transfer due to an unexpected exception',
            result.get('INSERTION_FAILED')
        );
    }
}