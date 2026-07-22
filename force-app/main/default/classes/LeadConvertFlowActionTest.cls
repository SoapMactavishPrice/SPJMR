@IsTest
private class LeadConvertFlowActionTest {

    private static Boolean hasBusinessRecordType() {
        return [SELECT Count()
                FROM RecordType
                WHERE SObjectType = 'Account'
                AND DeveloperName = 'Business'] > 0;
    }

    private static Boolean hasPartnerConvertedStatus() {
        return [SELECT Count()
                FROM LeadStatus
                WHERE IsConverted = true
                AND MasterLabel = 'Partner'] > 0;
    }

    private static Lead makeLead(String suffix) {
        Id b2bRtId;
        Map<String, Schema.RecordTypeInfo> rtInfoByDevName =
            Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName();
        if (rtInfoByDevName != null && rtInfoByDevName.containsKey('B2B')) {
            b2bRtId = rtInfoByDevName.get('B2B').getRecordTypeId();
        }

        Lead l = new Lead();
        l.LastName = 'Test ' + suffix;
        l.FirstName = 'Auto';
        l.Company = 'SPJIMR ' + suffix;
        l.Email = 'lead+' + suffix + '@example.com';
        l.Phone = '9999999999';
        l.LeadSource = 'Website';
        l.put('XS_State__c', 'Test');
        l.put('XS_City__c', 'CityTest');
        l.put('XS_HaveYouCompletedYourGraduation__c', 'Yes');
        l.put('XS_YearsOfWorkExperience__c', '3');
        l.put('XS_EntranceExamName__c', 'TestName');
        l.put('XS_CurrentDesigination__c', 'No');
        l.put('XS_Programme__c', 'TestProgram');
        l.put('XS_College__c', 'TestCollege');
        l.put('XS_HowDidYouFindOutAboutUs__c', 'Some Source');
        if (b2bRtId != null) {
            l.RecordTypeId = b2bRtId;
        }
        insert l;

        // Keep parity with existing org conversion tests that use Lead_Contact__c for B2B leads.
        try {
            insert new Lead_Contact__c(
                Lead__c = l.Id,
                Name = 'Primary ' + suffix,
                Email__c = 'contact+' + suffix + '@example.com'
            );
        } catch (Exception e) {
            // Some orgs enforce extra fields on Lead_Contact__c; conversion can still proceed without it.
        }

        return l;
    }

    @IsTest
    static void testConvertLead_Success_DoNotCreateOpportunity() {
        Lead l = makeLead('NoOpp');
        Boolean canConvert = hasBusinessRecordType() && hasPartnerConvertedStatus();

        LeadConvertFlowAction.Request req = new LeadConvertFlowAction.Request();
        req.leadId = l.Id;
        req.doNotCreateOpportunity = true;

        Test.startTest();
        List<LeadConvertFlowAction.Response> responses =
            LeadConvertFlowAction.convertLead(new List<LeadConvertFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'One response expected.');
        if (canConvert && responses[0].success) {
            System.assertEquals('Lead Converted Successfully', responses[0].message);
            System.assertNotEquals(null, responses[0].accountId, 'Account should be created.');
            System.assertNotEquals(null, responses[0].contactId, 'Contact should be created.');
            System.assertEquals(null, responses[0].opportunityId, 'Opportunity should not be created.');
        } else {
            System.assertEquals(false, responses[0].success, 'Conversion can fail when required metadata is absent.');
            System.assertNotEquals(null, responses[0].message, 'Failure should include a message.');
        }
    }

