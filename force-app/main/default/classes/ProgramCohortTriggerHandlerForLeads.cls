public without sharing class ProgramCohortTriggerHandlerForLeads {
    public static void handleTrigger(List<ProgramCohort> newList, Map<Id, ProgramCohort> oldMap){
        if (Trigger.isAfter && Trigger.isUpdate) {
            ApplicationNumberController.updateNonPaidOpportunities(newList,oldMap);
        }
    }
}