trigger DepartmentMasterTrigger on Department_Master__c (
    before insert,
    before update
) {
    DuplicateValidationController.validateDepartmentCodes(
        Trigger.new
    );
}