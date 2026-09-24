public without sharing class ProgramGroupMemberQueueable
    implements Queueable {

    private Set<Id> memberIds;
    private Integer attemptNumber;

    public ProgramGroupMemberQueueable(
        Set<Id> memberIds
    ) {
        this(memberIds, 0);
    }

    public ProgramGroupMemberQueueable(
        Set<Id> memberIds,
        Integer attemptNumber
    ) {
        this.memberIds = memberIds;
        this.attemptNumber = attemptNumber;
    }

    public void execute(QueueableContext context) {

        if (memberIds == null || memberIds.isEmpty()) {
            return;
        }

        List<Program_Team_Members__c> members = [
            SELECT Id,
                   User__c,
                   Program_Team__c,
                   Program_Team__r.Program__c,
                   Program_Team__r.Program__r.Program_Code__c
            FROM Program_Team_Members__c
            WHERE Id IN :memberIds
        ];

        ProgrammeGroupService.addTeamMembersToGroups(
            members
        );

        /*
         * Missing-group retry can be added here once
         * the agreed retry behavior is confirmed.
         */
    }
}