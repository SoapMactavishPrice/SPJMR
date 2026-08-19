@IsTest
private class OpportunityTriggerHandlerTest {

    @testSetup
    static void setup() {
        User admin = createSystemAdminUser();
        system.runAs(admin) {
            Country_Master__c country = new Country_Master__c(
                Name='India', Country_Code__c='91', AcceptedNumberLength__c='10'
            );
            insert country;

            State__c state = new State__c(Name='Kerala', Country_Master__c=country.Id);
            insert state;

            City__c city = new City__c(Name='Kochi', State__c=state.Id, CityCode__c='34');
            insert city;

            Program program1 = new Program(
                Name='PGDM', Program_Code__c='PGDM', Short_Programme_Code__c='PM',
                Programme_Type__c='Modular', Programme_Sub_Type__c='Class Room',
                StartDate=System.Today(), EndDate=System.Today().addDays(3)
            );
            insert program1;

            Program program2 = new Program(
                Name='PGPM', Program_Code__c='PGPM', Short_Programme_Code__c='PP',
                Programme_Type__c='Modular', Programme_Sub_Type__c='Class Room',
                StartDate=System.Today(), EndDate=System.Today().addDays(3)
            );
            insert program2;

            // Lead #1 -> will be converted, with a Lead_Program__c BEFORE conversion
            Lead lead = new Lead(
                RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId(),
                FirstName='John', LastName='Doe', Company='Individual', Status='Untouched',
                Email='john@test.com', Phone='9876543210',
                Country_Master_backend__c=country.Id, State_Master__c=state.Id, District_City__c=city.Id,
                Country='India', State='Kerala', City='Kochi', XS_Age__c='25'
            );
            insert lead;

            insert new Lead_Program__c(
                Lead__c=lead.Id, Program__c=program1.Id,
                Lead_Source__c='Website', OwnerId=UserInfo.getUserId()
            );

            insert new Sequence_Master__c(
                Name='PGDM-' + Date.today().year(), Program_Code__c='PGDM',
                Year__c=String.valueOf(Date.today().year()), Last_Used_Number__c=10
            );

            Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Applicant').getRecordTypeId();

            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(lead.Id);
            lc.setConvertedStatus(
                [SELECT MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1].MasterLabel
            );
            lc.setDoNotCreateOpportunity(true);
            Database.convertLead(lc);

            Account app = new Account(
                RecordTypeId = recordTypeId, FirstName='Applicant', LastName='2',
                PersonEmail='s@m.com', Phone='9876543123', OwnerId = admin.Id
            );
            insert app;

            Opportunity opp = new Opportunity(
                Program__c=program2.Id, AccountId=lc.getAccountId(), Name='TestMe',
                StageName='Untouched', CloseDate=System.Today().addDays(30)
            );
            insert opp;

            // OPEN lead (not converted), same email as the "app" person account,
            // with a Lead_Program__c row for program2 -> drives the open-lead fallback path
            Lead openLead = new Lead(
                RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId(),
                FirstName='Jane', LastName='Roe', Company='Individual', Status='Untouched',
                Email='s@m.com', Phone='9876543299',
                Country_Master_backend__c=country.Id, State_Master__c=state.Id, District_City__c=city.Id,
                Country='India', State='Kerala', City='Kochi', XS_Age__c='30'
            );
            insert openLead;

            insert new Lead_Program__c(
                Lead__c=openLead.Id, Program__c=program2.Id,
                Lead_Source__c='Website', OwnerId=admin.Id
            );

            Profile applicantProfile = [SELECT Id FROM Profile WHERE Name = 'SPJIMR Applicant' LIMIT 1];

            Account pa = [
                SELECT Id, PersonContactId, PersonEmail, FirstName, LastName
                FROM Account WHERE IsPersonAccount = true LIMIT 1
            ];
            User applicantUser = new User(
                FirstName = pa.FirstName, LastName = pa.LastName, Alias = 'appt',
                Email = 'apptest123@test.com', Username = 'apptest123@test.com',
                CommunityNickname = 'apptest123@test.com', ProfileId = applicantProfile.Id,
                ContactId = pa.PersonContactId, TimeZoneSidKey = 'Asia/Kolkata',
                LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            insert applicantUser;
        }
    }

    private static User createSystemAdminUser() {
        Profile sysAdminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        UserRole counsellorRole = [SELECT Id FROM UserRole WHERE Name = 'Student Counsellor' LIMIT 1];

        User u = new User(
            FirstName = 'System', LastName = 'Admin', Alias = 'sadm',
            Email = 'sysadmin' + System.currentTimeMillis() + '@test.com',
            Username = 'sysadmin' + System.currentTimeMillis() + '@test.com',
            CommunityNickname = 'sysadmin' + System.currentTimeMillis(),
            ProfileId = sysAdminProfile.Id, UserRoleId = counsellorRole.Id,
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert u;
        return u;
    }

    private static Id b2cOppRecordTypeId() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('B2C_Opportunity').getRecordTypeId();
    }

    @IsTest
    static void testHandleBeforeInsert_NullAndEmptyList() {
        Test.startTest();
        try {
            OpportunityTriggerHandler.handleBeforeInsert(null);
            OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>());
        } catch (Exception e) {
            System.assert(false, 'Should not throw on null/empty list: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testHandleBeforeInsert_NoQualifyingOpportunities() {
        // Program__c null -> never added to b2cWithProgram -> early return
        Opportunity opp = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(),
            Program__c = null,
            Name = 'No Program'
        );

        Test.startTest();
        OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>{ opp });
        Test.stopTest();

        //System.assertEquals(null, opp.OwnerId);
    }

