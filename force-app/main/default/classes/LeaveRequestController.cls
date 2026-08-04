public without sharing class LeaveRequestController {

    /* =========================================================
       GET SESSIONS
    ========================================================= */
    @AuraEnabled
public static List<SessionWrapper> getSessions(String startDate, String endDate) {

    if(startDate == null || endDate == null){
        return new List<SessionWrapper>();
    }
//test
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
        AND Session__r.Start_Time__c >= :startDT    // FIX: SE-1170,Se-1171changed from partial-overlap check to full-containment check// Only show sessions the student misses ENTIRELY during the leave window,// not sessions they're only partially absent for.
        AND Session__r.End_Time__c   <= :endDT      // Only show sessions the student misses ENTIRELY during the leave window,// not sessions they're only partially absent for.
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
    Datetime startDT = Datetime.valueOf(startClean);   // FIX:SE-1171,1170 changed from valueOfGmt to valueOf — same timezone bug as getSessions(),
    Datetime endDT   = Datetime.valueOf(endClean);       // was causing leave records to be saved with Start_Date__c/End_Date__c shifted

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