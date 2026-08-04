@IsTest
private class ConvertB2CLeadControllerTest {

    @testSetup
    static void setup() {
		 User admin =  createSystemAdminUser();
        system.runAS(admin){
            Country_Master__c country = new Country_Master__c(
            Name='India',
            Country_Code__c='91',
            AcceptedNumberLength__c='10'
        );
        insert country;

        State__c state = new State__c(
            Name='Kerala',
            Country_Master__c=country.Id
        );
        insert state;

        City__c city = new City__c(
            Name='Kochi',
            State__c=state.Id,
            CityCode__c ='34'
        );
        insert city;

         Program Program = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c ='Modular',
            Programme_Sub_Type__c = 'Blended',
            StartDate=System.Today(),
            EndDate = System.Today().AddDays(3)
        );
        insert Program;
        
        Lead lead = new Lead(
            RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId(),
            FirstName='John',
            LastName='Doe',
            Company='Individual',
            Status='Untouched',
            Email='john@test.com',
            Phone='9876543210',
            Country_Master_backend__c=country.Id,
            State_Master__c=state.Id,
            District_City__c=city.Id,
            Country='India',
            State='Kerala',
            City='Kochi',
            XS_Age__c='25'
        );
        insert lead;

        insert new Lead_Program__c(
            Lead__c=lead.Id,
            Program__c=program.Id,
            Lead_Source__c='Website',
            OwnerId=UserInfo.getUserId()
        );

        insert new Sequence_Master__c(
            Name='PGDM-' + Date.today().year(),
            Program_Code__c='PGDM',
            Year__c=String.valueOf(Date.today().year()),
            Last_Used_Number__c=10
        );
        Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                        .get('Applicant')
                        .getRecordTypeId();
       
         Account app =  new Account(RecordTypeId = recordTypeId,
        FirstName='Applicant',LastName='2',PersonEmail='s@m.com',
                                    Phone='9876543123',OwnerId = admin.Id);
        insert app;
        
        Opportunity opp = new Opportunity(Program__c=program.Id,AccountId=app.Id,Name='TestMe',
                                         StageName='Untouched',CloseDate=System.Today().addDays(30));
        insert opp;
        Profile applicantProfile = [
    SELECT Id
    FROM Profile
    WHERE Name = 'SPJIMR Applicant'
    LIMIT 1
];
       
        Account pa = [
    SELECT Id, PersonContactId, PersonEmail, FirstName, LastName
    FROM Account
    WHERE IsPersonAccount = true
    LIMIT 1
];
User applicantUser = new User(
    FirstName = pa.FirstName,
    LastName = pa.LastName,
    Alias = 'appt',
    Email = 'apptest123@test.com',
    Username = 'apptest'  + '123@test.com',
    CommunityNickname = 'apptest' +'123@test.com' ,
    ProfileId = applicantProfile.Id,
    ContactId = pa.PersonContactId,
    TimeZoneSidKey = 'Asia/Kolkata',
    LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8',
    LanguageLocaleKey = 'en_US'
);

insert applicantUser;
}
        
    }
    
    private static User createSystemAdminUser() {

    Profile sysAdminProfile = [
        SELECT Id
        FROM Profile
        WHERE Name = 'System Administrator'
        LIMIT 1
    ];

    UserRole counsellorRole = [
        SELECT Id
        FROM UserRole
        WHERE Name = 'Student Counsellor'
        LIMIT 1
    ];

    User u = new User(
        FirstName = 'System',
        LastName = 'Admin',
        Alias = 'sadm',
        Email = 'sysadmin' + System.currentTimeMillis() + '@test.com',
        Username = 'sysadmin' + System.currentTimeMillis() + '@test.com',
        CommunityNickname = 'sysadmin' + System.currentTimeMillis(),
        ProfileId = sysAdminProfile.Id,
        UserRoleId = counsellorRole.Id,
        TimeZoneSidKey = 'Asia/Kolkata',
        LocaleSidKey = 'en_US',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
    );

    insert u;
    return u;
}

    private static Lead getLead() {
        return [
            SELECT Id, Email
            FROM Lead
            LIMIT 1
        ];
    }

    private static Program getProgram() {
        return [
            SELECT Id, Program_Code__c
            FROM Program
            LIMIT 1
        ];
    }
    
    @IsTest
