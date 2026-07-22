public class ProgramTermCountHandler {

    public static void handleAfterInsert(List<AcademicTerm> newList) {
        updateProgramTermCount(newList);
    }

    public static void handleAfterDelete(Map<Id, AcademicTerm> oldMap) {
        updateProgramTermCount(oldMap);
    }

    /*
     * Update Programme Terms Count
     */
    private static void updateProgramTermCount(List<AcademicTerm> termList) {

        Set<Id> programIds = new Set<Id>();

        for (AcademicTerm t : termList) {

            if (t.Program_Name__c != null) {
                programIds.add(t.Program_Name__c);
            }
        }

        updateProgrammeCount(programIds);
    }

    /*
     * Overloaded Method for Delete
     */
    private static void updateProgramTermCount(Map<Id, AcademicTerm> termMap) {

        Set<Id> programIds = new Set<Id>();

        for (AcademicTerm t : termMap.values()) {

            if (t.Program_Name__c != null) {
                programIds.add(t.Program_Name__c);
            }
        }

        updateProgrammeCount(programIds);
    }

    /*
     * Common Method to Update Count
     */
    private static void updateProgrammeCount(Set<Id> programIds) {

        if (programIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> countMap = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT Program_Name__c progId,
                   COUNT(Id) totalCount
            FROM AcademicTerm
            WHERE Program_Name__c IN :programIds
            GROUP BY Program_Name__c
        ]) {

            countMap.put(
                (Id) ar.get('progId'),
                (Integer) ar.get('totalCount')
            );
        }

        List<Program> programsToUpdate = new List<Program>();

        for (Id progId : programIds) {

            Integer total = countMap.containsKey(progId)
                ? countMap.get(progId)
                : 0;

            programsToUpdate.add(
                new Program(
                    Id = progId,
                    Programme_Terms__c = total
                )
            );
        }

        if (!programsToUpdate.isEmpty()) {
            update programsToUpdate;
        }
    }
}