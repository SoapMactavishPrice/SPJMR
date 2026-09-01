@IsTest
private class ConvertLeadInvocableTest {

    
    @TestSetup
    static void setupData() {
        
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE Name='System Administrator'
            LIMIT 1
        ];
		
        UserRole role = [
            SELECT Id
            FROM UserRole
            WHERE Name='Student Counsellor'
            LIMIT 1
        ];
        
         User u = new User(
            FirstName='System',
            LastName='Admin',
            Alias='sadm',
            Email='sys'+System.currentTimeMillis()+'@test.com',
            Username='sys'+System.currentTimeMillis()+'@test.com',
            CommunityNickname='sys'+System.currentTimeMillis(),
            ProfileId=profile.Id,
            TimeZoneSidKey='Asia/Kolkata',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US'
        );

        insert u;
	
       PermissionSet educloud = [SELECT Id FROM PermissionSet WHERE Name='EducationCloudAccess' LIMIT 1];
                  insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = educloud.Id
        );
         PermissionSet ps = new PermissionSet(
            Name = 'Coverage_Full',
            Label = 'CoverageFullAccess'
        );
        insert ps;
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Slab__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        
         insert new List<FieldPermissions>{
            new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Actual_Fees__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Discount__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Discount_Amount__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Discount_in__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Discounted_Fees__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.End_Range__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Final_Price_After_Discount__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Program_Fee__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Program_Master__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Range__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Slab__c',
                Field = 'Slab__c.Start_Range__c',
                PermissionsRead = true,
                PermissionsEdit = true
            )
                };
        system.runAs(u){
             Program program = new Program(
            Name = 'PGDM',
            Program_Code__c = 'PGDM',
            Short_Programme_Code__c = 'PM',
            Programme_Type__c = 'Modular',
            Programme_Sub_Type__c = 'Blended',
            StartDate = System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert program;

        // ---------------------------------------------------------
        // Product
        // ---------------------------------------------------------
        Product2 product = new Product2(
            Name = 'PGDM',
            ProductCode = 'PGDM',
            IsActive = true
        );
        insert product;

        // ---------------------------------------------------------
        // Standard Pricebook
        // ---------------------------------------------------------
        Id standardPricebookId = Test.getStandardPricebookId();

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert pbe;

        // ---------------------------------------------------------
        // Slab - present in the reference test setup
        // ---------------------------------------------------------
        insert new Slab__c(
            Program_Master__c = program.Id,
            Start_Range__c = 3,
            End_Range__c = 10
        );
        }
       
    }


    @IsTest
    static void testConvertLead() {

        // ---------------------------------------------------------
        // Get B2B Lead Record Type
        // ---------------------------------------------------------
        Id b2bRtId =
            Schema.SObjectType.Lead
                .getRecordTypeInfosByDeveloperName()
                .get('B2B')
                .getRecordTypeId();

        // ---------------------------------------------------------
        // Get Program
        // ---------------------------------------------------------
        Program program = [
            SELECT Id, Name, Program_Code__c
            FROM Program
            WHERE Program_Code__c = 'PGDM'
            LIMIT 1
        ];

        // ---------------------------------------------------------
        // Create Lead
        // ---------------------------------------------------------
        Lead lead = new Lead(
            RecordTypeId = b2bRtId,
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test B2B Company',
            Email = 'testlead@example.com',
            Phone = '9000000000',
            Status = 'Open - Not Contacted',
            LeadSource = 'Web',
            Opportunity_Close_Date__c = Date.today().addDays(30),
            Opportunity_Stage__c = 'Prospecting',
            Is_MOU_Contract_Required__c = false,
            Minimum_Number_of_Students__c = 3,
            Maximum_Number_of_Students__c = 10
        );

        insert lead;

        // ---------------------------------------------------------
        // Create Contact linked to Lead
        // ---------------------------------------------------------
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test.contact@example.com',
            Phone = '9000000001',
            MobilePhone = '9000000001',
            Lead__c = lead.Id,
            Is_Primary_Contact__c = true
        );

        insert con;

        // ---------------------------------------------------------
        // Create Lead Program linked to Contact
        // ---------------------------------------------------------
        Lead_Program__c leadProgram = new Lead_Program__c(
            Contact__c = con.Id,
            Program__c = program.Id
        );

        insert leadProgram;

        // ---------------------------------------------------------
        // Prepare Invocable Request
        // ---------------------------------------------------------
        ConvertLeadInvocable.ConvertLeadRequest request =
            new ConvertLeadInvocable.ConvertLeadRequest();

        request.leadId = lead.Id;
        request.isMouContractRequired = false;

        List<ConvertLeadInvocable.ConvertLeadRequest> requests =
            new List<ConvertLeadInvocable.ConvertLeadRequest>();

        requests.add(request);

        // ---------------------------------------------------------
        // Call Convert Lead
        // ---------------------------------------------------------
        Test.startTest();

        List<ConvertLeadInvocable.ConvertLeadResult> results =
            ConvertLeadInvocable.convertLead(requests);

        Test.stopTest();

        System.assertEquals(
            1,
            results.size()
        );

        ConvertLeadInvocable.ConvertLeadResult result = results[0];
		system.debug('res:'+result);
        System.assertEquals(
            true,
            result.isSuccess,
            'Conversion failed: ' + result.message
        );

        System.assertNotEquals(
            null,
            result.accountId,
            'Account should be created'
        );

        System.assertNotEquals(
            null,
            result.contactId,
            'Contact should be returned'
        );

        System.assertNotEquals(
            null,
            result.opportunityId,
            'Opportunity should be created'
        );

        Lead convertedLead = [
            SELECT Id,
                   IsConverted,
                   ConvertedAccountId,
                   ConvertedContactId
            FROM Lead
            WHERE Id = :lead.Id
        ];

        System.assertEquals(
            true,
            convertedLead.IsConverted
        );

        System.assertEquals(
            result.accountId,
            convertedLead.ConvertedAccountId
        );
        Contact convertedContact = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Id = :con.Id
        ];

        System.assertEquals(
            result.accountId,
            convertedContact.AccountId
        );
        Opportunity opp = [
            SELECT Id,
                   AccountId,
                   Amount,
                   CloseDate,
                   StageName,
                   LeadSource,
                   RecordType.DeveloperName
            FROM Opportunity
            WHERE Id = :result.opportunityId
        ];

        System.assertEquals(
            result.accountId,
            opp.AccountId
        );

        System.assertEquals(
            1000,
            opp.Amount
        );

        System.assertEquals(
            'Prospecting',
            opp.StageName
        );

        System.assertEquals(
            'B2B_Opportunity',
            opp.RecordType.DeveloperName
        );

        List<OpportunityContactRole> roles = [
            SELECT Id,
                   ContactId,
                   OpportunityId,
                   IsPrimary,
                   Role
            FROM OpportunityContactRole
            WHERE OpportunityId = :result.opportunityId
        ];

        System.assertEquals(
            1,
            roles.size()
        );

        System.assertEquals(
            con.Id,
            roles[0].ContactId
        );

        System.assertEquals(
            true,
            roles[0].IsPrimary
        );

        System.assertEquals(
            'Decision Maker',
            roles[0].Role
        );

        // ---------------------------------------------------------
        // Verify Opportunity Line Item
        // ---------------------------------------------------------
        List<OpportunityLineItem> lineItems = [
            SELECT Id,
                   OpportunityId,
                   Quantity,
                   UnitPrice,
                   PricebookEntry.Product2.ProductCode
            FROM OpportunityLineItem
            WHERE OpportunityId = :result.opportunityId
        ];

        System.assertEquals(
            1,
            lineItems.size()
        );

        System.assertEquals(
            'PGDM',
            lineItems[0].PricebookEntry.Product2.ProductCode
        );

        System.assertEquals(
            1,
            lineItems[0].Quantity
        );
    }
}