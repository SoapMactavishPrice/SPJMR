public without sharing class ProgramGroupQueueable
    implements Queueable {

    private Set<Id> programIds;

    public ProgramGroupQueueable(Set<Id> programIds) {
        this.programIds = programIds;
    }

    public void execute(QueueableContext context) {

        if (programIds == null || programIds.isEmpty()) {
            return;
        }

        List<Program> programs = [
            SELECT Id, Program_Code__c
            FROM Program
            WHERE Id IN :programIds
        ];

        ProgrammeGroupService.createGroupsForPrograms(programs);
         // New record-level sharing
       Map<Id, String> programCodes =
    new Map<Id, String>();

for (Program programRecord : programs) {
    if (
        programRecord.Id != null &&
        String.isNotBlank(programRecord.Program_Code__c)
    ) {
        programCodes.put(
            programRecord.Id,
            programRecord.Program_Code__c
        );
    }
}

ProgrammeSharingService.shareRecords(
    'Program',
    programCodes
);
    }
}