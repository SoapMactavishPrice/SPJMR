@IsTest
private class InterviewBookingImportControllerTest {
    private static Integer sequence = 0;
    private static final String TEST_ADMIN_USERNAME = 'testadmin987@example.com';

    @testSetup
    static void setup() {
        Profile sysAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        UserRole studentCounsellorRole = new UserRole(
            Name = 'Student_Counsellor',
            DeveloperName = 'StudentCounsellor'
        );
        insert studentCounsellorRole;

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'Admin',
            Alias = 'tadmin',
            Email = 'testadmin@example.com',
            Username = TEST_ADMIN_USERNAME,
            ProfileId = sysAdminProfile.Id,
            UserRoleId = studentCounsellorRole.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert testUser;

        Map<String, Id> permissionSetIds = new Map<String, Id>();

        for (PermissionSet ps : [
            SELECT Id, Name
            FROM PermissionSet
            WHERE Name IN ('Admissions_Team', 'EducationCloudAccess')
        ]) {
            permissionSetIds.put(ps.Name, ps.Id);
        }

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetIds.get('Admissions_Team')
            ),
            new PermissionSetAssignment(
                AssigneeId = testUser.Id,
                PermissionSetId = permissionSetIds.get('EducationCloudAccess')
            )
        };
    }

    private static User getTestUser() {
        return [
            SELECT Id
            FROM User
            WHERE Username = :TEST_ADMIN_USERNAME
            LIMIT 1
        ];
    }

    private static Program createProgram() {
        sequence++;
        Program programRecord = new Program(
            Name = 'Interview Import Test Program ' + sequence,
            Program_Code__c = 'PGPM',
            Short_Programme_Code__c = 'I' + sequence,
            Programme_Type__c = 'Full-time',
            Programme_Sub_Type__c = 'Class Room',
            IsActive = true
        );
        insert programRecord;
        return programRecord;
    }

    // ---------------------------------------------------------------
    // uploadChunk
    // ---------------------------------------------------------------

    @IsTest
    static void uploadChunkThrowsWhenFileNameIsBlank() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Boolean threw = false;
            try {
                InterviewBookingImportController.uploadChunk(
                    null, 'col1,col2\nval1,val2', 1
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw);
        }
    }

    @IsTest
    static void uploadChunkThrowsWhenCsvChunkIsBlank() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Boolean threw = false;
            try {
                InterviewBookingImportController.uploadChunk(
                    'interviews.csv', '', 1
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw);
        }
    }

    @IsTest
    static void uploadChunkCreatesContentVersionAndReturnsId() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews.csv', 'col1,col2\nval1,val2', 1
            );
            Test.stopTest();

            System.assertNotEquals(null, versionId);

            ContentVersion version = [
                SELECT Title, PathOnClient
                FROM ContentVersion
                WHERE Id = :versionId
            ];
            System.assertEquals('interviews_Part_1', version.Title);
            System.assertEquals('interviews_Part_1.csv', version.PathOnClient);
        }
    }

    @IsTest
    static void uploadChunkStripsCsvExtensionEvenWhenFileNameHasNoExtensionMatch() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Test.startTest();
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews_no_ext', 'col1,col2\nval1,val2', 2
            );
            Test.stopTest();

            ContentVersion version = [
                SELECT Title, PathOnClient
                FROM ContentVersion
                WHERE Id = :versionId
            ];
            System.assertEquals('interviews_no_ext_Part_2', version.Title);
            System.assertEquals('interviews_no_ext_Part_2.csv', version.PathOnClient);
        }
    }

    // ---------------------------------------------------------------
    // startImport — validation guard clauses
    // ---------------------------------------------------------------

    @IsTest
    static void startImportThrowsWhenContentVersionIdsIsNullOrEmpty() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Boolean nullThrew = false;
            try {
                InterviewBookingImportController.startImport(
                    null, 'WITHOUT_PANEL', null, false, false, false
                );
            } catch (AuraHandledException e) {
                nullThrew = true;
            }
            System.assert(nullThrew);

            Boolean emptyThrew = false;
            try {
                InterviewBookingImportController.startImport(
                    new List<Id>(), 'WITHOUT_PANEL', null, false, false, false
                );
            } catch (AuraHandledException e) {
                emptyThrew = true;
            }
            System.assert(emptyThrew);
        }
    }

    @IsTest
    static void startImportThrowsForInvalidImportType() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews.csv', 'col1,col2\nval1,val2', 1
            );

            Boolean threw = false;
            try {
                InterviewBookingImportController.startImport(
                    new List<Id>{ versionId },
                    'SOME_INVALID_TYPE',
                    null,
                    false,
                    false,
                    false
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw);
        }
    }

    @IsTest
    static void startImportThrowsWhenWithPanelAndProgramIdMissing() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews.csv', 'col1,col2\nval1,val2', 1
            );

            Boolean threw = false;
            try {
                InterviewBookingImportController.startImport(
                    new List<Id>{ versionId },
                    'WITH_PANEL',
                    null,
                    false,
                    false,
                    false
                );
            } catch (AuraHandledException e) {
                threw = true;
                // System.assert(
                //     e.getMessage().contains('Select a program for Book Interview With Panel.')
                // );
            }
            System.assert(threw);
        }
    }

    // ---------------------------------------------------------------
    // OPTIONAL / RISKY — actually runs Database.executeBatch against
    // the real InterviewBookingImportBatch class, which I have not
    // seen. If its start/execute/finish logic fails for reasons
    // unrelated to this controller, remove or adjust these tests.
    // ---------------------------------------------------------------

    @IsTest
    static void startImportEnqueuesBatchForWithoutPanelImportType_OPTIONAL() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews.csv', 'col1,col2\nval1,val2', 1
            );

            Test.startTest();
            String jobId = InterviewBookingImportController.startImport(
                new List<Id>{ versionId },
                'WITHOUT_PANEL',
                null,
                true,
                true,
                true
            );
            Test.stopTest();

            System.assertNotEquals(null, jobId);
        }
    }

    @IsTest
    static void startImportEnqueuesBatchForWithPanelImportTypeWhenProgramProvided_OPTIONAL() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Program programRecord = createProgram();
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews.csv', 'col1,col2\nval1,val2', 1
            );

            Test.startTest();
            String jobId = InterviewBookingImportController.startImport(
                new List<Id>{ versionId },
                'WITH_PANEL',
                programRecord.Id,
                false,
                false,
                false
            );
            Test.stopTest();

            System.assertNotEquals(null, jobId);
        }
    }

    @IsTest
    static void startImportEnqueuesBatchForAssignPanelImportType_OPTIONAL() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Id versionId = InterviewBookingImportController.uploadChunk(
                'interviews.csv', 'col1,col2\nval1,val2', 1
            );

            Test.startTest();
            String jobId = InterviewBookingImportController.startImport(
                new List<Id>{ versionId },
                'ASSIGN_PANEL',
                null,
                false,
                false,
                false
            );
            Test.stopTest();

            System.assertNotEquals(null, jobId);
        }
    }
}