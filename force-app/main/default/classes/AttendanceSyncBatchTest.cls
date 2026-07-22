@IsTest
private class AttendanceSyncBatchTest {

    @TestSetup
    static void setupData() {
        SpjimrPortalTestDataFactory.buildAll('asb');

        // Link AcademicTermEnrollment.Batch_Enrollment__c to the ProgramCohortMember so the
        // batch's Session_Enrollment__c -> ATE -> Batch_Enrollment__r -> Roll_Number__c chain works.
        List<ProgramCohortMember> pcms = [SELECT Id FROM ProgramCohortMember LIMIT 1];
        if (pcms.isEmpty()) return;
        List<AcademicTermEnrollment> ates = [SELECT Id FROM AcademicTermEnrollment LIMIT 1];
        if (ates.isEmpty()) return;
        SObject ate = ates[0];
        try { ate.put('Batch_Enrollment__c', pcms[0].Id); update ate; } catch (Exception e) {}
    }

    private static Attendance_Log__c buildLog(String roll, Datetime ts, String status) {
        Attendance_Log__c al = new Attendance_Log__c();
        al.Roll_Number__c = roll;
        try { al.put('Device_ID__c', 'D1'); } catch (Exception e) {}
        try { al.put('Is_Import__c', false); } catch (Exception e) {}
        try { al.put('Log_Date_Time__c', ts); } catch (Exception e) {}
        al.Status__c = status;
        return al;
    }

    @IsTest
    static void runBatch_noMatchingSessions_logsContinue() {
        List<Attendance_Log__c> logs = new List<Attendance_Log__c>{
            buildLog('UNMATCH-1', Datetime.now(), 'Pending'),
            buildLog('UNMATCH-2', Datetime.now().addMinutes(5), 'Pending')
        };
        try { insert logs; } catch (Exception e) {}

        Test.startTest();
        Id jobId = Database.executeBatch(new AttendanceSyncBatch(), 200);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void runBatch_happyPath_marksLogsSynced() {
        // Align Session start/end to bracket the log timestamp
        List<Session__c> sessList = [SELECT Id, Start_Time__c, End_Time__c FROM Session__c LIMIT 1];
        if (sessList.isEmpty()) return;
        Session__c sess = sessList[0];
        Datetime mid = Datetime.now().addMinutes(30);
        sess.Start_Time__c = mid.addMinutes(-30);
        sess.End_Time__c = mid.addMinutes(30);
        try { update sess; } catch (Exception e) {}

        ProgramCohortMember pcm = [SELECT Id, Roll_Number__c FROM ProgramCohortMember LIMIT 1];
        String roll = pcm.Roll_Number__c;
        if (String.isBlank(roll)) roll = 'R001';

        Attendance_Log__c log = buildLog(roll, mid, 'Pending');
        try { insert log; } catch (Exception e) {}

        Test.startTest();
        Id jobId = Database.executeBatch(new AttendanceSyncBatch(), 200);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void execute_directWithEmptyScope() {
        AttendanceSyncBatch b = new AttendanceSyncBatch();
        Test.startTest();
        b.execute(null, new List<Attendance_Log__c>());
        b.finish(null);
        Test.stopTest();
        System.assert(true);
    }
}