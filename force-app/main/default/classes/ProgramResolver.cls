public class ProgramResolver {

    public static Map<Id, Id> resolvePrograms(
        String objectApiName,
        Set<Id> recordIds
    ) {
        system.debug('ApiName: '+objectApiName);
        system.debug('recordIds: '+recordIds);

        Map<Id, Id> result = new Map<Id, Id>();

        if (String.isBlank(objectApiName) || recordIds == null || recordIds.isEmpty()) {
            return result;
        }

        Program_Object_Config__mdt config =
            ProgramConfigService.getConfig(objectApiName);

        if (config == null) {
            return result;
        }

        // 🔹 CASE 1: Direct Program Lookup
        if (String.isNotBlank(config.Program_Lookup_Field__c)) {

            String query =
                'SELECT Id,' + config.Program_Lookup_Field__c +
                ' FROM ' + objectApiName +
                ' WHERE Id IN :recordIds';
            system.debug('Found Program query '+query);
            for (SObject record : Database.query(query)) {

                Id programId =
                    (Id) record.get(config.Program_Lookup_Field__c);

                if (programId != null) {
                    result.put(record.Id, programId);
                }
            }

            return result;
        }

        // 🔹 CASE 2: Resolve via Parent Chain
        if (String.isNotBlank(config.Parent_Object__c) &&
            String.isNotBlank(config.Parent_Lookup_Field__c)) {

            return resolveViaParent(
                objectApiName,
                recordIds,
                config
            );
        }

        return result;
    }

    private static Map<Id, Id> resolveViaParent(
        String objectApiName,
        Set<Id> recordIds,
        Program_Object_Config__mdt config
    ) {

        Map<Id, Id> result = new Map<Id, Id>();

        String parentField = config.Parent_Lookup_Field__c;

        String query =
            'SELECT Id,' + parentField +
            ' FROM ' + objectApiName +
            ' WHERE Id IN :recordIds';

        Map<Id, Id> childToParentMap = new Map<Id, Id>();
        Set<Id> parentIds = new Set<Id>();

        for (SObject record : Database.query(query)) {

            Id parentId = (Id) record.get(parentField);

            if (parentId != null) {
                childToParentMap.put(record.Id, parentId);
                parentIds.add(parentId);
            }
        }

        if (parentIds.isEmpty()) {
            return result;
        }

        // 🔁 Recursive call
        Map<Id, Id> parentToProgramMap =
            resolvePrograms(config.Parent_Object__c, parentIds);

        // Map child → program
        for (Id childId : childToParentMap.keySet()) {

            Id parentId = childToParentMap.get(childId);

            if (parentToProgramMap.containsKey(parentId)) {
                result.put(childId, parentToProgramMap.get(parentId));
            }
        }

        return result;
    }
}