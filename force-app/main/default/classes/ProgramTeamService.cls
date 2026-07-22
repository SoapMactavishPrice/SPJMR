public class ProgramTeamService {

    public static Map<Id, List<Program_Team_Members__c>> getActiveMembers(Set<Id> programIds) {

        Map<Id, List<Program_Team_Members__c>> result =
            new Map<Id, List<Program_Team_Members__c>>();

        if (programIds == null || programIds.isEmpty()) {
            return result;
        }

        List<Program_Team_Members__c> members = [
            SELECT Id,
                   User__c,
                   AccessLevel__c,
                   Program_Team__c,
                   Program_Team__r.Program__c
            FROM Program_Team_Members__c WHERE
            User__c != NULL
            AND Program_Team__r.Program__c IN :programIds
        ];

        for (Program_Team_Members__c member : members) {

            Id programId = member.Program_Team__r.Program__c;

            if (programId == null) continue;

            if (!result.containsKey(programId)) {
                result.put(programId, new List<Program_Team_Members__c>());
            }

            result.get(programId).add(member);
        }

        return result;
    }
}