static void testInsertApplicationRelatedRecords() {

    Lead lead = [
        SELECT Id, FirstName, LastName, Email, Phone, XS_Age__c
        FROM Lead
        LIMIT 1
    ];

    Account pa = [
        SELECT Id
        FROM Account
        WHERE IsPersonAccount = true
        LIMIT 1
    ];

    Program prog = [
        SELECT Id
        FROM Program
        LIMIT 1
    ];

    Application__c app = new Application__c(
        Applicant__c = pa.Id,
        Program__c = prog.Id,
        Name = 'APP00001'
    );
    insert app;

    Test.startTest();

    ConvertB2CLeadController.insertApplicationRelatedRecords(
        new List<Application__c>{ app },
        lead,
        lead.Email,
        UserInfo.getUserId()
    );

    Test.stopTest();

    Personal_Detail__c pd = [
        SELECT Application__c,
               First_Name__c,
               Last_Name__c,
               Primary_E_mail__c,
               Mobile_Number__c,
               Age_as_on_Customisable_Date__c,
               OwnerId
        FROM Personal_Detail__c
        WHERE Application__c = :app.Id
        LIMIT 1
    ];

    System.assertEquals(app.Id, pd.Application__c);
    System.assertEquals(lead.FirstName, pd.First_Name__c);
    System.assertEquals(lead.LastName, pd.Last_Name__c);
    System.assertEquals(lead.Email, pd.Primary_E_mail__c);
    System.assertEquals(lead.Phone, pd.Mobile_Number__c);
    System.assertEquals(UserInfo.getUserId(), pd.OwnerId);
    System.assertEquals(
        Decimal.valueOf(lead.XS_Age__c),
        pd.Age_as_on_Customisable_Date__c
    );
}

    @IsTest
    static void testGenerateApplicationNumbersExistingSequence() {

        Test.startTest();

        List<String> nums =
            ConvertB2CLeadController.generateApplicationNumbersInBulk(
                new List<String>{'PGDM','PGDM'}
            );

        Test.stopTest();

        System.assertEquals(2, nums.size());
        System.assert(nums[0].startsWith('PGDM'));
        System.assert(nums[1].startsWith('PGDM'));

        Sequence_Master__c seq=[
            SELECT Last_Used_Number__c
            FROM Sequence_Master__c
            WHERE Program_Code__c='PGDM'
            LIMIT 1
        ];

        System.assertEquals(12,seq.Last_Used_Number__c);
    }

    @IsTest
    static void testGenerateApplicationNumbersNewSequence(){

        Test.startTest();

        List<String> nums=
            ConvertB2CLeadController.generateApplicationNumbersInBulk(
                new List<String>{'GMP'}
            );

        Test.stopTest();

        System.assertEquals(1,nums.size());

        Sequence_Master__c seq=[
            SELECT Program_Code__c
            FROM Sequence_Master__c
            WHERE Program_Code__c='GMP'
            LIMIT 1
        ];

        System.assertEquals('GMP',seq.Program_Code__c);
    }
    
    @IsTest
static void testHandleLeadConversionFailure() {

    ConvertB2CLeadController.ConversionResult result =
        new ConvertB2CLeadController.ConversionResult();

    result = ConvertB2CLeadController.handleLeadConversionFailure(
        'Error 1 Error 2'
    );

    System.assertEquals(false, result.isSuccess);
    System.assertEquals(
        'Lead conversion failed: Error 1 Error 2',
        result.message
    );
}

    @IsTest
    static void testGetLeadDetails(){

        Lead l=getLead();

        Test.startTest();

        Map<String,Object> result=
            ConvertB2CLeadController.getLeadDetails(l.Id);

        Test.stopTest();

        System.assert(result.containsKey('lead'));
        System.assertEquals(false,result.get('isConverted'));
        System.assertEquals(1,(Integer)result.get('programCount'));
    }

    @IsTest
    static void testCreateCommunityUserNoAccount(){

        Test.startTest();

        Map<String,String> result=
            ConvertB2CLeadController.createCommunityUser(
                null,
                'PGDM'
            );

        Test.stopTest();

        System.assert(result.containsKey('ERROR'));
    }

    @IsTest
    static void testAutoApplicationFlag(){

        Test.startTest();

        Boolean flag=
            ConvertB2CLeadController.isAutoApplicationCreationEnabled();

        Test.stopTest();

        System.assertNotEquals(null,flag);
    }

