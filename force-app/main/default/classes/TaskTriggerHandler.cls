public class TaskTriggerHandler {
	 public void beforeInsert(List<Task> newList) {
         TaskTriggerHelper.validateFields(newList);
       TaskTriggerHelper.updateCompanyOnTaskB2B(newList);
    }

    public void beforeUpdate(List<Task> newList, Map<Id,Task> newMap, List<Task> oldList, Map<Id,Task> oldMap) {
        TaskTriggerHelper.updateCompanyOnTaskB2B(newList);
    }

    public void afterInsert(List<Task> newList, Map<Id,Task> newMap) {
       // TaskTriggerHelper.updateCompanyOnTaskB2B(newList);
        TaskTriggerHelper.createFollowUpTaskB2C(newList);
    }

    public void afterUpdate(List<Task> newList, Map<Id,Task> newMap, List<Task> oldList, Map<Id,Task> oldMap) {
        
        TaskTriggerHelper.updateCompanyOnTaskB2B(newList);
    }

    public void beforeDelete(List<Task> oldList, Map<Id,Task> oldMap) {
        
    }

    public void afterDelete(List<Task> oldList, Map<Id,Task> oldMap) {
       
    }
    
    public void afterUndelete(List<Task> newList, Map<Id,Task> newMap) {

    }
}