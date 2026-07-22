public without sharing class StudentProfileDashboardController {
    
    /**
     * Wrapper class to return user information
     */
    public class UserInfoWrapper {
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public String gender;
        @AuraEnabled public Date dateOfBirth;
        @AuraEnabled public String rollNumber;
        @AuraEnabled public String programCode;
        @AuraEnabled public String programName;
        @AuraEnabled public String batchName;
        @AuraEnabled public String mobileNumber;
        @AuraEnabled public String prevQualification;
        @AuraEnabled public String graduationYear;
        @AuraEnabled public String orgName;
        @AuraEnabled public String workDuration;
        /** Sum of all PersonEmployment periods for this account (human-readable). */
        @AuraEnabled public String totalWorkExperience;
        @AuraEnabled public Decimal marks;
        @AuraEnabled public String term;
        @AuraEnabled public String address;
        @AuraEnabled public List<Map<String, String>> termOptions;
        @AuraEnabled public Map<String, Integer> courseCount;
        @AuraEnabled public Id currentTermId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public Boolean profileWindowIsActive;
        @AuraEnabled public Datetime profileWindowStartTime;
        @AuraEnabled public Datetime profileWindowEndTime;
        /** Program Cohort (batch) Instructions__c — shown before profile photo upload */
        @AuraEnabled public String photoUploadInstruction;
        public UserInfoWrapper(String fullName, String email, String gender, Date dateOfBirth, String rollNumber, String programCode,String programName, String batchName, String mobileNumber,String prevQualification ,String graduationYear ,String orgName,String workDuration, String totalWorkExperience, Decimal marks, String term,String address,List<Map<String, String>> termOptions, Map<String, Integer> courseCount,Id currentTermId, Id accountId, Boolean profileWindowIsActive, Datetime profileWindowStartTime, Datetime profileWindowEndTime, String photoUploadInstruction) {
            this.fullName = fullName;
            this.email = email;
            this.gender = gender;
            this.dateOfBirth = dateOfBirth; 
            this.rollNumber = rollNumber;
            this.programCode = programCode;
            this.programName = programName;
            this.batchName = batchName;
            this.mobileNumber = mobileNumber;
            this.prevQualification = prevQualification;
            this.graduationYear = graduationYear;
            this.orgName=orgName;
            this.workDuration=workDuration;
            this.totalWorkExperience = totalWorkExperience;
            this.marks = marks;
            this.term = term;
            this.address = address;
            this.termOptions = termOptions;
            this.courseCount = courseCount;
            this.currentTermId = currentTermId;
            this.accountId = accountId;
            this.profileWindowIsActive = profileWindowIsActive;
            this.profileWindowStartTime = profileWindowStartTime;
            this.profileWindowEndTime = profileWindowEndTime;
            this.photoUploadInstruction = photoUploadInstruction;
        }
    }
    
    
    /**
     * Get the current logged-in user's name, email, and gender
     * @return UserInfoWrapper - Contains name, email, and gender
     */

    @AuraEnabled(cacheable=true)
    public static UserInfoWrapper getUserInfo() {
        try {
            try {
                if (Auth.CommunitiesUtil.isGuestUser()) {
                    return null;
                }
            } catch (Exception guestCheckEx) {
                // Not in community context; continue with normal user lookup
            }
            User currentUser = [SELECT Id, FirstName, LastName, Name, Email, ContactId 
                                FROM User 
                                WHERE Id = :UserInfo.getUserId() 
                                LIMIT 1];
            
            // Get full name
            String fullName;
            if (String.isNotBlank(currentUser.FirstName) && String.isNotBlank(currentUser.LastName)) {
                fullName = currentUser.FirstName + ' ' + currentUser.LastName;
            } else if (String.isNotBlank(currentUser.Name)) {
                fullName = currentUser.Name;
            } else {
                fullName = 'User';
            }
            
            // Get email
            String userEmail = currentUser.Email != null ? currentUser.Email : '';
            
            // Get gender from Account (via Contact) if available
            String gender = '';
            Id accountId = null;
            String rollNumber = '';
            String mobileNumber = '';
            Date dateOfBirth;
            String programCode = '';
            String programName = '';
            String batchName = '';
            String prevQualification = '';
            String graduationYear = '';
            Decimal marks;
            String term='';
            String address = '';
            Id batchId = null;
            String orgName = '';
            String workDuration;
            String totalWorkExperience = '';
            List<Map<String, String>> termOptions = new List<Map<String, String>>();
            Map<String, Integer> courseCount = new  Map<String, Integer>();
            Id currentTermId;
            Boolean profileWindowIsActive = false;
            Datetime profileWindowStartTime;
            Datetime profileWindowEndTime;
            String photoUploadInstruction = '';
            

            if (currentUser.ContactId != null) {
                try {
                    Contact userContact = [SELECT AccountId, Account.Gender__c, Account.Date_Of_Birth__c , Account.PersonMobilePhone, Account.Address__c
                                          FROM Contact 
                                          WHERE Id = :currentUser.ContactId 
                                          LIMIT 1];
                    if (userContact.AccountId != null) {
                        accountId = (Id) userContact.AccountId;
                    }

                    if (userContact.Account.Gender__c != null) {
                        gender = userContact.Account.Gender__c;
                    }

                    if (userContact.AccountId != null && userContact.Account.Date_Of_Birth__c != null) {
                        dateOfBirth = userContact.Account.Date_Of_Birth__c;
                    }
                    if (userContact.AccountId != null && userContact.Account.PersonMobilePhone != null) {
                        mobileNumber = userContact.Account.PersonMobilePhone;
                    }
                     if (accountId != null) {

            List<PersonEmployment> allEmployment = [
                SELECT Id, Name, StartDate, EndDate
                FROM PersonEmployment
                WHERE AccountId = :accountId
            ];

          /*  Integer totalEmploymentDays = 0;
            for (PersonEmployment pe : allEmployment) {
                if (pe.StartDate == null) {
                    continue;
                }
                Date periodEnd = pe.EndDate != null ? pe.EndDate : Date.today();
                if (pe.StartDate <= periodEnd) {
                    totalEmploymentDays += pe.StartDate.daysBetween(periodEnd);
                }
            }
            if (totalEmploymentDays > 0) {
                totalWorkExperience = formatTotalDaysAsExperience(totalEmploymentDays);
            }*/
            /*SE1210, Se1218*/
            Date earliestStart = null;
            Date latestEnd = null;
            for (PersonEmployment pe : allEmployment) {
                if (pe.StartDate == null) {
                    continue;
                }
                Date periodEnd = pe.EndDate != null ? pe.EndDate : Date.today();
                if (pe.StartDate <= periodEnd) {
                    if (earliestStart == null || pe.StartDate < earliestStart) {
                        earliestStart = pe.StartDate;
                    }
                    if (latestEnd == null || periodEnd > latestEnd) {
                        latestEnd = periodEnd;
                    }
                }
            }
            if (earliestStart != null && latestEnd != null) {
                totalWorkExperience = calculateDuration(earliestStart, latestEnd);
            }
            /*SE1210,Se1218 */

            PersonEmployment latest = null;
            Date bestSortEnd = null;
            Date bestStart = null;
            for (PersonEmployment pe : allEmployment) {
                if (pe.StartDate == null) {
                    continue;
                }
                Date sortEnd = pe.EndDate != null ? pe.EndDate : Date.today();
                if (latest == null
                    || sortEnd > bestSortEnd
                    || (sortEnd == bestSortEnd && (bestStart == null || pe.StartDate > bestStart))) {
                    latest = pe;
                    bestSortEnd = sortEnd;
                    bestStart = pe.StartDate;
                }
            }
            if (latest != null) {
                orgName = latest.Name != null ? latest.Name.trim() : '';
                if (latest.StartDate != null) {
                    Date startDate = latest.StartDate;
                    Date endDate = latest.EndDate != null ? latest.EndDate : Date.today();
                    if (startDate <= endDate) {
                        workDuration = calculateDuration(startDate, endDate);
                    } else {
                        workDuration = 'Invalid Dates';
                    }
                }
            }
        }

                } catch (Exception contactEx) {
                    System.debug('Contact or Account not found, or Gender field not available: ' + contactEx.getMessage());
                    // Gender will remain empty string
                }
            }
            List<Address_Information__c> addInfoList = [SELECT Id, Correspondence_Address__c,Current_State__c,Current_Country__c,Current_City__c,Current_Zip_Postal_Code__c FROM Address_Information__c WHERE Account__c = :accountId LIMIT 1];
            if (!addInfoList.isEmpty()) {
            Address_Information__c addInfo = addInfoList[0];
        /*    address = addInfo.Correspondence_Address__c + ', ' + addInfo.Current_City__c + ', ' + addInfo.Current_Zip_Postal_Code__c + ', ' + addInfo.Current_State__c + ', ' + addInfo.Current_Country__c;  */
           /* SE-1049*/
            List<String> addressParts = new List<String>();
            if (String.isNotBlank(addInfo.Correspondence_Address__c)) {
                addressParts.add(addInfo.Correspondence_Address__c);
            }
            if (String.isNotBlank(addInfo.Current_City__c)) {
                addressParts.add(addInfo.Current_City__c);
            }
            if (String.isNotBlank(addInfo.Current_Zip_Postal_Code__c)) {
                addressParts.add(addInfo.Current_Zip_Postal_Code__c);
            }
            if (String.isNotBlank(addInfo.Current_State__c)) {
                addressParts.add(addInfo.Current_State__c);
            }
            if (String.isNotBlank(addInfo.Current_Country__c)) {
                addressParts.add(addInfo.Current_Country__c);
            }
            address = String.join(addressParts, ', ');
            }
            /*SE-1049*/
			system.debug('accountId::'+accountId);

   
            List<ProgramEnrollment> programEnrollments = [SELECT Program.Id,Program.Name,Program.Program_Code__c,Program.Duration_to_Complete__c FROM ProgramEnrollment WHERE AccountId = :accountId LIMIT 1];
            if (!programEnrollments.isEmpty()){        /*SE-946*/
                programCode = programEnrollments[0].Program.Program_Code__c;
            }
            List<ProgramCohortMember> programCohortMemberList = [
                SELECT Roll_Number__c,
                    ProgramCohortId,
                    ProgramCohort.Name,
                    ProgramCohort.Program.Name,
                    ProgramCohort.Program_Code__c,
                    ProgramCohort.Profile_Window_IsActive__c,
                    ProgramCohort.Profile_Window_Start_Time__c,
                    ProgramCohort.Profile_Window_End_Time__c,
                    ProgramCohort.Instructions__c
                FROM ProgramCohortMember
                WHERE ProgramEnrolleeId = :accountId
                LIMIT 1
            ];
            if (programCohortMemberList != null && programCohortMemberList.size() > 0) {
                ProgramCohortMember programCohortMember = programCohortMemberList[0];
                rollNumber = programCohortMember.Roll_Number__c;
                // programCode = programCohortMember.ProgramCohort.Program_Code__c;
                programName = programCohortMember.ProgramCohort.Program.Name;
                batchName = programCohortMember.ProgramCohort.Name;
                batchId = programCohortMember.ProgramCohortId;
                profileWindowIsActive = programCohortMember.ProgramCohort.Profile_Window_IsActive__c;
                profileWindowStartTime = programCohortMember.ProgramCohort.Profile_Window_Start_Time__c;
                profileWindowEndTime = programCohortMember.ProgramCohort.Profile_Window_End_Time__c;
                if (programCohortMember.ProgramCohort.Instructions__c != null) {
                    photoUploadInstruction = programCohortMember.ProgramCohort.Instructions__c;
                }
            }
          
               List<PersonEducation> personEduList = [SELECT Id, Name, GraduationDate, SPJIMR_Obtained_Marks__c, GpaScale,CumulativeGpa FROM PersonEducation WHERE AccountId = :accountId ORDER BY CreatedDate DESC LIMIT 1];

                if (personEduList != null && personEduList.size() > 0) {
                    PersonEducation personEdu = personEduList[0];
                    prevQualification = personEdu.Name;

                    if (personEdu.GraduationDate != null) {
                        graduationYear = String.valueOf(personEdu.GraduationDate.year());
                    }

                    if (personEdu.CumulativeGpa != null) {
                        marks = personEdu.CumulativeGpa;
                    }
            }


            Date todayDate = Date.today();
            for (AcademicTermEnrollment ate : [ SELECT AcademicTermId,AcademicTerm.Name, AcademicTerm.Term_Start_Date__c, AcademicTerm.Term_End_Date__c,AcademicTerm.Is_Active__c
                FROM AcademicTermEnrollment  WHERE LearnerAccountId = :accountId ORDER BY AcademicTerm.Term_Start_Date__c DESC]) {
              termOptions.add(new Map<String, String>{
                  'label' => ate.AcademicTerm.Name,
                  'value' => ate.AcademicTerm.Id
              });
               if (String.isBlank(term) && ate.AcademicTerm.Term_Start_Date__c <= todayDate && ate.AcademicTerm.Term_End_Date__c >= todayDate &&  ate.AcademicTerm.Is_Active__c == true) {
                    term = ate.AcademicTerm.Name;
                    currentTermId = ate.AcademicTermId;
                }
            }
            System.debug('currenttermId:'+currentTermId);
            if (currentTermId == null) {
              return new UserInfoWrapper(
                  fullName, userEmail, gender, dateOfBirth, rollNumber,
                  programCode, programName, batchName, mobileNumber,
                  prevQualification, graduationYear, orgName, workDuration, totalWorkExperience, marks,
                  term, address, termOptions, new Map<String, Integer>(), currentTermId, accountId, profileWindowIsActive, profileWindowStartTime, profileWindowEndTime, photoUploadInstruction
              );
          }
         /* else{
            Integer core=0;
            Integer elective = 0;
            Integer specialisation = 0;
            for(CourseOffering courseOff : [SELECT Id,name,Academic_Term__r.name,Course_Type__c FROM CourseOffering where Academic_Term__c =:currentTermId]){
                if(courseOff.Course_Type__c == 'Core'){
                  core++;
                  courseCount.put(courseOff.Course_Type__c,core);
                }
                else if(courseOff.Course_Type__c == 'Elective'){
                  elective++;
                  courseCount.put(courseOff.Course_Type__c,elective);
                }
                else if(courseOff.Course_Type__c == 'Specialisation'){
                  specialisation++;
                  courseCount.put(courseOff.Course_Type__c,specialisation);
                }
            }
          }*/

       /*SE-771*/   else{
                Integer core=0;
                Integer elective = 0;
                Integer specialisation = 0;
                // Only count courses tied to a Division the student is enrolled in for this term
                Set<Id> enrolledDivisionIds = new Set<Id>();
                for (Division_Enrollment__c de : [
                    SELECT Id, Division__c
                    FROM Division_Enrollment__c
                    WHERE Academic_Term_Enrollment__r.LearnerAccountId = :accountId
                    AND Academic_Term_Enrollment__r.AcademicTermId = :currentTermId
                    AND Division__c != null
                ]) {
                enrolledDivisionIds.add(de.Division__c);
                }
                if (!enrolledDivisionIds.isEmpty()) {
                    for (DivisionCourse__c dc : [
                        SELECT Id, Course_Offering__r.Course_Type__c
                        FROM DivisionCourse__c
                        WHERE Division__c IN :enrolledDivisionIds
                        AND Course_Offering__r.Academic_Term__c = :currentTermId
                        ]) {
                        String courseType = dc.Course_Offering__r != null ? dc.Course_Offering__r.Course_Type__c : null;
                        
                        if (courseType == 'Core') {
                        core++;
                        courseCount.put('Core', core);
                        } else if (courseType == 'Elective') {
                            elective++;
                        courseCount.put('Elective', elective);
                        } else if (courseType == 'Specialisation') {
                        specialisation++;
                        courseCount.put('Specialisation', specialisation);
                        }
                    }
                }
            }  /* SE-771*/
             return new UserInfoWrapper(fullName, userEmail, gender, dateOfBirth, rollNumber, programCode,programName, batchName, mobileNumber,prevQualification,graduationYear, orgName, workDuration, totalWorkExperience, marks,term,address,termOptions,courseCount,currentTermId, accountId, profileWindowIsActive, profileWindowStartTime, profileWindowEndTime, photoUploadInstruction);
        } catch (Exception e) {
            System.debug('Error fetching user info: ' + e.getMessage());
            throw new AuraHandledException('Error fetching user info: ' + e.getMessage());
        }
    }
    private static String calculateDuration(Date startDate, Date endDate) {

    Integer years = endDate.year() - startDate.year();
    Integer months = endDate.month() - startDate.month();
    Integer days = endDate.day() - startDate.day();

    if (days < 0) {
        months--;
        Date prevMonth = endDate.addMonths(-1);
        days += Date.daysInMonth(prevMonth.year(), prevMonth.month());
    }

    if (months < 0) {
        years--;
        months += 12;
    }

    // Round up to the next whole month if only 1 day short of a full month
  /*SE1210,Se1218*/
    Integer daysInThisMonth = Date.daysInMonth(endDate.year(), endDate.month());
    if (days == daysInThisMonth - 1) {
        months++;
        days = 0;
        if (months == 12) {
            years++;
            months = 0;
        }
    } /*Se1210/
   /* if (years > 0) {
        return years + ' Years ' + months + ' Months';
    } else if (months > 0) {
        return months + ' Months';
    } 
    else {
        return days + ' Days';
    }
}*/ 
    /*SE-1209,SE-1218*/
    List<String> parts = new List<String>();
        if (years > 0) {
        parts.add(years + (years == 1 ? ' Year' : ' Years'));
    }
        if (months > 0) {
        parts.add(months + (months == 1 ? ' Month' : ' Months'));
    }
        if (days > 0) {
        parts.add(days + (days == 1 ? ' Day' : ' Days'));
        }
        if (parts.isEmpty()) {
            parts.add('0 Days');
        }
        return String.join(parts, ' ');
    } /*SE-1210,SE-1218*/
    /**
     * Converts summed calendar days across employments into a short label (approximate months/years).
     */
 /* SE1210  private static String formatTotalDaysAsExperience(Integer totalDays) {
        if (totalDays == null || totalDays <= 0) {
            return '';
        }
        Integer years = totalDays / 365;
        Integer remainder = totalDays - (years * 365);
        Integer months = remainder / 30;
        Integer days = remainder - (months * 30);
        if (years > 0) {
            return years + ' Years ' + months + ' Months';
        }
        if (months > 0) {
            return months + ' Months ' + days + ' Days';
        }
        return days + ' Days';
    } Se1210 */

    /**
     * Returns image data URLs for instruction images referenced in ProgramCohort.Instructions__c.
     * Security: only images whose ContentDocument is linked to the current user's ProgramCohort are returned.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPhotoUploadInstructionImageData(List<String> contentVersionIds, List<String> contentDocumentIds) {
        Map<String, String> result = new Map<String, String>();

        Set<Id> requestedVersionIds = new Set<Id>();
        Set<Id> requestedDocumentIds = new Set<Id>();

        if (contentVersionIds != null) {
            for (String rawId : contentVersionIds) {
                String s = String.valueOf(rawId).trim();
                if (s.length() >= 15 && s.startsWith('068')) {
                    try { requestedVersionIds.add((Id) s); } catch (Exception e) {}
                }
            }
        }
        if (contentDocumentIds != null) {
            for (String rawId : contentDocumentIds) {
                String s = String.valueOf(rawId).trim();
                if (s.length() >= 15 && s.startsWith('069')) {
                    try { requestedDocumentIds.add((Id) s); } catch (Exception e) {}
                }
            }
        }

        if (requestedVersionIds.isEmpty() && requestedDocumentIds.isEmpty()) {
            return result;
        }

        User currentUser = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (currentUser.ContactId == null) {
            return result;
        }
        Contact userContact = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :currentUser.ContactId
            LIMIT 1
        ];
        if (userContact.AccountId == null) {
            return result;
        }

        List<ProgramCohortMember> cohortMembers = [
            SELECT ProgramCohortId
            FROM ProgramCohortMember
            WHERE ProgramEnrolleeId = :userContact.AccountId
            LIMIT 1
        ];
        if (cohortMembers.isEmpty() || cohortMembers[0].ProgramCohortId == null) {
            return result;
        }
        Id cohortId = cohortMembers[0].ProgramCohortId;

        // Fetch the trusted, admin-authored Instructions__c HTML — used as a fallback
        // when ContentDocumentLink to the cohort is missing (which can happen if the
        // image was inserted via API or an older rich text editor).
        String instructionsHtml = '';
        List<ProgramCohort> cohortRecords = [
            SELECT Instructions__c
            FROM ProgramCohort
            WHERE Id = :cohortId
            LIMIT 1
        ];
        if (!cohortRecords.isEmpty() && cohortRecords[0].Instructions__c != null) {
            instructionsHtml = cohortRecords[0].Instructions__c;
        }

        Map<Id, ContentVersion> versionById = new Map<Id, ContentVersion>();
        if (!requestedVersionIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId, VersionData, FileType, FileExtension
                FROM ContentVersion
                WHERE Id IN :requestedVersionIds
            ]) {
                versionById.put(cv.Id, cv);
            }
        }
        if (!requestedDocumentIds.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId, VersionData, FileType, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId IN :requestedDocumentIds
                AND IsLatest = true
            ]) {
                if (!versionById.containsKey(cv.Id)) {
                    versionById.put(cv.Id, cv);
                }
            }
        }
        if (versionById.isEmpty()) {
            return result;
        }

        Set<Id> candidateDocumentIds = new Set<Id>();
        for (ContentVersion cv : versionById.values()) {
            if (cv.ContentDocumentId != null) candidateDocumentIds.add(cv.ContentDocumentId);
        }
        if (candidateDocumentIds.isEmpty()) {
            return result;
        }

        Set<Id> allowedDocumentIds = new Set<Id>();
        // Primary check: the file is linked (Files related list) to the cohort.
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :cohortId
            AND ContentDocumentId IN :candidateDocumentIds
        ]) {
            allowedDocumentIds.add(cdl.ContentDocumentId);
        }
        // Fallback: the image's ContentDocumentId or its ContentVersionId appears in the
        // cohort's Instructions__c HTML. Safe because Instructions__c is admin-authored.
        if (!String.isBlank(instructionsHtml)) {
            for (ContentVersion cv : versionById.values()) {
                if (cv.ContentDocumentId == null || allowedDocumentIds.contains(cv.ContentDocumentId)) {
                    continue;
                }
                if (instructionsHtml.contains(String.valueOf(cv.Id))
                        || instructionsHtml.contains(String.valueOf(cv.ContentDocumentId))) {
                    allowedDocumentIds.add(cv.ContentDocumentId);
                }
            }
        }
        if (allowedDocumentIds.isEmpty()) {
            return result;
        }

        for (ContentVersion cv : versionById.values()) {
            if (cv.ContentDocumentId == null || !allowedDocumentIds.contains(cv.ContentDocumentId)) {
                continue;
            }
            String ext = cv.FileExtension != null ? cv.FileExtension.toLowerCase() : '';
            String fileType = cv.FileType != null ? cv.FileType.toUpperCase() : '';
            Boolean isImage = fileType == 'PNG' || fileType == 'JPG' || fileType == 'JPEG'
                || ext == 'png' || ext == 'jpg' || ext == 'jpeg';
            if (!isImage || cv.VersionData == null) {
                continue;
            }

            String mime = (fileType == 'PNG' || ext == 'png') ? 'image/png' : 'image/jpeg';
            String dataUrl = 'data:' + mime + ';base64,' + EncodingUtil.base64Encode(cv.VersionData);
            result.put(String.valueOf(cv.Id), dataUrl);
            result.put(String.valueOf(cv.ContentDocumentId), dataUrl);
        }

        return result;
    }

    private static final String LEAVE_MODULE_CMDT_DEVELOPER_NAME = 'Student_Portal_Leave_Module_Visibility';
    private static final String LEAVE_ATTENDANCE_ROUTE_TOKEN = 'leave-and-attendance';
    private static final String NAV_LABEL_LEAVE_AND_ATTENDANCE = 'Leave';
    private static final String NAV_LABEL_ATTENDANCE_ONLY = 'Attendance';

    /** Writable menu DTO — ConnectApi.NavigationMenuItem labels cannot be mutated at runtime. */
    public class NavMenuItemWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String actionType;
        @AuraEnabled public String actionValue;
        @AuraEnabled public String target;
        @AuraEnabled public List<NavMenuItemWrapper> subMenu;
    }

    @TestVisible
    private static Boolean testLeaveModuleEnabledOverride;

    final private static List<ConnectApi.NavigationMenuItemType> EXCLUDED_TYPES = new List<ConnectApi.NavigationMenuItemType>{
    ConnectApi.NavigationMenuItemType.Event,
    ConnectApi.NavigationMenuItemType.SystemLink
  };

    /**
     * Feature flag from Feature_Configuration__mdt (Student_Portal_Leave_Module_Visibility).
     * Defaults to true when the CMDT record is missing so existing orgs keep current behaviour.
     * Must be cacheable — consumed via @wire in LWC.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isStudentPortalLeaveModuleEnabled() {
        return resolveStudentPortalLeaveModuleEnabled();
    }

    private static Boolean resolveStudentPortalLeaveModuleEnabled() {
        if (Test.isRunningTest() && testLeaveModuleEnabledOverride != null) {
            return testLeaveModuleEnabledOverride;
        }
        Feature_Configuration__mdt config = Feature_Configuration__mdt.getInstance(
            LEAVE_MODULE_CMDT_DEVELOPER_NAME
        );
        if (config == null) {
            return true;
        }
        return config.Is_Enabled__c == true;
    }

    private static Boolean isLeaveAndAttendanceNavItem(ConnectApi.NavigationMenuItem item) {
        if (item == null) {
            return false;
        }
        String actionValue = item.actionValue != null
            ? item.actionValue.trim().toLowerCase()
            : '';
        if (actionValue.contains(LEAVE_ATTENDANCE_ROUTE_TOKEN)) {
            return true;
        }
        String label = item.label != null ? item.label.trim().toLowerCase() : '';
        return label == NAV_LABEL_LEAVE_AND_ATTENDANCE.toLowerCase()
            || label == 'leave & attendance';
    }

    @TestVisible
    private static List<NavMenuItemWrapper> toNavMenuItemWrappers(
        List<ConnectApi.NavigationMenuItem> items
    ) {
        String leaveLabel = resolveStudentPortalLeaveModuleEnabled()
            ? NAV_LABEL_LEAVE_AND_ATTENDANCE
            : NAV_LABEL_ATTENDANCE_ONLY;
        return toNavMenuItemWrappers(items, leaveLabel);
    }

    private static List<NavMenuItemWrapper> toNavMenuItemWrappers(
        List<ConnectApi.NavigationMenuItem> items,
        String leaveLabel
    ) {
        List<NavMenuItemWrapper> result = new List<NavMenuItemWrapper>();
        if (items == null || items.isEmpty()) {
            return result;
        }
        for (ConnectApi.NavigationMenuItem item : items) {
            if (item != null) {
                result.add(toNavMenuItemWrapper(item, leaveLabel));
            }
        }
        return result;
    }

    private static NavMenuItemWrapper toNavMenuItemWrapper(
        ConnectApi.NavigationMenuItem item,
        String leaveLabel
    ) {
        NavMenuItemWrapper wrapper = new NavMenuItemWrapper();
        wrapper.label = item.label;
        wrapper.actionValue = item.actionValue;
        if (item.target != null) {
            wrapper.target = String.valueOf(item.target);
        }
        if (item.actionType != null) {
            wrapper.actionType = String.valueOf(item.actionType);
        }
        if (isLeaveAndAttendanceNavItem(item)) {
            wrapper.label = leaveLabel;
        }
        if (item.subMenu != null && !item.subMenu.isEmpty()) {
            wrapper.subMenu = toNavMenuItemWrappers(item.subMenu, leaveLabel);
        }
        return wrapper;
    }

    @AuraEnabled(cacheable=true)
  public static List<NavMenuItemWrapper> getMenuItems(String menuName) {
    
    if (String.isEmpty(menuName)) {
      System.debug(LoggingLevel.ERROR, 'getMenuItems: END KO / Missing navigation Menu Name');
      throw new System.AuraHandledException('Missing Navigation Menu Name!');
    }

    String networkId;
    if (!Test.isRunningTest()) {
      networkId = Network.getNetworkId();
    } else {
      System.debug('getMenuItems: setting networkId to userId for tests');
      networkId = '00D000000000000';
    }
    if (String.isEmpty(networkId)) {
      System.debug(LoggingLevel.ERROR, 'getMenuItems: END KO / No networkId');
      throw new System.AuraHandledException('Network ID not available!');
    }
    System.debug('getMenuItems: networkId retrieved ' + networkId);

    NavigationLinkSet navigationLink = null;
    if (!Test.isRunningTest()) {
      navigationLink = [
        SELECT DeveloperName
        FROM NavigationLinkSet
        WHERE NetworkId = :networkId AND DeveloperName = :menuName
        LIMIT 1
      ];
    } else {
      System.debug(LoggingLevel.ERROR, 'getMenuItems: setting test navigation set');
      if (menuName != 'NONE') {
        System.debug(LoggingLevel.FINEST, 'getMenuItems: registering menu ' + menuName);
        navigationLink = new NavigationLinkSet(DeveloperName = menuName, MasterLabel = menuName);
      } else {
        System.debug(LoggingLevel.FINEST, 'getMenuItems: ignoring menu ' + menuName);
      }
    }
    if (navigationLink == null) {
      System.debug(
        LoggingLevel.ERROR,
        'getMenuItems: END KO / No navigation found with name ' + menuName + ' on network ' + networkId
      );
      throw new System.AuraHandledException('Navigation menu not found!');
    }
    System.debug('getMenuItems: navigationLink retrieved ' + navigationLink);
    String navName = navigationLink.DeveloperName;
    System.debug('getMenuItems: navName extracted ' + navName);

    ConnectApi.NavigationMenuItemCollection navMenu;
    if (!Test.isRunningTest()) {
      navMenu = ConnectApi.NavigationMenu.getCommunityNavigationMenu(
        networkId,
        null,
        navName,
        ConnectApi.PublishStatus.Live,
        false,
        false,
        EXCLUDED_TYPES
      );
      System.debug('getMenuItems: navigation Menu retrieved ' + navMenu);
    } else {
      System.debug('getMenuItems: setting test navigation menu');
      navMenu = new ConnectApi.NavigationMenuItemCollection();
      navMenu.menuItems = new List<ConnectApi.NavigationMenuItem>();
      ConnectApi.NavigationMenuItem newItem = new ConnectApi.NavigationMenuItem();
      newItem.Label = 'Home';
      newItem.actionValue = 'www.home.test';
      navMenu.menuItems.add(newItem);
    }

    List<ConnectApi.NavigationMenuItem> navItems = navMenu.menuItems;
    List<NavMenuItemWrapper> menuWrappers = toNavMenuItemWrappers(navItems);
    System.debug('getMenuItems: END returning ' + menuWrappers.size() + ' items');
    return menuWrappers;

  }
  @AuraEnabled(cacheable=true)
public static Program programInfo() {
    // Get the logged-in user's account ID directly from User
    User currentUser = [SELECT Id, AccountId 
                        FROM User 
                        WHERE Id = :UserInfo.getUserId() 
                        LIMIT 1];
    
    if (currentUser.AccountId == null) {
        return null;
    }
    
    // Query ProgramEnrollment where AccountId matches the logged-in user's account ID
    List<ProgramEnrollment> programEnrollments = [
        SELECT Program.Id,Program.Name,Program.Program_Code__c,
               Program.Programme_Duration__c,Program.Programme_Duration_In_Days__c,
               Program.Programme_Duration_In_Months__c,Program.Programme_Duration_In_Weeks__c,Program.Programme_Duration_In_Years__c
        FROM ProgramEnrollment
        WHERE AccountId = :currentUser.AccountId
        LIMIT 1
    ];
    
    if (programEnrollments != null && programEnrollments.size() > 0 && programEnrollments[0].ProgramId != null) {
        // Return the Program object with Name, Program_Code__c, and Duration_to_Complete__c
        Program programObj = new Program(); 
        programObj.Id = programEnrollments[0].Program.ID;
        programObj.Name = programEnrollments[0].Program.Name;
        programObj.Program_Code__c = programEnrollments[0].Program.Program_Code__c;
        programObj.Programme_Duration__c = programEnrollments[0].Program.Programme_Duration__c;
        if(programEnrollments[0].Program.Programme_Duration__c=='Year'){
            programObj.Duration_to_Complete__c = programEnrollments[0].Program.Programme_Duration_In_Years__c;
        }
        else if(programEnrollments[0].Program.Programme_Duration__c=='Months'){
            programObj.Duration_to_Complete__c = programEnrollments[0].Program.Programme_Duration_In_Months__c;
        }
        else if(programEnrollments[0].Program.Programme_Duration__c=='Weeks'){
            programObj.Duration_to_Complete__c = programEnrollments[0].Program.Programme_Duration_In_Weeks__c;
        }
        else if(programEnrollments[0].Program.Programme_Duration__c=='Days'){
            programObj.Duration_to_Complete__c = programEnrollments[0].Program.Programme_Duration_In_Days__c;
        }
        return programObj;
    }
    
    return null;
}

  @AuraEnabled(cacheable=true)
  public static List<CourseDTO> courseEnrolled(Id currentTermId) {

      if (currentTermId == null) {
        system.debug('287---');
          return new List<CourseDTO>();
      }
    
      List<CourseDTO> results = new List<CourseDTO>();

      for (CourseOffering co : [
          SELECT Id,
                Name,
                Course_Type__c,
                PrimaryFaculty.Name,ProgramCourse__r.SPJIMR_specialisation__r.specialisation_Name__r.Name
          FROM CourseOffering
          WHERE Academic_Term__c = :currentTermId
      ]) {
          results.add(new CourseDTO(
              co.Id,
              co.Name,
              co.PrimaryFaculty != null ? co.PrimaryFaculty.Name : '',
              co.Course_Type__c,
              co.ProgramCourse__r.SPJIMR_specialisation__r.specialisation_Name__r.Name !=null ? co.ProgramCourse__r.SPJIMR_specialisation__r.specialisation_Name__r.Name : '-' 
          ));
      }

      return results;
  }

public class CourseDTO {
    @AuraEnabled public String id;
    @AuraEnabled public String courseName;
    @AuraEnabled public String faculty;
    @AuraEnabled public String evaluationType;
    @AuraEnabled public String specialisation;

    public CourseDTO(
        String id,
        String courseName,
        String faculty,
        String evaluationType,
        String specialisation
    ) {
        this.id = id;
        this.courseName = courseName;
        this.faculty = faculty;
        this.evaluationType = evaluationType;
        this.specialisation = specialisation;
    }
}

/**
 * Wrapper for division table row: Division Name and Division Group
 */
