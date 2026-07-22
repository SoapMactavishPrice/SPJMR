public class LeadDuplicateHandler {

    public static void checkBeforeAllDuplicates(List<Lead> newList) {

        Set<String> emails = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<Id> programIds = new Set<Id>();

        // Collect all fields
        for (Lead l : newList) {

            if (l.RecordType.DeveloperName != 'B2C') continue;

            if (!String.isBlank(l.Email))
                emails.add(l.Email.toLowerCase().trim());

            if (!String.isBlank(l.Phone))
                phones.add(clean(l.Phone));

            if (l.Program_Master__c != null)
                programIds.add(l.Program_Master__c);
        }

        if (emails.isEmpty() && phones.isEmpty()) return;

        // Query all matching database leads
        List<Lead> db = [
            SELECT Id, Email, Phone, Program_Master__c
            FROM Lead
            WHERE RecordType.DeveloperName = 'B2C'
              AND (
                    Email IN :emails 
                 OR Phone IN :phones
                 OR Program_Master__c IN :programIds
              )
        ];

        // Now compare each input lead with DB leads
        for (Lead newL : newList) {

            if (newL.RecordType.DeveloperName != 'B2C') continue;

            for (Lead oldL : db) {

                if (oldL.Id == newL.Id) continue;

                Boolean emailMatch =
                    !String.isBlank(newL.Email) &&
                    newL.Email.toLowerCase().trim() == oldL.Email?.toLowerCase().trim();

                Boolean phoneMatch =
                    !String.isBlank(newL.Phone) &&
                    clean(newL.Phone) == clean(oldL.Phone);

                Boolean programMatch =
                    newL.Program_Master__c != null &&
                    oldL.Program_Master__c == newL.Program_Master__c;

                // RULE: Program + (Email OR Phone)
                if (programMatch && (emailMatch || phoneMatch)) {
                    newL.addError(
                        'Duplicate Found: Same Program + Email/Phone.\nExisting Lead: ' + oldL.Id
                    );
                }

                // Backup rule: email/phone-only duplicate
                if (emailMatch || phoneMatch) {
                    newL.addError('Duplicate Email or Phone exists → existing lead: ' + oldL.Id);
                }
            }
        }
    }

    private static String clean(String p) {
        return p == null ? '' : p.replaceAll('[^0-9]', '');
    }
}