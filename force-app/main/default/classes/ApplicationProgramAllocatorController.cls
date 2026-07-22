public with sharing class ApplicationProgramAllocatorController {
@AuraEnabled(cacheable=true)
    public static Map<String, Object> loadData(Id programId) {
        Map<String, Object> result = new Map<String, Object>();

        if (programId == null) {
            result.put('applications', new List<Application__c>());
            result.put('verifiers', new List<UserWrapper>());
            return result;
        }

        // Applications that have related Document_Details__c with AllDocumentsUploaded__c = TRUE
        List<Application__c> apps = [
            SELECT Id, Name, Applicant__r.Name
            FROM Application__c
            WHERE Program__c = :programId
              AND Id IN (
                  SELECT Application_No__c
                  FROM Document_Details__c
                  WHERE AllDocumentsUploaded__c = TRUE
              )
            ORDER BY CreatedDate
        ];

        // Fetch ProgramTeam records of Type = 'Verifier' and their team members
        List<Program_Team__c> teams = [
            SELECT Id,
               (SELECT Id, User__c, User__r.Name FROM Program_Team_Members__r)
            FROM Program_Team__c
            WHERE Program__c = :programId
              AND Type__c = 'Verifier'
        ];

        List<UserWrapper> verifiers = new List<UserWrapper>();

        for (Program_Team__c t : teams) {
            if (t.Program_Team_Members__r != null) {
                for (Program_Team_Members__c m : t.Program_Team_Members__r) {
                    if (m.User__c != null) {
                        verifiers.add(new UserWrapper(String.valueOf(m.User__c), m.User__r != null ? m.User__r.Name : ''));
                    }
                }
            }
        }

        result.put('applications', apps);
        result.put('verifiers', verifiers);
        return result;
    }

    // Simple wrapper for LWC
    public class UserWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        public UserWrapper(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }
}