public class DivisionRow {
    @AuraEnabled public String id;
    @AuraEnabled public String divisionName;
    @AuraEnabled public String divisionGroup;

    public DivisionRow(String id, String divisionName, String divisionGroup) {
        this.id = id;
        this.divisionName = divisionName;
        this.divisionGroup = divisionGroup;
    }
}

@AuraEnabled(cacheable=true)
public static List<DivisionRow> getDivisionEnrollmentTable(Id currentTermId) {
    if (currentTermId == null) {
        return new List<DivisionRow>();
    }
    Id accountId = null;
    try {
        User currentUser = [SELECT Id, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (currentUser.ContactId != null) {
            Contact c = [SELECT AccountId FROM Contact WHERE Id = :currentUser.ContactId LIMIT 1];
            accountId = c.AccountId;
        }
    } catch (Exception e) {
        return new List<DivisionRow>();
    }
    if (accountId == null) {
        return new List<DivisionRow>();
    }
    List<DivisionRow> rows = new List<DivisionRow>();
    for (AcademicTermEnrollment ate : [
        SELECT Id, AcademicTermId,
               (SELECT Id, Division__r.Id, Division__r.Division_Name__c, Division__r.Division_Group__r.Name
                FROM Division_Enrollments__r)
        FROM AcademicTermEnrollment
        WHERE LearnerAccountId = :accountId
        AND AcademicTermId = :currentTermId
    ]) {
        if (ate.Division_Enrollments__r != null) {
            for (Division_Enrollment__c de : ate.Division_Enrollments__r) {
                if (de.Division__r != null) {
                    String divName = de.Division__r.Division_Name__c != null ? de.Division__r.Division_Name__c : '';
                    String divGroup = (de.Division__r.Division_Group__r != null && de.Division__r.Division_Group__r.Name != null)
                        ? de.Division__r.Division_Group__r.Name : '';
                    rows.add(new DivisionRow(de.Id != null ? String.valueOf(de.Id) : '', divName, divGroup));
                }
            }
        }
    }
    return rows;
}

/**
 * Wrapper for combined table row:
 * Course Name, Credits, Course Type, specialisation, Division Name, Division Group
 */
public class DivisionCourseRow {
    @AuraEnabled public String id;
    @AuraEnabled public String courseName;
    @AuraEnabled public String credits;
    @AuraEnabled public String courseType;
    @AuraEnabled public String specialisation;
    @AuraEnabled public String divisionName;
    @AuraEnabled public String divisionGroup;

    public DivisionCourseRow(String id, String courseName, String credits, String courseType, String specialisation, String divisionName, String divisionGroup) {
        this.id = id;
        this.courseName = courseName;
        this.credits = credits;
        this.courseType = courseType;
        this.specialisation = specialisation;
        this.divisionName = divisionName;
        this.divisionGroup = divisionGroup;
    }
}

/**
 * Division courses for the learner's enrolled divisions.
 * If currentTermId is passed, rows are scoped to that term's enrollments.
 */
@AuraEnabled(cacheable=true)
public static List<DivisionCourseRow> getDivisionCourseTable(Id currentTermId) {
    List<DivisionCourseRow> rows = new List<DivisionCourseRow>();
    Id accountId = null;
    try {
        User currentUser = [SELECT Id, ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (currentUser.ContactId != null) {
            Contact c = [SELECT AccountId FROM Contact WHERE Id = :currentUser.ContactId LIMIT 1];
            accountId = c.AccountId;
        }
    } catch (Exception e) {
        return rows;
    }
    if (accountId == null) return rows;

    // 1) Division_Enrollment__c: divisions for learner account (scoped by selected term when provided)
    List<Division_Enrollment__c> divisionEnrollments;
    if (currentTermId != null) {
        divisionEnrollments = [
            SELECT Id,
                   Division__r.Id,
                   Division__r.Division_Name__c,
                   Division__r.Division_Group__r.Name,
                   Student_Name__c,
                   Academic_Term_Enrollment__r.LearnerAccountId
            FROM Division_Enrollment__c
            WHERE Academic_Term_Enrollment__r.LearnerAccountId = :accountId
              AND Academic_Term_Enrollment__r.AcademicTermId = :currentTermId
        ];
    } else {
        divisionEnrollments = [
            SELECT Id,
                   Division__r.Id,
                   Division__r.Division_Name__c,
                   Division__r.Division_Group__r.Name,
                   Student_Name__c,
                   Academic_Term_Enrollment__r.LearnerAccountId
            FROM Division_Enrollment__c
            WHERE Academic_Term_Enrollment__r.LearnerAccountId = :accountId
        ];
    }

    Set<Id> divisionIds = new Set<Id>();
    for (Division_Enrollment__c de : divisionEnrollments) {
        if (de.Division__r != null && de.Division__r.Id != null) {
            divisionIds.add(de.Division__r.Id);
        }
    }
    if (divisionIds.isEmpty()) return rows;

    // 2) DivisionCourse__c for all collected Division__c Ids
    for (DivisionCourse__c dc : [
        SELECT Id,
               Course_Offering__r.Course_Type__c,Course_Offering__r.ProgramCourse__r.Course_Credit__c,
               Course_Name__c,
               Division__r.Division_Group__r.Name,
               Division__r.Division_Name__c,Course_Offering__r.ProgramCourse__r.SPJIMR_specialisation__r.specialisation_Name__r.Name
        FROM DivisionCourse__c
        WHERE Division__c IN :divisionIds
    ]) {
        rows.add(new DivisionCourseRow(
            String.valueOf(dc.Id),
            dc.Course_Name__c != null ? dc.Course_Name__c : '',
            //(dc.Course_Offering__r != null && dc.Course_Offering__r.ProgramCourse__r != null) ? dc.Course_Offering__r.ProgramCourse__r.Course_Credit__c : '',
            dc.Course_Offering__r?.ProgramCourse__r?.Course_Credit__c != null ? String.valueOf(dc.Course_Offering__r.ProgramCourse__r.Course_Credit__c) : '-',
            (dc.Course_Offering__r != null && dc.Course_Offering__r.Course_Type__c != null) ? dc.Course_Offering__r.Course_Type__c : '',
            dc.Course_Offering__r.ProgramCourse__r.SPJIMR_specialisation__r.specialisation_Name__r.Name,
            (dc.Division__r != null && dc.Division__r.Division_Name__c != null) ? dc.Division__r.Division_Name__c : '',
            (dc.Division__r != null && dc.Division__r.Division_Group__r != null && dc.Division__r.Division_Group__r.Name != null) ? dc.Division__r.Division_Group__r.Name : ''
        ));
    }

    return rows;
}

@AuraEnabled(cacheable=true)
public static List<Emergency_Details__c> fetchEmergencyDetails() {

    // Get current user's AccountId safely
    Id accountId = [ SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId()].AccountId;

    
    if (accountId == null) {
        return new List<Emergency_Details__c>();
    }

   
    return [SELECT Id,Name,Relationship__c,Address__c,Phone__c,Alternate_Number__c FROM Emergency_Details__c WHERE Account__c = :accountId];
}

@AuraEnabled
public static String saveEmergencyContact(String recordId, String name, String relationship, String phone, String alternateNumber, String address) {
    try {
        // Get current user's AccountId
        Id accountId = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].AccountId;
        if (accountId == null) {
            User u = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if (u.ContactId != null) {
                accountId = [SELECT AccountId FROM Contact WHERE Id = :u.ContactId LIMIT 1].AccountId;
            }
        }
        if (accountId == null) {
            throw new AuraHandledException('User Account ID not found');
        }

        Emergency_Details__c emergencyDetail;
        
        if (String.isNotBlank(recordId)) {
            emergencyDetail = [SELECT Id FROM Emergency_Details__c WHERE Id = :recordId LIMIT 1];
        } else {
            emergencyDetail = new Emergency_Details__c();
            emergencyDetail.Account__c = accountId;
        }
        
        emergencyDetail.Name = name;
        emergencyDetail.Relationship__c = relationship;
        emergencyDetail.Phone__c = phone;
        emergencyDetail.Alternate_Number__c = alternateNumber;
        emergencyDetail.Address__c = address;
        
        upsert emergencyDetail;
        
        return emergencyDetail.Id;
    } catch (Exception e) {
        throw new AuraHandledException('Error saving emergency contact: ' + e.getMessage());
    }
}

    // ---------- Profile photo (passport photo) ----------
    private static final String PASSPORT_PHOTO_NAME = 'PASSPORT_PHOTO';
    private static final Set<String> ALLOWED_EXTENSIONS = new Set<String>{ 'jpg', 'jpeg', 'png' };

    @AuraEnabled
    public static Id getOrCreatePassportPhotoDocumentDetail(Id accountId) {
        if (accountId == null) throw new AuraHandledException('Account ID is required.');
        List<Document_Details__c> docs = [
            SELECT Id FROM Document_Details__c
            WHERE Student_Name__c = :accountId AND Name = :PASSPORT_PHOTO_NAME
            LIMIT 1
        ];
        if (!docs.isEmpty()) return docs[0].Id;
        Document_Details__c doc = new Document_Details__c(
            Name = PASSPORT_PHOTO_NAME,
            Student_Name__c = accountId
        );
        insert doc;
        return doc.Id;
    }

    @AuraEnabled
    public static String uploadProfilePhoto(Id accountId, String base64Data, String fileName, String userName, String rollNumber) {
        if (accountId == null || String.isBlank(base64Data) || String.isBlank(fileName)) {
            throw new AuraHandledException('Account ID, file data, and file name are required.');
        }
        String ext = fileName.substringAfterLast('.').toLowerCase();
        if (!ALLOWED_EXTENSIONS.contains(ext)) {
            throw new AuraHandledException('Only JPG, JPEG, and PNG formats are allowed.');
        }
        String safeName = (userName != null ? userName : 'User').replaceAll('[^a-zA-Z0-9]', '_');
        String safeRoll = (rollNumber != null ? rollNumber : '').replaceAll('[^a-zA-Z0-9]', '_');
        String title = safeName + '_' + safeRoll + '_' + System.now().getTime();
        if (title.length() > 255) title = title.substring(0, 255);

        Id docDetailId = getOrCreatePassportPhotoDocumentDetail(accountId);

        // Deactivate other profile photos for this account (only one isActive = true)
        Set<Id> docDetailIds = new Set<Id>{ docDetailId };
        List<ContentDocumentLink> cdlList = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docDetailIds
        ];
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdlList) contentDocIds.add(cdl.ContentDocumentId);
        if (!contentDocIds.isEmpty()) {
            List<ContentVersion> toDeactivate = [
                SELECT Id FROM ContentVersion
                WHERE ContentDocumentId IN :contentDocIds
                AND (Is_Profile_Photo__c = true OR isActive__c = true)
                AND IsLatest = true
            ];
            for (ContentVersion cv : toDeactivate) {
                cv.isActive__c = false;
                cv.Is_Profile_Photo__c = false;
            }
            if (!toDeactivate.isEmpty()) update toDeactivate;
        }

        ContentVersion cv = new ContentVersion();
        cv.Title = title;
        cv.PathOnClient = title + '.' + ext;
        cv.VersionData = EncodingUtil.base64Decode(base64Data);
        cv.Is_Profile_Photo__c = true;
        cv.isActive__c = true;
        insert cv;

        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cv.ContentDocumentId;
        cdl.LinkedEntityId = docDetailId;
        cdl.Visibility = 'AllUsers';
        cdl.ShareType = 'V';
        insert cdl;

        return cv.Id;
    }

    @AuraEnabled(cacheable=false)
    public static String getProfilePhotoContentVersionId(Id accountId) {
        if (accountId == null) return null;
        List<Document_Details__c> docs = [
            SELECT Id FROM Document_Details__c
            WHERE Student_Name__c = :accountId AND Name = 'PASSPORT_PHOTO'
            LIMIT 1
        ];
        if (docs.isEmpty()) return null;
        Set<Id> docDetailIds = new Set<Id>{ docs[0].Id };
        List<ContentDocumentLink> cdlList = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docDetailIds
        ];
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdlList) contentDocIds.add(cdl.ContentDocumentId);
        if (contentDocIds.isEmpty()) return null;
        List<ContentVersion> cvs = [
            SELECT Id FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds
            AND isActive__c = true AND Is_Profile_Photo__c = true
            LIMIT 1
        ];
        return cvs.isEmpty() ? null : cvs[0].Id;
    }

    /** Returns profile photo as base64 data URL for reliable display in LWC (avoids download-URL issues in Community). */
    @AuraEnabled(cacheable=false)
    public static String getProfilePhotoBase64(Id accountId) {
        if (accountId == null) return null;
        List<Document_Details__c> docs = [
            SELECT Id FROM Document_Details__c
            WHERE Student_Name__c = :accountId AND Name = :PASSPORT_PHOTO_NAME
            LIMIT 1
        ];
        if (docs.isEmpty()) return null;
        Set<Id> docDetailIds = new Set<Id>{ docs[0].Id };
        List<ContentDocumentLink> cdlList = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :docDetailIds
        ];
        Set<Id> contentDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : cdlList) contentDocIds.add(cdl.ContentDocumentId);
        if (contentDocIds.isEmpty()) return null;
        // Only true image files (excludes PDFs / misc uploads that might have been flagged incorrectly).
        // IsLatest = true avoids stale versions; prefer most recently created image.
        List<ContentVersion> cvs = [
            SELECT Id, VersionData, FileType, FileExtension
            FROM ContentVersion
            WHERE ContentDocumentId IN :contentDocIds
            AND IsLatest = true
            AND isActive__c = true
            AND Is_Profile_Photo__c = true
            AND (
                FileType IN ('PNG', 'JPG', 'JPEG')
                OR FileExtension IN ('png', 'jpg', 'jpeg', 'PNG', 'JPG', 'JPEG')
            )
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (cvs.isEmpty()) return null;
        ContentVersion cv = cvs[0];
        String mime = 'image/jpeg';
        String ext = (cv.FileExtension != null) ? cv.FileExtension.toLowerCase() : '';
        if (cv.FileType == 'PNG' || ext == 'png') mime = 'image/png';
        else if (cv.FileType == 'JPG' || cv.FileType == 'JPEG' || ext == 'jpg' || ext == 'jpeg') mime = 'image/jpeg';
        String b64 = EncodingUtil.base64Encode(cv.VersionData);
        return 'data:' + mime + ';base64,' + b64;
    }

    /**
     * Profile photo upload window for the current learner's cohort, evaluated at server time
     * using Profile_Window_Start_Time__c and Profile_Window_End_Time__c on ProgramCohort.
     * Not cacheable so the LWC can poll for midnight/window boundaries.
     */
    public class ProfileUploadWindowStatus {
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String endTimeFormatted { get; set; }
    }

    @AuraEnabled(cacheable = false)
    public static ProfileUploadWindowStatus getProfileUploadWindowStatus() {
        ProfileUploadWindowStatus status = new ProfileUploadWindowStatus();
        status.isActive = false;
        status.endTimeFormatted = '';
        try {
            try {
                if (Auth.CommunitiesUtil.isGuestUser()) {
                    return status;
                }
            } catch (Exception guestCheckEx) {
                // Not in community context; continue
            }
            User currentUser = [
                SELECT Id, ContactId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            if (currentUser.ContactId == null) {
                return status;
            }
            Contact userContact = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :currentUser.ContactId
                LIMIT 1
            ];
            Id accountId = userContact.AccountId;
            if (accountId == null) {
                return status;
            }
            List<ProgramCohortMember> memberRows = [
                SELECT
                    ProgramCohort.Profile_Window_Start_Time__c,
                    ProgramCohort.Profile_Window_End_Time__c
                FROM ProgramCohortMember
                WHERE ProgramEnrolleeId = :accountId
                LIMIT 1
            ];
            if (memberRows.isEmpty()) {
                return status;
            }
            Datetime startT = memberRows[0].ProgramCohort.Profile_Window_Start_Time__c;
            Datetime endT = memberRows[0].ProgramCohort.Profile_Window_End_Time__c;
            if (startT == null || endT == null) {
                return status;
            }
            Datetime now = System.now();
            status.isActive = (now >= startT && now <= endT);
            // Display deadline in India Standard Time (IST) for students
            status.endTimeFormatted = endT.format('MMMM d, yyyy h:mm a z', 'Asia/Kolkata');
        } catch (Exception e) {
            System.debug('getProfileUploadWindowStatus: ' + e.getMessage());
        }
        return status;
    }

}