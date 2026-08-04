@IsTest
private class RawDataControllerTest {

    private static final String ADMIN_EMAIL = 'rdc.coverage.admin@example.com';

    private static User createAdminUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User(
            ProfileId = p.Id,
            FirstName = 'Coverage',
            LastName = 'Admin',
            Email = ADMIN_EMAIL,
            Username = ADMIN_EMAIL + '.' + DateTime.now().getTime(),
            Alias = 'covadm2',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert u;

        // Belt-and-braces: explicitly grant Modify/View All Data so this user
        // bypasses FLS regardless of any org-specific profile customization
        // or package license gating.
        PermissionSet ps = new PermissionSet(
            Name = 'Coverage_Full_Access_RDC',
            Label = 'Coverage Full Access RDC'
        );
        insert ps;

        insert new PermissionSetAssignment(
            AssigneeId = u.Id,
            PermissionSetId = ps.Id
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

        insert new List<FieldPermissions>{
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
            )
        };

        return u;
    }

    @IsTest
    static void testStartImport() {

        User adminUser = createAdminUser();
        Id importId;

        System.runAs(adminUser) {
            Test.startTest();
            importId = RawDataController.startImport('Test Import', 'Test Description');
            Test.stopTest();
        }

        Lead_Import_Parent__c parent = [
            SELECT Id, Title__c, Description__c, Status__c
            FROM Lead_Import_Parent__c
            WHERE Id = :importId
        ];

        System.assertEquals('Test Import', parent.Title__c);
        System.assertEquals('Test Description', parent.Description__c);
        System.assertEquals('Uploaded', parent.Status__c);
    }

    @IsTest
    static void testInsertImportRows() {

        User adminUser = createAdminUser();
        Lead_Import_Parent__c parent = new Lead_Import_Parent__c(
            Title__c = 'Import',
            Status__c = 'Uploaded'
        );

        System.runAs(adminUser) {
            insert parent;

            RawDataController.ImportRowWrapper row = new RawDataController.ImportRowWrapper();
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
            row.age = '28';
            row.college = 'CUSAT';
            row.graduationYear = '2020';

            Test.startTest();
            RawDataController.insertImportRows(
                parent.Id,
                new List<RawDataController.ImportRowWrapper>{ row }
            );
            Test.stopTest();
        }

        Lead_Import__c record = [
            SELECT Lead_Import_Parent__c,
                   Row_Number__c,
                   Name__c,
                   Email__c,
                   Phone__c,
                   Programme__c,
                   LeadSource__c,
                   Country__c,
                   State__c,
                   City__c,
                   Years_of_Work_Experience__c,
                   Do_you_have_Entrance_Exam_Scores__c,
                   Entrance_Exam_Name__c,
                   SPJIMR_Partner_Company__c,
                   Organization__c,
                   How_did_you_find_out_about_us__c,
                   Current_Designation__c,
                   Age__c,
                   College__c,
                   Graduation_Year__c,
                   Send_Welcome_and_Verification_Email__c,
                   Status__c
            FROM Lead_Import__c
            LIMIT 1
        ];

        System.assertEquals(parent.Id, record.Lead_Import_Parent__c);
        System.assertEquals(1, record.Row_Number__c);
        System.assertEquals('John Doe', record.Name__c);
        System.assertEquals('john@test.com', record.Email__c);
        System.assertEquals('9999999999', record.Phone__c);
        System.assertEquals('PGDM', record.Programme__c);
        System.assertEquals('Website', record.LeadSource__c);
        System.assertEquals('India', record.Country__c);
        System.assertEquals('Kerala', record.State__c);
        System.assertEquals('Kochi', record.City__c);
        System.assertEquals('5', record.Years_of_Work_Experience__c);
        System.assertEquals('Yes', record.Do_you_have_Entrance_Exam_Scores__c);
        System.assertEquals('CAT', record.Entrance_Exam_Name__c);
        System.assertEquals('ABC', record.SPJIMR_Partner_Company__c);
        System.assertEquals('XYZ', record.Organization__c);
        System.assertEquals('Google', record.How_did_you_find_out_about_us__c);
        System.assertEquals('Developer', record.Current_Designation__c);
        System.assertEquals(28, record.Age__c);
        System.assertEquals('CUSAT', record.College__c);
        System.assertEquals('2020', record.Graduation_Year__c);
        System.assertEquals('No', record.Send_Welcome_and_Verification_Email__c);
        System.assertEquals('New', record.Status__c);
    }

    @IsTest
    static void testStartProcessing() {

        User adminUser = createAdminUser();
        Lead_Import_Parent__c parent = new Lead_Import_Parent__c(
            Title__c = 'Import',
            Status__c = 'Uploaded'
        );

        System.runAs(adminUser) {
            insert parent;

            Test.startTest();
            RawDataController.startProcessing(parent.Id);
            Test.stopTest();
        }

        parent = [SELECT Status__c FROM Lead_Import_Parent__c WHERE Id = :parent.Id];
        System.assertEquals('Processing', parent.Status__c);
    }
}