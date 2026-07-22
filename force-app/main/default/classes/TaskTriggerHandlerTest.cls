@IsTest
private class TaskTriggerHandlerTest {
    @IsTest
    static void lifecycleMethodsRunWithEmptyCollections() {
        TaskTriggerHandler h = new TaskTriggerHandler();
        List<Task> emptyList = new List<Task>();
        Map<Id, Task> emptyMap = new Map<Id, Task>();
        h.beforeInsert(emptyList);
        h.beforeUpdate(emptyList, emptyMap, emptyList, emptyMap);
        h.afterInsert(emptyList, emptyMap);
        h.afterUpdate(emptyList, emptyMap, emptyList, emptyMap);
        h.beforeDelete(emptyList, emptyMap);
        h.afterDelete(emptyList, emptyMap);
        h.afterUndelete(emptyList, emptyMap);
        System.assert(true);
    }
}