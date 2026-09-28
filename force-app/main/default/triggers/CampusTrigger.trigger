trigger CampusTrigger on Campus__c (before insert, before update,after insert,after update) {
  //  SPJIMR_ProgramCodeCopyHandler.syncCampus(Trigger.new, Trigger.oldMap);
 if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (Campus__c record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Programme_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (Campus__c record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Programme_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'Campus__c',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }
}