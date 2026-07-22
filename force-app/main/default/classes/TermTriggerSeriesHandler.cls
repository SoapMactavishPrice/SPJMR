public with sharing class TermTriggerSeriesHandler {

    /**
     * Main Entry Point
     */
    public static void handleTrigger(List<AcademicTerm> newList) {
        if (Trigger.isBefore && Trigger.isInsert) {
            generateSeries(newList);
        }
    }

    /*
     * Generate Term Number & Term Code*/
     private static void generateSeries(List<AcademicTerm> newTerms) {

        Set<Id> academicYearIds = new Set<Id>();

        // Collect Academic Year Ids
        for (AcademicTerm t : newTerms) {
            if (t.AcademicYearId != null &&
                t.Term_numbers__c == null) {

                academicYearIds.add(t.AcademicYearId);
            }
        }

        if (academicYearIds.isEmpty()) {
            return;
        }

        // 🔹 Fetch Batch Group Code
        Map<Id, String> academicYearToBatchCode = new Map<Id, String>();

        for (AcademicYear ay : [
            SELECT Id, Batch_Group_Code__c
            FROM AcademicYear
            WHERE Id IN :academicYearIds
        ]) {
            academicYearToBatchCode.put(ay.Id, ay.Batch_Group_Code__c);
        }

        // 🔹 Get Existing Max Term Number
        Map<Id, Integer> academicYearToMaxTerm = new Map<Id, Integer>();

        for (AggregateResult ar : [
            SELECT AcademicYearId ayId,
                   MAX(Term_numbers__c) maxTerm
            FROM AcademicTerm
            WHERE AcademicYearId IN :academicYearIds
            GROUP BY AcademicYearId
        ]) {

            Decimal maxValue = (Decimal) ar.get('maxTerm');

            Integer maxNumber = (maxValue != null)
                ? maxValue.intValue()
                : 0;

            academicYearToMaxTerm.put(
                (Id) ar.get('ayId'),
                maxNumber
            );
        }

        // 🔹 Track running max for bulk inserts
        Map<Id, Integer> runningMaxMap = new Map<Id, Integer>();

        for (AcademicTerm t : newTerms) {

            if (t.AcademicYearId == null ||
                t.Term_numbers__c != null) {
                continue;
            }

            Integer currentMax = 0;

            if (runningMaxMap.containsKey(t.AcademicYearId)) {
                currentMax = runningMaxMap.get(t.AcademicYearId);
            }
            else if (academicYearToMaxTerm.containsKey(t.AcademicYearId)) {
                currentMax = academicYearToMaxTerm.get(t.AcademicYearId);
            }

            Integer nextTermNumber = currentMax + 1;

            // 🔹 Get Batch Group Code
            String prefix = academicYearToBatchCode.get(t.AcademicYearId);

            // Safety check (optional but recommended)
            if (prefix == null) {
                t.addError('Batch Group Code missing on Academic Year');
                continue;
            }

            // 🔹 Generate Term Code
            String generatedCode = prefix + '.' + nextTermNumber;

            // 🔹 Assign values
            t.Term_numbers__c = nextTermNumber;
            t.Term_Code__c = generatedCode;

            runningMaxMap.put(
                t.AcademicYearId,
                nextTermNumber
            );
        }
    }
}