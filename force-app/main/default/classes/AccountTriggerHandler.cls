public class AccountTriggerHandler {

    public static void checkDuplicateStudents(List<Account> newRecords) {

        Id studentRTId = Schema.SObjectType.Account
            .getRecordTypeInfosByName()
            .get('Student')
            .getRecordTypeId();

        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<Date> dobs = new Set<Date>();
        Set<String> aadhars = new Set<String>();
        Set<String> pans = new Set<String>();
        Set<String> passports = new Set<String>();   // ✅ NEW

        List<Account> studentRecords = new List<Account>();

        for (Account acc : newRecords) {
            if (acc.RecordTypeId == studentRTId) {
                studentRecords.add(acc);

                if (acc.PersonEmail != null) emails.add(acc.PersonEmail);
                if (acc.PersonMobilePhone != null) phones.add(acc.PersonMobilePhone);
                if (acc.Date_Of_Birth__c != null) dobs.add(acc.Date_Of_Birth__c);
                if (acc.Aadhaar_Card_Number__c != null) aadhars.add(acc.Aadhaar_Card_Number__c);
                if (acc.PAN_Number__c != null) pans.add(acc.PAN_Number__c);
                if (acc.Passport_Number__c != null) passports.add(acc.Passport_Number__c); // ✅ NEW
            }
        }

        if (studentRecords.isEmpty()) return;

        List<Account> existingAccounts = [
            SELECT Id, PersonEmail, PersonMobilePhone, Date_Of_Birth__c,
                   Aadhaar_Card_Number__c, PAN_Number__c, Passport_Number__c  // ✅ NEW
            FROM Account
            WHERE RecordTypeId = :studentRTId AND (
                PersonEmail IN :emails
                OR PersonMobilePhone IN :phones
                OR Date_Of_Birth__c IN :dobs
                OR Aadhaar_Card_Number__c IN :aadhars
                OR PAN_Number__c IN :pans
                OR Passport_Number__c IN :passports   // ✅ NEW
            )
        ];

        for (Account newAcc : studentRecords) {
            for (Account existing : existingAccounts) {

                if (
                    (newAcc.PersonEmail != null && newAcc.PersonEmail == existing.PersonEmail) ||
                    (newAcc.PersonMobilePhone != null && newAcc.PersonMobilePhone == existing.PersonMobilePhone) ||
                    (newAcc.Date_Of_Birth__c != null && newAcc.Date_Of_Birth__c == existing.Date_Of_Birth__c) ||
                    (newAcc.Aadhaar_Card_Number__c != null && newAcc.Aadhaar_Card_Number__c == existing.Aadhaar_Card_Number__c) ||
                    (newAcc.PAN_Number__c != null && newAcc.PAN_Number__c == existing.PAN_Number__c) ||
                    (newAcc.Passport_Number__c != null && newAcc.Passport_Number__c == existing.Passport_Number__c) // ✅ NEW
                ) {
                    newAcc.addError('Duplicate Student found! Matching data already exists.');
                    break;
                }
            }
        }
    }

    // ✅ NEW METHOD — Faculty Code duplicate check
    public static void checkDuplicateFacultyCode(
        List<Account> newAccounts,
        Map<Id, Account> oldMap
    ) {
        Set<String> facultyCodes = new Set<String>();
        for (Account acc : newAccounts) {
            if (String.isNotBlank(acc.SPJIMR_Faculty_Code__c)) {
                if (oldMap != null) {
                    Account oldAcc = oldMap.get(acc.Id);
                    if (oldAcc != null
                        && acc.SPJIMR_Faculty_Code__c == oldAcc.SPJIMR_Faculty_Code__c) {
                        continue;
                    }
                }
                facultyCodes.add(acc.SPJIMR_Faculty_Code__c);
            }
        }

        if (facultyCodes.isEmpty()) return;

        Map<String, Id> codeToId = new Map<String, Id>();
        for (Account existing : [
            SELECT Id, SPJIMR_Faculty_Code__c
            FROM Account
            WHERE SPJIMR_Faculty_Code__c IN :facultyCodes
        ]) {
            codeToId.put(existing.SPJIMR_Faculty_Code__c, existing.Id);
        }

        for (Account acc : newAccounts) {
            if (String.isNotBlank(acc.SPJIMR_Faculty_Code__c)
                && codeToId.containsKey(acc.SPJIMR_Faculty_Code__c)) {

                if (oldMap != null
                    && codeToId.get(acc.SPJIMR_Faculty_Code__c) == acc.Id) {
                    continue;
                }

                acc.addError(
    'Duplicate value found: Faculty Code already exists.'
     ); 
            }
        }
    }
}