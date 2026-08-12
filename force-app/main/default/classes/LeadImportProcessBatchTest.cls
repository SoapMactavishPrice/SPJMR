@IsTest
private class LeadImportProcessBatchTest {

    @testSetup
    static void setup() {
        User u = createSystemAdminUser();
        system.runAs(u){
            Country_Master__c s = new Country_Master__c(Name='India',Country_Code__c='91',AcceptedNumberLength__c='10');
        insert s;
        State__c st = new State__c(Country_Master__c = s.Id,Name='Kerala');
        insert st;
        //Insert new City__c(Name='Kochi',State__c=st.Id);
        }
         
        
       
        
		 

    }

    private static User createSystemAdminUser(){

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
        
        PermissionSet ps = new PermissionSet(
            Name = 'Coverage_Full_Access_RDC',
            Label = 'CoverageFullAccessRDC'
        );
        insert ps;
		PermissionSet educloud = [SELECT Id FROM PermissionSet WHERE Name='EducationCloudAccess' LIMIT 1];
        
        

        User u = new User(
            FirstName='System',
            LastName='Admin',
            Alias='sadm',
            Email='sys'+System.currentTimeMillis()+'@test.com',
            Username='sys'+System.currentTimeMillis()+'@test.com',
            CommunityNickname='sys'+System.currentTimeMillis(),
            ProfileId=profile.Id,
            UserRoleId=role.Id,
            TimeZoneSidKey='Asia/Kolkata',
            LocaleSidKey='en_US',
            EmailEncodingKey='UTF-8',
            LanguageLocaleKey='en_US'
        );

        insert u;
        
        
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Country_Master__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'State__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'City__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Lead_Import_Parent__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Lead_Import__c',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Lead',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        insert new ObjectPermissions(
            ParentId = ps.Id,
            SobjectType = 'Lead_Program__c',
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
                SobjectType = 'Country_Master__c',
                Field = 'Country_Master__c.Country_Code__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
            new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Country_Master__c',
                Field = 'Country_Master__c.AcceptedNumberLength__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
            new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'State__c',
                Field = 'State__c.Country_Master__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                 new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'City__c',
                Field = 'City__c.State__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
              
                
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Lead_Import_Parent__c',
                Field = 'Lead_Import_Parent__c.Title__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Lead_Import_Parent__c',
                Field = 'Lead_Import_Parent__c.Description__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                new FieldPermissions(
                ParentId = ps.Id,
                SobjectType = 'Lead_Import_Parent__c',
                Field = 'Lead_Import_Parent__c.Status__c',
                PermissionsRead = true,
                PermissionsEdit = true
            ),
                 new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Lead_Import_Parent__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Name__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Email__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Phone__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Programme__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.LeadSource__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Country__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.State__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.City__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Status__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Age__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
                new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Error_Message__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Years_of_Work_Experience__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Do_you_have_Entrance_Exam_Scores__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Entrance_Exam_Name__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.SPJIMR_Partner_Company__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Organization__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.How_did_you_find_out_about_us__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Current_Designation__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.College__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),
    new FieldPermissions(
        ParentId = ps.Id,
        SobjectType = 'Lead_Import__c',
        Field = 'Lead_Import__c.Graduation_Year__c',
        PermissionsRead = true,
        PermissionsEdit = true
    ),// Lead Fields
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.Description',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.Title',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.Send_Welcome_and_Verification_Email__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.Country_Master_backend__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.State_Master__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.District_City__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.Email',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.Phone',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.LeadSource',
    PermissionsRead = true,
    PermissionsEdit = true
),

new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_Age__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_YearsOfWorkExperience__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_DoYouHaveEntranceExamScore__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_EntranceExamName__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_SPJIMR_PartnerCompany__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_EnterOrganisation__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_HowDidYouFindOutAboutUs__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_CurrentDesigination__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_College__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead',
    Field = 'Lead.XS_Year__c',
    PermissionsRead = true,
    PermissionsEdit = true
),

// Lead_Program__c Fields
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Program__c',
    Field = 'Lead_Program__c.Lead__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Program__c',
    Field = 'Lead_Program__c.Program__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Program__c',
    Field = 'Lead_Program__c.Email__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Program__c',
    Field = 'Lead_Program__c.Phone__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Program__c',
    Field = 'Lead_Program__c.Lead_Source__c',
    PermissionsRead = true,
    PermissionsEdit = true
)
        };
            
           insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
        );
        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = educloud.Id
        );
            return u;
    }

    private static Lead_Import_Parent__c createParent(){
       
            Country_Master__c country = new Country_Master__c(
                Name = 'India',
                Country_Code__c = '91',
                AcceptedNumberLength__c = '10'
            );
            insert country;

            State__c state = new State__c(
                Name = 'Kerala',
                Country_Master__c = country.Id
            );
            insert state;
            
             Lead_Import_Parent__c parent = new Lead_Import_Parent__c(
            Title__c='Imported Title',
            Description__c='Imported Description',
            Status__c='Processing'
        );
            insert parent;
        
        

           
        Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;

       

        
        return [SELECT Id FROM Lead_Import_Parent__c LIMIT 1];
    }

    
    @IsTest