private static Lead createLeadWithoutPrograms() {

    Country_Master__c country = [SELECT Id, Name FROM Country_Master__c LIMIT 1];
    State__c state = [SELECT Id, Name FROM State__c LIMIT 1];
    City__c city = [SELECT Id, Name FROM City__c LIMIT 1];

    Lead l = new Lead(
        RecordTypeId = Schema.SObjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId(),
        FirstName='No',
        LastName='Program',
        Company='Individual',
        Status='Untouched',
        Email='noprogram@test.com',
        Phone='9999999999',
        Country_Master_backend__c=country.Id,
        State_Master__c=state.Id,
        District_City__c=city.Id,
        Country=country.Name,
        State=state.Name,
        City=city.Name
    );
    insert l;
    return l;
}
    
    @IsTest
static void testConvertLead_WithLeadPrograms() {

    Lead_Program__c l = [SELECT Lead__c,Lead__r.Email FROM Lead_Program__c LIMIT 1];

    Test.startTest();

    ConvertB2CLeadController.ConversionResult result =
        ConvertB2CLeadController.convertB2CLead(
            l.Lead__c,
            l.Lead__r.Email
        );

    Test.stopTest();

   system.debug('Result:'+result);
}

@IsTest
static void testConvertLead_NoLeadPrograms() {

    Lead l = createLeadWithoutPrograms();

    Test.startTest();

    ConvertB2CLeadController.ConversionResult result =
        ConvertB2CLeadController.convertB2CLead(
            l.Id,
            l.Email
        );

    Test.stopTest();

    System.assertEquals(false, result.isSuccess);
    System.assert(
        result.message.contains('No programs')
    );
}

@IsTest
static void testConvertLead_AlreadyConverted() {

    Lead l = getLead();

    Database.LeadConvert lc = new Database.LeadConvert();
    lc.setLeadId(l.Id);
    lc.setConvertedStatus(
        [SELECT MasterLabel
         FROM LeadStatus
         WHERE IsConverted=true
         LIMIT 1].MasterLabel
    );
    lc.setDoNotCreateOpportunity(true);

    Database.convertLead(lc);

    Test.startTest();

    ConvertB2CLeadController.ConversionResult result =
        ConvertB2CLeadController.convertB2CLead(
            l.Id,
            l.Email
        );

    Test.stopTest();

    System.assertEquals(false,result.isSuccess);
    System.assert(
        result.message.contains('already converted')
    );
}
    @IsTest
static void testCreateApplicationForOpportunity_AlreadyExists() {

    Account acc = [SELECT Id FROM Account WHERE IsPersonAccount = true LIMIT 1];

    Program prog = [SELECT Id FROM Program LIMIT 1];

    Application__c app = new Application__c(
        Applicant__c = acc.Id,
        Program__c = prog.Id,
        Name = 'TESTAPP001'
    );
    insert app;

    Opportunity opp = new Opportunity(
        Name = 'Test Opportunity',
        AccountId = acc.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today(),
        Program__c = prog.Id,
        Application__c = app.Id
    );
    insert opp;
    
    Opportunity opp2 = new Opportunity(
        Name = 'Test Opportunity',
        AccountId = acc.Id,
        StageName = 'Prospecting',
        CloseDate = Date.today(),
        Program__c = prog.Id
    );
    insert opp2;

    Test.startTest();

    Map<String,Object> result =
        ConvertB2CLeadController.createApplicationForOpportunity(opp.Id);

     Map<String,Object> result2 =
        ConvertB2CLeadController.createApplicationForOpportunity(opp2.Id);
    Test.stopTest();

    System.assertEquals(false, result.get('isSuccess'));
    System.assertEquals(
        'Application is already linked with this Opportunity.',
        result.get('message')
    );
}
    
    
    @IsTest
