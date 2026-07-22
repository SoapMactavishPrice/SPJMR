trigger BatchSpecialisationTrigger on Specialisation__c (
    before insert,
    before update
) {
    SpecialisationHandler.validateDuplicateSpecialisation(Trigger.new);
}