public class ProgramCohortMemberHelper {

    // 🔒 Recursion guard
    public static Boolean isProcessing = false;

    /* =========================================================
       SPECIALISATION LOGIC
    ========================================================== */
    public static void assignSpecialisation(List<ProgramCohortMember> pcmList) {

        Set<Id> enrollmentIds = new Set<Id>();

        for (ProgramCohortMember pcm : pcmList) {
            if (pcm.ProgramEnrollmentId != null) {
                enrollmentIds.add(pcm.ProgramEnrollmentId);
            }
        }

        if (enrollmentIds.isEmpty()) return;

        Map<Id, Program> programByEnrollment = new Map<Id, Program>();

        for (ProgramEnrollment pe : [
            SELECT Id,
                   Program.SPJIMR_Is_Specialisation_Program__c,
                   Program.SPJIMR_Is_Major_Specialisation__c
            FROM ProgramEnrollment
            WHERE Id IN :enrollmentIds
        ]) {
            programByEnrollment.put(pe.Id, pe.Program);
        }

        Map<Id, Student_Specialisation__c> specByEnrollment =
            new Map<Id, Student_Specialisation__c>();

        for (Student_Specialisation__c ss : [
            SELECT Id, Program_Enrollment__c
            FROM Student_Specialisation__c
            WHERE Program_Enrollment__c IN :enrollmentIds
            AND Program_Cohort_Member__c = NULL
        ]) {
            specByEnrollment.put(ss.Program_Enrollment__c, ss);
        }

        List<Student_Specialisation__c> specsToUpdate =
            new List<Student_Specialisation__c>();

        for (ProgramCohortMember pcm : pcmList) {

            Program program = programByEnrollment.get(pcm.ProgramEnrollmentId);
            if (program == null) continue;

            if (!program.SPJIMR_Is_Specialisation_Program__c) continue;
            if (!program.SPJIMR_Is_Major_Specialisation__c) continue;

            Student_Specialisation__c ss =
                specByEnrollment.get(pcm.ProgramEnrollmentId);

            if (ss != null) {
                ss.Program_Cohort_Member__c = pcm.Id;
                specsToUpdate.add(ss);
            }
        }

        if (!specsToUpdate.isEmpty()) {
            update specsToUpdate;
        }
    }

    /* =========================================================
       ENROLLMENT UPDATE LOGIC
    ========================================================== */
    public static void updateEnrollment(List<ProgramCohortMember> pcmList) {

        // 🚫 Prevent recursion
        if (isProcessing) return;
        isProcessing = true;

        Map<Id, Id> enrollmentToBatchMap = new Map<Id, Id>();

        for (ProgramCohortMember pcm : pcmList) {

            if (pcm.ProgramEnrollmentId != null &&
                pcm.ProgramCohortId != null) {

                enrollmentToBatchMap.put(
                    pcm.ProgramEnrollmentId,
                    pcm.ProgramCohortId
                );
            }
        }

        if (enrollmentToBatchMap.isEmpty()) return;

        List<ProgramEnrollment> enrollmentsToUpdate = new List<ProgramEnrollment>();

        for (ProgramEnrollment pe : [
            SELECT Id, Batch__c
            FROM ProgramEnrollment
            WHERE Id IN :enrollmentToBatchMap.keySet()
        ]) {

            Id newBatch = enrollmentToBatchMap.get(pe.Id);

            if (pe.Batch__c != newBatch) {

                pe.Batch__c = newBatch;
                enrollmentsToUpdate.add(pe);
            }
        }

        if (!enrollmentsToUpdate.isEmpty()) {
            update enrollmentsToUpdate;
        }
    }
}