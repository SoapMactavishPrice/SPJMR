public without sharing class ProgramTeamMemberSharingHandler {

    /**
     * Called from trigger after insert on Program_Team_Members__c
     */
    public static void shareAccess(List<Program_Team_Members__c> newMembers) {
        if (newMembers.isEmpty()) return;

        Map<Id, Id> userToProgram = new Map<Id, Id>();
        Map<Id, String> userToAccessType = new Map<Id, String>();

        //  Fetch User, Program, and Access Type
        for (Program_Team_Members__c tm : [
            SELECT User__c, Program_Team__r.Program__c, Program_Team__r.Access_Type__c
            FROM Program_Team_Members__c
            WHERE Id IN :newMembers
        ]) {
            if (tm.User__c != null && tm.Program_Team__r.Program__c != null) {
                userToProgram.put(tm.User__c, tm.Program_Team__r.Program__c);
                userToAccessType.put(tm.User__c, tm.Program_Team__r.Access_Type__c);
            }
        }

        if (userToProgram.isEmpty()) return;

        Set<Id> programIds = new Set<Id>(userToProgram.values());

        //  Get Applications and Leads related to Programs
        List<Application__c> apps = [
            SELECT Id, Program__c, Applicant__c
            FROM Application__c
            WHERE Program__c IN :programIds AND Applicant__c != null
        ];

        List<Lead> leads = [
            SELECT Id, Program_Master__c
            FROM Lead
            WHERE Program_Master__c IN :programIds
        ];

        //  Share record collections
        List<AccountShare> accountShares = new List<AccountShare>();
        List<Application__Share> appShares = new List<Application__Share>();
        List<LeadShare> leadShares = new List<LeadShare>();

        for (Id userId : userToProgram.keySet()) {
            Id programId = userToProgram.get(userId);
            String accessType = userToAccessType.get(userId);

            //  Determine access level
            String accountLevel = (accessType == 'Read/Write') ? 'Edit' : 'Read';
            String appLevel     = (accessType == 'Read/Write') ? 'Edit' : 'Read';
            String leadLevel    = (accessType == 'Read/Write') ? 'Edit' : 'Read';

            //  Application → Account & Application sharing
            for (Application__c app : apps) {
                if (app.Program__c == programId) {

                    // Account Share
                    AccountShare accShare = new AccountShare();
                    accShare.AccountId = app.Applicant__c;
                    accShare.UserOrGroupId = userId;
                    accShare.AccountAccessLevel = accountLevel;
                    accShare.OpportunityAccessLevel = 'None';
                    accShare.CaseAccessLevel = 'None';
                    accountShares.add(accShare);

                    // Application Share
                    Application__Share aShare = new Application__Share();
                    aShare.ParentId = app.Id;
                    aShare.UserOrGroupId = userId;
                    aShare.AccessLevel = appLevel;
                    aShare.RowCause = Schema.Application__Share.RowCause.Manual;
                    appShares.add(aShare);
                }
            }

            //  Lead sharing
            for (Lead l : leads) {
                if (l.Program_Master__c == programId) {
                    LeadShare lShare = new LeadShare();
                    lShare.LeadId = l.Id;
                    lShare.UserOrGroupId = userId;
                    lShare.LeadAccessLevel = leadLevel;
                    lShare.RowCause = Schema.LeadShare.RowCause.Manual;
                    leadShares.add(lShare);
                }
            }
        }

        //  Perform DML in system context
        try {
            if (!accountShares.isEmpty()) Database.insert(accountShares, false);
            if (!appShares.isEmpty()) Database.insert(appShares, false);
            if (!leadShares.isEmpty()) Database.insert(leadShares, false);
        } catch (DmlException ex) {
            System.debug('⚠️ Share insert failed: ' + ex.getMessage());
        }
    }

    /**
     * Called from trigger after delete on Program_Team_Members__c
     */
    public static void removeAccess(List<Program_Team_Members__c> oldMembers) {
        if (oldMembers.isEmpty()) return;

        Set<Id> userIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();

        // Get Program IDs from deleted members
        for (Program_Team_Members__c tm : [
            SELECT User__c, Program_Team__r.Program__c
            FROM Program_Team_Members__c
            WHERE Id IN :oldMembers
        ]) {
            if (tm.User__c != null && tm.Program_Team__r.Program__c != null) {
                userIds.add(tm.User__c);
                programIds.add(tm.Program_Team__r.Program__c);
            }
        }

        // Account Shares to delete
        List<AccountShare> accToDelete = [
            SELECT Id FROM AccountShare
            WHERE UserOrGroupId IN :userIds AND RowCause = 'Manual'
            AND AccountId IN (
                SELECT Applicant__c FROM Application__c
                WHERE Program__c IN :programIds
            )
        ];

        // Application Shares to delete
        List<Application__Share> appToDelete = [
            SELECT Id FROM Application__Share
            WHERE UserOrGroupId IN :userIds AND RowCause = 'Manual'
            AND ParentId IN (
                SELECT Id FROM Application__c
                WHERE Program__c IN :programIds
            )
        ];

        // Lead Shares to delete
        List<LeadShare> leadToDelete = [
            SELECT Id FROM LeadShare
            WHERE UserOrGroupId IN :userIds AND RowCause = 'Manual'
            AND LeadId IN (
                SELECT Id FROM Lead
                WHERE Program_Master__c IN :programIds
            )
        ];

        //  Perform deletions
        try {
            if (!accToDelete.isEmpty()) delete accToDelete;
            if (!appToDelete.isEmpty()) delete appToDelete;
            if (!leadToDelete.isEmpty()) delete leadToDelete;
        } catch (DmlException ex) {
            System.debug('️ Share delete failed: ' + ex.getMessage());
        }
    }
}