static void testPermissionSetAssigner() {



   user u = [SELECT Id FROM User LIMIT 1];

   

   Test.startTest();

try{
    System.enqueueJob(
        new ConvertB2CLeadController.PermissionSetAssigner(u.Id)
    );
    Test.stopTest();
}
catch(Exception e){
    System.assert(
        e.getMessage().contains('user license')
    );
}

    List<PermissionSetAssignment> psa = [
        SELECT Id
        FROM PermissionSetAssignment
        WHERE AssigneeId = :u.Id
    ];

    System.assert(psa.size() > 0);
}
    
    @IsTest
static void testCreateCommunityUser_UserAlreadyExists() {
    User adminUser = [SELECT Id FROM User WHERE FirstName='System' LIMIT 1];
 Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                        .get('Applicant')
                        .getRecordTypeId();
    Account app =  new Account(RecordTypeId = recordTypeId,
        FirstName='Applicant',LastName='2',PersonEmail='ssadsa@m.com',Phone='9876043123',OwnerId=adminUser.Id);
        insert app;
    
  Account pa =  [SELECT Id,PersonEmail,PersonContactId FROM Account WHERE
                PersonEmail='ssadsa@m.com' LIMIT 1];

    Profile p = [
        SELECT Id
        FROM Profile
        WHERE Name='SPJIMR Applicant'
        LIMIT 1
    ];

    User u = new User(
        FirstName='Test',
        LastName='Applicant',
        Alias='tapp',
        Email=pa.PersonEmail,
        Username=pa.PersonEmail,
        CommunityNickname='existing'+System.currentTimeMillis(),
        ProfileId=p.Id,
        ContactId=pa.PersonContactId,
        TimeZoneSidKey='Asia/Kolkata',
        LocaleSidKey='en_US',
        EmailEncodingKey='UTF-8',
        LanguageLocaleKey='en_US'
    );
    insert u;

    Test.startTest();

    Map<String,String> result =
        ConvertB2CLeadController.createCommunityUser(
            pa.Id,
            'PGDM'
        );

    Test.stopTest();

    System.assertEquals(
        'User already exists',
        result.get('SUCCESS')
    );

    System.assertEquals(
        u.Id,
        result.get('USERID')
    );
}
    
    @IsTest
static void testCreateCommunityUser_NoEmail() {

    Id applicantRt = Schema.SObjectType.Account
        .getRecordTypeInfosByDeveloperName()
        .get('Applicant')
        .getRecordTypeId();

    Account pa = new Account(
        RecordTypeId = applicantRt,
        FirstName = 'Test',
        LastName = 'User'
        // Intentionally no PersonEmail
    );
    insert pa;

    Test.startTest();

    Map<String,String> result =
        ConvertB2CLeadController.createCommunityUser(
            pa.Id,
            'PGDM'
        );

    Test.stopTest();

    System.assert(result.containsKey('ERROR'));
    System.assertEquals(
        'Person Email is required to create a community user',
        result.get('ERROR')
    );
}
    @IsTest
static void testCreateCommunityUser_AccountNotFound() {

    // Valid Account Id, but no record exists
    Id fakeAccountId = '001000000000001AAA';

    Test.startTest();

    Map<String, String> result =
        ConvertB2CLeadController.createCommunityUser(
            fakeAccountId,
            'PGDM'
        );

    Test.stopTest();

    System.assertEquals(
        'Account not found',
        result.get('ERROR')
    );
}
    @IsTest
static void testCreateCommunityUser_NoPersonContact() {

    Account acc = new Account(
        Name = 'Business Account'
    );
    insert acc;

    Test.startTest();

    Map<String, String> result =
        ConvertB2CLeadController.createCommunityUser(
            acc.Id,
            'PGDM'
        );

    Test.stopTest();

    System.assertEquals(
        'Person Contact not found for this Account',
        result.get('ERROR')
    );
}
    
  @IsTest
static void testHandleCreateCommunityUserException() {

    Map<String,String> result =
        ConvertB2CLeadController.handleCreateCommunityUserException(
            'Test Exception'
        );

    System.assertEquals(
        'Error creating user: Test Exception',
        result.get('ERROR')
    );
}
    
    
    
    @IsTest
static void testHandleCreateApplicationException() {

    Map<String, Object> result =
        ConvertB2CLeadController.handleCreateApplicationException(
            'Test Exception'
        );

    System.assertEquals(false, result.get('isSuccess'));
    System.assertEquals(
        'Error creating application: Test Exception',
        result.get('message')
    );
}
    
}