static void testProcessScope() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
    Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c='john@test.com',
        Phone__c='9999999999',
        Programme__c='PGDM',
        Country__c='India',
        State__c='Kerala',
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );
System.debug('Can Create Lead_Import__c: ' +
    Schema.sObjectType.Lead_Import__c.isCreateable());

// Field permissions
Map<String, Schema.SObjectField> fields =
    Schema.SObjectType.Lead_Import__c.fields.getMap();

for (String fieldName : fields.keySet()) {
    Schema.DescribeFieldResult dfr = fields.get(fieldName).getDescribe();

    System.debug(
        fieldName +
        ' | Createable: ' + dfr.isCreateable() +
        ' | Updateable: ' + dfr.isUpdateable() +
        ' | Accessible: ' + dfr.isAccessible()
    );
}
    insert li;
    Test.startTest();
	
    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();

    

    Lead_Import__c updated = [
        SELECT Status__c
        FROM Lead_Import__c
        WHERE Id=:li.Id
    ];
	//system.assertEquals('Complete',updated.Status__c,'Lead Import is not successful');
    }   
}
    @IsTest
static void test_stateMissing() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
    Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c='john@test.com',
        Phone__c='9999999999',
        Programme__c='PGDM',
        Country__c='India',
        State__c=null,
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );

    insert li;

    Test.startTest();

    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();
    }
}
    @IsTest
static void test_emailMissing() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
    Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c=null,
        Phone__c='9999999999',
        Programme__c='PGDM',
        Country__c='India',
        State__c='Kerala',
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );

    insert li;

    Test.startTest();

    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();
    }
}
    @IsTest
static void test_phoneMissing() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
    Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c='john@test.com',
        Phone__c=null,
        Programme__c='PGDM',
        Country__c='India',
        State__c='Kerala',
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );

    insert li;

    Test.startTest();

    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();
    }
}
    @IsTest
static void test_programmeMissing() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
    Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c='john@test.com',
        Phone__c='9999999999',
        Programme__c=null,
        Country__c='India',
        State__c='Kerala',
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );

    insert li;

    Test.startTest();

    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();
    }
}
    
    @isTest
    static void test_countryMissing(){
        User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
        Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
        Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c='john@test.com',
        Phone__c='9999999999',
        Programme__c='PGDM',
        Country__c=null,
        State__c='Kerala',
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );

    insert li;

    Test.startTest();

    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();
    }
    }
    
    @IsTest
static void test_existingLead() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
    Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
   // Id b2cRecType = Schema.SobjectType.Lead.getRecordTypeInfosByDeveloperName().get('B2C').getRecordTypeId();
    Lead l = new Lead(Email='john@test.com',//RecordTypeId=b2cRecType,
                      Phone='9999999999',FirstName='John', LastName='Doe');
    insert l;
    Insert new Lead_Program__c(Lead__c=l.Id,Email__c='john@test.com',Phone__c='9999999999',Program__c=p.Id);

    Lead_Import__c li = new Lead_Import__c(
        Name__c='John Doe',
        Email__c='john@test.com',
        Phone__c='9999999999',
        Programme__c='PGDM',
        Country__c='India',
        State__c='Kerala',
        City__c='Kochi',
        Status__c='New',
        Age__c=25
    );

    insert li;

    Test.startTest();

    LeadImportProcessBatch.processScope(
        new List<Lead_Import__c>{li},
        'Test Description',
        'Test Title'
    );

    Test.stopTest();
    }
}
    
    @isTest
    static void test_happyPathExistingLead(){
         User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAS(u){
      
        Program p = new Program(
                Name='PGDM',
                Program_Code__c='PGDM',
                Short_Programme_Code__c='PM',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p;
         Program p2 = new Program(
                Name='GMP',
                Program_Code__c='GMP',
                Short_Programme_Code__c='GMP',
                Programme_Type__c='Modular',
                Programme_Sub_Type__c='Blended',
                StartDate=Date.today(),
                EndDate=Date.today().addDays(10)
            );
            insert p2;
        Lead l = new Lead(Email='s@n.com',Phone='999999999',LastName='John',FirstName='Doe');
        insert l;
        Insert new Lead_Program__c(Lead__c=l.Id,Program__c=p.Id,Email__c='s@n.com',Phone__c='999999999');
        
        Lead_Import_Parent__c par = new Lead_Import_Parent__c(Title__c='T',Description__c='D');
        insert par;
        Lead_Import__c lp1 = new Lead_Import__c(Lead_Import_Parent__c = par.Id,Status__c='New',
        Email__c='s@n.com',Phone__c='999999999',Name__c='John Doe',Programme__c='PGDM',
        LeadSource__c='Events',Country__c='India',State__c='Kerala',City__c='Kochi');
        insert lp1;
        
        Lead_Import__c lp2 = new Lead_Import__c(Lead_Import_Parent__c = par.Id,Status__c='New',
        Email__c='s@n.com',Phone__c='999999999',Name__c='John Doe',Programme__c='GMP',
        LeadSource__c='Events',Country__c='India',State__c='Kerala',City__c='Kochi');
        insert lp2;
        
        LeadImportProcessBatchStarter.startBatch(par.Id);
        LeadImportProcessBatchStarter.startBatch(null);
        Database.executeBatch(new LeadImportProcessBatch(null));
    }
    }
    
    
    @IsTest
static void test_nameMissing() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
        Program p = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c='Modular',
            Programme_Sub_Type__c='Blended',
            StartDate=Date.today(),
            EndDate=Date.today().addDays(10)
        );
        insert p;

        Lead_Import__c li = new Lead_Import__c(
            Name__c = null,
            Email__c = 'john@test.com',
            Phone__c = '9999999999',
            Programme__c = 'PGDM',
            Country__c = 'India',
            State__c = 'Kerala',
            City__c = 'Kochi',
            Status__c = 'New',
            Age__c = 25
        );

        insert li;

        Test.startTest();

        LeadImportProcessBatch.processScope(
            new List<Lead_Import__c>{li},
            'Test Description',
            'Test Title'
        );
        LeadImportProcessBatchStarter.startBatch(null);
        Test.stopTest();
    }
}
    
    @IsTest
