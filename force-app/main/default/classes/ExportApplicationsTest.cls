@IsTest
private class ExportApplicationsTest {

    private class DummyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"success":true}');
            return res;
        }
    }

    private class MockBatchContext implements Database.BatchableContext {
        private Id jobId;

        MockBatchContext(Id jobId) {
            this.jobId = jobId;
        }

        public Id getJobId() {
            return jobId;
        }

        public Id getChildJobId() {
            return null;
        }
    }

    @TestSetup
    static void setupData() {

        Program prog = new Program(
            Name = 'Export Test Program',
            Program_Code__c = 'EXP01',
            Programme_Type__c = 'Full-Time',
            Programme_Sub_Type__c = 'Class Room',
            Short_Programme_Code__c = 'EX1',
            Programme_Contact__c = '9876543210',
            StartDate = Date.today().addDays(10),
            EndDate = Date.today().addDays(40)
        );
        insert prog;

        insert new List<Application__c>{
            new Application__c(
                Name = 'Export App 1',
                Program__c = prog.Id,
                Application_Number__c = 'APP-001',
                Applicant_State_Management__c = 'Offer Issued',
                Application_Status__c = 'Submitted'
            ),
            new Application__c(
                Name = 'Export App 2',
                Program__c = prog.Id,
                Application_Number__c = 'APP-002',
                Application_Status__c = 'Submitted'
            )
        };
    }

    @IsTest
    static void testExportApplications_EndToEnd() {

        Id fakeJobId = UserInfo.getUserId();
        MockBatchContext ctx = new MockBatchContext(fakeJobId);

        ExportApplications batchJob = new ExportApplications('EXP01');

        Test.startTest();

        batchJob.start(ctx);

        List<Application__c> scope = [
            SELECT Id,
                   Name,
                   Applicant__r.Name,
                   Applicant_State_Management__c,
                   Program__r.Program_Code__c,
                   Application_Stage__c,
                   Application_Status__c
            FROM Application__c
            WHERE Program__r.Program_Code__c = 'EXP01'
        ];

        batchJob.execute(ctx, scope);
        batchJob.finish(ctx);

        Test.stopTest();

        ContentVersion createdFile = [
            SELECT Id, Title, PathOnClient, ContentDocumentId
            FROM ContentVersion
            WHERE Title LIKE 'EXP01_Applications_%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        System.assertNotEquals(null, createdFile.Id);
        System.assert(createdFile.PathOnClient.endsWith('.csv'));

        Export_Job__c exportJob = [
            SELECT Id, Name, JobId__c, Status__c, DocumentId__c
            FROM Export_Job__c
            WHERE JobId__c = :String.valueOf(fakeJobId)
            LIMIT 1
        ];

        System.assertEquals('Completed', exportJob.Status__c);
        System.assertEquals(createdFile.ContentDocumentId, exportJob.DocumentId__c);
    }
}