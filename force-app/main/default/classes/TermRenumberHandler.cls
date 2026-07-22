public class TermRenumberHandler {

    public static void renumberAfterDelete(List<AcademicTerm> deletedTerms) {

        if (deletedTerms == null || deletedTerms.isEmpty()) {
            return;
        }

        // 1️⃣ Collect Batch Group Ids
        Set<Id> batchGroupIds = new Set<Id>();
        for (AcademicTerm t : deletedTerms) {
            if (t.AcademicYearId != null) {
                batchGroupIds.add(t.AcademicYearId);
            }
        }

        if (batchGroupIds.isEmpty()) return;

        // 2️⃣ Query remaining Terms
        List<AcademicTerm> remainingTerms = [
            SELECT Id,
                   AcademicYearId,
                   Term_Numbers__c,
                   Term_Code__c,
                   AcademicYear.Batch_Group_Number__c
            FROM AcademicTerm
            WHERE AcademicYearId IN :batchGroupIds
            ORDER BY AcademicYearId, Term_Numbers__c
        ];

        List<AcademicTerm> termsToUpdate = new List<AcademicTerm>();

        // 3️⃣ Renumber per Batch Group
        Map<Id, Integer> counterMap = new Map<Id, Integer>();

        for (AcademicTerm term : remainingTerms) {

            if (!counterMap.containsKey(term.AcademicYearId)) {
                counterMap.put(term.AcademicYearId, 1);
            }

            Integer nextNumber = counterMap.get(term.AcademicYearId);

            // Only update if changed
            if (term.Term_Numbers__c != nextNumber) {

                term.Term_Numbers__c = nextNumber;

                Integer batchGroupNum =
    term.AcademicYear.Batch_Group_Number__c.intValue();

Integer termNum = nextNumber;

// Pad term number to 2 digits
String formattedTermNum = String.valueOf(termNum).leftPad(2, '0');

term.Term_Code__c =
    String.valueOf(batchGroupNum)
    + '.'
    + formattedTermNum;


                termsToUpdate.add(term);
            }

            counterMap.put(term.AcademicYearId, nextNumber + 1);
        }

        // 4️⃣ Update
        if (!termsToUpdate.isEmpty()) {
            update termsToUpdate;
        }
    }
    
    public static void renumberAfterBatchGroupChange(Set<Id> batchGroupIds) {

    if (batchGroupIds.isEmpty()) return;

    List<AcademicTerm> terms = [
        SELECT Id,
               AcademicYearId,
               Term_Numbers__c,
               AcademicYear.Batch_Group_Number__c
        FROM AcademicTerm
        WHERE AcademicYearId IN :batchGroupIds
        ORDER BY AcademicYearId, Term_Numbers__c
    ];

    List<AcademicTerm> updates = new List<AcademicTerm>();

for (AcademicTerm t : terms) {
    String termNum = String.valueOf(
        Integer.valueOf(t.Term_Numbers__c)
    ).leftPad(2, '0');

    Integer batchGroupNum = Integer.valueOf(t.AcademicYear.Batch_Group_Number__c);

    t.Term_Code__c = String.valueOf(batchGroupNum) + '.' + termNum;

    updates.add(t); // ✅ Add to updates list
}

if (!updates.isEmpty()) {
    update updates;
}

}

}