@IsTest
private class TaskBrochureTrackingHandlerTest {

    @IsTest
    static void shouldCreateFollowUp_truthTable() {
        Id leadFake = '00Q000000000001';
        Id contactFake = '003000000000001';
        // Happy path: subject mentions Brochure, not already 'Brochure Sent', WhoId is a Lead
        Task t1 = new Task(Subject = 'Send Brochure', WhoId = leadFake);
        System.assertEquals(true, TaskBrochureTrackingHandler.shouldCreateFollowUp(t1));
        // Already a follow-up: subject equals 'Brochure Sent' should NOT create another
        Task t2 = new Task(Subject = 'Brochure Sent', WhoId = leadFake);
        System.assertEquals(false, TaskBrochureTrackingHandler.shouldCreateFollowUp(t2));
        // No 'Brochure' in subject
        Task t3 = new Task(Subject = 'Call back', WhoId = leadFake);
        System.assertEquals(false, TaskBrochureTrackingHandler.shouldCreateFollowUp(t3));
        // WhoId is a Contact, not a Lead
        Task t4 = new Task(Subject = 'Brochure follow', WhoId = contactFake);
        System.assertEquals(false, TaskBrochureTrackingHandler.shouldCreateFollowUp(t4));
        // Null subject
        Task t5 = new Task(Subject = null, WhoId = leadFake);
        System.assertEquals(false, TaskBrochureTrackingHandler.shouldCreateFollowUp(t5));
        // Null WhoId
        Task t6 = new Task(Subject = 'Brochure', WhoId = null);
        System.assertEquals(false, TaskBrochureTrackingHandler.shouldCreateFollowUp(t6));
    }

    @IsTest
    static void buildFollowUpTask_copiesIdentityFields() {
        Id leadFake = '00Q000000000002';
        Id ownerFake = UserInfo.getUserId();
        Task source = new Task(Subject = 'Send Brochure', WhoId = leadFake, OwnerId = ownerFake);
        Task built = TaskBrochureTrackingHandler.buildFollowUpTask(source);
        System.assertEquals('Brochure Sent', built.Subject);
        System.assertEquals('Send Brochure', built.Type__c);
        System.assertEquals('Completed', built.Status);
        System.assertEquals('Task', built.TaskSubtype);
        System.assertEquals(Date.today(), built.ActivityDate);
        System.assertEquals(leadFake, built.WhoId);
        System.assertEquals(ownerFake, built.OwnerId);
    }

    @IsTest
    static void handleAfterInsert_insertsFollowUpsForQualifyingTasks() {
        Lead l = new Lead(FirstName = 'Bro', LastName = 'Brochure Test', Company = 'Test Co');
        insert l;

        // Build a qualifying task referencing the lead
        Task brochureTask = new Task(Subject = 'Send Brochure now', WhoId = l.Id, ActivityDate = Date.today());
        insert brochureTask;

        Test.startTest();
        // Re-query so trigger has fired; manually invoke handler with the inserted task
        Task fresh = [SELECT Id, Subject, WhoId, OwnerId FROM Task WHERE Id = :brochureTask.Id];
        TaskBrochureTrackingHandler.handleAfterInsert(new List<Task>{ fresh });
        Test.stopTest();

        Integer followUps = [
            SELECT count() FROM Task WHERE Subject = 'Brochure Sent' AND WhoId = :l.Id
        ];
        System.assert(followUps >= 1, 'At least one follow-up should be inserted');
    }

    @IsTest
    static void handleAfterInsert_noFollowUpsForEmptyList() {
        // Should be a no-op
        TaskBrochureTrackingHandler.handleAfterInsert(new List<Task>());
    }
}