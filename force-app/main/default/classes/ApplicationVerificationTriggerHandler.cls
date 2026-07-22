public with sharing class ApplicationVerificationTriggerHandler {

    public static void afterUpdate(List<Application_Verification__c> newList,
                                   Map<Id, Application_Verification__c> oldMap) {

        Set<Id> appIds_AppVerified = new Set<Id>();
        Set<Id> appIds_DocVerified = new Set<Id>();
        Set<Id> ptmIds = new Set<Id>();
        List<Application_Verification__c> recordsToUpdate = new List<Application_Verification__c>();

        // Collect PTM ids
        for (Application_Verification__c av : newList) {
            if (av.Program_Team_Members__c != null)
                ptmIds.add(av.Program_Team_Members__c);
        }

        // Fetch role flags
        Map<Id, Program_Team_Members__c> ptmMap = new Map<Id, Program_Team_Members__c>();
        if (!ptmIds.isEmpty()) {
            ptmMap = new Map<Id, Program_Team_Members__c>(
                [
                    SELECT Id,
                           Program_Team__r.IsApplicationVerifier__c,
                           Program_Team__r.IsDocumentVerifier__c,
                           User__c
                    FROM Program_Team_Members__c
                    WHERE Id IN :ptmIds
                ]
            );
        }

        // Process each updated record
        for (Application_Verification__c av : newList) {
            Application_Verification__c oldAv = oldMap.get(av.Id);
            if (oldAv == null) continue;

            Boolean isApp = false, isDoc = false;
            if (ptmMap.containsKey(av.Program_Team_Members__c)) {
                isApp = ptmMap.get(av.Program_Team_Members__c).Program_Team__r.IsApplicationVerifier__c;
                isDoc = ptmMap.get(av.Program_Team_Members__c).Program_Team__r.IsDocumentVerifier__c;
            }

            // ------------------------------
            // APPLICATION VERIFICATION COMPLETED
            // ------------------------------
            if (av.Application_Verification_Status__c == 'Completed' &&
                oldAv.Application_Verification_Status__c != 'Completed') {

                // Always update Application to "Application Verified"
                appIds_AppVerified.add(av.Application__c);

                // If same verifier does both → auto move to document verification
                if (isApp && isDoc) {
                    Application_Verification__c upd = new Application_Verification__c(
                        Id = av.Id,
                        Status__c = 'Assigned',
                        OwnerId = ptmMap.get(av.Program_Team_Members__c).User__c
                    );
                    recordsToUpdate.add(upd);
                }
            }

            // ------------------------------
            // DOCUMENT VERIFICATION COMPLETED
            // ------------------------------
            if (av.Status__c == 'Completed' &&
                oldAv.Status__c != 'Completed') {

                appIds_DocVerified.add(av.Application__c);
            }
        }

        // Update Application Verified
        if (!appIds_AppVerified.isEmpty()) {
            List<Application__c> apps = [
                SELECT Id FROM Application__c WHERE Id IN :appIds_AppVerified
            ];
            for (Application__c a : apps)
                a.Assignment_Status__c = 'Application Verified';
            update apps;
        }

        // Update Document Verified
        if (!appIds_DocVerified.isEmpty()) {
            List<Application__c> apps2 = [
                SELECT Id FROM Application__c WHERE Id IN :appIds_DocVerified
            ];
            for (Application__c a :apps2)
                a.Assignment_Status__c = 'Document Verified';
            update apps2;
        }

        // Update AV records (auto DV assignment)
        if (!recordsToUpdate.isEmpty())
            update recordsToUpdate;
    }
}