static void test_countryNotFoundInSystem() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
        Program p = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c='Modular',
            Programme_Sub_Type__c='Blended',
            StartDate=Date.today(),
            EndDate=Date.today().addDays(10)
        );
        insert p;

        Lead_Import__c li = new Lead_Import__c(
            Name__c = 'John Doe',
            Email__c = 'john@test.com',
            Phone__c = '9999999999',
            Programme__c = 'PGDM',
            Country__c = 'USA',      // No Country_Master__c with this name
            State__c = 'Kerala',
            City__c = 'Kochi',
            Status__c = 'New',
            Age__c = 25
        );

        insert li;

        Test.startTest();

        LeadImportProcessBatch.processScope(
            new List<Lead_Import__c>{li},
            'Test Description',
            'Test Title'
        );

        Test.stopTest();
    }
}

@IsTest
static void test_stateNotFoundInSystem() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
        Program p = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c='Modular',
            Programme_Sub_Type__c='Blended',
            StartDate=Date.today(),
            EndDate=Date.today().addDays(10)
        );
        insert p;

        Lead_Import__c li = new Lead_Import__c(
            Name__c='John Doe',
            Email__c='john@test.com',
            Phone__c='9999999999',
            Programme__c='PGDM',
            Country__c='India',
            State__c='Tamil Nadu', // Does not exist
            City__c='Kochi',
            Status__c='New',
            Age__c=25
        );

        insert li;

        Test.startTest();

        LeadImportProcessBatch.processScope(
            new List<Lead_Import__c>{li},
            'Test Description',
            'Test Title'
        );

        Test.stopTest();
    }
}
@IsTest
static void test_cityNotFoundInSystem() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
        Program p = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c='Modular',
            Programme_Sub_Type__c='Blended',
            StartDate=Date.today(),
            EndDate=Date.today().addDays(10)
        );
        insert p;

        Lead_Import__c li = new Lead_Import__c(
            Name__c='John Doe',
            Email__c='john@test.com',
            Phone__c='9999999999',
            Programme__c='PGDM',
            Country__c='India',
            State__c='Kerala',
            City__c='Trivandrum', // Does not exist
            Status__c='New',
            Age__c=25
        );

        insert li;

        Test.startTest();

        LeadImportProcessBatch.processScope(
            new List<Lead_Import__c>{li},
            'Test Description',
            'Test Title'
        );

        Test.stopTest();
    }
}

@IsTest
static void test_cityMissing() {
    User u = [SELECT Id FROM User WHERE LastName='Admin' LIMIT 1];
    System.runAs(u){
        Program p = new Program(
            Name='PGDM',
            Program_Code__c='PGDM',
            Short_Programme_Code__c='PM',
            Programme_Type__c='Modular',
            Programme_Sub_Type__c='Blended',
            StartDate=Date.today(),
            EndDate=Date.today().addDays(10)
        );
        insert p;

        Lead_Import__c li = new Lead_Import__c(
            Name__c='John Doe',
            Email__c='john@test.com',
            Phone__c='9999999999',
            Programme__c='PGDM',
            Country__c='India',
            State__c='Kerala',
            City__c=null,
            Status__c='New',
            Age__c=25
        );

        insert li;

        Test.startTest();

        LeadImportProcessBatch.processScope(
            new List<Lead_Import__c>{li},
            'Test Description',
            'Test Title'
        );

        Test.stopTest();
    }
}
    
}