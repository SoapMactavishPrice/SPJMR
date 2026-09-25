trigger CampusTrigger on Campus__c (before insert, before update,after insert) {
    SPJIMR_ProgramCodeCopyHandler.syncCampus(Trigger.new, Trigger.oldMap);
    if (Trigger.isAfter && Trigger.isInsert){
    Map<Id, String> campusCodes = new Map<Id, String>();

for (Campus__c campusRecord : Trigger.new) {
    campusCodes.put(
        campusRecord.Id,
        campusRecord.Programme_Code__c
    );
}

ProgrammeSharingService.shareRecords(
    'Campus__c',
    campusCodes
);
}
}