public with sharing class EnrollStudentController {

    @AuraEnabled
    public static BatchStudentWrapper getStudentsForBatch(Id batchId) {
        ProgramCohort batch = [
            SELECT Id, ProgramId, Batch_Intake__c
            FROM ProgramCohort
            WHERE Id = :batchId
            LIMIT 1
        ];

        Program prog = [
            SELECT Programme_Intake__c, Programme_Intake_AICTE__c, Is_AICTE_Approved__c
            FROM Program
            WHERE Id = :batch.ProgramId
            LIMIT 1
        ];

        Set<Id> enrolledStudentIds = new Set<Id>();
        List<ProgramCohortMember> existingMembers = [
            SELECT ProgramEnrollmentId
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :batchId
        ];
        for (ProgramCohortMember pcm : existingMembers) {
            enrolledStudentIds.add(pcm.ProgramEnrollmentId);
        }

        Integer currentMemberCount = enrolledStudentIds.size();

        Set<String> excludedStatuses = new Set<String>{
            'Enrolled in Batch'
        };

        List<ProgramEnrollment> tempEnrollments = [
            SELECT Id, Student_Name__c, Status
            FROM ProgramEnrollment
            WHERE ProgramId = :batch.ProgramId
            AND Status NOT IN :excludedStatuses
            AND Id NOT IN :enrolledStudentIds
            ORDER BY Student_Name__c ASC
        ];

        List<Id> enrollmentIds = new List<Id>();
        for (ProgramEnrollment pe : tempEnrollments) {
            enrollmentIds.add(pe.Id);
        }

        Set<Id> alreadyEnrolledIds = new Set<Id>();
        for (ProgramCohortMember pcm : [
            SELECT ProgramEnrollmentId
            FROM ProgramCohortMember
            WHERE ProgramEnrollmentId IN :enrollmentIds
        ]) {
            alreadyEnrolledIds.add(pcm.ProgramEnrollmentId);
        }

        Map<Id, ProgramEnrollment> enrollmentsById = new Map<Id, ProgramEnrollment>();
        for (ProgramEnrollment pe : tempEnrollments) {
            if (!alreadyEnrolledIds.contains(pe.Id)) {
                enrollmentsById.put(pe.Id, pe);
            }
        }

        // Deferred students assigned to this batch via Deferment Request.Rejoining_Batch__c
        // must appear even when they still have membership in their original batch.
        for (ProgramEnrollment pe : rejoiningEnrollmentsForBatch(
            batchId,
            enrolledStudentIds
        )) {
            enrollmentsById.put(pe.Id, pe);
        }

        List<ProgramEnrollmentWrapper> students = new List<ProgramEnrollmentWrapper>();
        for (ProgramEnrollment pe : enrollmentsById.values()) {
            students.add(new ProgramEnrollmentWrapper(
                pe.Id,
                pe.Student_Name__c,
                pe.Status,
                true
            ));
        }
        students.sort();

        BatchStudentWrapper wrapper = new BatchStudentWrapper();
        wrapper.students = students;
        wrapper.batchIntake = batch.Batch_Intake__c != null
            ? Integer.valueOf(batch.Batch_Intake__c)
            : null;
        wrapper.currentMemberCount = currentMemberCount;
        wrapper.programmeIntake = prog.Programme_Intake__c != null
            ? Integer.valueOf(prog.Programme_Intake__c)
            : 0;
        wrapper.currentProgrammeCount = [
            SELECT COUNT()
            FROM ProgramCohortMember
            WHERE ProgramEnrollment.ProgramId = :batch.ProgramId
        ];

        return wrapper;
    }

    public class BatchStudentWrapper {
        @AuraEnabled public List<ProgramEnrollmentWrapper> students;
        @AuraEnabled public Integer batchIntake;
        @AuraEnabled public Integer currentMemberCount;
        @AuraEnabled public Integer programmeIntake;
        @AuraEnabled public Integer currentProgrammeCount;
    }

    public class ProgramEnrollmentWrapper implements Comparable {
        @AuraEnabled public Id Id;
        @AuraEnabled public String studentName;
        @AuraEnabled public String Status;
        @AuraEnabled public Boolean Selected;

        public ProgramEnrollmentWrapper(
            Id id,
            String name,
            String status,
            Boolean selected
        ) {
            this.Id = id;
            this.studentName = name;
            this.Status = status;
            this.Selected = selected;
        }

        public Integer compareTo(Object other) {
            ProgramEnrollmentWrapper that = (ProgramEnrollmentWrapper) other;
            String left = this.studentName == null ? '' : this.studentName;
            String right = that.studentName == null ? '' : that.studentName;
            return left.toLowerCase().compareTo(right.toLowerCase());
        }
    }

    @AuraEnabled
    public static void saveSelectedStudents(
        Id batchId,
        List<Id> selectedStudentIds,
        List<Id> unselectedStudentIdsToWithdraw
    ) {
        if (selectedStudentIds == null) {
            selectedStudentIds = new List<Id>();
        }
        if (unselectedStudentIdsToWithdraw == null) {
            unselectedStudentIdsToWithdraw = new List<Id>();
        }

        ProgramCohort batch = [
            SELECT Id, ProgramId, Batch_Intake__c, Short_Batch_Code__c
            FROM ProgramCohort
            WHERE Id = :batchId
            LIMIT 1
        ];

        Program prog = [
            SELECT Id, Programme_Intake__c, Programme_Intake_AICTE__c, Is_AICTE_Approved__c
            FROM Program
            WHERE Id = :batch.ProgramId
            LIMIT 1
        ];

        Integer batchIntake = batch.Batch_Intake__c != null
            ? Integer.valueOf(batch.Batch_Intake__c)
            : 0;

        Integer programmeIntake = prog.Is_AICTE_Approved__c == true
            ? (prog.Programme_Intake_AICTE__c != null
                ? Integer.valueOf(prog.Programme_Intake_AICTE__c)
                : 0)
            : (prog.Programme_Intake__c != null
                ? Integer.valueOf(prog.Programme_Intake__c)
                : 0);

        Set<Id> existingBatchEnrollments = new Set<Id>();
        for (ProgramCohortMember pcm : [
            SELECT ProgramEnrollmentId
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :batchId
        ]) {
            existingBatchEnrollments.add(pcm.ProgramEnrollmentId);
        }

        List<Id> newStudentIds = new List<Id>();
        for (Id stuId : selectedStudentIds) {
            if (!existingBatchEnrollments.contains(stuId)) {
                newStudentIds.add(stuId);
            }
        }

        if (newStudentIds.isEmpty()) {
            return;
        }

        Map<Id, RejoiningRollInfo> rejoiningByPe =
            rejoiningRollByEnrollment(batchId, newStudentIds);

        Integer currentBatchCount = [
            SELECT COUNT()
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :batchId
        ];

        if (currentBatchCount + newStudentIds.size() > batchIntake) {
            Integer remaining = batchIntake - currentBatchCount;
            if (remaining < 0) {
                remaining = 0;
            }
            throw new AuraHandledException(
                'Batch intake exceeded. Only ' + remaining +
                ' slot(s) remaining in this batch.'
            );
        }

        // Rejoining students already occupy a programme seat via their original batch.
        Integer freshSeatCount = 0;
        for (Id peId : newStudentIds) {
            if (!rejoiningByPe.containsKey(peId)) {
                freshSeatCount++;
            }
        }

        Integer currentProgrammeCount = [
            SELECT COUNT()
            FROM ProgramCohortMember
            WHERE ProgramEnrollment.ProgramId = :batch.ProgramId
        ];

        if (freshSeatCount > 0
            && currentProgrammeCount + freshSeatCount > programmeIntake
        ) {
            Integer remaining = programmeIntake - currentProgrammeCount;
            if (remaining < 0) {
                remaining = 0;
            }
            throw new AuraHandledException(
                'Programme intake exceeded. Only ' + remaining +
                ' seat(s) remaining across all batches.'
            );
        }

        List<ProgramEnrollment> enrollmentsToProcess = [
            SELECT Id,
                   Student_Name__c,
                   ProgramId,
                   Program.Short_Programme_Code__c,
                   Status
            FROM ProgramEnrollment
            WHERE Id IN :newStudentIds
            ORDER BY Student_Name__c ASC
        ];

        if (enrollmentsToProcess.isEmpty()) {
            return;
        }

        String batchCode = batch.Short_Batch_Code__c;
        String programCode =
            enrollmentsToProcess[0].Program.Short_Programme_Code__c;

        Integer maxSerial = 0;
        List<ProgramCohortMember> lastMember = [
            SELECT Serial_Number__c
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :batchId
            AND Serial_Number__c != null
            ORDER BY Serial_Number__c DESC
            LIMIT 1
        ];
        if (!lastMember.isEmpty()) {
            maxSerial = Integer.valueOf(lastMember[0].Serial_Number__c);
        }

        List<ProgramEnrollment> toUpdate = new List<ProgramEnrollment>();
        List<ProgramCohortMember> toInsert = new List<ProgramCohortMember>();

        for (ProgramEnrollment pe : enrollmentsToProcess) {
            pe.Status = 'Enrolled in Batch';
            toUpdate.add(pe);

            ProgramCohortMember member = new ProgramCohortMember();
            member.ProgramCohortId = batchId;
            member.ProgramEnrollmentId = pe.Id;

            RejoiningRollInfo rejoining = rejoiningByPe.get(pe.Id);
            if (rejoining != null && String.isNotBlank(rejoining.rollNumber)) {
                member.Roll_Number__c = rejoining.rollNumber;
                member.Serial_Number__c = rejoining.serialNumber;
            } else {
                maxSerial++;
                String serialStr = String.valueOf(maxSerial);
                if (serialStr.length() == 1) {
                    serialStr = '00' + serialStr;
                } else if (serialStr.length() == 2) {
                    serialStr = '0' + serialStr;
                }
                member.Serial_Number__c = maxSerial;
                member.Roll_Number__c =
                    programCode + '-' + batchCode + '-' + serialStr;
            }

            toInsert.add(member);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private class RejoiningRollInfo {
        String rollNumber;
        Decimal serialNumber;

        RejoiningRollInfo(String rollNumber, Decimal serialNumber) {
            this.rollNumber = rollNumber;
            this.serialNumber = serialNumber;
        }
    }

    private static List<ProgramEnrollment> rejoiningEnrollmentsForBatch(
        Id batchId,
        Set<Id> alreadyInThisBatch
    ) {
        Set<Id> peIds = new Set<Id>();
        for (Deferment_Request__c request : [
            SELECT Program_Cohort_Member__r.ProgramEnrollmentId
            FROM Deferment_Request__c
            WHERE Rejoining_Batch__c = :batchId
            AND Program_Cohort_Member__c != null
            AND Program_Cohort_Member__r.ProgramEnrollmentId != null
        ]) {
            Id peId = request.Program_Cohort_Member__r.ProgramEnrollmentId;
            if (!alreadyInThisBatch.contains(peId)) {
                peIds.add(peId);
            }
        }

        if (peIds.isEmpty()) {
            return new List<ProgramEnrollment>();
        }

        return [
            SELECT Id, Student_Name__c, Status
            FROM ProgramEnrollment
            WHERE Id IN :peIds
            ORDER BY Student_Name__c ASC
        ];
    }

    private static Map<Id, RejoiningRollInfo> rejoiningRollByEnrollment(
        Id batchId,
        List<Id> enrollmentIds
    ) {
        Map<Id, RejoiningRollInfo> byPe = new Map<Id, RejoiningRollInfo>();
        if (enrollmentIds == null || enrollmentIds.isEmpty()) {
            return byPe;
        }

        Set<Id> peIdSet = new Set<Id>(enrollmentIds);
        for (Deferment_Request__c request : [
            SELECT Roll_Number__c,
                   Program_Cohort_Member__r.ProgramEnrollmentId,
                   Program_Cohort_Member__r.Roll_Number__c,
                   Program_Cohort_Member__r.Serial_Number__c
            FROM Deferment_Request__c
            WHERE Rejoining_Batch__c = :batchId
            AND Program_Cohort_Member__c != null
            AND Program_Cohort_Member__r.ProgramEnrollmentId IN :peIdSet
        ]) {
            Id peId = request.Program_Cohort_Member__r.ProgramEnrollmentId;
            if (peId == null || byPe.containsKey(peId)) {
                continue;
            }

            String roll = String.isNotBlank(request.Roll_Number__c)
                ? request.Roll_Number__c
                : request.Program_Cohort_Member__r.Roll_Number__c;

            byPe.put(
                peId,
                new RejoiningRollInfo(
                    roll,
                    request.Program_Cohort_Member__r.Serial_Number__c
                )
            );
        }

        return byPe;
    }
}