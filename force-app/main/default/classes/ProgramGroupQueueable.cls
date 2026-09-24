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
    }
}