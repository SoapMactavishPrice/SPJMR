public with sharing class BatchGroupSequenceController {

   // Get existing batch group numbers and missing numbers for a Batch
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getBatchGroupNumbers(Id batchId) {

        List<AcademicYear> existingBatchGroups = [
            SELECT Batch_Group_Number__c
            FROM AcademicYear
            WHERE Batch__c = :batchId
        ];

        Set<Integer> usedNumbers = new Set<Integer>();
        Integer maxNumber = 0;

        for (AcademicYear bg : existingBatchGroups) {
            Integer num = bg.Batch_Group_Number__c != null ? bg.Batch_Group_Number__c.intValue() : null;
            if (num != null) {
                usedNumbers.add(num);
                if (num > maxNumber) maxNumber = num;
            }
        }

        // Find missing numbers
        List<Integer> missingNumbers = new List<Integer>();
        for (Integer i = 1; i <= maxNumber; i++) {
            if (!usedNumbers.contains(i)) missingNumbers.add(i);
        }

        Integer nextNumber = maxNumber + 1;

        return new Map<String, Object>{
            'missingNumbers' => missingNumbers,
            'nextNumber' => nextNumber
        };
    }

    // Create new batch group
    @AuraEnabled
    public static AcademicYear createBatchGroup(Id batchId, Integer groupNumber) {
        AcademicYear bg = new AcademicYear(
            Batch__c = batchId,
            Batch_Group_Number__c = groupNumber
        );
        insert bg;
        return bg;
    }
}