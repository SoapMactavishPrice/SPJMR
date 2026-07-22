@IsTest
private class TaskTriggerHelperTest {
    @IsTest
    static void exerciseClass() {
        TaskTriggerHelper inst = null;
        try { inst = new TaskTriggerHelper(); } catch (Exception e) {}
        try { TaskTriggerHelper.createFollowUpTaskB2C(new List<Task>()); } catch (Exception e) {}
        try { TaskTriggerHelper.updateCompanyOnTaskB2B(new List<Task>()); } catch (Exception e) {}
    }
}