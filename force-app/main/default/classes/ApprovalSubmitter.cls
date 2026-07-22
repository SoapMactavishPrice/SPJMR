public class ApprovalSubmitter implements Queueable {

    private List<Id> requestIds;

    public ApprovalSubmitter(List<Id> requestIds){
        this.requestIds = requestIds;
    }

    public void execute(QueueableContext context){

        List<Field_Change_Request__c> requests = [
            SELECT Id, Record_Id__c
            FROM Field_Change_Request__c
            WHERE Id IN :requestIds
        ];

        Set<Id> programIds = new Set<Id>();
        for(Field_Change_Request__c r : requests){
            programIds.add((Id)r.Record_Id__c);
        }

        Map<Id, List<Id>> programToUsersMap = new Map<Id, List<Id>>();

        for (Program_Team_Members__c member : [
            SELECT User__c, Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Program_Team__r.Program__c IN :programIds
            AND Role__c = 'Registrar'
        ]) {
            Id progId = member.Program_Team__r.Program__c;

            if (!programToUsersMap.containsKey(progId)) {
                programToUsersMap.put(progId, new List<Id>());
            }

            if (member.User__c != null) {
                programToUsersMap.get(progId).add(member.User__c);
            }
        }
        

        for (Field_Change_Request__c rec : requests) {
            

            List<Id> approverIds = programToUsersMap.get((Id)rec.Record_Id__c);
            Group queue = [SELECT Id FROM Group WHERE Type = 'Queue' AND Name = 'Program Approval Queue' LIMIT 1];

// Remove old members (optional but recommended)
List<GroupMember> existing = [SELECT Id FROM GroupMember WHERE GroupId = :queue.Id];
delete existing;

// Add new members
List<GroupMember> newMembers = new List<GroupMember>();

for(Id userId : approverIds){
    newMembers.add(new GroupMember(
        GroupId = queue.Id,
        UserOrGroupId = userId
    ));
}

insert newMembers;

            if (approverIds != null && !approverIds.isEmpty()) {
				
                for(Integer i=0;i<approverIds.size();i++){
                    Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                req.setObjectId(rec.Id);
                req.setNextApproverIds(new List<Id>{ approverIds[i] });
                req.setSkipEntryCriteria(true);
                Approval.process(req);
                }
                
                
                
            }
        }
    }
}