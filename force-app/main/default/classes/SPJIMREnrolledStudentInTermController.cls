/**
* @description Controller for enrolling students in Academic Term
* @author SPJIMR
* @date 2025
*/
public with sharing class SPJIMREnrolledStudentInTermController {
    
    /**
* @description Fetches students for enrollment based on Term's Previous Term status
* @param termId The AcademicTerm ID
* @return StudentEnrollmentWrapper containing students list and term information
* 
* Logic:
* - If Previous Term is blank: Fetch all ProgramCohortMembers for the Batch
* - If Previous Term is NOT blank: Fetch AcademicTermEnrollments from previous term (only Active students)
*/
    @AuraEnabled
    public static StudentEnrollmentWrapper getStudentsForTerm(Id termId) {
        StudentEnrollmentWrapper wrapper = new StudentEnrollmentWrapper();
        
        try {
            // Fetch Term with Previous Term, Batch, and Auto Create Fundamental Division information
            AcademicTerm term = [
                SELECT Id, SPJIMR_Previous_term__c, 
                Term_End_Date__c,
                AcademicYear.Batch__c,
                AcademicYear.Batch__r.CurrentMemberCount,
                SPJIMR_Auto_create_fundamental_division__c
                FROM AcademicTerm 
                WHERE Id = :termId 
                LIMIT 1
            ];
            
            // Set wrapper properties
            wrapper.isPreviousTermBlank = (term.SPJIMR_Previous_term__c == null);
            wrapper.batchId = term.AcademicYear.Batch__c;
            wrapper.previousTermId = term.SPJIMR_Previous_term__c;
            wrapper.autoCreateFundamentalDivision = term.SPJIMR_Auto_create_fundamental_division__c == true;
            wrapper.termEndDate = term.Term_End_Date__c;

            // ✅ ADD THIS BLOCK
            wrapper.batchStudentCount = 
                term.AcademicYear.Batch__r != null && term.AcademicYear.Batch__r.CurrentMemberCount != null
                ? Integer.valueOf(term.AcademicYear.Batch__r.CurrentMemberCount)
                : 0;
            
            // Scenario 1: Previous Term is blank - Get all ProgramCohortMembers for the Batch
            // Filter out students already enrolled in current term
            if (wrapper.isPreviousTermBlank && wrapper.batchId != null) {
                wrapper.students = getProgramCohortMembersForBatch(wrapper.batchId, termId);
            } 
            // Scenario 2: Previous Term is NOT blank - Get AcademicTermEnrollments from previous term
            // Filter out students already enrolled in current term
            else if (!wrapper.isPreviousTermBlank && wrapper.previousTermId != null) {
                wrapper.students = getTermEnrollmentsFromPreviousTerm(wrapper.previousTermId, termId);
            } 
            // Scenario 3: No valid data - Return empty list
            else {
                wrapper.students = new List<StudentWrapper>();
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching students: ' + e.getMessage());
        }
        
        return wrapper;
    }
    
    /**
* @description Helper method to fetch ProgramCohortMembers for a Batch
* Filters out students already enrolled in the current term
* @param batchId The Batch (ProgramCohort) ID
* @param termId The current AcademicTerm ID to check against
* @return List of StudentWrapper objects (all pre-selected) that are not already enrolled
*/
    private static List<StudentWrapper> getProgramCohortMembersForBatch(Id batchId, Id termId) {
        // Query ProgramCohortMembers for the batch and get related ProgramEnrollment data
        List<ProgramCohortMember> cohortMembers = [
            SELECT Id, ProgramEnrollmentId, Roll_Number__c,
            ProgramEnrollment.Id, 
            ProgramEnrollment.Name,
            ProgramEnrollment.Student_Name__c, 
            ProgramEnrollment.AccountId, 
            ProgramEnrollment.Account.PersonContact.Id
            FROM ProgramCohortMember
            WHERE ProgramCohortId = :batchId
            AND ProgramEnrollmentId != null
            AND ProgramEnrollment.AccountId != null
            AND ProgramEnrollment.Account.PersonContact.Id != null
            ORDER BY ProgramEnrollment.Student_Name__c, Roll_Number__c
        ];
        
        if (cohortMembers.isEmpty()) {
            return new List<StudentWrapper>();
        }
        
        // Build sets for checking existing enrollments (single loop optimization)
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (ProgramCohortMember pcm : cohortMembers) {
            if (pcm.ProgramEnrollment != null && pcm.ProgramEnrollment.AccountId != null) {
                accountIds.add(pcm.ProgramEnrollment.AccountId);
                if (pcm.ProgramEnrollment.Account != null && pcm.ProgramEnrollment.Account.PersonContact != null) {
                    contactIds.add(pcm.ProgramEnrollment.Account.PersonContact.Id);
                }
            }
        }
        
        // Get existing AcademicTermEnrollments for this term
        Set<String> existingKeys = getExistingEnrollmentKeys(termId, accountIds, contactIds);
        
        // Filter and build StudentWrapper in single loop (optimized key building)
        List<StudentWrapper> students = new List<StudentWrapper>();
        String termIdStr = String.valueOf(termId);
        for (ProgramCohortMember pcm : cohortMembers) {
            if (pcm.ProgramEnrollment != null && 
                pcm.ProgramEnrollment.AccountId != null && 
                pcm.ProgramEnrollment.Account != null && 
                pcm.ProgramEnrollment.Account.PersonContact != null) {
                    
                    String key = termIdStr + '_' + pcm.ProgramEnrollment.AccountId + '_' + pcm.ProgramEnrollment.Account.PersonContact.Id;
                    if (!existingKeys.contains(key)) {
                        StudentWrapper sw = new StudentWrapper();
                        sw.enrollmentId = pcm.Id; // Store ProgramCohortMember ID instead of ProgramEnrollment ID
                        sw.studentName = String.isNotBlank(pcm.ProgramEnrollment.Student_Name__c) 
                            ? pcm.ProgramEnrollment.Student_Name__c 
                            : pcm.ProgramEnrollment.Name;
                        sw.rollNumber = String.isNotBlank(pcm.Roll_Number__c) 
                            ? pcm.Roll_Number__c 
                            : '';
                        sw.selected = true;
                        students.add(sw);
                    }
                }
        }
        
        return students;
    }
    
    /**
* @description Helper method to fetch AcademicTermEnrollments from previous term
* Filters out students that are already enrolled in the current term
* @param previousTermId The Previous AcademicTerm ID
* @param currentTermId The Current AcademicTerm ID to check against
* @return List of StudentWrapper objects (pre-selected) that are not already enrolled in current term
*/
    public static List<StudentWrapper> getTermEnrollmentsFromPreviousTerm(Id previousTermId, Id currentTermId) {
        // Fetch AcademicTermEnrollments from previous term
        List<AcademicTermEnrollment> termEnrollments = [
            SELECT Id, LearnerAccountId, LearnerContactId, Program_Enrolled__c, Batch_Enrollment__c,
            LearnerAccount.Name, Program_Enrolled__r.Student_Name__c,
            Program_Enrolled__r.Roll_Number__c, Batch_Enrollment__r.Roll_Number__c
            FROM AcademicTermEnrollment
            WHERE AcademicTermId = :previousTermId
            AND LearnerAccountId != null
            AND LearnerContactId != null
            ORDER BY LearnerAccount.Name, Batch_Enrollment__r.Roll_Number__c
        ];
        
        if (termEnrollments.isEmpty()) {
            return new List<StudentWrapper>();
        }
        
        // Build sets for checking existing enrollments in current term (single loop optimization)
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (AcademicTermEnrollment ate : termEnrollments) {
            accountIds.add(ate.LearnerAccountId);
            contactIds.add(ate.LearnerContactId);
        }
        
        // Get existing AcademicTermEnrollments for current term
        Set<String> existingKeys = getExistingEnrollmentKeys(currentTermId, accountIds, contactIds);
        
        // Filter and build StudentWrapper in single loop (optimized key building)
        List<StudentWrapper> students = new List<StudentWrapper>();
        String currentTermIdStr = String.valueOf(currentTermId);
        for (AcademicTermEnrollment ate : termEnrollments) {
            String key = currentTermIdStr + '_' + ate.LearnerAccountId + '_' + ate.LearnerContactId;
            if (!existingKeys.contains(key)) {
                StudentWrapper sw = new StudentWrapper();
                sw.enrollmentId = ate.Program_Enrolled__c;
                sw.academicTermEnrollmentId = ate.Id;
                sw.studentName = String.isNotBlank(ate.Program_Enrolled__r.Student_Name__c) 
                    ? ate.Program_Enrolled__r.Student_Name__c 
                    : (String.isNotBlank(ate.LearnerAccount.Name) ? ate.LearnerAccount.Name : '');
                        // Get roll number from Batch Enrollment (ProgramCohortMember) instead of Program Enrollment
                        sw.rollNumber = (ate.Batch_Enrollment__r != null && String.isNotBlank(ate.Batch_Enrollment__r.Roll_Number__c))
                        ? ate.Batch_Enrollment__r.Roll_Number__c
                        : (String.isNotBlank(ate.Program_Enrolled__r.Roll_Number__c) 
                           ? ate.Program_Enrolled__r.Roll_Number__c 
                           : '');
                               sw.selected = true;
                students.add(sw);
            }
        }
        
        return students;
    }
    
    /**
* @description Creates AcademicTermEnrollment records for selected students
* Handles two scenarios:
* 1. Previous Term is blank: Creates from ProgramCohortMember IDs
* 2. Previous Term is NOT blank: Creates from previous term's AcademicTermEnrollment IDs
* 
* @param termId The AcademicTerm ID where students will be enrolled
* @param enrollmentIds List of IDs (ProgramCohortMember IDs when previous term is blank, AcademicTermEnrollment IDs when previous term is NOT blank)
* @param batchId The Batch ID for the current term
* @param isPreviousTermBlank Boolean flag to determine which scenario
* @param divisionCreationOption Division creation option ('previousTermDivision' or 'newDivision')
* @param divisions List of DivisionWrapper objects to save/update (when creating new divisions)
* @return Integer The count of records actually inserted (may be less than enrollmentIds size due to duplicates or missing data)
*/
    @AuraEnabled
    public static Integer createTermEnrollments(Id termId, List<Id> enrollmentIds, Id batchId, Boolean isPreviousTermBlank, String divisionCreationOption, List<DivisionWrapper> divisions, Boolean autoCreateFundamentalDivision) {
        // Input validation
        if (termId == null) {
            throw new AuraHandledException('Term ID is required');
        }
        
        if (enrollmentIds == null || enrollmentIds.isEmpty()) {
            String errorMsg = isPreviousTermBlank 
                ? 'At least one Program Cohort Member is required'
                : 'At least one AcademicTermEnrollment is required';
            throw new AuraHandledException(errorMsg);
        }
        
        try {
            List<AcademicTermEnrollment> enrollmentsToInsert;
            Id previousTermId = null;
            
            // Get previous term ID if previous term is not blank
            if (!isPreviousTermBlank) {
                AcademicTerm term = [SELECT SPJIMR_Previous_term__c FROM AcademicTerm WHERE Id = :termId LIMIT 1];
                previousTermId = term.SPJIMR_Previous_term__c;
                
                // Create divisions from previous term if option is selected
                if (previousTermId != null && String.isNotBlank(divisionCreationOption) && divisionCreationOption == 'previousTermDivision') {
                    createDivisionsFromPreviousTerm(termId, previousTermId);
                }
            }
            
            // Save/update divisions if "Create new division" option is selected OR previous term is blank with divisions
            Boolean divisionsSaved = false;
            if (divisions != null && !divisions.isEmpty()) {
                if (String.isNotBlank(divisionCreationOption) && divisionCreationOption == 'newDivision') {
                    saveDivisions(termId, divisions);
                    divisionsSaved = true;
                } else if (isPreviousTermBlank) {
                    // When previous term is blank, save divisions if provided
                    saveDivisions(termId, divisions);
                    divisionsSaved = true;
                }
            }
            
            // Scenario 1: Previous Term is blank - Create from ProgramCohortMember IDs
            if (isPreviousTermBlank) {
                enrollmentsToInsert = createFromProgramEnrollments(termId, enrollmentIds);
            } 
            // Scenario 2: Previous Term is NOT blank - Create from previous term's AcademicTermEnrollment IDs
            else {
                enrollmentsToInsert = createFromPreviousTermEnrollments(termId, enrollmentIds, previousTermId, divisionCreationOption);
            }
            
            // Bulk insert new enrollments
            Integer insertedCount = 0;
            List<Id> insertedEnrollmentIds = new List<Id>();
            if (!enrollmentsToInsert.isEmpty()) {
                for (AcademicTermEnrollment ate : enrollmentsToInsert) {
                }
                insert enrollmentsToInsert;
                insertedCount = enrollmentsToInsert.size();
                
                // Collect inserted enrollment IDs for division enrollment creation
                for (AcademicTermEnrollment ate : enrollmentsToInsert) {
                    insertedEnrollmentIds.add(ate.Id);
                }
                
            }
            
            return insertedCount;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating term enrollments: ' + e.getMessage());
        }
    }
    
    /**
* @description Creates AcademicTermEnrollment records from ProgramCohortMember IDs
* Used when Previous Term is blank
*/
    private static List<AcademicTermEnrollment> createFromProgramEnrollments(Id termId, List<Id> programCohortMemberIds) {
        
        // Fetch ProgramCohortMembers with related ProgramEnrollment, Account and Contact
        List<ProgramCohortMember> cohortMembers = [
            SELECT Id, ProgramEnrollmentId, 
            ProgramEnrollment.Id, 
            ProgramEnrollment.AccountId, 
            ProgramEnrollment.Account.PersonContact.Id
            FROM ProgramCohortMember
            WHERE Id IN :programCohortMemberIds
            AND ProgramEnrollmentId != null
            AND ProgramEnrollment.AccountId != null
            AND ProgramEnrollment.Account.PersonContact.Id != null
        ];
        
        
        if (cohortMembers.isEmpty()) {
            return new List<AcademicTermEnrollment>();
        }
        
        // Build sets for duplicate checking (optimized - removed redundant null checks)
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (ProgramCohortMember pcm : cohortMembers) {
            if (pcm.ProgramEnrollment != null && 
                pcm.ProgramEnrollment.AccountId != null && 
                pcm.ProgramEnrollment.Account != null && 
                pcm.ProgramEnrollment.Account.PersonContact != null) {
                    accountIds.add(pcm.ProgramEnrollment.AccountId);
                    contactIds.add(pcm.ProgramEnrollment.Account.PersonContact.Id);
                }
        }
        
        
        // Check for existing AcademicTermEnrollments to prevent duplicates
        Set<String> existingKeys = getExistingEnrollmentKeys(termId, accountIds, contactIds);
        
        // Create new AcademicTermEnrollment records (optimized key building)
        List<AcademicTermEnrollment> enrollmentsToInsert = new List<AcademicTermEnrollment>();
        String termIdStr = String.valueOf(termId);
        for (ProgramCohortMember pcm : cohortMembers) {
            if (pcm.ProgramEnrollment != null && 
                pcm.ProgramEnrollment.AccountId != null && 
                pcm.ProgramEnrollment.Account != null && 
                pcm.ProgramEnrollment.Account.PersonContact != null) {
                    String key = termIdStr + '_' + pcm.ProgramEnrollment.AccountId + '_' + pcm.ProgramEnrollment.Account.PersonContact.Id;
                    if (!existingKeys.contains(key)) {
                        AcademicTermEnrollment ate = new AcademicTermEnrollment();
                        ate.AcademicTermId = termId;
                        ate.LearnerAccountId = pcm.ProgramEnrollment.AccountId;
                        ate.Program_Enrolled__c = pcm.ProgramEnrollment.Id;
                        ate.LearnerContactId = pcm.ProgramEnrollment.Account.PersonContact.Id;
                        ate.Batch_Enrollment__c = pcm.Id; // Populate Batch Enrollment with ProgramCohortMember ID
                        enrollmentsToInsert.add(ate);
                    }
                }
        }
        
        return enrollmentsToInsert;
    }
    
    /**
* @description Creates AcademicTermEnrollment records from previous term's AcademicTermEnrollment IDs
* Used when Previous Term is NOT blank
* Copies data from previous term enrollment and updates Term to current term
* Program_Enrolled__c is copied if it exists in previous term enrollment, otherwise left null
* If divisionCreationOption is 'previousTermDivision', assigns Division__c based on previous term
* @param termId Current term ID
* @param academicTermEnrollmentIds List of previous term AcademicTermEnrollment IDs
* @param previousTermId Previous term ID
* @param divisionCreationOption Division creation option
*/
    private static List<AcademicTermEnrollment> createFromPreviousTermEnrollments(Id termId, List<Id> academicTermEnrollmentIds, Id previousTermId, String divisionCreationOption) {
        
        // Fetch previous term's AcademicTermEnrollment records with Division and Batch Enrollment
        List<AcademicTermEnrollment> previousEnrollments = [
            SELECT Id, LearnerAccountId, LearnerContactId, Program_Enrolled__c, Batch_Enrollment__c, Division__c, Division__r.Division_Name__c
            FROM AcademicTermEnrollment
            WHERE Id IN :academicTermEnrollmentIds
        ];
        
        if (previousEnrollments.isEmpty()) {
            return new List<AcademicTermEnrollment>();
        }
        
        // Build division mapping if creating divisions from previous term
        Map<String, Id> divisionNameToIdMap = new Map<String, Id>();
        if (String.isNotBlank(divisionCreationOption) && divisionCreationOption == 'previousTermDivision' && previousTermId != null) {
            // Query current term divisions created from previous term
            List<Division__c> currentTermDivisions = [
                SELECT Id, Division_Name__c
                FROM Division__c
                WHERE Term__c = :termId
            ];
            for (Division__c div : currentTermDivisions) {
                if (String.isNotBlank(div.Division_Name__c)) {
                    divisionNameToIdMap.put(div.Division_Name__c, div.Id);
                }
            }
        }
        
        // Build sets for duplicate checking (optimized - removed redundant null checks)
        Set<Id> accountIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        for (AcademicTermEnrollment ate : previousEnrollments) {
            accountIds.add(ate.LearnerAccountId);
            contactIds.add(ate.LearnerContactId);
        }
        
        
        // Check for existing AcademicTermEnrollments to prevent duplicates
        Set<String> existingKeys = getExistingEnrollmentKeys(termId, accountIds, contactIds);
        
        // Create new AcademicTermEnrollment records for current term (optimized - removed redundant null checks)
        List<AcademicTermEnrollment> enrollmentsToInsert = new List<AcademicTermEnrollment>();
        String termIdStr = String.valueOf(termId);
        for (AcademicTermEnrollment previousAte : previousEnrollments) {
            String key = termIdStr + '_' + previousAte.LearnerAccountId + '_' + previousAte.LearnerContactId;
            if (!existingKeys.contains(key)) {
                AcademicTermEnrollment newAte = new AcademicTermEnrollment();
                newAte.AcademicTermId = termId;
                newAte.LearnerAccountId = previousAte.LearnerAccountId;
                newAte.LearnerContactId = previousAte.LearnerContactId;
                // Assign division only if not using noDivision option
                if (divisionCreationOption != 'noDivision') {
                    newAte.Division__c = previousAte.Division__c;
                }
                if (previousAte.Program_Enrolled__c != null) {
                    newAte.Program_Enrolled__c = previousAte.Program_Enrolled__c;
                }
                // Copy Batch Enrollment from previous term
                if (previousAte.Batch_Enrollment__c != null) {
                    newAte.Batch_Enrollment__c = previousAte.Batch_Enrollment__c;
                }
                
                // Assign division if creating from previous term and division exists
                if (String.isNotBlank(divisionCreationOption) && divisionCreationOption == 'previousTermDivision' && 
                    previousAte.Division__r != null && String.isNotBlank(previousAte.Division__r.Division_Name__c)) {
                        Id divisionId = divisionNameToIdMap.get(previousAte.Division__r.Division_Name__c);
                        if (divisionId != null) {
                            newAte.Division__c = divisionId;
                        }
                    }
                
                enrollmentsToInsert.add(newAte);
            }
        }
        
        return enrollmentsToInsert;
    }
    
    /**
* @description Creates Division records for current term based on previous term divisions
* @param currentTermId Current term ID
* @param previousTermId Previous term ID
*/
    private static void createDivisionsFromPreviousTerm(Id currentTermId, Id previousTermId) {
        
        // Query divisions from previous term
        List<Division__c> previousTermDivisions = [
            SELECT Id, Division_Name__c, Capacity__c, Is_Active__c,
            Division_Group__c, SPJIMR_Division_Code__c, Division_Color__c
            FROM Division__c
            WHERE Term__c = :previousTermId
            AND Is_Active__c = true
            ORDER BY Division_Name__c
        ];
        
        if (previousTermDivisions.isEmpty()) {
            return;
        }
        
        // Check if divisions already exist for current term
        List<Division__c> existingDivisions = [
            SELECT Id, Division_Name__c
            FROM Division__c
            WHERE Term__c = :currentTermId
            AND Is_Active__c = true
        ];
        
        Map<String, Division__c> existingDivisionMap = new Map<String, Division__c>();
        for (Division__c div : existingDivisions) {
            if (String.isNotBlank(div.Division_Name__c)) {
                existingDivisionMap.put(div.Division_Name__c, div);
            }
        }
        
        // Create new divisions for current term based on previous term
        List<Division__c> divisionsToInsert = new List<Division__c>();
        for (Division__c previousDiv : previousTermDivisions) {
            // Skip if division with same name already exists
            if (String.isNotBlank(previousDiv.Division_Name__c) && 
                !existingDivisionMap.containsKey(previousDiv.Division_Name__c)) {
                    Division__c newDiv = new Division__c();
                    newDiv.Term__c = currentTermId;
                    newDiv.Division_Name__c = previousDiv.Division_Name__c;
                    newDiv.Capacity__c = previousDiv.Capacity__c;
                    newDiv.Is_Active__c = previousDiv.Is_Active__c != null ? previousDiv.Is_Active__c : true;
                    if (previousDiv.Division_Group__c != null) {
                        newDiv.Division_Group__c = previousDiv.Division_Group__c;
                    }
                    if (String.isNotBlank(previousDiv.Division_Group__c)) {
                        newDiv.Division_Group__c = previousDiv.Division_Group__c;
                    }
                    if (String.isNotBlank(previousDiv.SPJIMR_Division_Code__c)) {
                        newDiv.SPJIMR_Division_Code__c = previousDiv.SPJIMR_Division_Code__c;
                    }
                    if (String.isNotBlank(previousDiv.Division_Color__c)) {
                        newDiv.Division_Color__c = previousDiv.Division_Color__c;
                    }
                    divisionsToInsert.add(newDiv);
                }
        }
        
        if (!divisionsToInsert.isEmpty()) {
            insert divisionsToInsert;
        }
    }
    
    
    /**
* @description Helper method to get existing enrollment keys for duplicate prevention
* @param termId The AcademicTerm ID
* @param accountIds Set of Account IDs to check
* @param contactIds Set of Contact IDs to check
* @return Set of existing enrollment keys (format: TermId_AccountId_ContactId)
*/
    private static Set<String> getExistingEnrollmentKeys(Id termId, Set<Id> accountIds, Set<Id> contactIds) {
        Set<String> existingKeys = new Set<String>();
        
        if (accountIds.isEmpty() || contactIds.isEmpty()) {
            return existingKeys;
        }
        
        // Query existing enrollments for this term with matching accounts and contacts
        List<AcademicTermEnrollment> existingEnrollments = [
            SELECT Id, LearnerAccountId, LearnerContactId
            FROM AcademicTermEnrollment
            WHERE AcademicTermId = :termId
            AND LearnerAccountId IN :accountIds
            AND LearnerContactId IN :contactIds
        ];
        
        // Build keys: TermId_AccountId_ContactId (optimized - removed debug from loop)
        String termIdStr = String.valueOf(termId);
        for (AcademicTermEnrollment ate : existingEnrollments) {
            existingKeys.add(termIdStr + '_' + ate.LearnerAccountId + '_' + ate.LearnerContactId);
        }
        
        return existingKeys;
    }
    
    /**
* @description Fetches all Division Groups for selection
* @return List of OptionWrapper objects
*/
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getDivisionGroups() {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            List<Division_Group__c> divisionGroups = [
                SELECT Id, Name
                FROM Division_Group__c
                ORDER BY Name
            ];
            
            for (Division_Group__c dg : divisionGroups) {
                options.add(new OptionWrapper(dg.Id, dg.Name));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching division groups: ' + e.getMessage());
        }
        
        return options;
    }
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getDivisionColorPicklistOptions() {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            Schema.DescribeFieldResult fieldResult = Division__c.Division_Color__c.getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldResult.getPicklistValues();
            
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    options.add(new OptionWrapper(entry.getValue(), entry.getLabel()));
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching division color options: ' + e.getMessage());
        }
        
        return options;
    }
    /* @description Fetches active Specialisations related to the selected Batch
 * and returns them as dropdown options for Division Specialisation selection
 * @param batchId The Batch ID
 * @return List of OptionWrapper containing Specialisation Id and Name
 */
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getBatchSpecialisations(Id batchId) {
        
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        for (Specialisation__c spec : [
            SELECT Id,
            Specialisation_Name__r.Name
            FROM Specialisation__c
            WHERE Batch__c = :batchId
            AND Is_Active__c = true
            ORDER BY Specialisation_Name__r.Name
        ]) {
            
            options.add(
                new OptionWrapper(
                    spec.Id,
                    spec.Specialisation_Name__r.Name
                )
            );
        }
        
        return options;
    }
    /**
* @description Fetches fundamental divisions for a term
* @param termId The AcademicTerm ID
* @return List of DivisionWrapper objects
*/
    @AuraEnabled
    public static List<DivisionWrapper> getFundamentalDivisions(Id termId) {
        List<DivisionWrapper> divisions = new List<DivisionWrapper>();
        
        try {
            List<Division__c> fundamentalDivisions = [
                SELECT Id, Division_Group__c, Is_Active__c, Capacity__c, SPJIMR_Division_Code__c,Division_Color__c,
                Division_Group__r.Name,SPJIMR_Specialisation__c,SPJIMR_Specialisation__r.Name
                FROM Division__c
                WHERE Term__c = :termId
                AND Division_Group__c != null
                AND Is_Active__c = true
                ORDER BY Division_Name__c
            ];
            
            for (Division__c div : fundamentalDivisions) {
                DivisionWrapper dw = new DivisionWrapper();
                dw.divisionId = div.Id;
                dw.divisionGroup = div.Division_Group__r != null ? div.Division_Group__r.Name : '';
                dw.divisionGroupId = div.Division_Group__c;
                dw.isActive = div.Is_Active__c != null ? div.Is_Active__c : true;
                dw.capacity = div.Capacity__c != null ? div.Capacity__c : 0;
                dw.divisionCode = div.SPJIMR_Division_Code__c != null ? div.SPJIMR_Division_Code__c : '';
                dw.divisionColor = div.Division_Color__c != null ? div.Division_Color__c : '';
                // NEW FIELDS
                dw.specialisationId = div.SPJIMR_Specialisation__c;
                dw.specialisationName = div.SPJIMR_Specialisation__r != null ? div.SPJIMR_Specialisation__r.Name : '';
                // SHOW SPECIALISATION FIELD
                dw.showSpecialisation = dw.divisionGroup != null && dw.divisionGroup.contains('Specialisation');
                divisions.add(dw);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching fundamental divisions: ' + e.getMessage());
        }
        
        return divisions;
    }
    
    /**
* @description Saves or updates Division records for a term
* Updates existing divisions and inserts new ones, ensuring Term__c is set on all
* @param termId The AcademicTerm ID
* @param divisions List of DivisionWrapper objects containing division data
* @return Map<String, Object> containing success status and division mapping (divisionId -> newDivisionId for new divisions)
*/
    @AuraEnabled
    public static Map<String, Object> saveDivisions(Id termId, List<DivisionWrapper> divisions) {
        Map<String, Object> result = new Map<String, Object>();
        Map<Id, Id> oldToNewDivisionMap = new Map<Id, Id>(); // For tracking new division IDs if needed
        
        try {
            if (termId == null) {
                throw new AuraHandledException('Term ID is required');
            }
            
            if (divisions == null || divisions.isEmpty()) {
                result.put('success', true);
                result.put('message', 'No divisions to save');
                return result;
            }
            
            // Separate existing divisions (with divisionId) from new divisions (without divisionId)
            List<Division__c> divisionsToUpdate = new List<Division__c>();
            List<Division__c> divisionsToInsert = new List<Division__c>();
            
            Integer existingDivisionCount = [
                SELECT COUNT() FROM Division__c 
                WHERE Term__c = :termId
            ];
            
            for (DivisionWrapper dw : divisions) {
                Division__c div = new Division__c();
                
                // Set Term__c on all divisions
                div.Term__c = termId;
                
                if (dw.divisionId != null) {
                    // ✅ UPDATE existing division
                    div.Id = dw.divisionId;
                    div.Division_Group__c = dw.divisionGroupId;
                    div.Is_Active__c = dw.isActive != null ? dw.isActive : true;
                    div.Capacity__c = dw.capacity != null ? dw.capacity : 0;
                    div.SPJIMR_Specialisation__c = dw.specialisationId;
                    if (String.isNotBlank(dw.divisionColor)) {
                        div.Division_Color__c = dw.divisionColor;
                    }
                    divisionsToUpdate.add(div); // ✅ was missing
                } else {
                    // ✅ INSERT new division
                    div.Division_Group__c = dw.divisionGroupId;
                    div.Is_Active__c = dw.isActive != null ? dw.isActive : true;
                    div.Capacity__c = dw.capacity != null ? dw.capacity : 0;
                    div.SPJIMR_Specialisation__c = dw.specialisationId;
                    if (String.isNotBlank(dw.divisionColor)) {
                        div.Division_Color__c = dw.divisionColor;
                    }
                    // ✅ Auto-assign Division Name as A, B, C... based on sequence
                    
                    String divisionLetter = String.fromCharArray(new List<Integer>{ 65 + existingDivisionCount + divisionsToInsert.size() });
                    div.Division_Name__c = divisionLetter;
                    divisionsToInsert.add(div);
                }
            }
            
            // Update existing divisions
            if (!divisionsToUpdate.isEmpty()) {
                update divisionsToUpdate;
            }
            
            // Insert new divisions
            if (!divisionsToInsert.isEmpty()) {
                insert divisionsToInsert;
            }
            
            result.put('success', true);
            result.put('updatedCount', divisionsToUpdate.size());
            result.put('insertedCount', divisionsToInsert.size());
            result.put('message', 'Divisions saved successfully');
            
        } catch (Exception e) {
            throw new AuraHandledException('Error saving divisions: ' + e.getMessage());
        }
        
        return result;
    }
    
    /**
* @description Wrapper class to return term and student enrollment information
*/
    public class StudentEnrollmentWrapper {
        @AuraEnabled public Boolean isPreviousTermBlank {get; set;}
        @AuraEnabled public Id batchId {get; set;}
        @AuraEnabled public Id previousTermId {get; set;}
        @AuraEnabled public Boolean autoCreateFundamentalDivision {get; set;}
        @AuraEnabled public List<StudentWrapper> students {get; set;}
        @AuraEnabled public Integer batchStudentCount {get; set;}
        @AuraEnabled public Date termEndDate {get; set;}
    }
    
    /**
* @description Wrapper class for Division information
*/
    public class DivisionWrapper {
        @AuraEnabled public Id divisionId {get; set;}
        @AuraEnabled public String divisionGroup {get; set;}
        @AuraEnabled public Id divisionGroupId {get; set;}
        @AuraEnabled public Boolean isActive {get; set;}
        @AuraEnabled public Decimal capacity {get; set;}
        @AuraEnabled public String divisionCode {get; set;}
        @AuraEnabled public String divisionColor {get; set;}  // ✅ ADD THIS
        @AuraEnabled public String divisionName {get; set;}   // ✅ ADD THIS
        @AuraEnabled public Id specialisationId {get; set;}
        @AuraEnabled public String specialisationName {get; set;}
        @AuraEnabled public Boolean showSpecialisation {get; set;}
    }
    /**
* @description Wrapper class for individual student information
*/
    public class StudentWrapper {
        @AuraEnabled public Id enrollmentId {get; set;} // ProgramCohortMember ID (when previous term is blank) or ProgramEnrollment ID (when from previous term)
        @AuraEnabled public Id academicTermEnrollmentId {get; set;} // AcademicTermEnrollment ID (if from previous term)
        @AuraEnabled public String studentName {get; set;}
        @AuraEnabled public String rollNumber {get; set;}
        @AuraEnabled public Boolean selected {get; set;} // Checkbox selection state
    }
    
    /**
* @description Wrapper class for option values (Id and Label)
*/
    public class OptionWrapper {
        @AuraEnabled public String value {get; set;}
        @AuraEnabled public String label {get; set;}
        
        public OptionWrapper(String value, String label) {
            this.value = value;
            this.label = label;
        }
    }
}