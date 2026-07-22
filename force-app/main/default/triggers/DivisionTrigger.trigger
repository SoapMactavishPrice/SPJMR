trigger DivisionTrigger on Division__c (before insert, before update) {
    DivisionTriggerHandler.validateSpecialisationType(Trigger.new);
    if(Trigger.isBefore) {

        if(Trigger.isInsert || Trigger.isUpdate) {

      //      DivisionTriggerHandler.validateDuplicateDivision(Trigger.new);

        }
    }
}