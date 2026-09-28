trigger SPJIMR_AcademicYearTrigger on AcademicYear (after update,after insert) {
    SPJIMR_AcademicYearTriggerHandler.handleTrigger(Trigger.new, Trigger.oldMap);
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (AcademicYear record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Programme_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (AcademicYear record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Programme_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'AcademicYear',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }
}