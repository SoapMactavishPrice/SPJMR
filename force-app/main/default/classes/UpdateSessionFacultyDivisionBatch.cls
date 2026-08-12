global class UpdateSessionFacultyDivisionBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id,
                   Session__c,
                   Division_Names__c,
                   Divisions__c
            FROM Session_Faculty__c
            WHERE Session__c != null
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Session_Faculty__c> scope) {

        Set<Id> sessionIds = new Set<Id>();

        for (Session_Faculty__c sf : scope) {
            if (sf.Session__c != null) {
                sessionIds.add(sf.Session__c);
            }
        }

        // Store Division Names
        Map<Id, List<String>> sessionDivisionNames = new Map<Id, List<String>>();

        // Store Division Auto Codes
        Map<Id, List<String>> sessionDivisionCodes = new Map<Id, List<String>>();

        for (Session_Division__c sd : [
            SELECT Session__c,
                   Division__r.Name,
                   Division__r.Division_Name__c
            FROM Session_Division__c
            WHERE Session__c IN :sessionIds
        ]) {

            if (!sessionDivisionNames.containsKey(sd.Session__c)) {
                sessionDivisionNames.put(sd.Session__c, new List<String>());
                sessionDivisionCodes.put(sd.Session__c, new List<String>());
            }

            if (sd.Division__r != null) {

                if (String.isNotBlank(sd.Division__r.Division_Name__c)) {
                    sessionDivisionNames.get(sd.Session__c)
                        .add(sd.Division__r.Division_Name__c);
                }

                if (String.isNotBlank(sd.Division__r.Name)) {
                    sessionDivisionCodes.get(sd.Session__c)
                        .add(sd.Division__r.Name);
                }
            }
        }

        List<Session_Faculty__c> facultiesToUpdate = new List<Session_Faculty__c>();

        for (Session_Faculty__c sf : scope) {

            List<String> names = sessionDivisionNames.get(sf.Session__c);
            List<String> codes = sessionDivisionCodes.get(sf.Session__c);

            String divisionNames =
                (names == null) ? null : String.join(names, ', ');

            String divisionCodes =
                (codes == null) ? null : String.join(codes, ', ');

            Boolean changed = false;

            if (sf.Division_Names__c != divisionNames) {
                sf.Division_Names__c = divisionNames;
                changed = true;
            }

            if (sf.Divisions__c != divisionCodes) {
                sf.Divisions__c = divisionCodes;
                changed = true;
            }

            if (changed) {
                facultiesToUpdate.add(sf);
            }
        }

        if (!facultiesToUpdate.isEmpty()) {
            update facultiesToUpdate;
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Session Faculty Division update batch completed.');
    }
}