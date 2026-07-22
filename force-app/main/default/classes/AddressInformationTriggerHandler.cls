/**
 * Handles Address Information trigger logic.
 *
 * Applies lightweight data hygiene for Address_Information__c before insert.
 */
public with sharing class AddressInformationTriggerHandler {

    /**
     * Populates Name when it is blank on new Address Information records.
     *
     * Name format:
     * - "Address - <Account Name>" when Account__c is present.
     * - "Address Information - <YYYY-MM-DD>" as fallback.
     *
     * @param newList Incoming Address_Information__c records in before-insert context.
     */
    public static void populateNameIfBlank(List<Address_Information__c> newList) {
        Set<Id> accountIds = new Set<Id>();
        for (Address_Information__c row : newList) {
            if (String.isBlank(row.Name) && row.Account__c != null) {
                accountIds.add(row.Account__c);
            }
        }

        Map<Id, Account> accountById = new Map<Id, Account>();
        if (!accountIds.isEmpty()) {
            accountById = new Map<Id, Account>([
                SELECT Id, Name
                FROM Account
                WHERE Id IN :accountIds
            ]);
        }

        String todayLabel = String.valueOf(Date.today());
        for (Address_Information__c row : newList) {
            if (String.isBlank(row.Name)) {
                if (row.Account__c != null && accountById.containsKey(row.Account__c)) {
                    row.Name = 'Address - ' + accountById.get(row.Account__c).Name;
                } else {
                    row.Name = 'Address Information - ' + todayLabel;
                }
            }
        }
    }
}