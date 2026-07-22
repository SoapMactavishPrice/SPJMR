public with sharing class TermSeriesHandler {

    public static void afterInsert(List<AcademicTerm> newTerms) {

        // 1️⃣ Collect Batch Group Ids
        Set<Id> batchGroupIds = new Set<Id>();

        for (AcademicTerm t : newTerms) {
            if (t.AcademicYearId != null && t.Term_numbers__c == null) {
                batchGroupIds.add(t.AcademicYearId);
            }
        }

        if (batchGroupIds.isEmpty()) return;

        // 2️⃣ Query Batch Group numbers
        Map<Id, Integer> batchGroupToNumber = new Map<Id, Integer>();

        for (AcademicYear bg : [
            SELECT Id, Batch_Group_Number__c
            FROM AcademicYear
            WHERE Id IN :batchGroupIds
        ]) {
            if (bg.Batch_Group_Number__c != null) {
                batchGroupToNumber.put(
                    bg.Id,
                    bg.Batch_Group_Number__c.intValue()
                );
            }
        }

        // 3️⃣ Query existing Terms (LOCKED)
        Map<Id, Set<Integer>> bgToUsedTermNumbers = new Map<Id, Set<Integer>>();

        for (AcademicTerm t : [
            SELECT AcademicYearId, Term_numbers__c
            FROM AcademicTerm
            WHERE AcademicYearId IN :batchGroupIds
            AND Term_numbers__c != NULL
            FOR UPDATE
        ]) {
            if (!bgToUsedTermNumbers.containsKey(t.AcademicYearId)) {
                bgToUsedTermNumbers.put(t.AcademicYearId, new Set<Integer>());
            }
            bgToUsedTermNumbers
                .get(t.AcademicYearId)
                .add(t.Term_numbers__c.intValue());
        }

       // 4️⃣ Assign Term numbers + Term Code
List<AcademicTerm> termsToUpdate = new List<AcademicTerm>();

for (AcademicTerm t : newTerms) {

    if (t.AcademicYearId == null || t.Term_numbers__c != null) {
        continue;
    }

    Set<Integer> usedNumbers =
        bgToUsedTermNumbers.containsKey(t.AcademicYearId)
        ? bgToUsedTermNumbers.get(t.AcademicYearId)
        : new Set<Integer>();

    Integer nextTermNumber = 1;
    while (usedNumbers.contains(nextTermNumber)) {
        nextTermNumber++;
    }

    Integer batchGroupNumber = batchGroupToNumber.get(t.AcademicYearId);

    termsToUpdate.add(new AcademicTerm(
        Id = t.Id,
        Term_numbers__c = nextTermNumber,
        Term_Code__c = batchGroupNumber + '.' + nextTermNumber
    ));

    usedNumbers.add(nextTermNumber);
    bgToUsedTermNumbers.put(t.AcademicYearId, usedNumbers);
}

// 5️⃣ Update once
if (!termsToUpdate.isEmpty()) {
    update termsToUpdate;
}

    }
}