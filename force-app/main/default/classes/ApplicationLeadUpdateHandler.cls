public class ApplicationLeadUpdateHandler {

    public static void updateLeadFromApplication(List<Application__c> newApps) {
       

        // Collect all Account Ids
        Set<Id> accountIds = new Set<Id>();
        for (Application__c app : newApps) {
            if (app.Applicant__c != null) {
                accountIds.add(app.Applicant__c);
            }
        }

        if (accountIds.isEmpty()) return;

        // Query Leads that were converted to these Accounts
        Map<Id, Lead> leadMap = new Map<Id, Lead>(
            [SELECT Id, ConvertedAccountId,Application__c
             FROM Lead
             WHERE IsConverted = TRUE
             AND ConvertedAccountId IN :accountIds]
        );

        List<Lead> leadsToUpdate = new List<Lead>();

        // Loop applications and update lead fields
        for (Application__c app : newApps) {

            for (Lead l : leadMap.values()) {
                if (l.ConvertedAccountId == app.Applicant__c && l.Application__c == null) {

                    
                    l.Application__c = app.ID;
                    

                    leadsToUpdate.add(l);
                }
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
}