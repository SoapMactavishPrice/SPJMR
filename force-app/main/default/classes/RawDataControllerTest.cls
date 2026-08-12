@IsTest
private class RawDataControllerTest {

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
    Field = 'Lead_Import__c.Row_Number__c',
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
    Field = 'Lead_Import__c.Error_Message__c',
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
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Import__c',
    Field = 'Lead_Import__c.Send_Welcome_and_Verification_Email__c',
    PermissionsRead = true,
    PermissionsEdit = true
),
new FieldPermissions(
    ParentId = ps.Id,
    SobjectType = 'Lead_Import__c',
    Field = 'Lead_Import__c.Status__c',
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

    @testSetup
    static void setup() {
		User u = createSystemAdminUser();
        
    }

    private static User getAdmin() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = 'Admin'
            LIMIT 1
        ];
    }

    @IsTest
    static void testExpectedHeaders() {

       List<string> ls = RawDataController.EXPECTED_HEADERS;
    }

    @IsTest
    static void testStartImportAndGetImports() {

        User admin = getAdmin();

        System.runAs(admin) {

            Test.startTest();

            Id parentId = RawDataController.startImport(
                'Test File',
                'Test Description'
            );

            List<Lead_Import_Parent__c> imports =
                RawDataController.getImports();

            Test.stopTest();

            System.assertEquals(1, imports.size());
            System.assertEquals(parentId, imports[0].Id);
            System.assertEquals('Uploaded', imports[0].Status__c);
            System.assertEquals('Test File', imports[0].Title__c);
        }
    }

    @IsTest
    static void testInsertImportRows() {

        User admin = getAdmin();

        System.runAs(admin) {

            Id parentId = RawDataController.startImport(
                'Test',
                'Description'
            );

            RawDataController.ImportRowWrapper row =
                new RawDataController.ImportRowWrapper();

            row.rowNumber = 1;
            row.name = 'John Doe';
            row.email = 'john@test.com';
            row.phone = '9999999999';
            row.programme = 'PGDM';
            row.leadSource = 'Website';
            row.country = 'India';
            row.state = 'Kerala';
            row.city = 'Kochi';
            row.yearsOfWorkExperience = '5';
            row.entranceExamScore = 'Yes';
            row.entranceExamName = 'CAT';
            row.partnerCompany = 'ABC';
            row.organization = 'XYZ';
            row.referralSource = 'Google';
            row.designation = 'Developer';
            row.age = '25';
            row.college = 'SPJIMR';
            row.graduationYear = '2022';

            Test.startTest();

            RawDataController.insertImportRows(
                parentId,
                new List<RawDataController.ImportRowWrapper>{ row }
            );

            Test.stopTest();

            Lead_Import__c imported = [
                SELECT Name__c,
                       Email__c,
                       Phone__c,
                       Status__c,
                       Age__c,
                       Send_Welcome_and_Verification_Email__c
                FROM Lead_Import__c
                WHERE Lead_Import_Parent__c = :parentId
                LIMIT 1
            ];

            System.assertEquals('John Doe', imported.Name__c);
            System.assertEquals('john@test.com', imported.Email__c);
            System.assertEquals('9999999999', imported.Phone__c);
            System.assertEquals('New', imported.Status__c);
            System.assertEquals(25, imported.Age__c);
            System.assertEquals(
                'No',
                imported.Send_Welcome_and_Verification_Email__c
            );
        }
    }

    @IsTest
    static void testStartProcessing() {

        User admin = getAdmin();

        System.runAs(admin) {

            Id parentId = RawDataController.startImport(
                'File',
                'Description'
            );

            Test.startTest();

            RawDataController.startProcessing(parentId);

            Test.stopTest();

            Lead_Import_Parent__c parent = [
                SELECT Status__c
                FROM Lead_Import_Parent__c
                WHERE Id = :parentId
            ];

            System.assertEquals(
                'Processing',
                parent.Status__c
            );
        }
    }

    @IsTest
    static void testGetImportSummary() {

        User admin = getAdmin();

        System.runAs(admin) {

            Id parentId = RawDataController.startImport(
                'Summary',
                'Summary Description'
            );

            insert new List<Lead_Import__c>{
                new Lead_Import__c(
                    Lead_Import_Parent__c = parentId,
                    Row_Number__c = 1,
                    Name__c = 'John',
                    Email__c = 'john@test.com',
                    Status__c = 'Complete'
                ),
                new Lead_Import__c(
                    Lead_Import_Parent__c = parentId,
                    Row_Number__c = 2,
                    Name__c = 'Jane',
                    Email__c = 'jane@test.com',
                    Status__c = 'Failed',
                    Error_Message__c = 'Invalid Email'
                )
            };

            Test.startTest();

            RawDataController.ImportSummaryWrapper summary =
                RawDataController.getImportSummary(parentId);

            Test.stopTest();

            System.assertNotEquals(null, summary.parent);
            System.assertEquals(parentId, summary.parent.Id);
            System.assertEquals(1, summary.successCount);
            System.assertEquals(1, summary.failedCount);
            System.assertEquals(
                'Summary Description',
                summary.description
            );
            System.assertEquals(1, summary.failedRows.size());
            
        }
    }
}