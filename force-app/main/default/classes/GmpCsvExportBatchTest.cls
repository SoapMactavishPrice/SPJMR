/**
 * Test class for GmpCsvExportBatch
 */
@IsTest
private class GmpCsvExportBatchTest {

    @testSetup
    static void setupTestData() {
        Application__c app = new Application__c(
            Name = 'TEST001',
            HasExamScores__c = 'Yes',
            HasWorkExperience__c = 'Yes',
            HasCareerBreak__c = 'No',
            ShortTermLongTermGoal__c = 'Test goals',
            AdditonalInformationOnSelf__c = 'Additional info',
            AgreeToTerms__c = true
        );
        insert app;

        Program_Detail__c progDetail = new Program_Detail__c(
            Application__c = app.Id
        );
        insert progDetail;

        Personal_Detail__c persDetail = new Personal_Detail__c(
            Application__c = app.Id,
            Title__c = 'Mr',
            First_Name__c = 'John',
            Middle_Name__c = 'M',
            Last_Name__c = 'Doe',
            Gender__c = 'Male',
            Date_of_Birth_As_Per_10th_Marksheet__c = Date.newInstance(1990, 1, 1),
            Nationality__c = 'Indian',
            Primary_E_mail__c = 'john.doe@test.com',
            Mobile_Number__c = '9876543210'
        );
        insert persDetail;

        BasicAcademicDetail__c basicAcad = new BasicAcademicDetail__c(
            Application__c = app.Id,
            GraduationCompleted__c = 'Yes',
            AfterTen__c = '12th',
            AnyPostGraduation__c = 'No',
            HasAcademicBreak__c = 'No',
            HasProfessionalQualification__c = 'No'
        );
        insert basicAcad;
    }

    @IsTest
    static void testBatchExecution() {
        Application__c app = [
            SELECT Id
            FROM Application__c
            WHERE Name = 'TEST001'
            LIMIT 1
        ];

        Test.startTest();
        Database.executeBatch(
            new GmpCsvExportBatch(new List<Id>{ app.Id }),
            1
        );
        Test.stopTest();

        List<ContentVersion> cvList = [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE 'GMP_Export_%'
        ];

        System.assertEquals(1, cvList.size(),
            'ContentVersion should be created');
    }

    @IsTest
    static void testEmptyApplicationList() {
        Test.startTest();
        Database.executeBatch(
            new GmpCsvExportBatch(new List<Id>()),
            1
        );
        Test.stopTest();

        List<ContentVersion> cvList = [
            SELECT Id
            FROM ContentVersion
            WHERE Title LIKE 'GMP_Export_%'
        ];

        // Batch creates header-only CSV even with empty scope
        System.assertEquals(0, cvList.size(),
            'CSV should not be created');
    }
}