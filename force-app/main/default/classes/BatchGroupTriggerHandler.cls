public with sharing class BatchGroupTriggerHandler {
    
    public static void handleBeforeInsert(List<AcademicYear> newList) {
        Set<Id> batchIds = new Set<Id>();
        
        for (AcademicYear ay : newList) {
            if (ay.Batch__c != null) {
                batchIds.add(ay.Batch__c);
            }
        }
        
        if (batchIds.isEmpty()) return;
        
        /* ---------------- Get Batch Series ---------------- */
        
        Map<Id, String> batchSeriesMap = new Map<Id, String>();
        
        for (ProgramCohort b : [
            SELECT Id,Short_Batch_Code__c
            FROM ProgramCohort
            WHERE Id IN :batchIds
        ]) {
            batchSeriesMap.put(b.Id, b.Short_Batch_Code__c);
        }
        
        /* ---------------- Get Max Existing Sequence ---------------- */
        
        Map<Id, Integer> batchMaxMap = new Map<Id, Integer>();
        
        for (AggregateResult ar : [
            SELECT Batch__c batchId,
            MAX(Batch_Group_Number__c) maxNum
            FROM AcademicYear
            WHERE Batch__c IN :batchIds
            GROUP BY Batch__c
        ]) {
            Decimal val = (Decimal) ar.get('maxNum');
            batchMaxMap.put(
                (Id) ar.get('batchId'),
                val != null ? val.intValue() : 0
            );
        }
        
        /* ---------------- Assign Sequence + Code ---------------- */
        
        Map<Id, Integer> runningMap = new Map<Id, Integer>();
        
        for (AcademicYear ay : newList) {
            
            if (ay.Batch__c == null) continue;
            
            Integer currentMax = 0;
            
            if (runningMap.containsKey(ay.Batch__c)) {
                currentMax = runningMap.get(ay.Batch__c);
            } else if (batchMaxMap.containsKey(ay.Batch__c)) {
                currentMax = batchMaxMap.get(ay.Batch__c);
            }
            
            Integer nextNumber = currentMax + 1;
            
            String series = batchSeriesMap.get(ay.Batch__c);
            
            // ✅ FINAL CODE FORMAT
            ay.Batch_Group_Number__c = nextNumber;
            ay.Batch_Group_Code__c = series + '.' + nextNumber;
            
            runningMap.put(ay.Batch__c, nextNumber);
        }
    }
    
    public static void validateUniqueNames( List<AcademicYear> newRecords,Map<Id, AcademicYear> oldMap) {

        Set<Id> batchIds = new Set<Id>();
        Set<String> transactionKeys = new Set<String>();

        for (AcademicYear bg : newRecords) {

            if (bg.Batch__c == null || String.isBlank(bg.Name)) {
                continue;
            }

            String key = buildKey(bg.Batch__c, bg.Name);
            if (transactionKeys.contains(key)) {
                bg.Name.addError(
                    'Batch Group Name must be unique within the Batch.'
                );
            } else {
                transactionKeys.add(key);
            }

            if (oldMap != null &&
                oldMap.containsKey(bg.Id)) {

                AcademicYear oldRec = oldMap.get(bg.Id);

                Boolean nameChanged =
                    oldRec.Name != bg.Name;

                Boolean batchChanged =
                    oldRec.Batch__c != bg.Batch__c;

                if (!nameChanged && !batchChanged) {
                    continue;
                }
            }

            batchIds.add(bg.Batch__c);
        }

        if (batchIds.isEmpty()) {
            return;
        }

        List<AcademicYear> existingRecords = [
            SELECT Id, Name, Batch__c
            FROM AcademicYear
            WHERE Batch__c IN :batchIds
        ];

        Map<String, Id> existingMap = new Map<String, Id>();

        for (AcademicYear existing : existingRecords) {
            String key = buildKey(
                existing.Batch__c,
                existing.Name
            );
            existingMap.put(key, existing.Id);
        }

        for (AcademicYear bg : newRecords) {
            if (bg.Batch__c == null || String.isBlank(bg.Name)) {
                continue;
            }

            String key = buildKey(bg.Batch__c, bg.Name);

            if (existingMap.containsKey(key)) {
                if (bg.Id != null &&
                    existingMap.get(key) == bg.Id) {
                    continue;
                }

                bg.Name.addError(
                    'Batch Group Name must be unique within the Batch.'
                );
            }
        }
    }

    private static String buildKey(
        Id batchId,
        String name
    ) {
        return String.valueOf(batchId) +
            '-' +
            name.trim().toLowerCase();
    }
   
    
 // Set BatchGroupCurrency 
    public static void setBatchGroupCurrency(
        List<AcademicYear> newBatchGroups
    ) {

        Set<Id> programIds = new Set<Id>();

        for (AcademicYear bg : newBatchGroups) {

            if (bg.Program_Master__c != null) {
                programIds.add(bg.Program_Master__c);
            }
        }

        if (programIds.isEmpty()) {
            return;
        }

        Map<Id, Program> programMap =
            new Map<Id, Program>([
                SELECT Id,
                       Programme_Base_Currency__c
                FROM Program
                WHERE Id IN :programIds
            ]);

        for (AcademicYear bg : newBatchGroups) {

            Program prog = programMap.get(bg.Program_Master__c);

            if (prog != null) {

                bg.Batch_Group_Base_Currency__c =
                    prog.Programme_Base_Currency__c;
            }
        }
    }
}