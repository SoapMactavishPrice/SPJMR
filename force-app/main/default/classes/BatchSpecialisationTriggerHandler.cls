public class BatchSpecialisationTriggerHandler {

    public static void validateDuplicateSpecialisation(
        List<Specialisation__c> newRecords
    ) {

        Set<Id> batchIds = new Set<Id>();
        Set<Id> specialisationIds = new Set<Id>();

        // Collect Ids
        for (Specialisation__c rec : newRecords) {

            if (rec.Batch__c != null) {
                batchIds.add(rec.Batch__c);
            }

            if (rec.Specialisation_Name__c != null) {
                specialisationIds.add(rec.Specialisation_Name__c);
            }
        }

        // ============================================
        // AUTO POPULATE PROGRAM FROM BATCH
        // ============================================

        Map<Id, Id> batchToProgramMap = new Map<Id, Id>();

        for (SObject obj : Database.query(
            'SELECT Id, ProgramId FROM ProgramCohort WHERE Id IN :batchIds'
        )) {

            batchToProgramMap.put(
                (Id)obj.get('Id'),
                (Id)obj.get('ProgramId')
            );
        }

        // Assign Program
        for (Specialisation__c rec : newRecords) {

            if (rec.Batch__c != null &&
                batchToProgramMap.containsKey(rec.Batch__c)) {

                rec.Program__c =
                    batchToProgramMap.get(rec.Batch__c);
            }
        }

        // ============================================
        // DUPLICATE VALIDATION
        // ============================================

        List<Specialisation__c> existingRecords = [
            SELECT Id,
                   Batch__c,
                   Specialisation_Name__c
            FROM Specialisation__c
            WHERE Batch__c IN :batchIds
            AND Specialisation_Name__c IN :specialisationIds
        ];

        for (Specialisation__c newRec : newRecords) {

            for (Specialisation__c existing : existingRecords) {

                if (existing.Batch__c == newRec.Batch__c &&
                    existing.Specialisation_Name__c ==
                    newRec.Specialisation_Name__c &&
                    existing.Id != newRec.Id) {

                    newRec.addError(
                        'This specialisation is already added to this batch.'
                    );
                }
            }
        }
    }
}