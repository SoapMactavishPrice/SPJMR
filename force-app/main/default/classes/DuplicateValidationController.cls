public with sharing class DuplicateValidationController {

    /**
     * Validate Department Code duplicates
     * Object: Department_Master__c
     * Field: Department_Code__c
     */
    public static void validateDepartmentCodes(
        List<Department_Master__c> newRecords
    ) {
        Set<String> departmentCodes = new Set<String>();

        // Collect Department Codes from incoming records
        for (Department_Master__c record : newRecords) {
            if (String.isNotBlank(record.Department_Code__c)) {
                departmentCodes.add(record.Department_Code__c);
            }
        }

        if (departmentCodes.isEmpty()) {
            return;
        }

        // Check existing Department Master records
        Map<String, Id> existingCodes = new Map<String, Id>();

        for (Department_Master__c record : [
            SELECT Id, Department_Code__c
            FROM Department_Master__c
            WHERE Department_Code__c IN :departmentCodes
        ]) {
            existingCodes.put(record.Department_Code__c, record.Id);
        }

        // Check duplicates against existing database records
        // and duplicates within the same transaction
        Map<String, Id> transactionCodes = new Map<String, Id>();

        for (Department_Master__c record : newRecords) {

            if (String.isBlank(record.Department_Code__c)) {
                continue;
            }

            String code = record.Department_Code__c;

            // Check duplicate against existing database record
            if (existingCodes.containsKey(code)) {

                Id existingId = existingCodes.get(code);

                // For update, don't compare the record with itself
                if (existingId != record.Id) {
                    record.addError(
                        'Department Code already exists. Please enter a unique value.'
                    );
                    continue;
                }
            }

            // Check duplicate records within the same transaction
            if (transactionCodes.containsKey(code)) {
                record.addError(
                    'Department Code already exists. Please enter a unique value.'
                );
            } else {
                transactionCodes.put(code, record.Id);
            }
        }
    }


    /**
     * Validate Specialisation Code duplicates
     * Object: Specialisation_Master__c
     * Field: Specialisation_Code__c
     */
    public static void validateSpecialisationCodes(
        List<Specialisation_Master__c> newRecords
    ) {
        Set<String> specialisationCodes = new Set<String>();

        // Collect Specialisation Codes from incoming records
        for (Specialisation_Master__c record : newRecords) {
            if (String.isNotBlank(record.Specialisation_Code__c)) {
                specialisationCodes.add(record.Specialisation_Code__c);
            }
        }

        if (specialisationCodes.isEmpty()) {
            return;
        }

        // Check existing Focus Area Master records
        Map<String, Id> existingCodes = new Map<String, Id>();

        for (Specialisation_Master__c record : [
            SELECT Id, Specialisation_Code__c
            FROM Specialisation_Master__c
            WHERE Specialisation_Code__c IN :specialisationCodes
        ]) {
            existingCodes.put(record.Specialisation_Code__c, record.Id);
        }

        // Check duplicates against existing records
        // and duplicates within the same transaction
        Map<String, Id> transactionCodes = new Map<String, Id>();

        for (Specialisation_Master__c record : newRecords) {

            if (String.isBlank(record.Specialisation_Code__c)) {
                continue;
            }

            String code = record.Specialisation_Code__c;

            // Check duplicate against existing database record
            if (existingCodes.containsKey(code)) {

                Id existingId = existingCodes.get(code);

                // For update, don't compare the record with itself
                if (existingId != record.Id) {
                    record.addError(
                        'Specialisation Code already exists. Please enter a unique value.'
                    );
                    continue;
                }
            }

            // Check duplicate records within the same transaction
            if (transactionCodes.containsKey(code)) {
                record.addError(
                    'Specialisation Code already exists. Please enter a unique value.'
                );
            } else {
                transactionCodes.put(code, record.Id);
            }
        }
    }
}