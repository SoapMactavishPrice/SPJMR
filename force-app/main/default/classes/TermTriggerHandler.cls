public class TermTriggerHandler {

    public static void assignSequentialNames(List<Division__c> newDivisions) {
        // Filter divisions that have Division_Group__c set and collect their IDs
        Set<Id> divisionGroupIds = new Set<Id>();
        
        for (Division__c div : newDivisions) {
            if (div.Division_Group__c != null) {
                divisionGroupIds.add(div.Division_Group__c);
            }
        }
        
        // Query Division Groups to get their names
        Map<Id, String> groupIdToName = new Map<Id, String>();
        if (!divisionGroupIds.isEmpty()) {
            List<Division_Group__c> divisionGroups = [
                SELECT Id, Name
                FROM Division_Group__c
                WHERE Id IN :divisionGroupIds
            ];
            for (Division_Group__c divisionGroup : divisionGroups) {
                groupIdToName.put(divisionGroup.Id, divisionGroup.Name);
            }
        }
        
        // Group divisions by Term, but only for "Fundamental" groups
        Map<Id, List<Division__c>> divisionsByTerm = new Map<Id, List<Division__c>>();

        for (Division__c div : newDivisions) {
            // Only process if Term is set AND Division Group Name is "Fundamental"
            if (div.Term__c != null && div.Division_Group__c != null) {
                String groupName = groupIdToName.get(div.Division_Group__c);
                if (groupName == 'Fundamental') {
                    if (!divisionsByTerm.containsKey(div.Term__c)) {
                        divisionsByTerm.put(div.Term__c, new List<Division__c>());
                    }
                    divisionsByTerm.get(div.Term__c).add(div);
                }
            }
        }

        // For each Term, query existing divisions to know where to start
        for (Id termId : divisionsByTerm.keySet()) {
            // Query existing divisions already saved for this Term with Fundamental Division Group only
            List<Division__c> existingDivs = [
                SELECT Id, Division_Name__c
                FROM Division__c
                WHERE Term__c = :termId
                AND Division_Group__r.Name = 'Fundamental'
                ORDER BY Division_Name__c ASC
            ];

            Integer existingCount = existingDivs.size();

            // Assign sequential names starting after existing ones
            Integer counter = existingCount;
            for (Division__c div : divisionsByTerm.get(termId)) {
                counter++;
                div.Division_Name__c = getDivisionName(counter);
            }
        }
    }

    // Helper method: convert number to A, B, C… AA, AB, etc.
    private static String getDivisionName(Integer index) {
        String name = '';
        Integer dividend = index;
        while (dividend > 0) {
            Integer modulo = Math.mod(dividend - 1, 26);
            name = String.fromCharArray(new List<Integer>{65 + modulo}) + name;
            dividend = (dividend - modulo) / 26;
        }
        return name;
    }
}