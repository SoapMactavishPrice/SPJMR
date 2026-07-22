trigger SpecializationChangeRequestTrigger on Specialization_Change_Request__c (after insert) {

    SpecializationChangeRequestHandler.submitForApproval(Trigger.new);
}