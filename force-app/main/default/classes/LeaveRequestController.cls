public without sharing class LeaveRequestController {

    @AuraEnabled
    public static List<SessionWrapper> getSessions(String startDate, String endDate) {

        if(startDate == null || endDate == null){
            return new List<SessionWrapper>();
        }

        List<Id> ateIds = getStudentATEIds();

        if(ateIds.isEmpty()){
            return new List<SessionWrapper>();
        }

        String startClean = startDate.replace('T', ' ').left(19);
        String endClean   = endDate.replace('T', ' ').left(19);
        // FIX: SE-1170 SE-1171 changed from valueOfGmt to valueOf — input strings are local time,
        // not GMT, so valueOfGmt was shifting every comparison by the org's UTC offset.
        Datetime startDT = Datetime.valueOf(startClean);
        Datetime endDT   = Datetime.valueOf(endClean);

        List<Session_Enrollment__c> enrollments = [
            SELECT Id,
                   Session__c,
                   Session__r.Name,
                   Session__r.Start_Time__c,
                   Session__r.End_Time__c,
                   Attendance__c
            FROM Session_Enrollment__c
            WHERE Academic_Term_Enrollment__c IN :ateIds
            AND Session__r.Start_Time__c >= :startDT   // FIX: SE-1170,SE-1171 changed from partial-overlap check to full-containment check
            AND Session__r.End_Time__c   <= :endDT     // Only show sessions the student misses ENTIRELY during the leave window
        ];

        List<SessionWrapper> result = new List<SessionWrapper>();

        for(Session_Enrollment__c se : enrollments){
            result.add(new SessionWrapper(
                se.Id,
                se.Session__c,
                se.Session__r.Name,
                se.Session__r.Start_Time__c,
                se.Session__r.End_Time__c,
                se.Attendance__c
            ));
        }

        return result;
    }


    /* =========================================================
       SAVE LEAVE REQUEST
       (Handles both the "has clashing sessions" and "no clashing
       sessions" paths — the latter is called with an empty
       sessionEnrollmentIds list from handleApply's LWC-side branch
       where getSessions() returned nothing.)
    ========================================================= */

    @AuraEnabled
    public static Id saveLeaveRequest(String startDate,
                                  String endDate,
                                  String leaveType,
                                  String remark,
                                  List<Id> sessionEnrollmentIds,
                                  List<Id> uploadedFileIds) {

        if(startDate == null || endDate == null){
            throw new AuraHandledException('Invalid date range.');
        }
        String startClean = startDate.replace('T', ' ').left(19);
        String endClean   = endDate.replace('T', ' ').left(19);
        Datetime startDT = Datetime.valueOf(startClean);   // FIX: SE-1171,1170 changed from valueOfGmt to valueOf — same timezone bug as getSessions(),
        Datetime endDT   = Datetime.valueOf(endClean);      // was causing leave records to be saved with Start_Date__c/End_Date__c shifted

        // -------------------------------------------------
        // GET USER + CONTACT + ACCOUNT
        // -------------------------------------------------

        User u = [
            SELECT Id, ContactId, Contact.AccountId, AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Id contactId        = u.ContactId;
        Id studentAccountId;

        if(contactId != null){
            studentAccountId = u.Contact.AccountId;
        } else if(u.AccountId != null){
            studentAccountId = u.AccountId;
        } else{
            throw new AuraHandledException('No Contact or Account found.');
        }

        // -------------------------------------------------
        // GET TERM ENROLLMENT (CONTACT REQUIRED)
        // -------------------------------------------------

        if(contactId == null){
            throw new AuraHandledException('Contact required for Term Enrollment.');
        }

        List<AcademicTermEnrollment> ateList = [
            SELECT Id
            FROM AcademicTermEnrollment
            WHERE LearnerContactId = :contactId
            LIMIT 1
        ];

        if(ateList.isEmpty()){
            throw new AuraHandledException('No Term Enrollment found.');
        }

        Id termEnrollmentId = ateList[0].Id;

        // -------------------------------------------------
        // GET PROGRAM ENROLLMENT
        // -------------------------------------------------

        List<ProgramEnrollment> peList;

        if(contactId != null && studentAccountId != null){
            peList = [
                SELECT Id, ContactId, AccountId
                FROM ProgramEnrollment
                WHERE ContactId = :contactId
                OR AccountId   = :studentAccountId
                LIMIT 1
            ];
        } else if(contactId != null){
            peList = [
                SELECT Id, ContactId, AccountId
                FROM ProgramEnrollment
                WHERE ContactId = :contactId
                LIMIT 1
            ];
        } else{
            peList = [
                SELECT Id, ContactId, AccountId
                FROM ProgramEnrollment
                WHERE AccountId = :studentAccountId
                LIMIT 1
            ];
        }

        if(peList.isEmpty()){
            throw new AuraHandledException('No Program Enrollment found.');
        }

        // -------------------------------------------------
        // GET PROGRAM COHORT MEMBER
        // -------------------------------------------------

        List<ProgramCohortMember> pcmList;

        if(contactId != null && studentAccountId != null){
            pcmList = [
                SELECT Id
                FROM ProgramCohortMember
                WHERE
                    (ProgramEnrollment.ContactId = :contactId
                    OR ProgramEnrollment.AccountId = :studentAccountId)
                AND ProgramEnrollmentStatus = 'Enrolled in Batch'
                LIMIT 1
            ];
        } else if(contactId != null){
            pcmList = [
                SELECT Id
                FROM ProgramCohortMember
                WHERE ProgramEnrollment.ContactId = :contactId
                AND ProgramEnrollmentStatus = 'Enrolled in Batch'
                LIMIT 1
            ];
        } else{
            pcmList = [
                SELECT Id
                FROM ProgramCohortMember
                WHERE ProgramEnrollment.AccountId = :studentAccountId
                AND ProgramEnrollmentStatus = 'Enrolled in Batch'
                LIMIT 1
            ];
        }

        Id batchEnrollmentId;

        if(!pcmList.isEmpty()){
            batchEnrollmentId = pcmList[0].Id;
        }

        // -------------------------------------------------
        // CREATE LEAVE APPLICATION
        // -------------------------------------------------

        Leave_Application__c leaveRec = new Leave_Application__c();
        leaveRec.Start_Date__c       = startDT;
        leaveRec.End_Date__c         = endDT;
        leaveRec.Leave_Type__c       = leaveType;
        leaveRec.Reason__c           = remark;
        leaveRec.Term_Enrollment__c  = termEnrollmentId;
        leaveRec.Student__c          = studentAccountId;

        if(batchEnrollmentId != null){
            leaveRec.Batch_Enrollment__c = batchEnrollmentId;
        }

        // Populate Batch__c / Division__c / Division_Name__c / Programme_Master__c /
        // Batch_Group__c / Term__c from the student's current enrollment hierarchy.
        populateStudentHierarchyFields(leaveRec, studentAccountId, batchEnrollmentId);

        insert leaveRec;

        System.enqueueJob(new LeaveSubmissionController.SubmitLeaveJob(leaveRec.Id));

        // -------------------------------------------------
        // MISSED SESSION LOGIC
        // -------------------------------------------------

        if(sessionEnrollmentIds != null && !sessionEnrollmentIds.isEmpty()){

            List<Session_Enrollment__c> enrollments = [
                SELECT Id, Session__c,
                       Session__r.Start_Time__c,
                       Session__r.End_Time__c
                FROM Session_Enrollment__c
                WHERE Id IN :sessionEnrollmentIds
            ];

            List<Missed_Sessions__c> missedList = new List<Missed_Sessions__c>();

            for(Session_Enrollment__c se : enrollments){
                Boolean covered = se.Session__c != null && MissedSessionSyncService.isCovered(
                    startDT,
                    endDT,
                    se.Session__r.Start_Time__c,
                    se.Session__r.End_Time__c
                );
                if(covered){
                    Missed_Sessions__c ms         = new Missed_Sessions__c();
                    ms.Leave_Application__c        = leaveRec.Id;
                    ms.Session_Enrollment__c       = se.Id;
                    missedList.add(ms);
                }
            }

            if(!missedList.isEmpty()){
                insert missedList;
            }
        }

        return leaveRec.Id;
    }


    /* =========================================================
       POPULATE STUDENT HIERARCHY LOOKUPS ON LEAVE APPLICATION

       Confirmed field mappings (via Object Manager, per screenshots):
         - Batch__c            <- ProgramCohortMember.ProgramCohortId
         - Programme_Master__c <- ProgramEnrollment.ProgramId
         - Term__c              <- current active AcademicTermEnrollment.AcademicTermId
                                    (same "current term" logic as
                                    StudentProfileDashboardController.getUserInfo())
         - Batch_Group__c      <- AcademicTerm.AcademicYearId
                                    (the field labeled "Batch Group" on the Term
                                    object — Lookup(Batch Group). NOT sourced from
                                    Division; that was the earlier bug that threw
                                    FIELD_INTEGRITY_EXCEPTION because
                                    Division__r.Division_Group__c pointed to a
                                    different object than Batch_Group__c expects.)
         - Division__c /
           Division_Name__c    <- Division_Enrollment__c.Division__c /
                                    Division__r.Division_Name__c, scoped to the
                                    student's current-term AcademicTermEnrollment
    ========================================================= */
    private static void populateStudentHierarchyFields(Leave_Application__c leaveRec,
                                                         Id studentAccountId,
                                                         Id batchEnrollmentId) {

        if (studentAccountId == null) {
            return;
        }

        // Batch__c
        if (batchEnrollmentId != null) {
            List<ProgramCohortMember> pcmList = [
                SELECT ProgramCohortId
                FROM ProgramCohortMember
                WHERE Id = :batchEnrollmentId
                LIMIT 1
            ];
            if (!pcmList.isEmpty()) {
                leaveRec.Batch__c = pcmList[0].ProgramCohortId;
            }
        }

        // Programme_Master__c
        List<ProgramEnrollment> peList = [
            SELECT ProgramId
            FROM ProgramEnrollment
            WHERE AccountId = :studentAccountId
            LIMIT 1
        ];
        if (!peList.isEmpty()) {
            leaveRec.Programme_Master__c = peList[0].ProgramId;
        }

        // Current active AcademicTermEnrollment (same logic as getUserInfo())
        Date todayDate = Date.today();
        Id currentTermId;

        for (AcademicTermEnrollment ate : [
            SELECT Id, AcademicTermId,
                   AcademicTerm.Term_Start_Date__c,
                   AcademicTerm.Term_End_Date__c,
                   AcademicTerm.Is_Active__c
            FROM AcademicTermEnrollment
            WHERE LearnerAccountId = :studentAccountId
            ORDER BY AcademicTerm.Term_Start_Date__c DESC
        ]) {
            Boolean termInRange = ate.AcademicTerm.Term_Start_Date__c != null
                && ate.AcademicTerm.Term_End_Date__c != null
                && ate.AcademicTerm.Term_Start_Date__c <= todayDate
                && ate.AcademicTerm.Term_End_Date__c >= todayDate;
            if (ate.AcademicTerm.Is_Active__c == true && termInRange) {
                currentTermId = ate.AcademicTermId;
                break;
            }
        }

        if (currentTermId != null) {
            leaveRec.Term__c = currentTermId;

            // Batch_Group__c comes from Term.AcademicYearId (field labeled
            // "Batch Group" on the Term object) — confirmed via Object Manager.
            List<AcademicTerm> termList = [
                SELECT AcademicYearId
                FROM AcademicTerm
                WHERE Id = :currentTermId
                LIMIT 1
            ];
            if (!termList.isEmpty() && termList[0].AcademicYearId != null) {
                leaveRec.Batch_Group__c = termList[0].AcademicYearId;
            }
        }

        // Division__c / Division_Name__c
        if (currentTermId != null) {
            List<Division_Enrollment__c> deList = [
                SELECT Division__c,
                       Division__r.Division_Name__c
                FROM Division_Enrollment__c
                WHERE Academic_Term_Enrollment__r.LearnerAccountId = :studentAccountId
                AND Academic_Term_Enrollment__r.AcademicTermId = :currentTermId
                LIMIT 1
            ];
            if (!deList.isEmpty() && deList[0].Division__c != null) {
                leaveRec.Division__c      = deList[0].Division__c;
                leaveRec.Division_Name__c = deList[0].Division__r.Division_Name__c;
            }
        }
    }


    /* =========================================================
       FILE UPLOAD
    ========================================================= */

    @AuraEnabled
    public static Id uploadFiles(Id leaveId,
                                 List<String> fileNames,
                                 List<String> base64DataList) {

        if(leaveId == null){
            throw new AuraHandledException('Leave Id is required.');
        }

        if(base64DataList == null || base64DataList.isEmpty()){
            return leaveId;
        }

        List<ContentVersion> versions = new List<ContentVersion>();

        for(Integer i = 0; i < base64DataList.size(); i++){
            ContentVersion cv  = new ContentVersion();
            cv.Title           = fileNames[i];
            cv.PathOnClient    = fileNames[i];
            cv.VersionData     = EncodingUtil.base64Decode(base64DataList[i]);
            versions.add(cv);
        }

        insert versions;

        Set<Id> versionIds = new Set<Id>();
        for(ContentVersion cv : versions){
            versionIds.add(cv.Id);
        }

        List<ContentVersion> insertedVersions = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id IN :versionIds
        ];

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for(ContentVersion cv : insertedVersions){
            links.add(new ContentDocumentLink(
                ContentDocumentId = cv.ContentDocumentId,
                LinkedEntityId    = leaveId,
                ShareType         = 'V',
                Visibility        = 'AllUsers'
            ));
        }

        insert links;

        return leaveId;
    }


    /* =========================================================
       BATCH DATE RANGE (for leave date validation)
       ProgramCohort.StartDate / EndDate = Batch Start / End Date
    ========================================================= */

    public class BatchDateRange {
        @AuraEnabled public Date batchStartDate;
        @AuraEnabled public Date batchEndDate;
        @AuraEnabled public Boolean hasBatchDates;
    }

    @AuraEnabled(cacheable=true)
    public static BatchDateRange getBatchDateRange() {
        BatchDateRange result = new BatchDateRange();
        result.hasBatchDates = false;

        User u = [
            SELECT ContactId, Contact.AccountId, AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        Id studentAccountId;
        if (u.ContactId != null) {
            studentAccountId = u.Contact.AccountId;
        } else if (u.AccountId != null) {
            studentAccountId = u.AccountId;
        }

        if (studentAccountId == null) {
            return result;
        }

        List<ProgramCohortMember> memberRows = [
            SELECT ProgramCohort.StartDate, ProgramCohort.EndDate
            FROM ProgramCohortMember
            WHERE ProgramEnrolleeId = :studentAccountId
               OR ProgramEnrollment.AccountId = :studentAccountId
            LIMIT 1
        ];

        if (memberRows.isEmpty()) {
            return result;
        }

        Date batchStart = memberRows[0].ProgramCohort.StartDate;
        Date batchEnd   = memberRows[0].ProgramCohort.EndDate;
        if (batchStart == null || batchEnd == null) {
            return result;
        }

        result.hasBatchDates  = true;
        result.batchStartDate = batchStart;
        result.batchEndDate   = batchEnd;
        return result;
    }

    /* =========================================================
       GET STUDENT TERM ENROLLMENT IDS
    ========================================================= */

    private static List<Id> getStudentATEIds(){

        List<Id> ateIds = new List<Id>();

        User u = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        if(u.ContactId == null){
            return ateIds;
        }

        List<AcademicTermEnrollment> ateList = [
            SELECT Id
            FROM AcademicTermEnrollment
            WHERE LearnerContactId = :u.ContactId
        ];

        for(AcademicTermEnrollment ate : ateList){
            ateIds.add(ate.Id);
        }

        return ateIds;
    }


    /* =========================================================
       WRAPPER CLASS
    ========================================================= */

    public class SessionWrapper {

        @AuraEnabled public Id       enrollmentId;
        @AuraEnabled public Id       sessionId;
        @AuraEnabled public String   sessionName;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String   attendance;

        public SessionWrapper(Id       enrollmentId,
                              Id       sessionId,
                              String   sessionName,
                              Datetime startTime,
                              Datetime endTime,
                              String   attendance){

            this.enrollmentId = enrollmentId;
            this.sessionId    = sessionId;
            this.sessionName  = sessionName;
            this.startTime    = startTime;
            this.endTime      = endTime;
            this.attendance   = attendance;
        }
    }
}