    @IsTest
    static void testHandleBeforeInsert_AccountIdNull_DefaultFallback() {
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];

        // AccountId null -> accountIds stays empty -> resolveConvertedLeadIdByAccount /
        // resolveLeadProgramOwnerIdByConvertedLead / resolveLeadOwnerIdByOpenLeadProgram
        // all hit their early-return guards; falls through to default queue lookup.
        Opportunity opp = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(),
            Program__c = prog.Id,
            AccountId = null,
            Name = 'No Account'
        );

        Test.startTest();
        try {
            OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>{ opp });
        } catch (Exception e) {
            System.assert(false, 'Unexpected exception: ' + e.getMessage());
        }
        Test.stopTest();
        // No strict assertion on OwnerId here - depends on org's Program_Queue_Routing__mdt / default queue config.
    }

    @IsTest
    static void testHandleBeforeInsert_ConvertedLeadOwnerMatch() {
        // Account that IS the ConvertedAccountId of a Lead, with a matching Lead_Program__c row
        Lead convertedLead = [SELECT Id, ConvertedAccountId FROM Lead WHERE IsConverted = true LIMIT 1];
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];
        Lead_Program__c lp = [
            SELECT OwnerId FROM Lead_Program__c
            WHERE Lead__c = :convertedLead.Id AND Program__c = :prog.Id
            LIMIT 1
        ];

        Opportunity opp = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(),
            Program__c = prog.Id,
            AccountId = convertedLead.ConvertedAccountId,
            Name = 'Converted Lead Match'
        );

        Test.startTest();
        OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>{ opp });
        Test.stopTest();

        System.assertEquals(
            lp.OwnerId,
            opp.OwnerId,
            'Opportunity owner should be set from the converted Lead\'s Lead_Program__c owner'
        );
    }

    @IsTest
    static void testHandleBeforeInsert_OpenLeadEmailMatch() {
        // Person Account NOT tied to a converted Lead, but its PersonEmail matches an open Lead
        // that has a Lead_Program__c row for the same program.
        Account personAcc = [SELECT Id, PersonEmail FROM Account WHERE PersonEmail = 's@m.com' LIMIT 1];
        Program prog = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];
        Lead_Program__c lp = [
            SELECT OwnerId FROM Lead_Program__c
            WHERE Program__c = :prog.Id AND Lead__r.Email = :personAcc.PersonEmail
            LIMIT 1
        ];

        Opportunity opp = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(),
            Program__c = prog.Id,
            AccountId = personAcc.Id,
            Name = 'Open Lead Email Match'
        );

        Test.startTest();
        OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>{ opp });
        Test.stopTest();

        System.assertEquals(
            lp.OwnerId,
            opp.OwnerId,
            'Opportunity owner should be set from the open Lead\'s Lead_Program__c owner via email match'
        );
    }

    @IsTest
    static void testHandleBeforeInsert_BulkMixedScenarios() {
        // Exercises the bulk path with multiple opps in one call:
        // one converted-lead match, one open-lead match, one default-fallback (no match)
        Lead convertedLead = [SELECT Id, ConvertedAccountId FROM Lead WHERE IsConverted = true LIMIT 1];
        Program pgdm = [SELECT Id FROM Program WHERE Program_Code__c = 'PGDM' LIMIT 1];
        Program pgpm = [SELECT Id FROM Program WHERE Program_Code__c = 'PGPM' LIMIT 1];
        Account personAcc = [SELECT Id FROM Account WHERE PersonEmail = 's@m.com' LIMIT 1];

        Opportunity oppConvertedMatch = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(), Program__c = pgdm.Id,
            AccountId = convertedLead.ConvertedAccountId, Name = 'Bulk Converted Match'
        );
        Opportunity oppOpenLeadMatch = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(), Program__c = pgpm.Id,
            AccountId = personAcc.Id, Name = 'Bulk Open Lead Match'
        );
        Opportunity oppNoAccount = new Opportunity(
            RecordTypeId = b2cOppRecordTypeId(), Program__c = pgdm.Id,
            AccountId = null, Name = 'Bulk No Account'
        );
        Opportunity oppNonB2C = new Opportunity(
            Program__c = null, Name = 'Bulk Non Qualifying'
        );

        Test.startTest();
        OpportunityTriggerHandler.handleBeforeInsert(new List<Opportunity>{
            oppConvertedMatch, oppOpenLeadMatch, oppNoAccount, oppNonB2C
        });
        Test.stopTest();

       // System.assertNotEquals(null, oppConvertedMatch.OwnerId);
       // System.assertNotEquals(null, oppOpenLeadMatch.OwnerId);
        System.assertEquals(null, oppNonB2C.OwnerId);
    }
}