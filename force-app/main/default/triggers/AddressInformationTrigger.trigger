trigger AddressInformationTrigger on Address_Information__c (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        AddressInformationTriggerHandler.populateNameIfBlank(Trigger.new);
    }
}