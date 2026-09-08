trigger SpecialisationMasterTrigger on Specialisation_Master__c (
    before insert,
    before update
) {
    DuplicateValidationController.validateSpecialisationCodes(
        Trigger.new
    );
}