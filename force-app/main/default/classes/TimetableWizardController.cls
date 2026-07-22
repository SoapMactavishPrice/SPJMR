public with sharing class TimetableWizardController {
    
    /**
    Test
     * Returns programs for the timetable program dropdown.
     * - If the current user is a member of at least one Program Team (Program_Team_Members__c),
     *   only programs linked to those teams are returned.
     * - If the user is not on any program team, all active programs are returned (backward compatibility).
     * - defaultProgramId is set when exactly one program is returned, so the LWC can preselect it.
     */
    @AuraEnabled(cacheable=true)
    public static ProgramOptionsResult getPrograms() {
        List<OptionWrapper> options = new List<OptionWrapper>();
        String defaultProgramId = null;
        Id currentUserId = UserInfo.getUserId();

        try {
            // Get distinct Program IDs from Program_Team_Members__c for the current user
            Set<Id> programIdsForUser = new Set<Id>();
            for (Program_Team_Members__c ptm : [
                SELECT Program_Team__r.Program__c
                FROM Program_Team_Members__c
                WHERE User__c = :currentUserId
                  AND Program_Team__r.Program__c != null
            ]) {
                programIdsForUser.add(ptm.Program_Team__r.Program__c);
            }

            List<Program> programs;
            if (!programIdsForUser.isEmpty()) {
                programs = [
                    SELECT Id, Name
                    FROM Program
                    WHERE Id IN :programIdsForUser
                      AND IsActive = true
                    ORDER BY Name
                ];
            } else {
                // User not on any program team: show all active programs (e.g. admins)
                programs = [
                    SELECT Id, Name
                    FROM Program
                    WHERE IsActive = true
                    ORDER BY Name
                ];
            }

            for (Program program : programs) {
                options.add(new OptionWrapper(program.Id, program.Name));
            }
            if (options.size() == 1 && options[0].value != null) {
                defaultProgramId = options[0].value;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching programs: ' + e.getMessage());
        }

        return new ProgramOptionsResult(options, defaultProgramId);
    }

    /** Result wrapper for getPrograms: options list + optional default program id when user has exactly one program. */
    public class ProgramOptionsResult {
        @AuraEnabled public List<OptionWrapper> options;
        @AuraEnabled public String defaultProgramId;
        public ProgramOptionsResult(List<OptionWrapper> options, String defaultProgramId) {
            this.options = options;
            this.defaultProgramId = defaultProgramId;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getAllDivisions() {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            // Get all divisions from Division__c
            List<Division__c> divisions = [
                SELECT Id, Division_Name__c
                FROM Division__c
                ORDER BY Division_Name__c
            ];
            
            // Extract unique division labels
            Set<String> uniqueDivisions = new Set<String>();
            for (Division__c div : divisions) {
                if (div.Division_Name__c != null) {
                    if (!uniqueDivisions.contains(div.Division_Name__c)) {
                        uniqueDivisions.add(div.Division_Name__c);
                        options.add(new OptionWrapper(div.Id, div.Division_Name__c));
                    }
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching all divisions: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getAllTerms() {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            List<AcademicTerm> terms = [
                SELECT Id, Name
                FROM AcademicTerm
                ORDER BY Name
            ];
            
            for (AcademicTerm term : terms) {
                options.add(new OptionWrapper(term.Id, term.Name));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching all terms: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getTermsForPrograms(List<Id> programIds) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            if (programIds == null || programIds.isEmpty()) {
                return options;
            }
            
            // Program → ProgramCohort → AcademicYear → AcademicTerm
            // Get all ProgramCohorts for the selected programs
            List<ProgramCohort> cohorts = [
                SELECT Id
                FROM ProgramCohort
                WHERE ProgramId IN :programIds
            ];
            
            Set<Id> cohortIds = new Set<Id>();
            for (ProgramCohort cohort : cohorts) {
                cohortIds.add(cohort.Id);
            }
            
            if (cohortIds.isEmpty()) {
                return options;
            }
            
            // Get AcademicYears for these cohorts
            List<AcademicYear> academicYears = [
                SELECT Id
                FROM AcademicYear
                WHERE Batch__c IN :cohortIds
            ];
            
            Set<Id> academicYearIds = new Set<Id>();
            for (AcademicYear year : academicYears) {
                academicYearIds.add(year.Id);
            }
            
            if (academicYearIds.isEmpty()) {
                return options;
            }
            
            // Get all AcademicTerms for these AcademicYears
            List<AcademicTerm> allTerms = [
                SELECT Id, Name
                FROM AcademicTerm
                WHERE AcademicYearId IN :academicYearIds
                ORDER BY Name
            ];
            
            // Use a Set to avoid duplicates
            Set<Id> uniqueTermIds = new Set<Id>();
            for (AcademicTerm term : allTerms) {
                if (!uniqueTermIds.contains(term.Id)) {
                    uniqueTermIds.add(term.Id);
                    options.add(new OptionWrapper(term.Id, term.Name));
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching terms for programs: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getBatchesForProgram(Id programId) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            if (programId == null) {
                return options;
            }
            
            // Get ProgramCohorts (Batches) for the selected program
            List<ProgramCohort> batches = [
                SELECT Id, Name, Session_Duration__c, Allow_Multi_Program_Batch__c
                FROM ProgramCohort
                WHERE ProgramId = :programId
                AND is_Active__c = true
                ORDER BY Name
            ];
            
            for (ProgramCohort batch : batches) {
                OptionWrapper wrapper = new OptionWrapper(batch.Id, batch.Name);
                wrapper.sessionDuration = batch.Session_Duration__c;
                wrapper.allowMultiProgramBatch = batch.Allow_Multi_Program_Batch__c == true;
                options.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching batches: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getBatchGroupsForBatch(Id batchId) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            if (batchId == null) {
                return options;
            }
            
            // Get AcademicYears (Batch Groups) for the selected batch
            List<AcademicYear> batchGroups = [
                SELECT Id, Name
                FROM AcademicYear
                WHERE Batch__c = :batchId
                AND Is_Active__c = true
                ORDER BY Name
            ];
            
            for (AcademicYear batchGroup : batchGroups) {
                options.add(new OptionWrapper(batchGroup.Id, batchGroup.Name));
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching batch groups: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getTermsForBatchGroup(Id batchGroupId) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            if (batchGroupId == null) {
                return options;
            }
            
            // Get AcademicTerms for the selected Batch Group (AcademicYear)
            List<AcademicTerm> terms = [
                SELECT Id, Name, Term_Start_Date__c, Term_End_Date__c
                FROM AcademicTerm
                WHERE AcademicYearId = :batchGroupId
                ORDER BY Name
            ];
            
            for (AcademicTerm term : terms) {
                OptionWrapper ow = new OptionWrapper(String.valueOf(term.Id), term.Name);
                ow.termStartDate = term.Term_Start_Date__c != null ? String.valueOf(term.Term_Start_Date__c) : null;
                ow.termEndDate = term.Term_End_Date__c != null ? String.valueOf(term.Term_End_Date__c) : null;
                options.add(ow);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching terms: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getCoursesForDivision(String divisionId) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            if (String.isBlank(divisionId)) {
                return options;
            }
            
            // Resolve division ID - can be ID or name (for backward compatibility)
            Id divisionIdResolved = null;
            try {
                divisionIdResolved = Id.valueOf(divisionId);
            } catch (Exception e) {
                // If not a valid ID, treat as name and look it up
                List<Division__c> divisions = [
                    SELECT Id
                    FROM Division__c
                    WHERE Name = :divisionId
                    LIMIT 1
                ];
                if (!divisions.isEmpty()) {
                    divisionIdResolved = divisions[0].Id;
                } else {
                    return options;
                }
            }
            
            Set<Id> divisionIds = new Set<Id>{ divisionIdResolved };
            
            // Get DivisionCourse__c records for these divisions
            List<DivisionCourse__c> divisionCourses = [
                SELECT Id, Course_Name__c, Course_Offering__r.LearningCourseId
                FROM DivisionCourse__c
                WHERE Division__c IN :divisionIds
                AND Course_Name__c != null
                AND Course_Offering__r.LearningCourseId != null
                ORDER BY Course_Name__c
            ];
            
            // Extract unique course names with LearningCourseId
            Map<String, String> courseNameToLearningCourseId = new Map<String, String>();
            for (DivisionCourse__c dc : divisionCourses) {
                if (dc.Course_Name__c != null && dc.Course_Offering__r != null && 
                    dc.Course_Offering__r.LearningCourseId != null) {
                    if (!courseNameToLearningCourseId.containsKey(dc.Course_Name__c)) {
                        courseNameToLearningCourseId.put(dc.Course_Name__c, dc.Course_Offering__r.LearningCourseId);
                    }
                }
            }
            
            // Query LearningCourse records to get Department information
            Set<Id> learningCourseIds = new Set<Id>();
            for (String learningCourseId : courseNameToLearningCourseId.values()) {
                try {
                    learningCourseIds.add(Id.valueOf(learningCourseId));
                } catch (Exception e) {
                    // Skip invalid IDs
                }
            }
            
            Map<Id, String> learningCourseIdToDepartmentName = new Map<Id, String>();
            if (!learningCourseIds.isEmpty()) {
                // Query all LearningCourse records, even if they don't have a department
                List<LearningCourse> learningCourses = [
                    SELECT Id, Course_Department__r.Name
                    FROM LearningCourse
                    WHERE Id IN :learningCourseIds
                ];
                for (LearningCourse lc : learningCourses) {
                    if (lc.Course_Department__r != null && lc.Course_Department__r.Name != null) {
                        learningCourseIdToDepartmentName.put(lc.Id, lc.Course_Department__r.Name);
                    }
                }
            }
            
            // Create options with course name as both label and value (for backward compatibility)
            // Store LearningCourseId in a custom format: "courseName|learningCourseId"
            for (String courseName : courseNameToLearningCourseId.keySet()) {
                String learningCourseId = courseNameToLearningCourseId.get(courseName);
                String departmentName = null;
                try {
                    Id lcId = Id.valueOf(learningCourseId);
                    departmentName = learningCourseIdToDepartmentName.get(lcId);
                } catch (Exception e) {
                    // Skip if ID is invalid
                }
                // Store as "courseName|learningCourseId" so we can extract it later
                OptionWrapper wrapper = new OptionWrapper(courseName + '|' + learningCourseId, courseName);
                wrapper.departmentName = departmentName;
                options.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching courses for division: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<OptionWrapper> getDivisionsForTerms(List<Id> termIds) {
        List<OptionWrapper> options = new List<OptionWrapper>();
        
        try {
            if (termIds == null || termIds.isEmpty()) {
                return options;
            }
            
            // Get divisions for the selected terms (Division_Color__c for session tile color in All Divisions view)
            List<Division__c> divisions = [
                SELECT Id, Division_Name__c, Division_Color__c
                FROM Division__c
                WHERE Term__c IN :termIds
                ORDER BY Division_Name__c
            ];
            
            Set<Id> uniqueDivisionIds = new Set<Id>();
            for (Division__c div : divisions) {
                if (div.Id != null && !uniqueDivisionIds.contains(div.Id)) {
                    uniqueDivisionIds.add(div.Id);
                    OptionWrapper w = new OptionWrapper(div.Id, div.Division_Name__c);
                    w.divisionColor = (div.Division_Color__c != null) ? String.valueOf(div.Division_Color__c).trim() : null;
                    options.add(w);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching divisions for terms: ' + e.getMessage());
        }
        
        return options;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<CourseAssignmentOption> getCourseAssignments(String learningCourseId, String currentDivisionId, String currentProgramId, String currentBatchId, String currentBatchGroupId, String currentTermId) {
        List<CourseAssignmentOption> options = new List<CourseAssignmentOption>();
        
        try {
            if (String.isBlank(learningCourseId)) {
                return options;
            }
            
            // Resolve currentDivisionId - it might be a name or an ID
            Id currentDivisionIdResolved = null;
            if (String.isNotBlank(currentDivisionId)) {
                // Try to convert to ID first
                try {
                    currentDivisionIdResolved = Id.valueOf(currentDivisionId);
                } catch (Exception e) {
                    // If it's not a valid ID, treat it as a name and look it up
                    List<Division__c> divisions = [
                        SELECT Id
                        FROM Division__c
                        WHERE Name = :currentDivisionId
                        LIMIT 1
                    ];
                    if (!divisions.isEmpty()) {
                        currentDivisionIdResolved = divisions[0].Id;
                    }
                }
            }
            
            // Resolve currentProgramId
            Id currentProgramIdResolved = null;
            if (String.isNotBlank(currentProgramId)) {
                try {
                    currentProgramIdResolved = Id.valueOf(currentProgramId);
                } catch (Exception e) {
                    // Invalid program ID, ignore
                }
            }
            
            // Resolve current batch, batch group, term for excluding "already selected" row
            Id currentBatchIdResolved = null;
            Id currentBatchGroupIdResolved = null;
            Id currentTermIdResolved = null;
            if (String.isNotBlank(currentBatchId)) {
                try { currentBatchIdResolved = Id.valueOf(currentBatchId); } catch (Exception e) { }
            }
            if (String.isNotBlank(currentBatchGroupId)) {
                try { currentBatchGroupIdResolved = Id.valueOf(currentBatchGroupId); } catch (Exception e) { }
            }
            if (String.isNotBlank(currentTermId)) {
                try { currentTermIdResolved = Id.valueOf(currentTermId); } catch (Exception e) { }
            }
            
            // DEBUG: current context received and resolved
            System.debug(LoggingLevel.DEBUG, '[getCourseAssignments] Current context (raw): divisionId=' + currentDivisionId + ', programId=' + currentProgramId + ', batchId=' + currentBatchId + ', batchGroupId=' + currentBatchGroupId + ', termId=' + currentTermId);
            System.debug(LoggingLevel.DEBUG, '[getCourseAssignments] Current context (resolved): division=' + currentDivisionIdResolved + ', program=' + currentProgramIdResolved + ', batch=' + currentBatchIdResolved + ', batchGroup=' + currentBatchGroupIdResolved + ', term=' + currentTermIdResolved);

            Set<Id> selectedProgramCourseIds = new Set<Id>();
            for (Program_Courses__c pc : [
                SELECT Id
                FROM Program_Courses__c
                WHERE Learning_Course__c = :learningCourseId
                AND Batch__c = :currentBatchIdResolved
                AND Program_Master__c = :currentProgramIdResolved
            ]) {
                selectedProgramCourseIds.add(pc.Id);
            }
            
            // First Query: Get all DivisionCourse__c records with this LearningCourseId
            List<DivisionCourse__c> divisionCourses = [
                SELECT Id, Division__c, Division__r.Division_Name__c, Division__r.Term__c,
                       Division__r.Term__r.Name, Division__r.Term__r.AcademicYearId
                FROM DivisionCourse__c
                WHERE Course_Offering__r.LearningCourseId = :learningCourseId
                AND (
                    (
                        Course_Offering__r.ProgramCourse__r.IS_Host_Course__c = false
                        AND Course_Offering__r.ProgramCourse__r.LMS_Course__c IN :selectedProgramCourseIds
                    )
                    
                    OR (
                        Course_Offering__r.Academic_Term__c = :currentTermIdResolved
                    )
                )
                AND Division__c != null
                AND Division__r.Term__c != null
            ];
            
            // Exclude current division if provided
            Set<Id> divisionIds = new Set<Id>();
            Set<Id> termIds = new Set<Id>();
            for (DivisionCourse__c dc : divisionCourses) {
                if (dc.Division__c != null && 
                    (currentDivisionIdResolved == null || dc.Division__c != currentDivisionIdResolved)) {
                    divisionIds.add(dc.Division__c);
                    if (dc.Division__r.Term__c != null) {
                        termIds.add(dc.Division__r.Term__c);
                    }
                }
            }
            
            if (termIds.isEmpty() || divisionIds.isEmpty()) {
                return options;
            }
            
            // Second Query: Get AcademicTerms with their relationships
            List<AcademicTerm> terms = [
                SELECT Id, Name, AcademicYearId, 
                       AcademicYear.Name, AcademicYear.Batch__c,
                       AcademicYear.Batch__r.Name, AcademicYear.Batch__r.ProgramId,
                       AcademicYear.Batch__r.Program.Name
                FROM AcademicTerm
                WHERE Id IN :termIds 
                AND AcademicYear.Batch__r.ProgramId != null
                AND AcademicYear.Batch__r.Program.IsActive = true 
            ];
            
            // Get all unique Batch IDs to query Allow_Multi_Program_Batch__c
            Set<Id> batchIds = new Set<Id>();
            for (AcademicTerm term : terms) {
                if (term.AcademicYear != null && term.AcademicYear.Batch__c != null) {
                    batchIds.add(term.AcademicYear.Batch__c);
                }
            }
            
            // Query ProgramCohort (Batch) records to get Allow_Multi_Program_Batch__c
            Map<Id, ProgramCohort> batchMap = new Map<Id, ProgramCohort>();
            if (!batchIds.isEmpty()) {
                for (ProgramCohort batch : [
                    SELECT Id, ProgramId, Allow_Multi_Program_Batch__c
                    FROM ProgramCohort
                    WHERE Id IN :batchIds
                ]) {
                    batchMap.put(batch.Id, batch);
                }
            }
            
            // Create a map of term to academic year info
            Map<Id, AcademicTerm> termMap = new Map<Id, AcademicTerm>(terms);
            
            // Get all divisions with their term info
            List<Division__c> divisions = [
                SELECT Id, Division_Name__c, Term__c
                FROM Division__c
                WHERE Id IN :divisionIds
                AND Term__c IN :termIds
            ];
            
            // Create one option per division (not grouped)
            for (Division__c div : divisions) {
                AcademicTerm term = termMap.get(div.Term__c);
                if (term == null || term.AcademicYear == null || 
                    term.AcademicYear.Batch__r == null || 
                    term.AcademicYear.Batch__r.ProgramId == null) {
                    continue;
                }
                
                // Get the Batch record to check Allow_Multi_Program_Batch__c
                ProgramCohort batch = batchMap.get(term.AcademicYear.Batch__c);
                if (batch == null) {
                    continue;
                }
                
                // Filter logic: If currentProgramId is set, check if batch can be included
                if (currentProgramIdResolved != null) {
                    Id batchProgramId = batch.ProgramId;
                    Boolean allowMultiProgram = batch.Allow_Multi_Program_Batch__c == true;
                    
                    // If batch is from a different program, only include if Allow_Multi_Program_Batch__c is true
                    if (batchProgramId != currentProgramIdResolved && !allowMultiProgram) {
                        // Skip this batch - it's from a different program and doesn't allow multi-program
                        continue;
                    }
                }
                
                CourseAssignmentOption option = new CourseAssignmentOption();
                option.programId = term.AcademicYear.Batch__r.ProgramId;
                option.programName = term.AcademicYear.Batch__r.Program != null 
                    ? term.AcademicYear.Batch__r.Program.Name : '';
                option.batchId = term.AcademicYear.Batch__c;
                option.batchName = term.AcademicYear.Batch__r.Name;
                option.batchGroupId = term.AcademicYearId;
                option.batchGroupName = term.AcademicYear.Name;
                option.termId = term.Id;
                option.termName = term.Name;
                
                // Each option has a single division
                DivisionInfo divInfo = new DivisionInfo();
                divInfo.divisionId = div.Id;
                divInfo.divisionName = div.Division_Name__c;
                option.divisions = new List<DivisionInfo>{ divInfo };
                
                options.add(option);
            }
            
            // Exclude the "already selected" row: remove option that matches current context (compare by 15-char Id to handle 15 vs 18 char)
            if (currentDivisionIdResolved != null) {
                List<CourseAssignmentOption> filtered = new List<CourseAssignmentOption>();
                System.debug(LoggingLevel.DEBUG, '[getCourseAssignments] Filtering options: total before=' + options.size());
                for (CourseAssignmentOption opt : options) {
                    if (opt.divisions == null || opt.divisions.isEmpty()) { filtered.add(opt); continue; }
                    Id optDivId = null;
                    try { optDivId = Id.valueOf(opt.divisions[0].divisionId); } catch (Exception e) { }
                    Id optProgramId = null;
                    Id optBatchId = null;
                    Id optBatchGroupId = null;
                    Id optTermId = null;
                    try { optProgramId = String.isNotBlank(opt.programId) ? Id.valueOf(opt.programId) : null; } catch (Exception e) { }
                    try { optBatchId = String.isNotBlank(opt.batchId) ? Id.valueOf(opt.batchId) : null; } catch (Exception e) { }
                    try { optBatchGroupId = String.isNotBlank(opt.batchGroupId) ? Id.valueOf(opt.batchGroupId) : null; } catch (Exception e) { }
                    try { optTermId = String.isNotBlank(opt.termId) ? Id.valueOf(opt.termId) : null; } catch (Exception e) { }
                    // Match division when we have it; match program/batch/batchGroup/term only when provided (so we can exclude with just division, or full context)
                    Boolean divisionMatches = idsEqual(optDivId, currentDivisionIdResolved);
                    Boolean programMatches = currentProgramIdResolved == null || idsEqual(optProgramId, currentProgramIdResolved);
                    Boolean batchMatches = currentBatchIdResolved == null || idsEqual(optBatchId, currentBatchIdResolved);
                    Boolean batchGroupMatches = currentBatchGroupIdResolved == null || idsEqual(optBatchGroupId, currentBatchGroupIdResolved);
                    Boolean termMatches = currentTermIdResolved == null || idsEqual(optTermId, currentTermIdResolved);
                    Boolean isCurrentContext = divisionMatches && programMatches && batchMatches && batchGroupMatches && termMatches;
                    // DEBUG: compare each option
                    System.debug(LoggingLevel.DEBUG, '[getCourseAssignments] Option: ' + opt.programName + '|' + opt.batchName + '|' + opt.batchGroupName + '|' + opt.termName + '|' + (opt.divisions[0].divisionName));
                    System.debug(LoggingLevel.DEBUG, '[getCourseAssignments]   optIds: program=' + opt.programId + ', batch=' + opt.batchId + ', batchGroup=' + opt.batchGroupId + ', term=' + opt.termId + ', div=' + opt.divisions[0].divisionId);
                    System.debug(LoggingLevel.DEBUG, '[getCourseAssignments]   match: division=' + divisionMatches + ', program=' + programMatches + ', batch=' + batchMatches + ', batchGroup=' + batchGroupMatches + ', term=' + termMatches + ' => isCurrentContext=' + isCurrentContext);
                    if (!isCurrentContext) {
                        filtered.add(opt);
                    }
                }
                System.debug(LoggingLevel.DEBUG, '[getCourseAssignments] Filtering options: total after=' + filtered.size() + ' (excluded ' + (options.size() - filtered.size()) + ')');
                options = filtered;
            }
            
            // Sort by program name, then batch name, then batch group name, then division name
            options.sort(new CourseAssignmentOptionComparator());
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching course assignments: ' + e.getMessage());
        }
        
        return options;
    }

    @AuraEnabled(cacheable=false)
    public static List<ExistingSessionDivision> getSessionDivisions(Id sessionId, String refreshKey) {
        List<ExistingSessionDivision> divisions = new List<ExistingSessionDivision>();
        // refreshKey is optional and ignored; used by LWC to force a fresh request and avoid stale cached results
        if (sessionId == null) {
            return divisions;
        }
        
        try {
            // Query Session_Division__c records with division and term relationships
            List<Session_Division__c> sessionDivisions = [
                SELECT Id, Division__c, Division__r.Division_Name__c, Division__r.Term__c,
                       Division__r.Term__r.Name, Division__r.Term__r.AcademicYearId
                FROM Session_Division__c
                WHERE Session__c = :sessionId
            ];
            
            // Collect term IDs to query AcademicTerm records separately
            Set<Id> termIds = new Set<Id>();
            Map<Id, Session_Division__c> divisionToSessionDivisionMap = new Map<Id, Session_Division__c>();
            
            for (Session_Division__c sd : sessionDivisions) {
                if (sd.Division__r != null && sd.Division__r.Term__c != null) {
                    termIds.add(sd.Division__r.Term__c);
                    divisionToSessionDivisionMap.put(sd.Division__c, sd);
                }
            }
            
            if (termIds.isEmpty()) {
                return divisions;
            }
            
            // Query AcademicTerm records with their relationships
            List<AcademicTerm> terms = [
                SELECT Id, Name, AcademicYearId, 
                       AcademicYear.Name, AcademicYear.Batch__c,
                       AcademicYear.Batch__r.Name, AcademicYear.Batch__r.ProgramId,
                       AcademicYear.Batch__r.Program.Name
                FROM AcademicTerm
                WHERE Id IN :termIds 
                AND AcademicYear.Batch__r.ProgramId != null
                AND AcademicYear.Batch__r.Program.IsActive = true 
            ];
            
            // Create a map of term to academic year info
            Map<Id, AcademicTerm> termMap = new Map<Id, AcademicTerm>(terms);
            
            // Build the response
            for (Session_Division__c sd : sessionDivisions) {
                if (sd.Division__r != null && sd.Division__r.Term__c != null) {
                    ExistingSessionDivision div = new ExistingSessionDivision();
                    div.divisionId = sd.Division__c;
                    div.divisionName = sd.Division__r.Division_Name__c;
                    
                    AcademicTerm term = termMap.get(sd.Division__r.Term__c);
                    if (term != null) {
                        div.termName = term.Name;
                        
                        if (term.AcademicYear != null) {
                            div.batchGroupName = term.AcademicYear.Name;
                            
                            if (term.AcademicYear.Batch__r != null) {
                                div.batchName = term.AcademicYear.Batch__r.Name;
                                
                                if (term.AcademicYear.Batch__r.Program != null) {
                                    div.programName = term.AcademicYear.Batch__r.Program.Name;
                                }
                            }
                        }
                    }
                    
                    divisions.add(div);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching session divisions: ' + e.getMessage());
        }
        
        return divisions;
    }
    
    // Compare two Ids by 15-char form so 15-char and 18-char versions of same Id match
    private static Boolean idsEqual(Id a, Id b) {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        String sa = String.valueOf(a);
        String sb = String.valueOf(b);
        if (sa.length() >= 15 && sb.length() >= 15) {
            return sa.substring(0, 15) == sb.substring(0, 15);
        }
        return sa == sb;
    }
    
    public class CourseAssignmentOption {
        @AuraEnabled public String programId;
        @AuraEnabled public String programName;
        @AuraEnabled public String batchId;
        @AuraEnabled public String batchName;
        @AuraEnabled public String batchGroupId;
        @AuraEnabled public String batchGroupName;
        @AuraEnabled public String termId;
        @AuraEnabled public String termName;
        @AuraEnabled public List<DivisionInfo> divisions;
    }

    // Wrapper class for existing session divisions
    public class ExistingSessionDivision {
        @AuraEnabled public String divisionId { get; set; }
        @AuraEnabled public String divisionName { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String batchName { get; set; }
        @AuraEnabled public String batchGroupName { get; set; }
        @AuraEnabled public String termName { get; set; }
    }
    
    public class DivisionInfo {
        @AuraEnabled public String divisionId;
        @AuraEnabled public String divisionName;
    }
    
    public class CourseAssignmentOptionComparator implements Comparator<CourseAssignmentOption> {
        public Integer compare(CourseAssignmentOption a, CourseAssignmentOption b) {
            if (a.programName != b.programName) {
                return a.programName.compareTo(b.programName);
            }
            if (a.batchName != b.batchName) {
                return a.batchName.compareTo(b.batchName);
            }
            return a.batchGroupName.compareTo(b.batchGroupName);
        }
    }
    
    public class OptionWrapper {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal sessionDuration;
        @AuraEnabled public String departmentName;
        @AuraEnabled public Boolean allowMultiProgramBatch;
        /** Division_Color__c picklist value (Blue, Grey, Green, Red, Purple, Orange) for session tile styling. */
        @AuraEnabled public String divisionColor;
        /** Academic term bounds for client-side session date validation (YYYY-MM-DD). */
        @AuraEnabled public String termStartDate;
        @AuraEnabled public String termEndDate;

        public OptionWrapper(String value, String label) {
            this.value = value;
            this.label = label;
            this.sessionDuration = null;
            this.departmentName = null;
            this.allowMultiProgramBatch = null;
            this.divisionColor = null;
            this.termStartDate = null;
            this.termEndDate = null;
        }
    }
}