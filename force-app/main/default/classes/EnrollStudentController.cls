public with sharing class EnrollStudentController {
    
    @AuraEnabled
    public static BatchStudentWrapper getStudentsForBatch(Id batchId) {
       // Get Batch (ProgramCohort) to get its ProgramId and Batch Intake
        ProgramCohort batch = [
            SELECT Id, ProgramId, Batch_Intake__c
            FROM ProgramCohort 
            WHERE Id = :batchId 
            LIMIT 1];
        
       // Step 2: Fetch Program (Intake logic + AICTE flag)
        Program prog = [
          SELECT Programme_Intake__c , Programme_Intake_AICTE__c, Is_AICTE_Approved__c
          FROM Program
          WHERE Id = :batch.ProgramId
          LIMIT 1];
        
        // Get already enrolled student IDs from ProgramCohortMembers for this batch
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
        
        // Define excluded statuses - easily add more statuses here if needed
        Set<String> excludedStatuses = new Set<String>{
            'Enrolled in Batch'
            // Add more excluded statuses here as needed
            // Example: 'Completed', 'Graduated'
        };
        
        // Fetch Program Enrollments with status other than excluded statuses
        // WHERE ProgramId matches Batch's ProgramId
        // AND exclude students who already have ProgramCohortMember records for this batch
        // Ordered by Student Name in ascending order
        List<ProgramEnrollment> TempEnrollments = [
            SELECT Id, Student_Name__c, Status
            FROM ProgramEnrollment
            WHERE ProgramId = :batch.ProgramId
            AND Status NOT IN :excludedStatuses
            AND Id NOT IN :enrolledStudentIds
            ORDER BY Student_Name__c ASC
        ];
        List<Id> enrollmentIds = new List<Id>();

		for (ProgramEnrollment pe : TempEnrollments) {
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
        List<ProgramEnrollment> enrollments = new List<ProgramEnrollment>();

		for (ProgramEnrollment pe : TempEnrollments) {
  		  if (!alreadyEnrolledIds.contains(pe.Id)) {
       		  enrollments.add(pe);
    	}
	}
        
       
        // Build wrapper list for UI display
        // All students are selected by default
        List<ProgramEnrollmentWrapper> students = new List<ProgramEnrollmentWrapper>();
        for (ProgramEnrollment pe : enrollments) {
            students.add(new ProgramEnrollmentWrapper(
                pe.Id,
                pe.Student_Name__c,
                pe.Status,
                true // Default to selected
            ));
        }
        
        // Return wrapper with students and batch information
        BatchStudentWrapper wrapper = new BatchStudentWrapper();
        wrapper.students = students;
        wrapper.batchIntake = batch.Batch_Intake__c != null ? Integer.valueOf(batch.Batch_Intake__c) : null;
        wrapper.currentMemberCount = currentMemberCount;
        
        wrapper.programmeIntake = prog.Programme_Intake__c != null
        ? Integer.valueOf(prog.Programme_Intake__c)
        : 0;

        wrapper.currentProgrammeCount = [
        SELECT COUNT() FROM ProgramCohortMember
        WHERE ProgramEnrollment.ProgramId = :batch.ProgramId];
        
        return wrapper;
    }
    
    public class BatchStudentWrapper {
        @AuraEnabled public List<ProgramEnrollmentWrapper> students;
        @AuraEnabled public Integer batchIntake;
        @AuraEnabled public Integer currentMemberCount;
        @AuraEnabled public Integer programmeIntake;
        @AuraEnabled public Integer currentProgrammeCount;
    }
    
    public class ProgramEnrollmentWrapper {
        @AuraEnabled public Id Id;
        @AuraEnabled public String studentName;
        @AuraEnabled public String Status;
        @AuraEnabled public Boolean Selected;
        
        public ProgramEnrollmentWrapper(Id id, String name, String status, Boolean selected) {
            this.Id = id;
            this.studentName = name;
            this.Status = status;
            this.Selected = selected;
        }
    }
    
    // Save: enroll newly selected; withdraw previously selected but now unselected
    // Inserts students alphabetically and assigns roll numbers alphabetically
      @AuraEnabled
      public static void saveSelectedStudents(
      Id batchId,
      List<Id> selectedStudentIds,
      List<Id> unselectedStudentIdsToWithdraw) {

    if (selectedStudentIds == null) {
        selectedStudentIds = new List<Id>();
    }
    if (unselectedStudentIdsToWithdraw == null) {
        unselectedStudentIdsToWithdraw = new List<Id>();
    }

    /* =========================
       STEP 1: Batch Info
       ========================= */
    ProgramCohort batch = [
        SELECT Id, ProgramId, Batch_Intake__c
        FROM ProgramCohort
        WHERE Id = :batchId
        LIMIT 1
    ];

    /* =========================
       STEP 2: Programme Info
       ========================= */
    Program prog = [
        SELECT Id, Programme_Intake__c ,Programme_Intake_AICTE__c, Is_AICTE_Approved__c
        FROM Program
        WHERE Id = :batch.ProgramId
        LIMIT 1
    ];
          
      // Step 3: Batch intake

    Integer batchIntake = (batch.Batch_Intake__c != null)
        ? Integer.valueOf(batch.Batch_Intake__c)
        : 0;
          
     // Step 4: Program intake logic
        Integer programmeIntake = (prog.Is_AICTE_Approved__c == true)
            ? (prog.Programme_Intake_AICTE__c != null
                ? Integer.valueOf(prog.Programme_Intake_AICTE__c)
                : 0)
            : (prog.Programme_Intake__c != null
                ? Integer.valueOf(prog.Programme_Intake__c)
                : 0);

    /* =========================
       STEP 5: Existing Batch Members
       ========================= */
    Set<Id> existingBatchEnrollments = new Set<Id>();

    for (ProgramCohortMember pcm : [
        SELECT ProgramEnrollmentId
        FROM ProgramCohortMember
        WHERE ProgramCohortId = :batchId
    ]) {
        existingBatchEnrollments.add(pcm.ProgramEnrollmentId);
    }

    /* =========================
       STEP 6: Identify new students only
       ========================= */
    List<Id> newStudentIds = new List<Id>();

    for (Id stuId : selectedStudentIds) {
        if (!existingBatchEnrollments.contains(stuId)) {
            newStudentIds.add(stuId);
        }
    }

    if (newStudentIds.isEmpty()) {
        return;
    }

    /* =========================
       STEP 7: BATCH VALIDATION
       ========================= */
    Integer currentBatchCount = [
        SELECT COUNT()
        FROM ProgramCohortMember
        WHERE ProgramCohortId = :batchId
    ];

    if (currentBatchCount + newStudentIds.size() > batchIntake) {
        Integer remaining = batchIntake - currentBatchCount;
        if (remaining < 0) remaining = 0;

        throw new AuraHandledException(
            'Batch intake exceeded. Only ' + remaining +
            ' slot(s) remaining in this batch.'
        );
    }

    /* =========================
       STEP 8: PROGRAMME VALIDATION (GLOBAL)
       ========================= */
   Integer currentProgrammeCount = [
    SELECT COUNT()
    FROM ProgramCohortMember
    WHERE ProgramEnrollment.ProgramId = :batch.ProgramId];

  Integer requestedSeats = newStudentIds.size();

  if (currentProgrammeCount + requestedSeats > programmeIntake) {

    Integer remaining = programmeIntake - currentProgrammeCount;
    if (remaining < 0) remaining = 0;

    throw new AuraHandledException(
        'Programme intake exceeded. Only ' + remaining +
        ' seat(s) remaining across all batches.'
    );
}

    /* =========================
       STEP 9: Fetch Enrollments
       ========================= */
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

    String batchCode = [
        SELECT Short_Batch_Code__c
        FROM ProgramCohort
        WHERE Id = :batchId
        LIMIT 1
    ].Short_Batch_Code__c;

    String programCode =
        enrollmentsToProcess[0].Program.Short_Programme_Code__c;

    /* =========================
       STEP 10: Serial Number
       ========================= */
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

    /* =========================
       STEP 11: Create Records
       ========================= */
    List<ProgramEnrollment> toUpdate = new List<ProgramEnrollment>();
    List<ProgramCohortMember> toInsert = new List<ProgramCohortMember>();

    for (ProgramEnrollment pe : enrollmentsToProcess) {

        maxSerial++;

        String serialStr = String.valueOf(maxSerial);
        if (serialStr.length() == 1) serialStr = '00' + serialStr;
        else if (serialStr.length() == 2) serialStr = '0' + serialStr;

        String rollNumber =
            programCode + '-' +
            batchCode + '-' +
            serialStr;

        pe.Status = 'Enrolled in Batch';
        toUpdate.add(pe);

        ProgramCohortMember member = new ProgramCohortMember();
        member.ProgramCohortId = batchId;
        member.ProgramEnrollmentId = pe.Id;
        member.Serial_Number__c = maxSerial;
        member.Roll_Number__c = rollNumber;

        toInsert.add(member);
    }
    
    /* =========================
   STEP 10: DML
   ========================= */
try {

    if (!toUpdate.isEmpty()) {
        update toUpdate;
    }

    if (!toInsert.isEmpty()) {
        insert toInsert;
    }

}
catch (DmlException e) {

    throw new AuraHandledException(e.getDmlMessage(0));

}
catch (Exception e) {

    throw new AuraHandledException(e.getMessage());

}

}
}