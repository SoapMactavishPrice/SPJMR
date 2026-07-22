global class AttendanceSyncBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        System.debug('===== BATCH STARTED =====');

        return Database.getQueryLocator([
            SELECT Id, Roll_Number__c, Log_Date_Time__c, Status__c
            FROM Attendance_Log__c
            WHERE Roll_Number__c != NULL
            AND Log_Date_Time__c != NULL
            AND Status__c != 'Synced'
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Attendance_Log__c> scope) {

        System.debug('Processing Scope Size: ' + scope.size());

        Set<String> rollNumbers = new Set<String>();
        for (Attendance_Log__c log : scope) {
            rollNumbers.add(log.Roll_Number__c);
        }

        // Exclude Present and Sanctioned Leave so approved leave is never overwritten
        // by a biometric/log sync (AC: Sanctioned overrides auto-derived Present/Absent).
        List<Session_Enrollment__c> sessionEnrollments = [
            SELECT Id,
                   Attendance__c,
                   Session__r.Start_Time__c,
                   Session__r.End_Time__c,
                   Academic_Term_Enrollment__r.Batch_Enrollment__r.Roll_Number__c
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__r.Batch_Enrollment__r.Roll_Number__c IN :rollNumbers
            AND Attendance__c != 'Present'
            AND Attendance__c != 'Sanctioned Leave'
        ];

        // Map Roll → Sessions
        Map<String, List<Session_Enrollment__c>> rollToSessions = new Map<String, List<Session_Enrollment__c>>();

        for (Session_Enrollment__c se : sessionEnrollments) {
            String roll = se.Academic_Term_Enrollment__r.Batch_Enrollment__r.Roll_Number__c;

            if (!rollToSessions.containsKey(roll)) {
                rollToSessions.put(roll, new List<Session_Enrollment__c>());
            }
            rollToSessions.get(roll).add(se);
        }

        List<Session_Enrollment__c> sessionsToUpdate = new List<Session_Enrollment__c>();
        List<Attendance_Log__c> logsToUpdate = new List<Attendance_Log__c>();
        Set<Id> updatedSessionIds = new Set<Id>();

        for (Attendance_Log__c log : scope) {

            System.debug('Checking Log: ' + log.Id);

            if (!rollToSessions.containsKey(log.Roll_Number__c)) {
                System.debug('No sessions found for roll: ' + log.Roll_Number__c);
                continue;
            }

            for (Session_Enrollment__c se : rollToSessions.get(log.Roll_Number__c)) {

                Datetime startTime = se.Session__r.Start_Time__c;
                Datetime endTime   = se.Session__r.End_Time__c;

                if (startTime != null && endTime != null &&
                    log.Log_Date_Time__c >= startTime &&
                    log.Log_Date_Time__c <= endTime) {

                    System.debug('✅ Match Found → Session: ' + se.Id);

                    // Defense-in-depth: never overwrite Sanctioned Leave even if query drifts.
                    if (!updatedSessionIds.contains(se.Id)
                            && se.Attendance__c != 'Sanctioned Leave') {
                        se.Attendance__c = 'Present';
                        sessionsToUpdate.add(se);
                        updatedSessionIds.add(se.Id);
                    }

                    log.Status__c = 'Synced';
                    logsToUpdate.add(log);

                    break;
                }
            }
        }

        if (!sessionsToUpdate.isEmpty()) {
            update sessionsToUpdate;
            System.debug('Updated Sessions: ' + sessionsToUpdate.size());
        }

        if (!logsToUpdate.isEmpty()) {
            update logsToUpdate;
            System.debug('Updated Logs: ' + logsToUpdate.size());
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('===== BATCH FINISHED =====');
    }
}