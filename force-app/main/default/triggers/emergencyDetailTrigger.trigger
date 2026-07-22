trigger emergencyDetailTrigger on Emergency_Details__c (before insert,before update) {
    Set<Id> accountIds = new Set<Id>();
    Set<String> restrictedValues = new Set<String>{ 'Parent', 'Guardian' };

    
    for (Emergency_Details__c ed : Trigger.new) {
        if (
            ed.Account__c != null &&
            restrictedValues.contains(ed.Relationship__c)
        ) {
            accountIds.add(ed.Account__c);
        }
    }

    if (accountIds.isEmpty()) {
        return;
    }

 
    Map<String, Emergency_Details__c> existingMap = new Map<String, Emergency_Details__c>();

    for (Emergency_Details__c ed : [
        SELECT Id, Account__c, Relationship__c
        FROM Emergency_Details__c
        WHERE Account__c IN :accountIds
        AND Relationship__c IN :restrictedValues
    ]) {
        String key = ed.Account__c + '-' + ed.Relationship__c;
        existingMap.put(key, ed);
    }

    // Validation
    for (Emergency_Details__c ed : Trigger.new) {

        if (
            ed.Account__c == null ||
            !restrictedValues.contains(ed.Relationship__c)
        ) {
            continue;
        }

        String key = ed.Account__c + '-' + ed.Relationship__c;

        // INSERT case
        if (Trigger.isInsert && existingMap.containsKey(key)) {
            ed.addError(
                'Only one ' + ed.Relationship__c +
                ' record is allowed per account.'
            );
        }

       
        if (Trigger.isUpdate && existingMap.containsKey(key)) {
            Emergency_Details__c existing = existingMap.get(key);

            // Allow updating the same record
            if (existing.Id != ed.Id) {
                ed.addError(
                    'Only one ' + ed.Relationship__c +
                    ' record is allowed per account.'
                );
            }
        }
    }
}