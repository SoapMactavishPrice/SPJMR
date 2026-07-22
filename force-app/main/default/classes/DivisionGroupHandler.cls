public with sharing class DivisionGroupHandler {

    public static void beforeDelete(List<Division_Group__c> divisionGroups) {

        // 1️⃣ Collect all Division Group Ids
        Set<Id> divisionGroupIds = new Set<Id>();
        for (Division_Group__c dg : divisionGroups) {
            divisionGroupIds.add(dg.Id);
        }

        // 2️⃣ Check if any Division uses these groups
        Map<Id, Integer> usageMap = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Division_Group__c dgId, COUNT(Id) cnt
            FROM Division__c
            WHERE Division_Group__c IN :divisionGroupIds
            GROUP BY Division_Group__c
        ]) {
            usageMap.put(
                (Id) ar.get('dgId'),
                (Integer) ar.get('cnt')
            );
        }

        // 3️⃣ Block deletion if used
        for (Division_Group__c dg : divisionGroups) {
            if (usageMap.containsKey(dg.Id)) {
                dg.addError('This Division Group is in use and cannot be deleted.');
            }
        }
    }
}