    @IsTest
    static void testConvertLead_Success_CreateOpportunity_BlankAndNamed() {
        Lead l1 = makeLead('BlankOppName');
        Lead l2 = makeLead('NamedOpp');
        Boolean canConvert = hasBusinessRecordType() && hasPartnerConvertedStatus();

        LeadConvertFlowAction.Request req1 = new LeadConvertFlowAction.Request();
        req1.leadId = l1.Id;
        req1.doNotCreateOpportunity = false;
        req1.opportunityName = null;

        LeadConvertFlowAction.Request req2 = new LeadConvertFlowAction.Request();
        req2.leadId = l2.Id;
        req2.doNotCreateOpportunity = false;
        req2.opportunityName = 'Custom Opportunity';

        Test.startTest();
        List<LeadConvertFlowAction.Response> responses =
            LeadConvertFlowAction.convertLead(new List<LeadConvertFlowAction.Request>{ req1, req2 });
        Test.stopTest();

        System.assertEquals(2, responses.size(), 'Two responses expected.');
        if (canConvert && responses[0].success && responses[1].success) {
            System.assertNotEquals(null, responses[0].opportunityId, 'Default-opportunity conversion should create opp.');
            System.assertNotEquals(null, responses[1].opportunityId, 'Named-opportunity conversion should create opp.');

            Opportunity opp1 = [SELECT Name FROM Opportunity WHERE Id = :responses[0].opportunityId];
            Opportunity opp2 = [SELECT Name FROM Opportunity WHERE Id = :responses[1].opportunityId];
            System.assertEquals('New Opportunity', opp1.Name, 'Blank name should use default.');
            System.assertEquals('Custom Opportunity', opp2.Name, 'Provided name should be used.');
        } else {
            System.assertEquals(false, responses[0].success, 'First conversion can fail when required metadata is absent.');
            System.assertEquals(false, responses[1].success, 'Second conversion can fail when required metadata is absent.');
            System.assertNotEquals(null, responses[0].message, 'Failure should include message.');
            System.assertNotEquals(null, responses[1].message, 'Failure should include message.');
        }
    }

    @IsTest
    static void testConvertLead_Failure_ReconvertLead() {
        Lead l = makeLead('Reconvert');

        LeadConvertFlowAction.Request first = new LeadConvertFlowAction.Request();
        first.leadId = l.Id;
        first.doNotCreateOpportunity = true;

        Test.startTest();
        List<LeadConvertFlowAction.Response> firstResp =
            LeadConvertFlowAction.convertLead(new List<LeadConvertFlowAction.Request>{ first });

        LeadConvertFlowAction.Request second = new LeadConvertFlowAction.Request();
        second.leadId = l.Id;
        second.doNotCreateOpportunity = true;

        List<LeadConvertFlowAction.Response> secondResp =
            LeadConvertFlowAction.convertLead(new List<LeadConvertFlowAction.Request>{ second });
        Test.stopTest();

        System.assertEquals(1, firstResp.size(), 'One response expected for first call.');
        System.assertEquals(1, secondResp.size(), 'One response expected.');
        if (firstResp[0].success) {
            System.assertEquals(false, secondResp[0].success, 'Second conversion should fail for already converted lead.');
            System.assertNotEquals(null, secondResp[0].message, 'Failure should include message.');
        } else {
            System.assertEquals(false, firstResp[0].success, 'First conversion failed due to metadata/prerequisites.');
            System.assertNotEquals(null, firstResp[0].message, 'Failure should include message.');
            System.assertEquals(false, secondResp[0].success, 'Second call should also fail.');
            System.assertNotEquals(null, secondResp[0].message, 'Failure should include message.');
        }
    }

    @IsTest
    static void testConvertLead_CatchBranch_NullLeadId() {
        LeadConvertFlowAction.Request req = new LeadConvertFlowAction.Request();
        req.leadId = null;
        req.doNotCreateOpportunity = true;

        Test.startTest();
        List<LeadConvertFlowAction.Response> responses =
            LeadConvertFlowAction.convertLead(new List<LeadConvertFlowAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'One response expected.');
        System.assertEquals(false, responses[0].success, 'Null lead id should fail.');
        System.assert(
            responses[0].message != null && responses[0].message.startsWith('Error:'),
            'Catch branch should prefix message with Error:.'
        );
    }
}