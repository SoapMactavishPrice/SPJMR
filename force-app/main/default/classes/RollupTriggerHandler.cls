public class RollupTriggerHandler {
    public static void validateDateOverlap(
    List<AcademicYear> newRecords
) {

    Set<Id> recordIds = new Set<Id>();
    Set<Id> batchIds = new Set<Id>();

    // Collect Ids
    for (AcademicYear rec : newRecords) {

        if (rec.Id != null) {
            recordIds.add(rec.Id);
        }

        if (rec.Batch__c != null) {
            batchIds.add(rec.Batch__c);
        }
    }

    if (batchIds.isEmpty()) {
        return;
    }

    // Existing records from same Batch only
    List<AcademicYear> existingRecords = [

        SELECT Id,
               Batch__c,
               Batch_Group_Start_Date__c,
               Batch_Group_End_Date__c
        FROM AcademicYear
        WHERE Batch__c IN :batchIds
        AND Id NOT IN :recordIds
    ];

    // Validate overlap
    for (AcademicYear newRec : newRecords) {

        if (newRec.Batch__c == null ||
            newRec.Batch_Group_Start_Date__c == null ||
            newRec.Batch_Group_End_Date__c == null) {

            continue;
        }

        for (AcademicYear existing : existingRecords) {

            // SAME BATCH ONLY
            if (existing.Batch__c == newRec.Batch__c) {

                Boolean isOverlap =

                    newRec.Batch_Group_Start_Date__c <=
                    existing.Batch_Group_End_Date__c

                    &&

                    newRec.Batch_Group_End_Date__c >=
                    existing.Batch_Group_Start_Date__c;

                if (isOverlap) {

                    newRec.addError(
                        'Another Batch Group already exists within the selected date range. Please choose different dates.'
                    );

                    break;
                }
            }
        }
    }
}
public static void validateTermDateOverlap(
    List<AcademicTerm> newRecords
) {

    Set<Id> recordIds = new Set<Id>();
    Set<Id> batchGroupIds = new Set<Id>();

    // Collect Ids
    for (AcademicTerm rec : newRecords) {

        if (rec.Id != null) {
            recordIds.add(rec.Id);
        }

        if (rec.AcademicYearId != null) {
            batchGroupIds.add(rec.AcademicYearId);
        }
    }

    if (batchGroupIds.isEmpty()) {
        return;
    }

    // Existing terms from SAME Batch Group
    List<AcademicTerm> existingRecords = [

        SELECT Id,
               AcademicYearId,
               Term_Start_Date__c,
               Term_End_Date__c
        FROM AcademicTerm
        WHERE AcademicYearId IN :batchGroupIds
        AND Id NOT IN :recordIds
    ];

    // Validate overlap
    for (AcademicTerm newRec : newRecords) {

        if (newRec.AcademicYearId == null ||
            newRec.Term_Start_Date__c == null ||
            newRec.Term_End_Date__c == null) {

            continue;
        }

        for (AcademicTerm existing : existingRecords) {

            // SAME BATCH GROUP ONLY
            if (existing.AcademicYearId ==
                newRec.AcademicYearId) {

                Boolean isOverlap =

                    newRec.Term_Start_Date__c <=
                    existing.Term_End_Date__c

                    &&

                    newRec.Term_End_Date__c >=
                    existing.Term_Start_Date__c;

                if (isOverlap) {

                    newRec.addError(
                        'Another Term already exists within the selected date range. Please choose different dates.'
                    );

                    break;
                }
            }
        }
    }
}

    /*
     * ─────────────────────────────────────────────────────────
     *  Called from AcademicYearTrigger
     *  Updates: Number_of_Batch_Group__c on ProgramCohort
     *  Lookup: AcademicYear.Batch__c → ProgramCohort
     * ─────────────────────────────────────────────────────────
     */
    public static void updateBatchLevelData(List<AcademicYear> batchGroups) {

        Set<Id> batchIds = new Set<Id>();
        for (AcademicYear ay : batchGroups) {
            if (ay.Batch__c != null) {
                batchIds.add(ay.Batch__c);
            }
        }

        if (batchIds.isEmpty()) return;

        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (Id bId : batchIds) {
            countMap.put(bId, 0);
        }

        for (AggregateResult ar : [
            SELECT Batch__c, COUNT(Id) total
            FROM AcademicYear
            WHERE Batch__c IN :batchIds
            GROUP BY Batch__c
        ]) {
            countMap.put(
                (Id) ar.get('Batch__c'),
                (Integer) ar.get('total')
            );
        }

        List<ProgramCohort> toUpdate = new List<ProgramCohort>();
        for (Id bId : batchIds) {
            toUpdate.add(new ProgramCohort(
                Id                       = bId,
                Number_of_Batch_Group__c = countMap.get(bId)
            ));
        }

        commitUpdate(toUpdate, 'Number_of_Batch_Group__c');
    }

    /*
     * ─────────────────────────────────────────────────────────
     *  Called from AcademicTermTrigger
     *  Updates:
     *  1. Number_of_terms_in_Batch_Group__c on AcademicYear
     *  2. Batch_Terms__c on ProgramCohort
     *  Lookup: AcademicTerm.AcademicYearId → AcademicYear  ✅ FIXED
     *          AcademicYear.Batch__c → ProgramCohort
     * ─────────────────────────────────────────────────────────
     */
    public static void updateBatchLevelDataFromTerms(List<AcademicTerm> terms) {

        // Step 1: Collect AcademicYear Ids using correct field AcademicYearId
        Set<Id> academicYearIds = new Set<Id>();
        for (AcademicTerm t : terms) {
            if (t.AcademicYearId != null) {
                academicYearIds.add(t.AcademicYearId);
            }
        }

        if (academicYearIds.isEmpty()) return;

        // Step 2: Build AcademicYear → ProgramCohort map using Batch__c
        Set<Id> batchIds = new Set<Id>();
        Map<Id, Id> ayToBatchMap = new Map<Id, Id>();

        for (AcademicYear ay : [
            SELECT Id, Batch__c
            FROM AcademicYear
            WHERE Id IN :academicYearIds
        ]) {
            if (ay.Batch__c != null) {
                ayToBatchMap.put(ay.Id, ay.Batch__c);
                batchIds.add(ay.Batch__c);
            }
        }

        // ── UPDATE 1: Number_of_terms_in_Batch_Group__c on AcademicYear ──
        Map<Id, Integer> ayTermCountMap = new Map<Id, Integer>();
        for (Id ayId : academicYearIds) {
            ayTermCountMap.put(ayId, 0);
        }

        for (AggregateResult ar : [
            SELECT AcademicYearId, COUNT(Id) total
            FROM AcademicTerm
            WHERE AcademicYearId IN :academicYearIds
            GROUP BY AcademicYearId
        ]) {
            ayTermCountMap.put(
                (Id) ar.get('AcademicYearId'),
                (Integer) ar.get('total')
            );
        }

        List<AcademicYear> ayToUpdate = new List<AcademicYear>();
        for (Id ayId : academicYearIds) {
            ayToUpdate.add(new AcademicYear(
                Id                                = ayId,
                Number_of_terms_in_Batch_Group__c = ayTermCountMap.get(ayId)
            ));
        }

        commitAcademicYearUpdate(ayToUpdate);

        // ── UPDATE 2: Batch_Terms__c on ProgramCohort ──
        if (batchIds.isEmpty()) return;

        // Get ALL AcademicYears under these Batches
        Set<Id> allAyIds = new Set<Id>();
        Map<Id, Id> allAyToBatchMap = new Map<Id, Id>();

        for (AcademicYear ay : [
            SELECT Id, Batch__c
            FROM AcademicYear
            WHERE Batch__c IN :batchIds
        ]) {
            allAyIds.add(ay.Id);
            allAyToBatchMap.put(ay.Id, ay.Batch__c);
        }

        Map<Id, Integer> batchTermCountMap = new Map<Id, Integer>();
        for (Id bId : batchIds) {
            batchTermCountMap.put(bId, 0);
        }

        for (AggregateResult ar : [
            SELECT AcademicYearId, COUNT(Id) total
            FROM AcademicTerm
            WHERE AcademicYearId IN :allAyIds
            GROUP BY AcademicYearId
        ]) {
            Id ayId          = (Id) ar.get('AcademicYearId');
            Integer cnt      = (Integer) ar.get('total');
            Id parentBatchId = allAyToBatchMap.get(ayId);

            if (parentBatchId != null) {
                Integer existing = batchTermCountMap.get(parentBatchId);
                batchTermCountMap.put(
                    parentBatchId,
                    (existing != null ? existing : 0) + cnt
                );
            }
        }

        List<ProgramCohort> batchToUpdate = new List<ProgramCohort>();
        for (Id bId : batchIds) {
            batchToUpdate.add(new ProgramCohort(
                Id             = bId,
                Batch_Terms__c = batchTermCountMap.get(bId)
            ));
        }

        commitUpdate(batchToUpdate, 'Batch_Terms__c');
    }

    /*
     * ─────────────────────────────────────
     *  DML Helper — Update ProgramCohort
     * ─────────────────────────────────────
     */
    private static void commitUpdate(
        List<ProgramCohort> records,
        String fieldName
    ) {
        if (records.isEmpty()) return;
        try {
            update records;
            System.debug(fieldName + ' updated on '
                + records.size() + ' ProgramCohort record(s).');
        } catch (DmlException e) {
            System.debug('Error updating ' + fieldName + ': ' + e.getMessage());
        }
    }

    /*
     * ─────────────────────────────────────
     *  DML Helper — Update AcademicYear
     * ─────────────────────────────────────
     */
    private static void commitAcademicYearUpdate(List<AcademicYear> records) {
        if (records.isEmpty()) return;
        try {
            update records;
            System.debug('Number_of_terms_in_Batch_Group__c updated on '
                + records.size() + ' AcademicYear record(s).');
        } catch (DmlException e) {
            System.debug('Error updating AcademicYear: ' + e.getMessage());
        }
    }
}