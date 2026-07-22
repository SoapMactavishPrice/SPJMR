public class SpecialisationHandler {

    public static void validateDuplicateSpecialisation(
        List<Specialisation__c> newRecords
    ) {

        Set<Id> batchIds = new Set<Id>();
        Set<Id> specialisationIds = new Set<Id>();

        // ============================================
        // COLLECT IDS
        // ============================================

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

        if (!batchIds.isEmpty()) {

            List<String> batchIdStrings = new List<String>();

            for (Id batchId : batchIds) {
                batchIdStrings.add(String.valueOf(batchId));
            }

            String query =
                'SELECT Id, ProgramId ' +
                'FROM ProgramCohort ' +
                'WHERE Id IN (\'' +
                String.join(batchIdStrings, '\',\'') +
                '\')';

            for (SObject obj : Database.query(query)) {

                batchToProgramMap.put(
                    (Id)obj.get('Id'),
                    (Id)obj.get('ProgramId')
                );
            }
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

        Map<String, Id> existingMap = new Map<String, Id>();

        for (Specialisation__c existing : [

            SELECT Id,
                   Batch__c,
                   Specialisation_Name__c
            FROM Specialisation__c
            WHERE Batch__c IN :batchIds
            AND Specialisation_Name__c IN :specialisationIds
            AND IsDeleted = false
        ]) {

            String key =
                String.valueOf(existing.Batch__c) + '-' +
                String.valueOf(existing.Specialisation_Name__c);

            existingMap.put(key, existing.Id);
        }

        // Validate duplicates
        for (Specialisation__c newRec : newRecords) {

            String key =
                String.valueOf(newRec.Batch__c) + '-' +
                String.valueOf(newRec.Specialisation_Name__c);

            if (existingMap.containsKey(key)) {

                // Ignore same record during update
                if (newRec.Id == null ||
                    existingMap.get(key) != newRec.Id) {

                    newRec.addError(
                        'This specialisation is already added to this batch.'
                    );
                }
            }
        }
    }
}