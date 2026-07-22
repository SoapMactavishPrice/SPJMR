/**
 * Controller for Student Portal Attendance & Schedule.
 * Fetches sessions for the logged-in user's Account (LearnerAccountId) via:
 * Session -> Session_Enrollment__c -> Academic_Term_Enrollment__c -> LearnerAccountId
 */
public without sharing class StudentScheduleController {

    public class ScheduleFilter {
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String sessionType { get; set; } // Course_Activity__c value for filter
    }

    public class SessionSummaryDto {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public Date sessionDate { get; set; }
        @AuraEnabled public String startTime { get; set; }
        @AuraEnabled public String endTime { get; set; }
        @AuraEnabled public String courseActivity { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String instructorNames { get; set; }
    }

    private static final String DISPLAY_TZ = 'Asia/Kolkata';
   
    public class SessionDetailDto {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String instructorNames { get; set; }
        @AuraEnabled public String sessionDateFormatted { get; set; }
        @AuraEnabled public String startTime { get; set; }
        @AuraEnabled public String endTime { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public String activityType { get; set; }
        @AuraEnabled public String sessionName { get; set; }
        @AuraEnabled public List<FileDto> files { get; set; }
        @AuraEnabled public String url { get; set; }
    }

    public class FileDto {
        @AuraEnabled public Id contentDocumentId { get; set; }
        @AuraEnabled public String title { get; set; }
        public FileDto() {}
        public FileDto(Id contentDocumentId, String title) {
            this.contentDocumentId = contentDocumentId;
            this.title = title;
        }
    }

    /**
     * Get the current user's Learner Account Id (Contact.AccountId for community user).
     */
    @AuraEnabled(cacheable=true)
    public static Id getLearnerAccountId() {
        User currentUser = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (currentUser.ContactId == null) {
            return null;
        }
        List<Contact> contacts = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :currentUser.ContactId
            AND AccountId != null
            LIMIT 1
        ];
        return contacts.isEmpty() ? null : contacts[0].AccountId;
    }

    /**
     * Get sessions for the logged-in student (enrolled via Session_Enrollment__c -> Academic_Term_Enrollment__c).
     * Matches by LearnerAccountId (Contact.AccountId) OR LearnerContactId (User.ContactId) so sessions show
     * when enrollment is keyed by Account (e.g. "naman test") or by Contact.
     */
    @AuraEnabled(cacheable=true)
    public static List<SessionSummaryDto> getEnrolledSessions(String filterJson) {
        System.debug('inside getEnrolledSessions');
        System.debug('filterJson:'+filterJson);
        User currentUser = [
            SELECT Id, ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        Id contactId = currentUser.ContactId;
        Id accountId = null;

        if (contactId != null) {
            List<Contact> contacts = [
                SELECT AccountId
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            if (!contacts.isEmpty() && contacts[0].AccountId != null) {
                accountId = contacts[0].AccountId;
            }
        }
        system.debug('accountId+contactId:'+accountId+contactId);
        if (accountId == null && contactId == null) {
            system.debug('line 100');
            return new List<SessionSummaryDto>();
        }

        ScheduleFilter filter = parseFilter(filterJson);
        Date startDate = filter != null && filter.startDate != null ? normalizeDate(filter.startDate) : null;
        Date endDate = filter != null && filter.endDate != null ? normalizeDate(filter.endDate) : null;
        String sessionType = filter != null ? filter.sessionType : null;

        // Session_Enrollment__c -> Academic_Term_Enrollment__c: match by Account and/or Contact
        Set<Id> enrolledSessionIds = new Set<Id>();
        // SE-737U START: capture Division Color (picklist on Division__c) per session so the student tile uses the Division Color, not Session.Color__c
        Map<Id, String> divisionColorBySession = new Map<Id, String>();
        // SE-737U END

        if(accountId != null && contactId != null){
            for(Session_Enrollment__c se : [SELECT Id, Name, Session__c, Session__r.Name, Session__r.Start_Time__c, Session__r.End_Time__c,  Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.Name ,Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail,  Session__r.Schedule_Type__c, Division_Enrollment__r.Division__r.Division_Color__c FROM Session_Enrollment__c WHERE Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.Id = :accountId AND (Session__r.Schedule_Type__c = 'Published' or Session__r.Schedule_Type__c = 'Republished')]){
                enrolledSessionIds.add(se.Session__c);
                // SE-737U START
                if (se.Division_Enrollment__r != null && se.Division_Enrollment__r.Division__r != null
                        && se.Division_Enrollment__r.Division__r.Division_Color__c != null) {
                    divisionColorBySession.put(se.Session__c, String.valueOf(se.Division_Enrollment__r.Division__r.Division_Color__c));
                }
                // SE-737U END
            }
        }
        if (enrolledSessionIds.isEmpty()) {
            system.debug('line 144');
            return new List<SessionSummaryDto>();
        }

        Boolean filterByType = String.isNotBlank(sessionType);
        List<Session__c> sessions;
        if (startDate != null && endDate != null) {

            if (filterByType) {
                sessions = [SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Course_Activity__c, Course__r.Name, Color__c FROM Session__c WHERE Id IN :enrolledSessionIds AND (Schedule_Type__c ='Published' or Schedule_Type__c ='Republished')  AND Session_Date__c >= :startDate AND Session_Date__c <= :endDate AND Course_Activity__c = :sessionType ORDER BY Session_Date__c, Start_Time__c];

            } else {
                sessions = [SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Course_Activity__c, Course__r.Name, Color__c FROM Session__c WHERE Id IN :enrolledSessionIds AND (Schedule_Type__c ='Published' or Schedule_Type__c ='Republished')  AND Session_Date__c >= :startDate AND Session_Date__c <= :endDate ORDER BY Session_Date__c, Start_Time__c];

            }
        } else if (startDate != null) {
            if (filterByType) {

                sessions = [SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Course_Activity__c, Course__r.Name, Color__c FROM Session__c WHERE Id IN :enrolledSessionIds AND (Schedule_Type__c ='Published' or Schedule_Type__c ='Republished')  AND Session_Date__c >= :startDate AND Course_Activity__c = :sessionType ORDER BY Session_Date__c, Start_Time__c];
            } else {

                sessions = [SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Course_Activity__c, Course__r.Name, Color__c FROM Session__c WHERE Id IN :enrolledSessionIds AND (Schedule_Type__c ='Published' or Schedule_Type__c ='Republished')  AND Session_Date__c >= :startDate ORDER BY Session_Date__c, Start_Time__c];
            }
        } else if (endDate != null) {
            if (filterByType) {
                sessions = [SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Course_Activity__c, Course__r.Name, Color__c FROM Session__c WHERE Id IN :enrolledSessionIds AND (Schedule_Type__c ='Published' or Schedule_Type__c ='Republished')  AND Session_Date__c <= :endDate AND Course_Activity__c = :sessionType ORDER BY Session_Date__c, Start_Time__c];
            } else {
                sessions = [SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Course_Activity__c, Course__r.Name, Color__c FROM Session__c WHERE Id IN :enrolledSessionIds AND (Schedule_Type__c ='Published' or Schedule_Type__c ='Republished')  AND Session_Date__c <= :endDate ORDER BY Session_Date__c, Start_Time__c];
            }
        } 

        // Bulk fetch instructor names for these sessions
        Set<Id> sessionIds = new Set<Id>();
        for (Session__c s : sessions) sessionIds.add(s.Id);
        Map<Id, List<String>> facultyBySession = new Map<Id, List<String>>();
        try {
            for (Session_Faculty__c sf : [
                SELECT Session__c, Session_Faculty__r.Name
                FROM Session_Faculty__c
                WHERE Session__c IN :sessionIds
                AND Session_Faculty__r.Name != null
            ]) {
                if (sf.Session_Faculty__r == null || String.isBlank(sf.Session_Faculty__r.Name)) continue;
                if (!facultyBySession.containsKey(sf.Session__c)) {
                    facultyBySession.put(sf.Session__c, new List<String>());
                }
                facultyBySession.get(sf.Session__c).add(sf.Session_Faculty__r.Name);
            }
        } catch (Exception e) {
            System.debug('Session_Faculty__c bulk fetch failed: ' + e.getMessage());
        }

        List<SessionSummaryDto> result = new List<SessionSummaryDto>();
        for (Session__c s : sessions) {
            SessionSummaryDto dto = new SessionSummaryDto();
            dto.id = s.Id;
            dto.title = s.Name;
            dto.sessionDate = s.Session_Date__c;
            dto.startTime = s.Start_Time__c != null ? s.Start_Time__c.format('h:mma', DISPLAY_TZ) : null;
            dto.endTime = s.End_Time__c != null ? s.End_Time__c.format('h:mma', DISPLAY_TZ) : null;
            dto.courseActivity = s.Course_Activity__c;
            dto.courseName = s.Course__r != null ? s.Course__r.Name : null;
            // SE-737U START: prefer Division Color (picklist text like "LimeYellow") so all sessions of a division share one color
            String divColor = divisionColorBySession.get(s.Id);
            if (String.isNotBlank(divColor)) {
                dto.color = divColor;
            } else {
                dto.color = String.isNotBlank(s.Color__c) ? s.Color__c : 'blue';
            }
            // SE-737U END
            List<String> names = facultyBySession.get(s.Id);
            dto.instructorNames = (names != null && !names.isEmpty()) ? String.join(names, ', ') : '';
            result.add(dto);
        }
        system.debug('result::'+result);
        return result;
    }

    /**
     * Get full session details for the Session Details modal (instructor, date, time, location, description, files).
     */
    @AuraEnabled(cacheable=true)
    public static SessionDetailDto getSessionDetails(Id sessionId) {
        if (sessionId == null) {
            return null;
        }
        List<Session__c> sessions = [
            SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c,URL__c,Class_Room__c,Color__c,Remark__c,
                   Course__r.Name, Course_Activity__c
            FROM Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
        if (sessions.isEmpty()) {
            return null;
        }
        Session__c s = sessions[0];

        SessionDetailDto dto = new SessionDetailDto();
        dto.id = s.Id;
        dto.title = s.Name;
        dto.sessionDateFormatted = s.Session_Date__c != null ? s.Session_Date__c.format() : '';
        dto.startTime = s.Start_Time__c != null ? s.Start_Time__c.format('h:mma', DISPLAY_TZ) : null;
        dto.endTime = s.End_Time__c != null ? s.End_Time__c.format('h:mma', DISPLAY_TZ) : null;
        dto.location = s.Class_Room__c!=null ?  s.Class_Room__c : ''; // Session__c has no Location field; can be extended if added
        dto.description = s.Remark__c!=null ? s.Remark__c : 'Not Given' ;
        dto.url = s.URL__c;
        dto.courseName = (s.Course__r != null && String.isNotBlank(s.Course__r.Name)) ? s.Course__r.Name : '';
        dto.activityType = s.Course_Activity__c;
        dto.files = new List<FileDto>();

        // Instructor names from Session_Faculty__c (Session_Faculty__r = Contact or User)
        List<String> instructorNames = new List<String>();
        String sessionName;
        try {
            for (Session_Faculty__c sf : [
                SELECT Session_Faculty__r.Name, Session__r.Name,Session__r.Course__r.Name,Session__r.Course_Activity__c
                FROM Session_Faculty__c
                WHERE Session__c = :sessionId
                AND Session_Faculty__r.Name != null
            ]) {
                if (sf.Session_Faculty__r != null && String.isNotBlank(sf.Session_Faculty__r.Name)) {
                    instructorNames.add(sf.Session_Faculty__r.Name);
                }
                // sessionName = sf.Session__r.Name ? sf.Session__r.Name:'';
            }
        } catch (Exception e) {
            System.debug('Session_Faculty__c or relationship not available: ' + e.getMessage());
        }
        dto.instructorNames = instructorNames.isEmpty() ? '' : String.join(instructorNames, ', ');
        dto.sessionName = sessionName;


        // Files linked to this Session (ContentDocumentLink)
        try {
            for (ContentDocumentLink cdl : [
                SELECT ContentDocumentId, ContentDocument.Title
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :sessionId
                AND ContentDocumentId != null
            ]) {
                dto.files.add(new FileDto(
                    cdl.ContentDocumentId,
                    cdl.ContentDocument != null ? cdl.ContentDocument.Title : 'File'
                ));
            }
        } catch (Exception e) {
            System.debug('ContentDocumentLink not available: ' + e.getMessage());
        }

        return dto;
    }

    /**
     * Get Course_Activity__c picklist values for the Session filter dropdown.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSessionTypeOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        options.add(new Map<String, String>{ 'label' => 'All Sessions', 'value' => '' });
        try {
            Schema.DescribeFieldResult df = Session__c.Course_Activity__c.getDescribe();
            for (Schema.PicklistEntry pe : df.getPicklistValues()) {
                if (pe.isActive()) {
                    options.add(new Map<String, String>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
                }
            }
        } catch (Exception e) {
            System.debug('Course_Activity__c picklist: ' + e.getMessage());
        }
        return options;
    }

    private static ScheduleFilter parseFilter(String filterJson) {
        System.debug('parseFilter');
        if (String.isBlank(filterJson)) {
            return new ScheduleFilter();
        }
        try {
            ScheduleFilter f = (ScheduleFilter) JSON.deserialize(filterJson, ScheduleFilter.class);
            if (f.startDate != null) f.startDate = normalizeDate(f.startDate);
            if (f.endDate != null) f.endDate = normalizeDate(f.endDate);
            return f;
        } catch (Exception e) {
            return new ScheduleFilter();
        }
    }

    private static Date normalizeDate(Date d) {
        return d == null ? null : Date.newInstance(d.year(), d.month(), d.day());
    }

    private static String formatTime(Datetime dt) {
        return dt == null ? null : dt.format('h.mma').replace('AM', 'AM').replace('PM', 'PM');
    }
}