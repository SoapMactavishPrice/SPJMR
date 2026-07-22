public class ProgramCourseHandler {

    public static void preventDuplicates(List<Program_Courses__c> newRecords) {

        Set<String> newKeys = new Set<String>();
        Set<Id> courseIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();

        // 🔹 Step 1: Collect data
        for (Program_Courses__c rec : newRecords) {

            if (rec.Learning_Course__c != null && rec.Program_Master__c != null) {

                String key;

                // 🔥 Program Level
                if (rec.Batch__c == null) {
                    key = rec.Learning_Course__c + '-' + rec.Program_Master__c;
                }
                // 🔥 Batch Level
                else {
                    key = rec.Learning_Course__c + '-' + rec.Program_Master__c + '-' + rec.Batch__c;
                }

                // ❌ Duplicate in same transaction
                if (newKeys.contains(key)) {
                    rec.addError('Duplicate assignment not allowed');
                }

                newKeys.add(key);
                courseIds.add(rec.Learning_Course__c);
                programIds.add(rec.Program_Master__c);
            }
        }

        if (courseIds.isEmpty() || programIds.isEmpty()) return;

        // 🔹 Step 2: Fetch existing records
        List<Program_Courses__c> existing = [
            SELECT Learning_Course__c, Program_Master__c, Batch__c
            FROM Program_Courses__c
            WHERE Learning_Course__c IN :courseIds
            AND Program_Master__c IN :programIds
        ];

        Set<String> existingKeys = new Set<String>();

        for (Program_Courses__c rec : existing) {

            String key;

            if (rec.Batch__c == null) {
                key = rec.Learning_Course__c + '-' + rec.Program_Master__c;
            } else {
                key = rec.Learning_Course__c + '-' + rec.Program_Master__c + '-' + rec.Batch__c;
            }

            existingKeys.add(key);
        }

        // 🔹 Step 3: Validation
        for (Program_Courses__c rec : newRecords) {

            String key;

            if (rec.Batch__c == null) {
                // 🔴 Program Level duplicate
                key = rec.Learning_Course__c + '-' + rec.Program_Master__c;

                if (existingKeys.contains(key)) {
                    rec.addError('This course is already assigned to this program');
                }

            } else {
                // 🔴 Batch Level duplicate (same batch only)
                key = rec.Learning_Course__c + '-' + rec.Program_Master__c + '-' + rec.Batch__c;

                if (existingKeys.contains(key)) {
                    rec.addError('This course is already assigned to this batch');
                }
            }
        }
    }
}