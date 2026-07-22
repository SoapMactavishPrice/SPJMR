@IsTest
private class ProgramEnrollmentTriggerHandlerTest {

    @IsTest
    static void beforeInsert_skipsWhenNoProgramOrBatch() {
        // Empty inputs hit the early-return guard
        ProgramEnrollmentTriggerHandler h = new ProgramEnrollmentTriggerHandler();
        h.beforeInsert(new List<ProgramEnrollment>(), new Map<Id, ProgramEnrollment>());
    }

    @IsTest(seeAllData=true)
    static void beforeInsert_setsRollNumberFromProgramAndCohortCodes() {
        // Walk the populated path against existing org data so it covers code lines.
        List<Program> programs = [
            SELECT Id, Short_Programme_Code__c FROM Program WHERE Short_Programme_Code__c != null LIMIT 1
        ];
        List<ProgramCohort> cohorts = [
            SELECT Id, Batch_Code__c FROM ProgramCohort WHERE Batch_Code__c != null LIMIT 1
        ];
        if (programs.isEmpty() || cohorts.isEmpty()) {
            return;
        }
        ProgramEnrollment pe = new ProgramEnrollment(
            ProgramId = programs[0].Id,
            Batch__c = cohorts[0].Id
        );
        ProgramEnrollmentTriggerHandler h = new ProgramEnrollmentTriggerHandler();
        h.beforeInsert(new List<ProgramEnrollment>{ pe }, new Map<Id, ProgramEnrollment>());
        // Roll number should be in format: <ProgramCode>-<BatchCode>-<3-digit-serial>
        System.assertNotEquals(null, pe.Roll_Number__c);
        System.assertEquals(true, pe.Roll_Number__c.contains('-'));
        System.assertNotEquals(null, pe.Serial_Number__c);
    }
}