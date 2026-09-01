public without sharing class TimetableSessionController {
    private static final String PROGRAM_ENROLLMENT_STATUS_WITHDRAWN = 'Withdrawn';

    public class SessionFilter {
        @AuraEnabled public Id programId { get; set; }
        @AuraEnabled public Id batchId { get; set; }
        @AuraEnabled public Id batchGroupId { get; set; }
        @AuraEnabled public Id termId { get; set; }
        @AuraEnabled public String divisionId { get; set; }
        @AuraEnabled public List<String> divisionIds { get; set; }
        @AuraEnabled public List<String> facultyIds { get; set; }
        @AuraEnabled public String courseId { get; set; }
        @AuraEnabled public String batchWiseCourseId { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public List<String> scheduleTypes { get; set; }
        @AuraEnabled public Boolean sendNotifications { get; set; }
    }

    public class SessionInput {
        @AuraEnabled public Id sessionId { get; set; }
        @AuraEnabled public String sessionName { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String divisionId { get; set; }
        @AuraEnabled public List<String> divisionIds { get; set; }
        @AuraEnabled public String programId { get; set; }
        @AuraEnabled public String batchId { get; set; }
        @AuraEnabled public String academicYearId { get; set; }
        @AuraEnabled public String termId { get; set; }
        @AuraEnabled public String batchWiseCourseId { get; set; }
        @AuraEnabled public String courseId { get; set; }
        @AuraEnabled public Date sessionDate { get; set; }
        @AuraEnabled public Datetime startTime { get; set; }
        @AuraEnabled public Datetime endTime { get; set; }
        @AuraEnabled public Decimal numberOfSessions { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String courseActivity { get; set; }
        @AuraEnabled public String sessionType { get; set; }
        @AuraEnabled public String ownerId { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public Boolean isJointSession { get; set; }
        @AuraEnabled public List<String> selectedFacultyIds { get; set; }
        @AuraEnabled public List<String> selectedStudentIds { get; set; }

        @AuraEnabled public String leadFacultyId { get; set; }
        @AuraEnabled public List<String> leadFacultyIds { get; set; }
        @AuraEnabled public String classRoom { get; set; }
        @AuraEnabled public String remark { get; set; }
        @AuraEnabled public String url { get; set; }
        @AuraEnabled public String colorSourceDivisionId { get; set; }
        @AuraEnabled public String proposedConflictContextJson { get; set; }
        @AuraEnabled public Boolean ignoreConflicts { get; set; }
        @AuraEnabled public Boolean sendNotifications { get; set; }
    }

    public class SessionDto {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public Date sessionDate { get; set; }
        @AuraEnabled public String startTime { get; set; }
        @AuraEnabled public String endTime { get; set; }
        @AuraEnabled public String timezone { get; set; }
        @AuraEnabled public String location { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Id divisionId { get; set; }
        @AuraEnabled public String divisionName { get; set; }
        @AuraEnabled public Id courseId { get; set; }
        @AuraEnabled public String courseName { get; set; }
        @AuraEnabled public Id batchWiseCourseId { get; set; }
        @AuraEnabled public String courseActivity { get; set; }
        @AuraEnabled public String sessionType { get; set; }
        @AuraEnabled public String color { get; set; }
        @AuraEnabled public String divisionColor { get; set; }
        @AuraEnabled public Boolean isJointSession { get; set; }
        @AuraEnabled public List<String> facultyNames { get; set; }
        @AuraEnabled public List<String> leadFacultyNames { get; set; }
        @AuraEnabled public List<String> supportFacultyNames { get; set; }
        @AuraEnabled public List<String> selectedFacultyIds { get; set; }
        @AuraEnabled public String leadFacultyId { get; set; }
        @AuraEnabled public List<String> leadFacultyIds { get; set; }
        @AuraEnabled public String classRoom { get; set; }
        @AuraEnabled public String remark { get; set; }
        @AuraEnabled public String url { get; set; }
        @AuraEnabled public String scheduleType { get; set; }
        @AuraEnabled public List<String> studentNames { get; set; }
        @AuraEnabled public List<String> selectedStudentIds { get; set; }
        @AuraEnabled public Boolean hasGoogleEvent { get; set; }
        @AuraEnabled public Integer attendeesTotal { get; set; }
        @AuraEnabled public Integer attendeesAccepted { get; set; }
        @AuraEnabled public Integer attendeesDeclined { get; set; }
        @AuraEnabled public Integer attendeesTentative { get; set; }
        @AuraEnabled public Integer attendeesAwaiting { get; set; }
    }

    public class PicklistOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }

        public PicklistOption(String l, String v) {
            this.label = l;
            this.value = v;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<SessionDto> getSessions(String filterJson) {
        SessionFilter filter = parseFilter(filterJson);
        Set<Id> divisionFilterIds = new Set<Id>();

        if (!String.isBlank(filter.divisionId)) {
            try {
                divisionFilterIds.add(Id.valueOf(filter.divisionId));
            } catch (Exception e) {
                List<Division__c> divisions = [
                    SELECT Id
                    FROM Division__c
                    WHERE Name = :filter.divisionId
                    LIMIT 1
                ];
                if (!divisions.isEmpty()) {
                    divisionFilterIds.add(divisions[0].Id);
                }
            }
        }

        if (filter.divisionIds != null) {
            for (String rawId : filter.divisionIds) {
                if (String.isBlank(rawId)) continue;
                try {
                    divisionFilterIds.add(Id.valueOf(rawId));
                } catch (Exception ignore) {
                }
            }
        }

        if (divisionFilterIds.isEmpty()
            && filter.divisionIds != null
            && filter.divisionIds.isEmpty()
            && String.isBlank(filter.divisionId)) {
            return new List<SessionDto>();
        }

        Set<Id> filteredSessionIds = new Set<Id>();
        if (!divisionFilterIds.isEmpty()) {
            for (Session_Division__c sd : [
                SELECT Session__c
                FROM Session_Division__c
                WHERE Division__c IN :divisionFilterIds
            ]) {
                filteredSessionIds.add(sd.Session__c);
            }

            if (filteredSessionIds.isEmpty()) {
                return new List<SessionDto>();
            }
        }

        if (filter.facultyIds != null && !filter.facultyIds.isEmpty()) {
            Set<Id> facultyFilterIds = new Set<Id>();
            for (String fid : filter.facultyIds) {
                if (String.isNotBlank(fid)) {
                    try {
                        facultyFilterIds.add(Id.valueOf(fid));
                    } catch (Exception ignore) {}
                }
            }
            if (!facultyFilterIds.isEmpty()) {
                Set<Id> sessionIdsWithFaculty = new Set<Id>();
                List<Session_Faculty__c> facultyMatches = filteredSessionIds.isEmpty()
                    ? [SELECT Session__c FROM Session_Faculty__c WHERE Session_Faculty__c IN :facultyFilterIds]
                    : [SELECT Session__c FROM Session_Faculty__c WHERE Session__c IN :filteredSessionIds AND Session_Faculty__c IN :facultyFilterIds];
                for (Session_Faculty__c sf : facultyMatches) {
                    sessionIdsWithFaculty.add(sf.Session__c);
                }
                if (filteredSessionIds.isEmpty()) {
                    filteredSessionIds = sessionIdsWithFaculty;
                } else {
                    filteredSessionIds.retainAll(sessionIdsWithFaculty);
                }
                if (filteredSessionIds.isEmpty()) {
                    return new List<SessionDto>();
                }
            }
        }

        Set<String> scheduleTypeSet = new Set<String>();
        if (filter.scheduleTypes != null && !filter.scheduleTypes.isEmpty()) {
            for (String st : filter.scheduleTypes) {
                if (String.isNotBlank(st)) {
                    String normalized = st.trim();
                    if (normalized.equalsIgnoreCase('Draft')) {
                        scheduleTypeSet.add('Draft');
                    } else if (normalized.equalsIgnoreCase('Published')) {
                        scheduleTypeSet.add('Published');
                        scheduleTypeSet.add('Republished');
                    } else if (normalized.equalsIgnoreCase('Republished')) {
                        scheduleTypeSet.add('Republished');
                    }
                }
            }
        }
        if (scheduleTypeSet.isEmpty()) {
            scheduleTypeSet.add('Draft');
            scheduleTypeSet.add('Published');
            scheduleTypeSet.add('Republished');
        }

        Date normalizedStartDate = filter.startDate != null
            ? Date.newInstance(filter.startDate.year(), filter.startDate.month(), filter.startDate.day())
            : null;
        Date normalizedEndDate = filter.endDate != null
            ? Date.newInstance(filter.endDate.year(), filter.endDate.month(), filter.endDate.day())
            : null;

        List<Session__c> sessions;
        if (!filteredSessionIds.isEmpty()) {
            if (normalizedStartDate != null && normalizedEndDate != null) {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c, Session_Type__c,Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Session_Date__c >= :normalizedStartDate
                    AND Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            } else if (normalizedStartDate != null) {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c,Session_Type__c, Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Session_Date__c >= :normalizedStartDate
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            } else if (normalizedEndDate != null) {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c,Session_Type__c, Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            } else {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c, Session_Type__c,Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            }
        } else {
            if (normalizedStartDate != null && normalizedEndDate != null) {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c,Session_Type__c, Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Session_Date__c >= :normalizedStartDate
                    AND Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            } else if (normalizedStartDate != null) {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c,Session_Type__c, Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Session_Date__c >= :normalizedStartDate
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            } else if (normalizedEndDate != null) {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c,Session_Type__c, Color__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            } else {
                sessions = [
                    SELECT Id, Name, Session_Date__c, Start_Time__c, End_Time__c, Description__c,
                           Course__c, Course__r.Name, Course_Activity__c, Color__c,Session_Type__c, Is_Joint_Session__c,
                           Class_Room__c, Remark__c, URL__c, Schedule_Type__c
                    FROM Session__c
                    WHERE Schedule_Type__c IN :scheduleTypeSet
                    ORDER BY Session_Date__c, Start_Time__c
                ];
            }
        }

        if (sessions.isEmpty()) {
            return new List<SessionDto>();
        }

        Map<Id, Session__c> sessionsById = new Map<Id, Session__c>(sessions);

        Map<Id, Session__c> attendeeStatsById = new Map<Id, Session__c>([
            SELECT Id, Google_Event_Id__c, Faculty_Google_Event_Id__c,
                   Rsvp_Total__c, Rsvp_Accepted__c,
                   Rsvp_Declined__c, Rsvp_Tentative__c, Rsvp_Awaiting__c
            FROM   Session__c
            WHERE  Id IN :sessionsById.keySet()
        ]);

        Map<Id, List<String>> sessionIdToFacultyNames = new Map<Id, List<String>>();
        Map<Id, List<String>> sessionIdToLeadFacultyNames = new Map<Id, List<String>>();
        Map<Id, List<String>> sessionIdToSupportFacultyNames = new Map<Id, List<String>>();
        Map<Id, List<Id>> sessionIdToFacultyIds = new Map<Id, List<Id>>();
        Map<Id, String> sessionIdToLeadFacultyId = new Map<Id, String>();
        Map<Id, List<String>> sessionIdToLeadFacultyIds = new Map<Id, List<String>>();
        Map<Id, List<String>> sessionIdToStudentNames = new Map<Id, List<String>>();
		Map<Id, List<String>> sessionIdToStudentIds = new Map<Id, List<String>>();
        try {
            List<Session_Faculty__c> sessionFaculties = [
                SELECT Session__c, Session_Faculty__c, Faculty_Type__c
                FROM Session_Faculty__c
                WHERE Session__c IN :sessionsById.keySet()
                AND Session_Faculty__c != null
            ];
            Set<Id> facultyIds = new Set<Id>();
            for (Session_Faculty__c sf : sessionFaculties) {
                facultyIds.add(sf.Session_Faculty__c);
                List<Id> ids = sessionIdToFacultyIds.get(sf.Session__c);
                if (ids == null) {
                    ids = new List<Id>();
                    sessionIdToFacultyIds.put(sf.Session__c, ids);
                }
                ids.add(sf.Session_Faculty__c);
                if (sf.Faculty_Type__c == 'Lead') {
                    sessionIdToLeadFacultyId.put(sf.Session__c, String.valueOf(sf.Session_Faculty__c));
                    List<String> leadIds = sessionIdToLeadFacultyIds.get(sf.Session__c);
                    if (leadIds == null) {
                        leadIds = new List<String>();
                        sessionIdToLeadFacultyIds.put(sf.Session__c, leadIds);
                    }
                    leadIds.add(String.valueOf(sf.Session_Faculty__c));
                }
            }
            Map<Id, String> facultyIdToName = new Map<Id, String>();
            if (!facultyIds.isEmpty()) {
                for (Account a : [SELECT Id, Name FROM Account WHERE Id IN :facultyIds]) {
                    facultyIdToName.put(a.Id, a.Name);
                }
                Set<Id> missingIds = new Set<Id>();
                for (Id fid : facultyIds) {
                    if (!facultyIdToName.containsKey(fid)) {
                        missingIds.add(fid);
                    }
                }
                if (!missingIds.isEmpty()) {
                    for (User u : [SELECT Id, Name FROM User WHERE Id IN :missingIds]) {
                        facultyIdToName.put(u.Id, u.Name);
                    }
                }
            }
            for (Session_Faculty__c sf : sessionFaculties) {
                String name = facultyIdToName.get(sf.Session_Faculty__c);
                if (String.isBlank(name)) continue;
                if (sf.Faculty_Type__c == 'Support') {
                    List<String> names = sessionIdToSupportFacultyNames.get(sf.Session__c);
                    if (names == null) {
                        names = new List<String>();
                        sessionIdToSupportFacultyNames.put(sf.Session__c, names);
                    }
                    names.add(name);
                } else {
                    List<String> names = sessionIdToLeadFacultyNames.get(sf.Session__c);
                    if (names == null) {
                        names = new List<String>();
                        sessionIdToLeadFacultyNames.put(sf.Session__c, names);
                    }
                    names.add(name);
                }
            }
            for (Id sessionId : sessionIdToFacultyIds.keySet()) {
                List<Id> fids = sessionIdToFacultyIds.get(sessionId);
                String leadId = sessionIdToLeadFacultyId.get(sessionId);
                if (String.isNotBlank(leadId) && fids != null && fids.size() > 1) {
                    List<Id> ordered = new List<Id>();
                    for (Id fid : fids) {
                        if (String.valueOf(fid) == leadId) ordered.add(fid);
                    }
                    for (Id fid : fids) {
                        if (String.valueOf(fid) != leadId) ordered.add(fid);
                    }
                    sessionIdToFacultyIds.put(sessionId, ordered);
                    fids = ordered;
                }
                List<String> names = new List<String>();
                for (Id fid : fids) {
                    String n = facultyIdToName.get(fid);
                    if (String.isNotBlank(n)) names.add(n);
                }
                sessionIdToFacultyNames.put(sessionId, names);
            }
        } catch (Exception e) {
            System.debug('Session faculty names not available: ' + e.getMessage());
        }

        try {
            Map<Id, Set<Id>> sessionIdToStudentIdSet = new Map<Id, Set<Id>>();
            for (Session_Enrollment__c se : [
                SELECT Session__c,
                Academic_Term_Enrollment__r.LearnerAccount.Id,
                Academic_Term_Enrollment__r.LearnerAccount.Name
                FROM Session_Enrollment__c
                WHERE Session__c IN :sessionsById.keySet()
            ]) {
                Id sessionId = se.Session__c;
                Id learnerId = se.Academic_Term_Enrollment__r.LearnerAccount.Id;

                if (!sessionIdToStudentNames.containsKey(sessionId)) {
                sessionIdToStudentNames.put(sessionId, new List<String>());
                sessionIdToStudentIds.put(sessionId, new List<String>());
                sessionIdToStudentIdSet.put(sessionId, new Set<Id>());
                }

                if (!sessionIdToStudentIdSet.get(sessionId).contains(learnerId)) {
                sessionIdToStudentIdSet.get(sessionId).add(learnerId);
                sessionIdToStudentNames.get(sessionId).add(se.Academic_Term_Enrollment__r.LearnerAccount.Name);
                sessionIdToStudentIds.get(sessionId).add(String.valueOf(learnerId));
                }
            }
        }
        catch (Exception e) {
            System.debug('Student names not available: ' + e.getMessage());
        }

        List<Session_Division__c> sessionDivisions;
        if (!divisionFilterIds.isEmpty()) {
            sessionDivisions = [
                SELECT Session__c, Division__c, Division__r.Division_Name__c, Division__r.Division_Color__c
                FROM Session_Division__c
                WHERE Session__c IN :sessionsById.keySet()
                AND Division__c IN :divisionFilterIds
            ];
        } else {
            sessionDivisions = [
                SELECT Session__c, Division__c, Division__r.Division_Name__c, Division__r.Division_Color__c
                FROM Session_Division__c
                WHERE Session__c IN :sessionsById.keySet()
            ];
        }

        List<SessionDto> response = new List<SessionDto>();
        for (Session_Division__c sd : sessionDivisions) {
            Session__c s = sessionsById.get(sd.Session__c);
            if (s == null) continue;

            SessionDto dto = new SessionDto();
            dto.id = s.Id;
            dto.title = s.Name;
            dto.sessionDate = s.Session_Date__c;
            dto.startTime = formatTimeForClient(s.Start_Time__c);
            dto.endTime = formatTimeForClient(s.End_Time__c);
            dto.timezone = UserInfo.getTimeZone().getID();
            dto.description = s.Description__c;
            dto.classRoom = s.Class_Room__c;
            dto.remark = s.Remark__c;
            dto.url = s.URL__c;
            dto.scheduleType = s.Schedule_Type__c;
            dto.divisionId = sd.Division__c;
            dto.divisionName = sd.Division__r != null ? sd.Division__r.Division_Name__c : null;
            dto.courseId = s.Course__c;
            dto.courseName = s.Course__r != null ? s.Course__r.Name : null;
            dto.courseActivity = s.Course_Activity__c;
            dto.sessionType = s.Session_Type__c;
            dto.color = String.isNotBlank(s.Color__c) ? s.Color__c : 'blue';
            dto.divisionColor = (sd.Division__r != null && sd.Division__r.Division_Color__c != null)
                ? String.valueOf(sd.Division__r.Division_Color__c)
                : null;
            dto.isJointSession = s.Is_Joint_Session__c != null ? s.Is_Joint_Session__c : false;
            List<String> facultyNamesForSession = sessionIdToFacultyNames.get(s.Id);
            dto.facultyNames = facultyNamesForSession != null ? facultyNamesForSession : new List<String>();
            List<String> leadNames = sessionIdToLeadFacultyNames.get(s.Id);
            dto.leadFacultyNames = leadNames != null ? leadNames : new List<String>();
            List<String> supportNames = sessionIdToSupportFacultyNames.get(s.Id);
            dto.supportFacultyNames = supportNames != null ? supportNames : new List<String>();
            List<Id> facultyIdsForSession = sessionIdToFacultyIds.get(s.Id);
            if (facultyIdsForSession != null && !facultyIdsForSession.isEmpty()) {
                dto.selectedFacultyIds = new List<String>();
                for (Id fid : facultyIdsForSession) {
                    dto.selectedFacultyIds.add(String.valueOf(fid));
                }
            } else {
                dto.selectedFacultyIds = new List<String>();
            }
            dto.leadFacultyId = sessionIdToLeadFacultyId.get(s.Id);
            List<String> leadFacultyIdsForSession = sessionIdToLeadFacultyIds.get(s.Id);
            dto.leadFacultyIds = (leadFacultyIdsForSession != null && !leadFacultyIdsForSession.isEmpty())
                ? leadFacultyIdsForSession
                : (dto.leadFacultyId != null ? new List<String>{ dto.leadFacultyId } : null);
            dto.studentNames =
    sessionIdToStudentNames.containsKey(s.Id)
        ? sessionIdToStudentNames.get(s.Id)
        : new List<String>();

dto.selectedStudentIds =
    sessionIdToStudentIds.containsKey(s.Id)
        ? sessionIdToStudentIds.get(s.Id)
        : new List<String>();
            Session__c stat = attendeeStatsById.get(s.Id);
            // Either copy counts as synced: a Draft has only the faculty event.
            dto.hasGoogleEvent   = (stat != null
                && (String.isNotBlank(stat.Google_Event_Id__c)
                    || String.isNotBlank(stat.Faculty_Google_Event_Id__c)));
            dto.attendeesTotal     = toInt(stat != null ? stat.Rsvp_Total__c     : null);
            dto.attendeesAccepted  = toInt(stat != null ? stat.Rsvp_Accepted__c  : null);
            dto.attendeesDeclined  = toInt(stat != null ? stat.Rsvp_Declined__c  : null);
            dto.attendeesTentative = toInt(stat != null ? stat.Rsvp_Tentative__c : null);
            dto.attendeesAwaiting  = toInt(stat != null ? stat.Rsvp_Awaiting__c  : null);
            response.add(dto);
        }
        return response;
    }

    private static Integer toInt(Decimal d) {
        return (d == null) ? 0 : d.intValue();
    }

    @AuraEnabled
    public static AttendeeSummary refreshAttendees(Id sessionId) {
        AttendeeSummary summary = new AttendeeSummary();
        if (sessionId == null) {
            summary.message = 'No session specified.';
            return summary;
        }

        List<Session__c> sList = [
            SELECT Id, Google_Event_Id__c, Faculty_Google_Event_Id__c
            FROM Session__c WHERE Id = :sessionId LIMIT 1
        ];
        if (sList.isEmpty()) {
            summary.message = 'Session not found.';
            return summary;
        }
        // Students and faculty sit on separate events, so both have to be read to refresh
        // everybody's RSVP. Either may be missing: a Draft has no student copy yet.
        List<String> eventIds = new List<String>();
        if (String.isNotBlank(sList[0].Google_Event_Id__c)) {
            eventIds.add(sList[0].Google_Event_Id__c);
        }
        if (String.isNotBlank(sList[0].Faculty_Google_Event_Id__c)) {
            eventIds.add(sList[0].Faculty_Google_Event_Id__c);
        }

        if (eventIds.isEmpty()) {
            summary.message = 'This session has not been pushed to Google Calendar yet.';
        } else {
            String organizer  = GoogleCalendarHelper.getUserEmail('Default');
            String calendarId = GoogleCalendarHelper.getDefaultCalendarId('Default');
            if (String.isBlank(organizer)) {
                summary.message = 'Google Calendar is not configured.';
            } else {
                Map<String, String> merged = new Map<String, String>();
                Boolean readAny = false;
                for (String eventId : eventIds) {
                    try {
                        GoogleCalendarService.GoogleEventReadResponse resp =
                            GoogleCalendarService.getCalendarEvent(calendarId, eventId, organizer);
                        if (resp.success && resp.event != null) {
                            merged.putAll(SessionRsvpSyncService.parseResponses(resp.event));
                            readAny = true;
                        } else if (resp.notFound) {
                            summary.message =
                                'A Google event no longer exists; showing last synced data.';
                        } else {
                            summary.message =
                                'Could not refresh from Google; showing last synced data.';
                        }
                    } catch (Exception e) {
                        summary.message = 'Could not refresh from Google; showing last synced data.';
                    }
                }
                if (readAny) {
                    Map<Id, Map<String, String>> parsedResponses =
                        new Map<Id, Map<String, String>>{ sessionId => merged };
                    SessionRsvpSyncService.applyToEnrollments(parsedResponses);
                    SessionFacultyRsvpService.applyToSessionFaculty(parsedResponses);
                }
            }
        }

        for (Session_Enrollment__c e : [
            SELECT Invite_Response__c, Invite_Response_Checked__c, Student_Name__c,
                   Division_Enrollment__r.Academic_Term_Enrollment__r.LearnerAccount.PersonEmail
            FROM   Session_Enrollment__c
            WHERE  Session__c = :sessionId
            ORDER BY Invite_Response__c, Student_Name__c
        ]) {
            AttendeeDto d = new AttendeeDto();
            d.email  = e.Division_Enrollment__r?.Academic_Term_Enrollment__r?.LearnerAccount?.PersonEmail;
            d.status = String.isBlank(e.Invite_Response__c) ? 'No Response' : e.Invite_Response__c;
            d.type   = 'Student';
            summary.attendees.add(d);
            summary.total++;
            if (e.Invite_Response__c == 'Accepted') {
                summary.accepted++;
            } else if (e.Invite_Response__c == 'Declined') {
                summary.declined++;
            } else if (e.Invite_Response__c == 'Tentative') {
                summary.tentative++;
            } else {
                summary.awaiting++;
            }
            if (e.Invite_Response_Checked__c != null
                    && (summary.lastSynced == null || e.Invite_Response_Checked__c > summary.lastSynced)) {
                summary.lastSynced = e.Invite_Response_Checked__c;
            }
        }

        for (Session_Faculty__c f : [
            SELECT Invite_Response__c, Invite_Response_Checked__c,
                   Session_Faculty__r.Name, Session_Faculty__r.PersonEmail
            FROM   Session_Faculty__c
            WHERE  Session__c = :sessionId
            ORDER BY Invite_Response__c
        ]) {
            AttendeeDto d = new AttendeeDto();
            d.email  = (f.Session_Faculty__r != null) ? f.Session_Faculty__r.PersonEmail : null;
            d.status = String.isBlank(f.Invite_Response__c) ? 'No Response' : f.Invite_Response__c;
            d.type   = 'Faculty';
            summary.attendees.add(d);
            summary.total++;
            if (f.Invite_Response__c == 'Accepted') {
                summary.accepted++;
            } else if (f.Invite_Response__c == 'Declined') {
                summary.declined++;
            } else if (f.Invite_Response__c == 'Tentative') {
                summary.tentative++;
            } else {
                summary.awaiting++;
            }
            if (f.Invite_Response_Checked__c != null
                    && (summary.lastSynced == null || f.Invite_Response_Checked__c > summary.lastSynced)) {
                summary.lastSynced = f.Invite_Response_Checked__c;
            }
        }
        return summary;
    }

    public class AttendeeSummary {
        @AuraEnabled public Integer total = 0;
        @AuraEnabled public Integer accepted = 0;
        @AuraEnabled public Integer declined = 0;
        @AuraEnabled public Integer tentative = 0;
        @AuraEnabled public Integer awaiting = 0;
        @AuraEnabled public Datetime lastSynced { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public List<AttendeeDto> attendees = new List<AttendeeDto>();
    }

    public class AttendeeDto {
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public Boolean isOrganizer { get; set; }
    }

    @AuraEnabled
    public static Integer publishSessions(String filterJson) {
        SessionFilter filter = parseFilter(filterJson);
        Integer updatedCount = 0;

        Set<Id> divisionFilterIds = new Set<Id>();
        if (!String.isBlank(filter.divisionId)) {
            try {
                divisionFilterIds.add(Id.valueOf(filter.divisionId));
            } catch (Exception e) {
                List<Division__c> divisions = [
                    SELECT Id
                    FROM Division__c
                    WHERE Name = :filter.divisionId
                    LIMIT 1
                ];
                if (!divisions.isEmpty()) {
                    divisionFilterIds.add(divisions[0].Id);
                }
            }
        }
        if (filter.divisionIds != null) {
            for (String rawId : filter.divisionIds) {
                if (String.isBlank(rawId)) continue;
                try {
                    divisionFilterIds.add(Id.valueOf(rawId));
                } catch (Exception ignore) {}
            }
        }

        if (divisionFilterIds.isEmpty()
            && filter.divisionIds != null
            && filter.divisionIds.isEmpty()
            && String.isBlank(filter.divisionId)) {
            return 0;
        }

        Set<Id> filteredSessionIds = new Set<Id>();
        if (!divisionFilterIds.isEmpty()) {
            for (Session_Division__c sd : [
                SELECT Session__c
                FROM Session_Division__c
                WHERE Division__c IN :divisionFilterIds
            ]) {
                filteredSessionIds.add(sd.Session__c);
            }
            if (filteredSessionIds.isEmpty()) {
                return 0;
            }
        }

        Date normalizedStartDate = filter.startDate != null ? normalizeDate(filter.startDate) : null;
        Date normalizedEndDate = filter.endDate != null ? normalizeDate(filter.endDate) : null;

        List<Session__c> draftSessions;
        if (!filteredSessionIds.isEmpty()) {
            if (normalizedStartDate != null && normalizedEndDate != null) {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Session_Date__c >= :normalizedStartDate
                    AND Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            } else if (normalizedStartDate != null) {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Session_Date__c >= :normalizedStartDate
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            } else if (normalizedEndDate != null) {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            } else {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Id IN :filteredSessionIds
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            }
        } else {
            if (normalizedStartDate != null && normalizedEndDate != null) {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Session_Date__c >= :normalizedStartDate
                    AND Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            } else if (normalizedStartDate != null) {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Session_Date__c >= :normalizedStartDate
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            } else if (normalizedEndDate != null) {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Session_Date__c <= :normalizedEndDate
                    AND Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];

            } else {
                draftSessions = [
                    SELECT Id, Schedule_Type__c, Session_Date__c,End_Time__c
                    FROM Session__c
                    WHERE Schedule_Type__c = 'Draft'
                    AND Is_Completed__c = false
                ];
            }
        }

        Boolean callerWantsDraft     = filter.scheduleTypes == null || filter.scheduleTypes.isEmpty()
                                || new Set<String>(filter.scheduleTypes).contains('Draft');
		Boolean callerWantsPublished = filter.scheduleTypes != null
                                && (new Set<String>(filter.scheduleTypes).contains('Published')
                                    || new Set<String>(filter.scheduleTypes).contains('Republished'));

        Date today = Date.today();
        Datetime nowTs = Datetime.now();
        Integer pastDraftCount   = 0;
		Integer futureDraftCount = 0;
	for (Session__c s : draftSessions) {
        Boolean isPast = (s.End_Time__c != null && s.End_Time__c < nowTs) || (s.End_Time__c == null && s.Session_Date__c != null && s.Session_Date__c < today);
    if (isPast) {
        pastDraftCount++;
    } else {
        futureDraftCount++;
    }
}
	if (callerWantsPublished && !callerWantsDraft) {
    	throw new AuraHandledException(
        'In the selected date range all sessions are already published.');
	}

	if (callerWantsDraft && !callerWantsPublished
        && pastDraftCount > 0 && futureDraftCount == 0) {
    throw new AuraHandledException(

        'Past draft sessions cannot be published.'
    );
	}

	if (callerWantsDraft && callerWantsPublished && pastDraftCount > 0) {
    throw new AuraHandledException(

        'In the selected date range draft sessions are involved, cannot publish sessions.'
    );
}

	List<Session__c> publishableSessions = new List<Session__c>();

		for (Session__c sessionRecord : draftSessions) {
 	   	Boolean isPastRecord = (sessionRecord.End_Time__c != null && sessionRecord.End_Time__c < nowTs)
                    || (sessionRecord.End_Time__c == null && sessionRecord.Session_Date__c != null && sessionRecord.Session_Date__c < today);
        if (isPastRecord) {
        continue;
    }
    publishableSessions.add(sessionRecord);
	 }

         if (!publishableSessions.isEmpty()) {
            Set<Id> publishedIds = new Set<Id>();
            Date rangeStart;
            Date rangeEnd;
            for (Session__c sessionRecord : publishableSessions) {
                sessionRecord.Schedule_Type__c = 'Published';
                publishedIds.add(sessionRecord.Id);
                if (sessionRecord.Session_Date__c != null) {
                    if (rangeStart == null || sessionRecord.Session_Date__c < rangeStart) {
                        rangeStart = sessionRecord.Session_Date__c;
                    }
                    if (rangeEnd == null || sessionRecord.Session_Date__c > rangeEnd) {
                        rangeEnd = sessionRecord.Session_Date__c;
                    }
                }
            }

            Boolean notifyFaculty = filter.sendNotifications != false;
            try {
                // Faculty sit on their own Google event, so the answer only governs their copy.
                // The students' copy is always pushed silently and they are told once, here.
                SessionCalendarInviteHandler.skipUserNotifications = !notifyFaculty;
                SessionCalendarInviteHandler.facultyNotifyRequested = notifyFaculty;
                System.enqueueJob(
                    new SessionPublishSummaryEmailQueueable(publishedIds, rangeStart, rangeEnd, true)
                );
                update publishableSessions;
                updatedCount = publishableSessions.size();
            } catch (DmlException ex) {
                throw new AuraHandledException('Error publishing sessions: ' + ex.getDmlMessage(0));
            } finally {
                SessionCalendarInviteHandler.skipUserNotifications = false;
                SessionCalendarInviteHandler.facultyNotifyRequested = false;
            }
        }

        return updatedCount;
    }

    /**
     * @description Sends the students of a republished session the one consolidated
     *          "schedule republished" email, on Yes and on No alike. Students sit on their own
     *          Google event which is always pushed silently, so this email is the only thing that
     *          tells them their session moved. Faculty are deliberately left out (studentsOnly):
     *          they are notified by their own event's invitation, or not at all if the user said No.
     *          No-op for creates and for Draft edits, where no student sits on the calendar event
     *          yet and the Publish button does the notifying later.
     *          Enqueued BEFORE the upsert on purpose: the calendar chunker consumes this
     *          transaction's queueable slots while the trigger runs, so a job enqueued after the
     *          DML can silently never run. A failed DML rolls this enqueue back with it.
     * @param sessionRecord The session about to be upserted, already stamped with its new
     *          Schedule_Type__c.
     * @param requestedDate The session date being saved, quoted in the email.
     */
    @TestVisible
    private static void enqueueRepublishStudentEmail(Session__c sessionRecord, Date requestedDate) {
        if (sessionRecord == null
                || sessionRecord.Id == null
                || String.isBlank(sessionRecord.Schedule_Type__c)
                || !sessionRecord.Schedule_Type__c.equalsIgnoreCase('Republished')) {
            return;
        }
        Date onDate = requestedDate;
        if (onDate == null && sessionRecord.Start_Time__c != null) {
            onDate = sessionRecord.Start_Time__c.date();
        }
        System.enqueueJob(new SessionPublishSummaryEmailQueueable(
            new Set<Id>{ sessionRecord.Id }, onDate, onDate, true, true
        ));
    }

    @AuraEnabled
    public static SaveSessionResult saveSession(String requestJson) {
        SessionInput request = parseSessionInput(requestJson);
        validateInput(request);

        Id courseLookupId = null;
        if (String.isNotBlank(request.courseId)) {
            if (request.courseId.contains('|')) {
                String[] parts = request.courseId.split('\\|');
                if (parts.size() > 1 && String.isNotBlank(parts[1])) {
                    try {
                        courseLookupId = Id.valueOf(parts[1]);
                    } catch (Exception e) {
                        System.debug('Error parsing LearningCourseId: ' + e.getMessage());
                    }
                }
            } else {
                String courseObject = getLookupObjectApiName('Course__c');
                courseLookupId = resolveLookupId(request.courseId, courseObject);
            }
        }
        System.debug('request.courseId: ' + request.courseId);
        System.debug('request.batchId: ' + request.batchId);
        System.debug('request.programId: ' + request.programId);
        Program_Courses__c programCourse = [Select Id, Program_Master__c, IS_Host_Course__c, Batch__c, Batch__r.ProgramId FROM Program_Courses__c WHERE Learning_Course__c = :courseLookupId AND Batch__c = :request.batchId AND Program_Master__c = :request.programId LIMIT 1];

        Id ownerLookupId = resolveLookupId(request.ownerId, 'User');

        Id divisionLookupId = null;
        if (String.isNotBlank(request.divisionId)) {
            try {
                divisionLookupId = Id.valueOf(request.divisionId);
            } catch (Exception e) {
                List<Division__c> divisions = [
                    SELECT Id
                    FROM Division__c
                    WHERE Name = :request.divisionId
                    LIMIT 1
                ];
                if (!divisions.isEmpty()) {
                    divisionLookupId = divisions[0].Id;
                }
            }
        }

        Set<Id> facultyIds = new Set<Id>();
        if (request.selectedFacultyIds != null) {
            for (String fid : request.selectedFacultyIds) {
                if (String.isNotBlank(fid)) {
                    facultyIds.add(Id.valueOf(fid));
                }
            }
        }

        Id sessionIdForQuery = request.sessionId;
        String sessionQuery = 'SELECT Id, Name,Batch__c, Color__c, Is_Joint_Session__c, Schedule_Type__c, Session_Date__c, Start_Time__c, End_Time__c,' +
            ' Course__c, Description__c, Course_Activity__c,Session_Type__c, OwnerId, Class_Room__c, Remark__c, URL__c';
        List<String> sessionInfoFields = getSessionInfoFieldApiNames();
        if (!sessionInfoFields.isEmpty()) {
            sessionQuery += ',' + String.join(sessionInfoFields, ',');
        }
        sessionQuery += ' FROM Session__c WHERE Id = :sessionIdForQuery LIMIT 1';
        Session__c sessionRecord = sessionIdForQuery != null
            ? (Session__c) Database.query(sessionQuery)[0]
            : new Session__c();

        // The session AS IT STANDS IN THE ORG, captured before the request overwrites the fields
        // below. The reschedule availability check needs the old date/times to tell a genuine
        // reschedule from a save that left the timing alone. Null on create.
        Session__c existingSessionSnapshot = sessionIdForQuery != null
            ? sessionRecord.clone(true, true, true, true)
            : null;

        String normalizedName = getSessionName(request);
        sessionRecord.Name = normalizedName;
        sessionRecord.Course__c = courseLookupId;
        sessionRecord.Session_Date__c = request.sessionDate;
        sessionRecord.Start_Time__c = request.startTime;
        sessionRecord.End_Time__c = request.endTime;
        sessionRecord.Description__c = request.description;
        sessionRecord.Course_Activity__c = request.courseActivity;
        sessionRecord.Session_Type__c = request.sessionType;
        sessionRecord.OwnerId = ownerLookupId != null ? ownerLookupId : UserInfo.getUserId();
        sessionRecord.Class_Room__c = request.classRoom;
        sessionRecord.Remark__c = request.remark;
        sessionRecord.URL__c = request.url;
        sessionRecord.LMS_Programme_Course__c = programCourse.Id;

        sessionRecord.Is_Joint_Session__c = request.isJointSession != null ? request.isJointSession : false;

        if (request.sessionId == null) {
            sessionRecord.Schedule_Type__c = 'Draft';
        } else if (String.isNotBlank(sessionRecord.Schedule_Type__c)) {
            if (sessionRecord.Schedule_Type__c.equalsIgnoreCase('Published') ||
                sessionRecord.Schedule_Type__c.equalsIgnoreCase('Republished')) {
                sessionRecord.Schedule_Type__c = 'Republished';
            }
        }

        List<Id> divisionIdsToProcess = new List<Id>();

        if (request.divisionIds != null && !request.divisionIds.isEmpty()) {
            for (String divId : request.divisionIds) {
                if (String.isNotBlank(divId)) {
                    try {
                        Id divIdResolved = Id.valueOf(divId);
                        divisionIdsToProcess.add(divIdResolved);
                    } catch (Exception e) {
                        System.debug('Error parsing division ID: ' + divId);
                    }
                }
            }
        } else if (divisionLookupId != null) {
            divisionIdsToProcess.add(divisionLookupId);
        }

        applySessionColorFromDivision(request, sessionRecord, divisionLookupId, divisionIdsToProcess);

        Id programIdResolved = tryConvertToId(String.isNotBlank(request.programId) ? request.programId.trim() : null);
        if (programIdResolved != null) {
            try { sessionRecord.Program__c = programIdResolved; } catch (Exception e) { }
        }
        Id batchIdResolved = tryConvertToId(String.isNotBlank(request.batchId) ? request.batchId.trim() : null);
        if (batchIdResolved != null) {
            try { sessionRecord.Batch__c = batchIdResolved; } catch (Exception e) { }
        }
        Id academicYearIdResolved = tryConvertToId(String.isNotBlank(request.academicYearId) ? request.academicYearId.trim() : null);
        if (academicYearIdResolved != null) {
            try { sessionRecord.Academic_Year__c = academicYearIdResolved; } catch (Exception e) { }
        }
        Id termIdResolved = tryConvertToId(String.isNotBlank(request.termId) ? request.termId.trim() : null);
        if (termIdResolved != null) {
            try { sessionRecord.Term__c = termIdResolved; } catch (Exception e) { }
        }

        String studentConflictMessage = null;
        List<SessionConflictValidator.StudentSessionConflictDetail> studentConflictWarningDetails = null;
        try {

            Boolean skipHardConflicts = request.ignoreConflicts == true;

            if (!skipHardConflicts) {
                List<SessionConflictValidator.DivisionSessionConflictDetail> divisionConflictDetails = SessionConflictValidator.getDivisionSessionConflictDetails(
                    new Set<Id>(divisionIdsToProcess),
                    request.sessionDate,
                    request.startTime,
                    request.endTime,
                    request.sessionId,
                    getSessionName(request),
                    request.proposedConflictContextJson
                );
                if (!divisionConflictDetails.isEmpty()) {
                    Map<String, Object> errPayload = new Map<String, Object>{
                        'type' => 'DIVISION_SESSION_CONFLICT',
                        'message' => 'Conflicting session for this division. View details for more information.',
                        'details' => divisionConflictDetails
                    };
                    throw new AuraHandledException(JSON.serialize(errPayload));
                }

                List<SessionConflictValidator.FacultyConflictDetail> facultyConflictDetails = SessionConflictValidator.getFacultySessionConflictDetails(
                    facultyIds,
                    request.sessionDate,
                    request.startTime,
                    request.endTime,
                    request.sessionId,
                    getSessionName(request),
                    request.proposedConflictContextJson
                );
                if (!facultyConflictDetails.isEmpty()) {
                    Map<String, Object> errPayload = new Map<String, Object>{
                        'type' => 'FACULTY_CONFLICT',
                        'message' => 'Faculty has a conflicting session. View details for more information.',
                        'details' => facultyConflictDetails
                    };
                    throw new AuraHandledException(JSON.serialize(errPayload));
                }

                // Runs LAST of the hard checks: it is the only one that calls Google, so a clash
                // that Salesforce can see on its own is reported without spending a callout.
                assertFacultyCalendarAvailable(existingSessionSnapshot, request);
            }

            List<SessionConflictValidator.StudentSessionConflictDetail> studentConflictDetails = SessionConflictValidator.getStudentSessionConflictDetails(
                new Set<Id>(divisionIdsToProcess),
                request.sessionDate,
                request.startTime,
                request.endTime,
                request.sessionId,
                getSessionName(request)
            );
            if (!studentConflictDetails.isEmpty()) {
                studentConflictMessage = 'One or more students have overlapping sessions at this date and time. Consider adjusting the schedule or division.';
                studentConflictWarningDetails = studentConflictDetails;
            }

            Integer overlappingMergedLearners = SessionConflictValidator.countOverlappingLearnersAcrossDivisions(
                new Set<Id>(divisionIdsToProcess)
            );
            if (overlappingMergedLearners > 0) {
                String mergedOverlapWarning = 'One or more students are common between the selected main and merged programs/divisions.';
                studentConflictMessage = String.isNotBlank(studentConflictMessage)
                    ? (studentConflictMessage + ' ' + mergedOverlapWarning)
                    : mergedOverlapWarning;
            }

            Boolean skipNotify = request.sendNotifications == false;
            SessionCalendarInviteHandler.skipUserNotifications = skipNotify;
            SessionCalendarInviteHandler.facultyNotifyRequested = !skipNotify;
            // Students never receive a Google email for a republish now that they have their own
            // silent event, so the summary email is sent on Yes as well as on No.
            enqueueRepublishStudentEmail(sessionRecord, request.sessionDate);
            upsert sessionRecord;
        } catch (DmlException ex) {
            System.debug('Error saving session: ' + ex.getMessage());
            throw new AuraHandledException('Error saving session: ' + ex.getDmlMessage(0));
        }

        Set<Id> requestedDivisionIds = new Set<Id>(divisionIdsToProcess);
        if (request.sessionId != null) {
            List<Session_Division__c> existingSessionDivisions = [
                SELECT Id, Division__c
                FROM Session_Division__c
                WHERE Session__c = :sessionRecord.Id
            ];
            Set<Id> existingDivisionIds = new Set<Id>();
            for (Session_Division__c sd : existingSessionDivisions) {
                if (sd.Division__c != null) existingDivisionIds.add(sd.Division__c);
            }
            Set<Id> toRemove = new Set<Id>();
            for (Id id : existingDivisionIds) {
                if (!requestedDivisionIds.contains(id)) toRemove.add(id);
            }
            Set<Id> toAdd = new Set<Id>();
            for (Id id : requestedDivisionIds) {
                if (!existingDivisionIds.contains(id)) toAdd.add(id);
            }
            if (!toRemove.isEmpty()) {
                List<Session_Division__c> divsToDelete = new List<Session_Division__c>();
                for (Session_Division__c sd : existingSessionDivisions) {
                    if (sd.Division__c != null && toRemove.contains(sd.Division__c)) divsToDelete.add(sd);
                }
                if (!divsToDelete.isEmpty()) {
                    List<Session_Enrollment__c> enrollmentsToDelete = [
                        SELECT Id FROM Session_Enrollment__c WHERE Session_Division__c IN :divsToDelete
                    ];
                    if (!enrollmentsToDelete.isEmpty()) delete enrollmentsToDelete;
                    delete divsToDelete;
                }
            }
            if (!toAdd.isEmpty()) {
                List<Session_Division__c> sessionDivisions = new List<Session_Division__c>();
                for (Id divId : toAdd) {
                    sessionDivisions.add(new Session_Division__c(Session__c = sessionRecord.Id, Division__c = divId));
                }
                insert sessionDivisions;
                List<Division_Enrollment__c> enrollments = [
                    SELECT Id, Division__c, Academic_Term_Enrollment__c,
                           Academic_Term_Enrollment__r.LearnerAccount.FirstName,
                           Academic_Term_Enrollment__r.LearnerAccount.LastName
                    FROM Division_Enrollment__c
                    WHERE Division__c IN :toAdd
                    AND (
                        Academic_Term_Enrollment__r.Program_Enrolled__c = null
                        OR Academic_Term_Enrollment__r.Program_Enrolled__r.Status = null
                        OR Academic_Term_Enrollment__r.Program_Enrolled__r.Status != :PROGRAM_ENROLLMENT_STATUS_WITHDRAWN
                    )
                ];
                if (!enrollments.isEmpty()) {
                    String sessionTitle = sessionRecord.Name;
                    List<Session_Enrollment__c> sessionEnrollments = new List<Session_Enrollment__c>();
                    for (Division_Enrollment__c enrollment : enrollments) {
                        for (Session_Division__c sd : sessionDivisions) {
                            if (sd.Division__c == enrollment.Division__c) {
                                String firstName = (enrollment.Academic_Term_Enrollment__r != null && enrollment.Academic_Term_Enrollment__r.LearnerAccount != null)
                                    ? enrollment.Academic_Term_Enrollment__r.LearnerAccount.FirstName : null;
                                String lastName = (enrollment.Academic_Term_Enrollment__r != null && enrollment.Academic_Term_Enrollment__r.LearnerAccount != null)
                                    ? enrollment.Academic_Term_Enrollment__r.LearnerAccount.LastName : null;
                                Session_Enrollment__c se = new Session_Enrollment__c(
                                    Session__c = sessionRecord.Id,
                                    Academic_Term_Enrollment__c = enrollment.Academic_Term_Enrollment__c,
                                    Division_Enrollment__c = enrollment.Id,
                                    Session_Division__c = sd.Id
                                );
                                se.Name = buildSessionStudentName(sessionTitle, firstName, lastName);
                                sessionEnrollments.add(se);
                                break;
                            }
                        }
                    }
                    if (!sessionEnrollments.isEmpty()) insert sessionEnrollments;
                }
            }
        } else if (!divisionIdsToProcess.isEmpty()) {
            List<Session_Division__c> sessionDivisions = new List<Session_Division__c>();
            for (Id divId : divisionIdsToProcess) {
                sessionDivisions.add(new Session_Division__c(Session__c = sessionRecord.Id, Division__c = divId));
            }
            try {
                insert sessionDivisions;

Set<Id> selectedStudentIds = new Set<Id>();

if(request.selectedStudentIds != null) {

    for(String studentId : request.selectedStudentIds) {

        if(String.isNotBlank(studentId)) {

            selectedStudentIds.add(
                Id.valueOf(studentId)
            );
        }
    }
}

                List<Division_Enrollment__c> enrollments;
                if(request.courseActivity == 'Make Up Exam') {

        enrollments = [
            SELECT Id,
                   Division__c,
                   Academic_Term_Enrollment__c,
                   Academic_Term_Enrollment__r.LearnerAccount.FirstName,
                   Academic_Term_Enrollment__r.LearnerAccount.LastName
            FROM Division_Enrollment__c
            WHERE Division__c IN :divisionIdsToProcess
            AND (
                Academic_Term_Enrollment__r.Program_Enrolled__c = null
                OR Academic_Term_Enrollment__r.Program_Enrolled__r.Status = null
                OR Academic_Term_Enrollment__r.Program_Enrolled__r.Status != :PROGRAM_ENROLLMENT_STATUS_WITHDRAWN
            )
            AND Academic_Term_Enrollment__r.LearnerAccount.Id IN :selectedStudentIds
        ];
                       } else {
                           enrollments = [

                    SELECT Id, Division__c, Academic_Term_Enrollment__c,
                           Academic_Term_Enrollment__r.LearnerAccount.FirstName,
                           Academic_Term_Enrollment__r.LearnerAccount.LastName
                    FROM Division_Enrollment__c
                    WHERE Division__c IN :divisionIdsToProcess
                    AND (
                        Academic_Term_Enrollment__r.Program_Enrolled__c = null
                        OR Academic_Term_Enrollment__r.Program_Enrolled__r.Status = null
                        OR Academic_Term_Enrollment__r.Program_Enrolled__r.Status != :PROGRAM_ENROLLMENT_STATUS_WITHDRAWN
                    )
                ];
                           System.debug('enrollments found = ' + enrollments.size());
              }
                if (!enrollments.isEmpty()) {
                    String sessionTitle = sessionRecord.Name;
                    List<Session_Enrollment__c> sessionEnrollments = new List<Session_Enrollment__c>();
                    for (Division_Enrollment__c enrollment : enrollments) {
                        for (Session_Division__c sd : sessionDivisions) {
                            if (sd.Division__c == enrollment.Division__c) {
                                String firstName = (enrollment.Academic_Term_Enrollment__r != null && enrollment.Academic_Term_Enrollment__r.LearnerAccount != null)
                                    ? enrollment.Academic_Term_Enrollment__r.LearnerAccount.FirstName : null;
                                String lastName = (enrollment.Academic_Term_Enrollment__r != null && enrollment.Academic_Term_Enrollment__r.LearnerAccount != null)
                                    ? enrollment.Academic_Term_Enrollment__r.LearnerAccount.LastName : null;
                                Session_Enrollment__c se = new Session_Enrollment__c(
                                    Session__c = sessionRecord.Id,
                                    Academic_Term_Enrollment__c = enrollment.Academic_Term_Enrollment__c,
                                    Division_Enrollment__c = enrollment.Id,
                                    Session_Division__c = sd.Id
                                );
                                se.Name = buildSessionStudentName(sessionTitle, firstName, lastName);
                                sessionEnrollments.add(se);
                                break;
                            }
                        }
                    }
                    if (!sessionEnrollments.isEmpty()) insert sessionEnrollments;
                }
            } catch (DmlException ex) {
                System.debug('Error creating session divisions/enrollments: ' + ex.getMessage());
                throw new AuraHandledException('Error creating session divisions: ' + ex.getDmlMessage(0));
            }
        }
List<String> divisionNames = new List<String>();
List<String>divisionAutoCode=new List<String>();

for (Session_Division__c sd : [
    SELECT Division__r.Name,Division__r.Division_Name__c
    FROM Session_Division__c
    WHERE Session__c = :sessionRecord.Id
]) {
    if (sd.Division__r != null) {
        divisionNames.add(sd.Division__r.Division_Name__c);
        divisionAutoCode.add(sd.Division__r.Name);
    }
}
String divisionNameText = String.join(divisionNames, ', ');
String divisionAutoNameText = String.join(divisionAutoCode, ', ');

        if (request.selectedFacultyIds != null && !request.selectedFacultyIds.isEmpty()) {
            Set<Id> leadIds = new Set<Id>();
            if (request.leadFacultyIds != null && !request.leadFacultyIds.isEmpty()) {
                for (String s : request.leadFacultyIds) {
                    if (String.isNotBlank(s)) {
                        try {
                            leadIds.add(Id.valueOf(s.trim()));
                        } catch (Exception e) { }
                    }
                }
            }
            if (leadIds.isEmpty() && String.isNotBlank(request.leadFacultyId)) {
                try {
                    leadIds.add(Id.valueOf(request.leadFacultyId.trim()));
                } catch (Exception e) { }
            }

            if (request.sessionId != null) {
                List<Session_Faculty__c> existingList = [
                    SELECT Id, Session_Faculty__c, Faculty_Type__c,Divisions__c,Division_Names__c
                    FROM Session_Faculty__c
                    WHERE Session__c = :sessionRecord.Id
                ];
                Map<Id, Session_Faculty__c> existingByFacultyId = new Map<Id, Session_Faculty__c>();
                for (Session_Faculty__c sf : existingList) {
                    existingByFacultyId.put(sf.Session_Faculty__c, sf);
                }

                List<Session_Faculty__c> toInsert = new List<Session_Faculty__c>();
                List<Session_Faculty__c> toUpdate = new List<Session_Faculty__c>();
                Set<Id> requestedFacultyIds = new Set<Id>(facultyIds);

                for (Id facultyId : facultyIds) {
                    String newType = (!leadIds.isEmpty() && leadIds.contains(facultyId)) ? 'Lead' : 'Support';
                    Session_Faculty__c existing = existingByFacultyId.get(facultyId);
                    if (existing == null) {
                        Session_Faculty__c sf = new Session_Faculty__c(
                            Session__c = sessionRecord.Id,
                            Session_Faculty__c = facultyId,
                            Divisions__c= divisionAutoNameText,
                            Division_Names__c= divisionNameText

                        );
                        if (!leadIds.isEmpty()) {
                            sf.Faculty_Type__c = newType;
                        }
                        toInsert.add(sf);
                    } else {
                        existingByFacultyId.remove(facultyId);
                        String existingType = existing.Faculty_Type__c;
                        if (!leadIds.isEmpty() && (existingType != newType)) {
                            existing.Faculty_Type__c = newType;
                            toUpdate.add(existing);
                        }
                    }
                }

                List<Session_Faculty__c> toDelete = new List<Session_Faculty__c>(existingByFacultyId.values());
                if (!toDelete.isEmpty()) delete toDelete;
                if (!toUpdate.isEmpty()) update toUpdate;
                if (!toInsert.isEmpty()) insert toInsert;
            } else {
                if (!facultyIds.isEmpty()) {
                    List<Session_Faculty__c> sessionFaculties = new List<Session_Faculty__c>();
                    for (Id facultyId : facultyIds) {
                        Session_Faculty__c sf = new Session_Faculty__c(
                            Session__c = sessionRecord.Id,
                            Session_Faculty__c = facultyId,
                            Divisions__c= divisionAutoNameText,
                            Division_Names__c= divisionNameText

                        );
                        if (!leadIds.isEmpty()) {
                            sf.Faculty_Type__c = leadIds.contains(facultyId) ? 'Lead' : 'Support';
                        }
                        sessionFaculties.add(sf);
                    }
                    insert sessionFaculties;
                }
            }
        } else if (request.sessionId != null) {
            List<Session_Faculty__c> existingSessionFaculties = [
                SELECT Id
                FROM Session_Faculty__c
                WHERE Session__c = :sessionRecord.Id
            ];
            if (!existingSessionFaculties.isEmpty()) {
                delete existingSessionFaculties;
            }
        }

        SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ sessionRecord.Id });

        return new SaveSessionResult(sessionRecord.Id, studentConflictMessage, studentConflictWarningDetails);
    }

    private static String buildSessionStudentName(String sessionTitle, String firstName, String lastName) {
        String title = String.isNotBlank(sessionTitle) ? sessionTitle.trim() : '';
        String first = firstName != null ? firstName.trim() : '';
        String last = lastName != null ? lastName.trim() : '';
        String studentName = String.isNotBlank(first) || String.isNotBlank(last)
            ? (first + (String.isNotBlank(first) && String.isNotBlank(last) ? '-' : '') + last)
            : '';
        if (String.isBlank(title) && String.isBlank(studentName)) return null;
        if (String.isBlank(studentName)) return title;
        if (String.isBlank(title)) return studentName;
            String finalName = title + '_' + studentName;

            return finalName.length() > 80
                ? finalName.substring(0, 80)
                : finalName;
    }

    private static Boolean dateOrTimeChanged(Session__c existing, SessionInput request) {
        if (existing == null || request == null) return true;
        if (existing.Session_Date__c != request.sessionDate) return true;
        if (request.startTime == null || request.endTime == null) return false;
        if (existing.Start_Time__c == null || existing.End_Time__c == null) return true;
        Long existingStart = existing.Start_Time__c.getTime();
        Long existingEnd = existing.End_Time__c.getTime();
        Long reqStart = request.startTime.getTime();
        Long reqEnd = request.endTime.getTime();
        return existingStart != reqStart || existingEnd != reqEnd;
    }

    /**
     * @description Re-reads the assigned faculty's Google Calendar when an EXISTING session is
     *          moved to a new date or time, and blocks the save when any of them is already busy.
     *          Living on the save rather than on the screen is deliberate: the edit modal,
     *          drag-and-drop and resize all reach the org through saveSession, so one check here
     *          covers every reschedule route instead of three screens each remembering to ask.
     *
     *          The work itself is delegated to getFacultyCalendarConflictsForSessions — the same
     *          method the Create Sessions screen calls before a create — so both moments share one
     *          implementation, one payload shape and one conflict-card shape. That method also
     *          excludes the session's OWN two calendar entries, without which every reschedule
     *          would report the session clashing with itself.
     *
     * @note    No-op on create (the screen already checks before calling), when the timing did not
     *          actually change, and when the save carries the user's conflict override. Reading
     *          Google is fail-open by design: if the integration is down the underlying service
     *          returns no conflicts and the reschedule proceeds rather than being stuck.
     *
     * @param existingSession The session as it stood in the org before this save; null on create.
     * @param request The incoming save request carrying the proposed date, times and faculty.
     */
    @TestVisible
    private static void assertFacultyCalendarAvailable(Session__c existingSession, SessionInput request) {
        if (!isRescheduleNeedingCalendarCheck(existingSession, request)) {
            return;
        }
        List<String> facultyIdStrs = requestedFacultyIdStrings(request);
        if (facultyIdStrs.isEmpty()) {
            return;
        }
        // Local date + wall-clock times, exactly the shape the Create Sessions screen posts, so the
        // shared method parses them back to the same instants it would on create.
        String proposedJson = JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'sessionId'          => String.valueOf(existingSession.Id),
                'sessionName'        => getSessionName(request),
                'sessionDate'        => formatDateForQuery(request.sessionDate),
                'startTime'          => formatTimeForClient(request.startTime),
                'endTime'            => formatTimeForClient(request.endTime),
                'selectedFacultyIds' => facultyIdStrs
            }
        });
        List<FacultyCalendarConflictDetail> calendarConflicts =
            getFacultyCalendarConflictsForSessions(proposedJson);
        if (calendarConflicts == null || calendarConflicts.isEmpty()) {
            return;
        }
        Map<String, Object> errPayload = new Map<String, Object>{
            'type' => 'CALENDAR_CONFLICT',
            'message' => 'Faculty is not available at the new date and time. View details for more information.',
            'details' => calendarConflicts
        };
        throw new AuraHandledException(JSON.serialize(errPayload));
    }

    /**
     * @description Whether this save is a genuine reschedule of an existing session and therefore
     *          worth spending a Google callout on: there is a previous version to compare against,
     *          the request carries a complete window, and the date or times actually moved.
     * @param existingSession The session as it stood in the org before this save; null on create.
     * @param request The incoming save request.
     * @return True when the faculty's calendar should be re-read.
     */
    private static Boolean isRescheduleNeedingCalendarCheck(Session__c existingSession, SessionInput request) {
        if (existingSession == null || existingSession.Id == null || request == null) {
            return false;
        }
        if (request.sessionDate == null || request.startTime == null || request.endTime == null) {
            return false;
        }
        return dateOrTimeChanged(existingSession, request);
    }

    /**
     * @description The non-blank faculty ids on a save request, as strings ready for the shared
     *          conflict payload.
     * @param request The incoming save request.
     * @return The faculty ids, empty when none were sent.
     */
    private static List<String> requestedFacultyIdStrings(SessionInput request) {
        List<String> facultyIdStrs = new List<String>();
        if (request == null || request.selectedFacultyIds == null) {
            return facultyIdStrs;
        }
        for (String facultyIdStr : request.selectedFacultyIds) {
            if (String.isNotBlank(facultyIdStr)) {
                facultyIdStrs.add(facultyIdStr);
            }
        }
        return facultyIdStrs;
    }

    @TestVisible
    private static Id reschedulePublishedSession(Session__c existingSession, SessionInput request, Id courseLookupId, Id ownerLookupId, Set<Id> facultyIds) {
        List<Session_Division__c> existingDivs = [
            SELECT Id, Division__c
            FROM Session_Division__c
            WHERE Session__c = :existingSession.Id
        ];
        Set<Id> divisionIdsForValidation = new Set<Id>();
        for (Session_Division__c sd : existingDivs) {
            if (sd.Division__c != null) divisionIdsForValidation.add(sd.Division__c);
        }

        Boolean skipHardConflicts = request.ignoreConflicts == true;
        if (!skipHardConflicts) {
            List<SessionConflictValidator.DivisionSessionConflictDetail> divisionConflictDetails = SessionConflictValidator.getDivisionSessionConflictDetails(
                divisionIdsForValidation,
                request.sessionDate,
                request.startTime,
                request.endTime,
                null,
                getSessionName(request),
                request.proposedConflictContextJson
            );
            if (!divisionConflictDetails.isEmpty()) {
                Map<String, Object> errPayload = new Map<String, Object>{
                    'type' => 'DIVISION_SESSION_CONFLICT',
                    'message' => 'Conflicting session for this division. View details for more information.',
                    'details' => divisionConflictDetails
                };
                throw new AuraHandledException(JSON.serialize(errPayload));
            }
            List<SessionConflictValidator.FacultyConflictDetail> facultyConflictDetails = SessionConflictValidator.getFacultySessionConflictDetails(
                facultyIds,
                request.sessionDate,
                request.startTime,
                request.endTime,
                null,
                getSessionName(request),
                request.proposedConflictContextJson
            );
            if (!facultyConflictDetails.isEmpty()) {
                Map<String, Object> errPayload = new Map<String, Object>{
                    'type' => 'FACULTY_CONFLICT',
                    'message' => 'Faculty has a conflicting session. View details for more information.',
                    'details' => facultyConflictDetails
                };
                throw new AuraHandledException(JSON.serialize(errPayload));
            }
        }
        List<SessionConflictValidator.StudentSessionConflictDetail> studentConflictDetails = SessionConflictValidator.getStudentSessionConflictDetails(
            divisionIdsForValidation,
            request.sessionDate,
            request.startTime,
            request.endTime,
            null,
            getSessionName(request)
        );

        existingSession.Schedule_Type__c = 'Rescheduled';
        update existingSession;

        Session__c newSession = new Session__c();
        newSession.Name = getSessionName(request);
        newSession.Course__c = courseLookupId;
        newSession.Session_Date__c = request.sessionDate;
        newSession.Start_Time__c = request.startTime;
        newSession.End_Time__c = request.endTime;
        newSession.Description__c = request.description;
        newSession.Course_Activity__c = request.courseActivity;
        newSession.Session_Type__c = request.sessionType;
        newSession.OwnerId = ownerLookupId != null ? ownerLookupId : UserInfo.getUserId();
        newSession.Class_Room__c = request.classRoom;
        newSession.Remark__c = request.remark;
        newSession.URL__c = request.url;
        newSession.Color__c = existingSession.Color__c;
        newSession.Is_Joint_Session__c = existingSession.Is_Joint_Session__c != null ? existingSession.Is_Joint_Session__c : false;
        newSession.Schedule_Type__c = 'Published';
        Map<String, String> sessionInfoFieldMap = getSessionInfoFieldApiNameMap();
        for (String local : sessionInfoFieldMap.keySet()) {
            String apiName = sessionInfoFieldMap.get(local);
            try {
                Object val = existingSession.get(apiName);
                if (val != null) { newSession.put(apiName, val); }
            } catch (Exception e) { }
        }
        insert newSession;

        if (!existingDivs.isEmpty()) {
            List<Session_Division__c> newDivs = new List<Session_Division__c>();
            for (Session_Division__c sd : existingDivs) {
                newDivs.add(new Session_Division__c(Session__c = newSession.Id, Division__c = sd.Division__c));
            }
            insert newDivs;

            List<Session_Enrollment__c> existingEnrollments = [
                SELECT Session_Division__c, Academic_Term_Enrollment__c, Division_Enrollment__c,
                       Academic_Term_Enrollment__r.LearnerAccount.FirstName,
                       Academic_Term_Enrollment__r.LearnerAccount.LastName
                FROM Session_Enrollment__c
                WHERE Session_Division__c IN :existingDivs
            ];
            Map<Id, Id> oldDivIdToNewDivId = new Map<Id, Id>();
            for (Integer i = 0; i < existingDivs.size(); i++) {
                oldDivIdToNewDivId.put(existingDivs[i].Id, newDivs[i].Id);
            }
            String newSessionTitle = newSession.Name;
            List<Session_Enrollment__c> newEnrollments = new List<Session_Enrollment__c>();
            for (Session_Enrollment__c se : existingEnrollments) {
                Id newSdId = oldDivIdToNewDivId.get(se.Session_Division__c);
                if (newSdId != null) {
                    String firstName = (se.Academic_Term_Enrollment__r != null && se.Academic_Term_Enrollment__r.LearnerAccount != null)
                        ? se.Academic_Term_Enrollment__r.LearnerAccount.FirstName : null;
                    String lastName = (se.Academic_Term_Enrollment__r != null && se.Academic_Term_Enrollment__r.LearnerAccount != null)
                        ? se.Academic_Term_Enrollment__r.LearnerAccount.LastName : null;
                    Session_Enrollment__c newSe = new Session_Enrollment__c(
                        Session__c = newSession.Id,
                        Session_Division__c = newSdId,
                        Academic_Term_Enrollment__c = se.Academic_Term_Enrollment__c,
                        Division_Enrollment__c = se.Division_Enrollment__c
                    );
                    newSe.Name = buildSessionStudentName(newSessionTitle, firstName, lastName);
                    newEnrollments.add(newSe);
                }
            }
            if (!newEnrollments.isEmpty()) {
                insert newEnrollments;
            }
        }

        List<Session_Faculty__c> existingFaculties = [
            SELECT Session_Faculty__c, Faculty_Type__c
            FROM Session_Faculty__c
            WHERE Session__c = :existingSession.Id
        ];
        if (!existingFaculties.isEmpty()) {
            List<Session_Faculty__c> newFaculties = new List<Session_Faculty__c>();
            for (Session_Faculty__c sf : existingFaculties) {
                Session_Faculty__c nf = new Session_Faculty__c(Session__c = newSession.Id, Session_Faculty__c = sf.Session_Faculty__c);
                if (String.isNotBlank(sf.Faculty_Type__c)) nf.Faculty_Type__c = sf.Faculty_Type__c;
                newFaculties.add(nf);
            }
            insert newFaculties;
        }

        return newSession.Id;
    }

    public class StudentWrapper {
    @AuraEnabled public Id studentId;
    @AuraEnabled public String studentName;

    public StudentWrapper(Id studentId, String studentName) {
        this.studentId = studentId;
        this.studentName = studentName;
    }
}
    @AuraEnabled(cacheable=true)
public static List<StudentWrapper> getEligibleMakeupStudents(Id divisionId, Id courseId) {

    List<StudentWrapper> students = new List<StudentWrapper>();
    if(divisionId == null) return students;

    if(courseId != null) {
        List<DivisionCourse__c> divCourses = [
            SELECT Id
            FROM DivisionCourse__c
            WHERE Division__c = :divisionId
            AND Course_Offering__r.LearningCourseId = :courseId
            LIMIT 1
        ];
        if(divCourses.isEmpty()) return students;
    }

    Set<Id> eligibleStudentIds = new Set<Id>();
    for(Leave_Application__c leaveApp : [
        SELECT Student__c
        FROM Leave_Application__c
        WHERE Status__c = 'Approved - Eligible for Makeup'
        AND Student__c != null
    ]) {
        eligibleStudentIds.add(leaveApp.Student__c);
    }

    if(eligibleStudentIds.isEmpty()) return students;

    for(Division_Enrollment__c de : [
        SELECT Academic_Term_Enrollment__c,
               Academic_Term_Enrollment__r.LearnerAccount.Id,
               Academic_Term_Enrollment__r.LearnerAccount.Name
        FROM Division_Enrollment__c
        WHERE Division__c = :divisionId
        AND Academic_Term_Enrollment__r.LearnerAccount.Id IN :eligibleStudentIds
    ]) {
        students.add(
            new StudentWrapper(
                de.Academic_Term_Enrollment__r.LearnerAccount.Id,
                de.Academic_Term_Enrollment__r.LearnerAccount.Name
            )
        );
    }

    return students;
}
    @AuraEnabled
    public static Id deleteSession(Id sessionId, Id divisionIdToRemove) {
        if (sessionId == null) {
            throw new AuraHandledException('Session Id is required for deletion.');
        }

        Session__c sessionRecord = [
            SELECT Id, Schedule_Type__c
            FROM Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        List<Session_Division__c> sessionDivisions = [
            SELECT Id, Division__c
            FROM Session_Division__c
            WHERE Session__c = :sessionId
        ];

        Boolean isDraft = String.isNotBlank(sessionRecord.Schedule_Type__c) &&
            sessionRecord.Schedule_Type__c.equalsIgnoreCase('Draft');

        if (divisionIdToRemove != null && sessionDivisions.size() > 1) {
            if (String.isNotBlank(sessionRecord.Schedule_Type__c) &&
                (sessionRecord.Schedule_Type__c.equalsIgnoreCase('Published') ||
                 sessionRecord.Schedule_Type__c.equalsIgnoreCase('Republished'))) {
                sessionRecord.Schedule_Type__c = 'Republished';
                update sessionRecord;
            }
            removeDivisionFromSession(sessionId, divisionIdToRemove);
            SessionCalendarInviteHandler.handleRelatedRecordChange(new Set<Id>{ sessionId });
            return sessionId;
        }

        List<Session_Faculty__c> sessionFaculties = [
            SELECT Id
            FROM Session_Faculty__c
            WHERE Session__c = :sessionId
        ];

        Session__c record = [
            SELECT Id
            FROM Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
        delete record;

        if (!sessionFaculties.isEmpty()) {
            delete sessionFaculties;
        }
        return null;
    }

    @AuraEnabled
    public static Id cancelSession(Id sessionId) {
        if (sessionId == null) {
            throw new AuraHandledException('Session Id is required for cancel.');
        }

        Session__c sessionRecord = [
            SELECT Id, Schedule_Type__c
            FROM Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];

        sessionRecord.Schedule_Type__c = 'Cancelled';
        update sessionRecord;

        List<Session_Enrollment__c> enrollments = [
            SELECT Id
            FROM Session_Enrollment__c
            WHERE Session__c = :sessionId
        ];
        if (!enrollments.isEmpty()) {
            delete enrollments;
        }
        return sessionId;
    }

    private static void removeDivisionFromSession(Id sessionId, Id divisionIdToRemove) {
        List<Session_Division__c> toDelete = [
            SELECT Id
            FROM Session_Division__c
            WHERE Session__c = :sessionId
            AND Division__c = :divisionIdToRemove
        ];
        if (toDelete.isEmpty()) {
            return;
        }
        List<Session_Enrollment__c> enrollments = [
            SELECT Id
            FROM Session_Enrollment__c
            WHERE Session_Division__c IN :toDelete
        ];
        if (!enrollments.isEmpty()) {
            delete enrollments;
        }
        delete toDelete;
    }

    @TestVisible
    private static Id cancelAndCloneSessionWithoutDivision(Id sessionId, Id divisionIdToRemove, List<Session_Division__c> sessionDivisions) {
        String existingQuery = 'SELECT Id, Name, Course__c, Session_Date__c, Start_Time__c, End_Time__c, Description__c, Course_Activity__c,Session_Type__c, OwnerId, Class_Room__c, Remark__c, URL__c, Color__c, Is_Joint_Session__c, Schedule_Type__c';
        List<String> sessionInfoFields = getSessionInfoFieldApiNames();
        if (!sessionInfoFields.isEmpty()) {
            existingQuery += ',' + String.join(sessionInfoFields, ',');
        }
        existingQuery += ' FROM Session__c WHERE Id = :sessionId LIMIT 1';
        Session__c existing = (Session__c) Database.query(existingQuery)[0];

        existing.Schedule_Type__c = 'Cancelled';
        update existing;

        Session__c newSession = new Session__c();
        newSession.Name = existing.Name;
        newSession.Course__c = existing.Course__c;
        newSession.Session_Date__c = existing.Session_Date__c;
        newSession.Start_Time__c = existing.Start_Time__c;
        newSession.End_Time__c = existing.End_Time__c;
        newSession.Description__c = existing.Description__c;
        newSession.Course_Activity__c = existing.Course_Activity__c;
        newSession.Session_Type__c = existing.Session_Type__c;
        newSession.OwnerId = existing.OwnerId;
        newSession.Class_Room__c = existing.Class_Room__c;
        newSession.Remark__c = existing.Remark__c;
        newSession.URL__c = existing.URL__c;
        newSession.Color__c = existing.Color__c;
        newSession.Is_Joint_Session__c = existing.Is_Joint_Session__c != null ? existing.Is_Joint_Session__c : false;
        newSession.Schedule_Type__c = (String.isNotBlank(existing.Schedule_Type__c) && existing.Schedule_Type__c.equalsIgnoreCase('Published'))
            ? 'Published' : 'Draft';
        Map<String, String> sessionInfoFieldMap = getSessionInfoFieldApiNameMap();
        for (String local : sessionInfoFieldMap.keySet()) {
            String apiName = sessionInfoFieldMap.get(local);
            try {
                Object val = existing.get(apiName);
                if (val != null) { newSession.put(apiName, val); }
            } catch (Exception e) { }
        }
        insert newSession;

        List<Session_Division__c> divsToClone = new List<Session_Division__c>();
        for (Session_Division__c sd : sessionDivisions) {
            if (sd.Division__c != divisionIdToRemove) {
                divsToClone.add(sd);
            }
        }

        if (divsToClone.isEmpty()) {
            return newSession.Id;
        }

        List<Session_Division__c> newDivs = new List<Session_Division__c>();
        for (Session_Division__c sd : divsToClone) {
            newDivs.add(new Session_Division__c(Session__c = newSession.Id, Division__c = sd.Division__c));
        }
        insert newDivs;

        Map<Id, Id> oldDivIdToNewDivId = new Map<Id, Id>();
        for (Integer i = 0; i < divsToClone.size(); i++) {
            oldDivIdToNewDivId.put(divsToClone[i].Id, newDivs[i].Id);
        }

        List<Session_Enrollment__c> existingEnrollments = [
            SELECT Session_Division__c, Academic_Term_Enrollment__c, Division_Enrollment__c,
                   Academic_Term_Enrollment__r.LearnerAccount.FirstName,
                   Academic_Term_Enrollment__r.LearnerAccount.LastName
            FROM Session_Enrollment__c
            WHERE Session_Division__c IN :divsToClone
        ];
        String newSessionTitle = newSession.Name;
        List<Session_Enrollment__c> newEnrollments = new List<Session_Enrollment__c>();
        for (Session_Enrollment__c se : existingEnrollments) {
            Id newSdId = oldDivIdToNewDivId.get(se.Session_Division__c);
            if (newSdId != null) {
                String firstName = (se.Academic_Term_Enrollment__r != null && se.Academic_Term_Enrollment__r.LearnerAccount != null)
                    ? se.Academic_Term_Enrollment__r.LearnerAccount.FirstName : null;
                String lastName = (se.Academic_Term_Enrollment__r != null && se.Academic_Term_Enrollment__r.LearnerAccount != null)
                    ? se.Academic_Term_Enrollment__r.LearnerAccount.LastName : null;
                Session_Enrollment__c newSe = new Session_Enrollment__c(
                    Session__c = newSession.Id,
                    Session_Division__c = newSdId,
                    Academic_Term_Enrollment__c = se.Academic_Term_Enrollment__c,
                    Division_Enrollment__c = se.Division_Enrollment__c
                );
                newSe.Name = buildSessionStudentName(newSessionTitle, firstName, lastName);
                newEnrollments.add(newSe);
            }
        }
        if (!newEnrollments.isEmpty()) {
            insert newEnrollments;
        }

        List<Session_Faculty__c> existingFaculties = [
            SELECT Session_Faculty__c, Faculty_Type__c
            FROM Session_Faculty__c
            WHERE Session__c = :sessionId
        ];
        if (!existingFaculties.isEmpty()) {
            List<Session_Faculty__c> newFaculties = new List<Session_Faculty__c>();
            for (Session_Faculty__c sf : existingFaculties) {
                Session_Faculty__c nf = new Session_Faculty__c(Session__c = newSession.Id, Session_Faculty__c = sf.Session_Faculty__c);
                if (String.isNotBlank(sf.Faculty_Type__c)) nf.Faculty_Type__c = sf.Faculty_Type__c;
                newFaculties.add(nf);
            }
            insert newFaculties;
        }
        return newSession.Id;
    }

    @AuraEnabled
    public static List<SessionConflictValidator.FacultyConflictDetail> getFacultyConflictsForSessions(String sessionsJson) {
        List<SessionConflictValidator.FacultyConflictDetail> allConflicts = new List<SessionConflictValidator.FacultyConflictDetail>();
        if (String.isBlank(sessionsJson)) {
            System.debug('getFacultyConflictsForSessions: sessionsJson is blank');
            return allConflicts;
        }
        List<Object> rawList;
        try {
            rawList = (List<Object>) JSON.deserializeUntyped(sessionsJson);
        } catch (Exception e) {
            System.debug('getFacultyConflictsForSessions: Error deserializing JSON: ' + e.getMessage());
            return allConflicts;
        }
        if (rawList == null || rawList.isEmpty()) {
            System.debug('getFacultyConflictsForSessions: rawList is empty');
            return allConflicts;
        }
        System.debug('getFacultyConflictsForSessions: Processing ' + rawList.size() + ' sessions');
        for (Object item : rawList) {
            try {
                Map<String, Object> m = (Map<String, Object>) item;
                String sessionName = (String) m.get('sessionName');
                String sessionDateStr = (String) m.get('sessionDate');
                Object startObj = m.get('startTime');
                Object endObj = m.get('endTime');
                Id currentSessionId;
                Object sessionIdObj = m.get('sessionId');
                if (sessionIdObj != null && String.isNotBlank(String.valueOf(sessionIdObj))) {
                    currentSessionId = (Id)String.valueOf(sessionIdObj);
                }
                List<String> facultyIdStrs = extractStringListFromJson(m.get('selectedFacultyIds'));
                if (String.isBlank(sessionDateStr) || startObj == null || endObj == null || facultyIdStrs == null || facultyIdStrs.isEmpty()) {
                    System.debug('getFacultyConflictsForSessions: Skipping session due to missing data - date: ' + sessionDateStr + ', startTime: ' + startObj + ', endTime: ' + endObj + ', facultyIds: ' + facultyIdStrs);
                    continue;
                }
                Date sessionDate = parseDateFromString(sessionDateStr);
                Datetime startTime = parseDateTimeFromInput(sessionDateStr, startObj);
                Datetime endTime = parseDateTimeFromInput(sessionDateStr, endObj);
                if (sessionDate == null || startTime == null || endTime == null) {
                    System.debug('getFacultyConflictsForSessions: Skipping session due to parsing failure - date: ' + sessionDate + ', startTime: ' + startTime + ', endTime: ' + endTime);
                    continue;
                }
                Set<Id> facultyIds = new Set<Id>();
                for (String fid : facultyIdStrs) {
                    if (String.isNotBlank(fid)) {
                        try {
                            facultyIds.add(Id.valueOf(fid));
                        } catch (Exception ignore) {}
                    }
                }
                if (facultyIds.isEmpty()) {
                    System.debug('getFacultyConflictsForSessions: No valid faculty IDs');
                    continue;
                }
                System.debug('getFacultyConflictsForSessions: Checking conflicts for session: ' + sessionName + ', date: ' + sessionDate + ', startTime: ' + startTime + ', endTime: ' + endTime + ', facultyIds: ' + facultyIds);
                String proposedContextJson = serializeProposedContextFromJsonMap(m);
                List<SessionConflictValidator.FacultyConflictDetail> conflicts = SessionConflictValidator.getFacultySessionConflictDetails(
                    facultyIds, sessionDate, startTime, endTime, currentSessionId, sessionName, proposedContextJson
                );
                if (conflicts != null && !conflicts.isEmpty()) {
                    System.debug('getFacultyConflictsForSessions: Found ' + conflicts.size() + ' conflicts for session: ' + sessionName);
                    allConflicts.addAll(conflicts);
                }
            } catch (Exception e) {
                System.debug('getFacultyConflictsForSessions: Error processing session item: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            }
        }
        System.debug('getFacultyConflictsForSessions: Returning ' + allConflicts.size() + ' total conflicts');
        return allConflicts;
    }

    public class FacultyCalendarConflictDetail {
        @AuraEnabled public String proposedSessionName { get; set; }
        @AuraEnabled public String proposedDateStr { get; set; }
        @AuraEnabled public String proposedTimeStr { get; set; }
        @AuraEnabled public String facultyName { get; set; }
        @AuraEnabled public String facultyEmail { get; set; }
        @AuraEnabled public String conflictingSummary { get; set; }
        @AuraEnabled public String conflictingTimeStr { get; set; }
        @AuraEnabled public String conflictingEventId { get; set; }
        @AuraEnabled public Id conflictingSessionId { get; set; }
        @AuraEnabled public Boolean isSalesforceSession = false;
        @AuraEnabled public String source = 'Google Calendar';
    }

    @AuraEnabled
    public static List<FacultyCalendarConflictDetail> getFacultyCalendarConflictsForSessions(String sessionsJson) {
        List<FacultyCalendarConflictDetail> allConflicts = new List<FacultyCalendarConflictDetail>();
        if (String.isBlank(sessionsJson)) {
            return allConflicts;
        }
        List<Object> rawList;
        try {
            rawList = (List<Object>) JSON.deserializeUntyped(sessionsJson);
        } catch (Exception e) {
            return allConflicts;
        }
        if (rawList == null || rawList.isEmpty()) {
            return allConflicts;
        }

        List<Map<String, Object>> proposed = new List<Map<String, Object>>();
        Set<Id> facultyIds = new Set<Id>();
        for (Object item : rawList) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> m = (Map<String, Object>) item;
            String dateStr = (String) m.get('sessionDate');
            Datetime startTime = parseDateTimeFromInput(dateStr, m.get('startTime'));
            Datetime endTime = parseDateTimeFromInput(dateStr, m.get('endTime'));
            List<String> facultyIdStrs = extractStringListFromJson(m.get('selectedFacultyIds'));
            if (startTime == null || endTime == null || facultyIdStrs == null || facultyIdStrs.isEmpty()) {
                continue;
            }
            List<Id> sessionFacultyIds = new List<Id>();
            for (String fid : facultyIdStrs) {
                if (String.isBlank(fid)) {
                    continue;
                }
                try {
                    Id fEntity = Id.valueOf(fid);
                    sessionFacultyIds.add(fEntity);
                    facultyIds.add(fEntity);
                } catch (Exception ignore) {}
            }
            if (sessionFacultyIds.isEmpty()) {
                continue;
            }
            Id currentSessionId;
            Object sidObj = m.get('sessionId');
            if (sidObj != null && String.isNotBlank(String.valueOf(sidObj))) {
                try {
                    currentSessionId = (Id) String.valueOf(sidObj);
                } catch (Exception ignore) {}
            }
            proposed.add(new Map<String, Object>{
                'name'       => m.get('sessionName'),
                'dateStr'    => dateStr,
                'start'      => startTime,
                'end'        => endTime,
                'facultyIds' => sessionFacultyIds,
                'sessionId'  => currentSessionId
            });
        }
        if (proposed.isEmpty()) {
            return allConflicts;
        }

        Map<Id, Account> facById = new Map<Id, Account>([
            SELECT Id, Name, PersonEmail FROM Account WHERE Id IN :facultyIds
        ]);
        Set<Id> currentSessionIds = new Set<Id>();
        for (Map<String, Object> p : proposed) {
            if (p.get('sessionId') != null) {
                currentSessionIds.add((Id) p.get('sessionId'));
            }
        }
        // Both copies of the session's own event must be excluded. The faculty's calendar shows the
        // FACULTY copy, so excluding only the student copy would report the session clashing with
        // itself and block the save.
        Map<Id, Set<String>> ownEventIdsBySession = new Map<Id, Set<String>>();
        if (!currentSessionIds.isEmpty()) {
            for (Session__c s : [
                SELECT Id, Google_Event_Id__c, Faculty_Google_Event_Id__c
                FROM Session__c WHERE Id IN :currentSessionIds
            ]) {
                Set<String> own = new Set<String>();
                if (String.isNotBlank(s.Google_Event_Id__c)) {
                    own.add(s.Google_Event_Id__c);
                }
                if (String.isNotBlank(s.Faculty_Google_Event_Id__c)) {
                    own.add(s.Faculty_Google_Event_Id__c);
                }
                ownEventIdsBySession.put(s.Id, own);
            }
        }

        final Integer CALLOUT_CAP = 45;
        Integer calloutCount = 0;
        Set<String> conflictEventIds = new Set<String>();
        for (Map<String, Object> p : proposed) {
            Datetime startTime = (Datetime) p.get('start');
            Datetime endTime = (Datetime) p.get('end');
            Set<String> excludeEventIds = ownEventIdsBySession.get((Id) p.get('sessionId'));
            for (Id fId : (List<Id>) p.get('facultyIds')) {
                if (calloutCount >= CALLOUT_CAP) {
                    break;
                }
                Account fac = facById.get(fId);
                if (fac == null || String.isBlank(fac.PersonEmail)) {
                    continue;
                }
                calloutCount++;
                List<FacultyCalendarConflictService.BusyEvent> busy =
                    FacultyCalendarConflictService.findOverlaps(fac.PersonEmail, startTime, endTime, excludeEventIds);
                for (FacultyCalendarConflictService.BusyEvent b : busy) {
                    FacultyCalendarConflictDetail d = new FacultyCalendarConflictDetail();
                    d.proposedSessionName = (String) p.get('name');
                    d.proposedDateStr = (String) p.get('dateStr');
                    d.proposedTimeStr = startTime.format('h:mm a') + ' - ' + endTime.format('h:mm a');
                    d.facultyName = fac.Name;
                    d.facultyEmail = fac.PersonEmail;
                    d.conflictingEventId = b.eventId;
                    d.conflictingSummary = 'Busy';
                    d.conflictingTimeStr = (b.startTime != null ? b.startTime.format('h:mm a') : '?')
                        + ' - ' + (b.endTime != null ? b.endTime.format('h:mm a') : '?');
                    allConflicts.add(d);
                    if (String.isNotBlank(b.eventId)) {
                        conflictEventIds.add(b.eventId);
                    }
                }
            }
        }

        if (!conflictEventIds.isEmpty()) {
            // A busy block on a faculty's calendar is their own copy of the session, so match on
            // either id — otherwise a genuine clash shows as "Busy" with no session name.
            Map<String, Session__c> sfByEventId = new Map<String, Session__c>();
            for (Session__c s : [
                SELECT Id, Name, Google_Event_Id__c, Faculty_Google_Event_Id__c, Course__r.Name
                FROM Session__c
                WHERE Google_Event_Id__c IN :conflictEventIds
                   OR Faculty_Google_Event_Id__c IN :conflictEventIds
            ]) {
                if (String.isNotBlank(s.Google_Event_Id__c)) {
                    sfByEventId.put(s.Google_Event_Id__c, s);
                }
                if (String.isNotBlank(s.Faculty_Google_Event_Id__c)) {
                    sfByEventId.put(s.Faculty_Google_Event_Id__c, s);
                }
            }
            for (FacultyCalendarConflictDetail d : allConflicts) {
                Session__c s = (d.conflictingEventId != null) ? sfByEventId.get(d.conflictingEventId) : null;
                if (s != null) {
                    d.conflictingSessionId = s.Id;
                    d.isSalesforceSession = true;
                    String label = String.isNotBlank(s.Name) ? s.Name : '(session)';
                    if (s.Course__r != null && String.isNotBlank(s.Course__r.Name)) {
                        label += ' (' + s.Course__r.Name + ')';
                    }
                    d.conflictingSummary = label;
                }
            }
        }
        return allConflicts;
    }

    @AuraEnabled
    public static List<SessionConflictValidator.DivisionSessionConflictDetail> getDivisionSessionConflictsForSessions(String sessionsJson) {
        List<SessionConflictValidator.DivisionSessionConflictDetail> allConflicts = new List<SessionConflictValidator.DivisionSessionConflictDetail>();
        if (String.isBlank(sessionsJson)) {
            return allConflicts;
        }
        List<Object> rawList;
        try {
            rawList = (List<Object>) JSON.deserializeUntyped(sessionsJson);
        } catch (Exception e) {
            System.debug('getDivisionSessionConflictsForSessions: Error deserializing JSON: ' + e.getMessage());
            return allConflicts;
        }
        if (rawList == null || rawList.isEmpty()) {
            return allConflicts;
        }
        for (Object item : rawList) {
            try {
                Map<String, Object> m = (Map<String, Object>) item;
                String sessionName = (String) m.get('sessionName');
                String sessionDateStr = (String) m.get('sessionDate');
                Object startObj = m.get('startTime');
                Object endObj = m.get('endTime');
                Id currentSessionId;
                Object sessionIdObj = m.get('sessionId');
                if (sessionIdObj != null &&
                    String.isNotBlank(String.valueOf(sessionIdObj))) {

                    currentSessionId = (Id)String.valueOf(sessionIdObj);
                }
                List<String> divisionIdStrs = extractStringListFromJson(m.get('divisionIds'));
                if (String.isBlank(sessionDateStr) || startObj == null || endObj == null || divisionIdStrs == null || divisionIdStrs.isEmpty()) {
                    continue;
                }
                Date sessionDate = parseDateFromString(sessionDateStr);
                Datetime startTime = parseDateTimeFromInput(sessionDateStr, startObj);
                Datetime endTime = parseDateTimeFromInput(sessionDateStr, endObj);
                if (sessionDate == null || startTime == null || endTime == null) {
                    continue;
                }
                Set<Id> divisionIds = new Set<Id>();
                for (String did : divisionIdStrs) {
                    if (String.isNotBlank(did)) {
                        try {
                            divisionIds.add(Id.valueOf(did));
                        } catch (Exception ignore) {}
                    }
                }
                if (divisionIds.isEmpty()) {
                    continue;
                }
                String proposedContextJson = serializeProposedContextFromJsonMap(m);
                List<SessionConflictValidator.DivisionSessionConflictDetail> conflicts = SessionConflictValidator.getDivisionSessionConflictDetails(
                    divisionIds, sessionDate, startTime, endTime, currentSessionId, sessionName, proposedContextJson
                );
                if (conflicts != null && !conflicts.isEmpty()) {
                    allConflicts.addAll(conflicts);
                }
            } catch (Exception e) {
                System.debug('getDivisionSessionConflictsForSessions: Error processing session item: ' + e.getMessage());
            }
        }
        return allConflicts;
    }

    private static String serializeProposedContextFromJsonMap(Map<String, Object> m) {
        if (m == null) {
            return null;
        }
        Object pc = m.get('proposedContext');
        if (pc == null) {
            return null;
        }
        return JSON.serialize(pc);
    }

    private static List<String> extractStringListFromJson(Object jsonArray) {
        List<String> out = new List<String>();
        if (jsonArray == null) return out;
        if (jsonArray instanceof List<Object>) {
            for (Object o : (List<Object>) jsonArray) {
                if (o != null) out.add(String.valueOf(o));
            }
        } else if (jsonArray instanceof List<String>) {
            return (List<String>) jsonArray;
        }
        return out;
    }

    private static Date parseDateFromString(String dateStr) {
        if (String.isBlank(dateStr)) return null;
        try {
            if (dateStr.indexOf('T') >= 0) {
                dateStr = dateStr.split('T')[0];
            }
            return Date.valueOf(dateStr);
        } catch (Exception e) {
            System.debug('Error parsing date: ' + dateStr + ' - ' + e.getMessage());
            return null;
        }
    }

    private static Datetime parseDateTimeFromInput(String dateStr, Object timeInput) {
        if (String.isBlank(dateStr) || timeInput == null) return null;
        if (timeInput instanceof String) {
            String s = (String) timeInput;
            if (s.length() > 10 && s.indexOf('T') >= 0) {
                try {
                    String cleaned = s.replace('Z', '').replaceAll('\\.\\d+', '');
                    String[] parts = cleaned.split('T');
                    if (parts.size() == 2) {
                        String[] dateParts = parts[0].split('-');
                        String[] timeParts = parts[1].split(':');
                        if (dateParts.size() == 3 && timeParts.size() >= 2) {
                            Integer year = Integer.valueOf(dateParts[0]);
                            Integer month = Integer.valueOf(dateParts[1]);
                            Integer day = Integer.valueOf(dateParts[2]);
                            Integer hour = Integer.valueOf(timeParts[0]);
                            Integer minute = Integer.valueOf(timeParts[1]);
                            Integer second = timeParts.size() > 2 ? Integer.valueOf(timeParts[2]) : 0;
                            return Datetime.newInstance(year, month, day, hour, minute, second);
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error parsing ISO datetime: ' + s + ' - ' + e.getMessage());
                }
            }
            String timePart = s.length() == 5 ? s + ':00' : (s.length() == 8 ? s : s + ':00');
            String combined = dateStr + ' ' + timePart;
            try {
                return Datetime.valueOf(combined);
            } catch (Exception e2) {
                System.debug('Error parsing datetime: ' + combined + ' - ' + e2.getMessage());
                return null;
            }
        }
        return null;
    }

    public class ExistingSessionDivision {
        @AuraEnabled public String divisionId { get; set; }
        @AuraEnabled public String divisionName { get; set; }
        @AuraEnabled public String programName { get; set; }
        @AuraEnabled public String batchName { get; set; }
        @AuraEnabled public String batchGroupName { get; set; }
        @AuraEnabled public String termName { get; set; }
    }

    private static void validateInput(SessionInput request) {
        String normalizedName = getSessionName(request);
        if (String.isBlank(normalizedName)) {
            throw new AuraHandledException('Session Name is required.');
        }
        if (request.sessionDate == null) {
            throw new AuraHandledException('Session Date is required.');
        }
        if (request.startTime == null || request.endTime == null) {
            throw new AuraHandledException('Start Time and End Time are required.');
        }
        if (request.endTime.getTime() <= request.startTime.getTime()) {
            throw new AuraHandledException('End Time must be after Start Time.');
        }
        if (request.selectedFacultyIds == null || request.selectedFacultyIds.isEmpty()) {
            throw new AuraHandledException('Faculty is required.');
        }
        Boolean hasLead = (request.leadFacultyIds != null && !request.leadFacultyIds.isEmpty())
            || String.isNotBlank(request.leadFacultyId);
        if (!hasLead) {
            throw new AuraHandledException('At least one Faculty (lead) is required. Support faculty alone is not enough.');
        }
        Set<String> selectedSet = new Set<String>();
        for (String fid : request.selectedFacultyIds) {
            if (String.isNotBlank(fid)) selectedSet.add(fid.trim());
        }
        Set<String> leadSet = new Set<String>();
        if (request.leadFacultyIds != null) {
            for (String s : request.leadFacultyIds) {
                if (String.isNotBlank(s)) leadSet.add(s.trim());
            }
        }
        if (String.isNotBlank(request.leadFacultyId)) leadSet.add(request.leadFacultyId.trim());
        Boolean atLeastOneLeadInSelected = false;
        for (String leadId : leadSet) {
            if (selectedSet.contains(leadId)) {
                atLeastOneLeadInSelected = true;
                break;
            }
        }
        if (!atLeastOneLeadInSelected && !leadSet.isEmpty()) {
            throw new AuraHandledException('At least one selected faculty must be Faculty (lead). Support faculty alone is not enough.');
        }
        if (isInvalidClassRoomOrRemark(request.classRoom)) {
            throw new AuraHandledException('Negative values and values starting with \'-\' are not allowed.');
        }
        if (isInvalidClassRoomOrRemark(request.remark)) {
            throw new AuraHandledException('Negative values and values starting with \'-\' are not allowed.');
        }
    }

    private static Boolean isInvalidClassRoomOrRemark(String val) {
        if (String.isBlank(val)) return false;
        String trimmed = val.trim();
        if (trimmed.startsWith('-')) return true;
        try {
            Decimal d = Decimal.valueOf(trimmed);
            return d < 0;
        } catch (Exception e) {
            return false;
        }
    }

    private static String formatDateForQuery(Date dateValue) {
        if (dateValue == null) {
            return null;
        }
        String year = String.valueOf(dateValue.year());
        String month = String.valueOf(dateValue.month());
        String day = String.valueOf(dateValue.day());
        if (month.length() == 1) month = '0' + month;
        if (day.length() == 1) day = '0' + day;
        return year + '-' + month + '-' + day;
    }

    private static String formatTimeForClient(Datetime dateTimeValue) {
        return dateTimeValue == null ? null : dateTimeValue.format('HH:mm');
    }

    private static String getSessionName(SessionInput request) {
        if (request == null) {
            return null;
        }
        if (!String.isBlank(request.sessionName)) {
            return request.sessionName;
        }
        return request.name;
    }

    private static SessionFilter parseFilter(String filterJson) {
        if (String.isBlank(filterJson)) {
            return new SessionFilter();
        }
        try {
            Map<String, Object> filterMap = (Map<String, Object>) JSON.deserializeUntyped(filterJson);
            SessionFilter filter = new SessionFilter();

            if (filterMap.containsKey('programId')) filter.programId = (Id) filterMap.get('programId');
            if (filterMap.containsKey('batchId')) filter.batchId = (Id) filterMap.get('batchId');
            if (filterMap.containsKey('batchGroupId')) filter.batchGroupId = (Id) filterMap.get('batchGroupId');
            if (filterMap.containsKey('termId')) filter.termId = (Id) filterMap.get('termId');
            if (filterMap.containsKey('divisionId')) filter.divisionId = (String) filterMap.get('divisionId');
            if (filterMap.containsKey('courseId')) filter.courseId = (String) filterMap.get('courseId');
            if (filterMap.containsKey('batchWiseCourseId')) filter.batchWiseCourseId = (String) filterMap.get('batchWiseCourseId');

            if (filterMap.containsKey('divisionIds')) {
                Object divisionIdsObj = filterMap.get('divisionIds');
                if (divisionIdsObj != null && divisionIdsObj instanceof List<Object>) {
                    List<String> divisionIdsList = new List<String>();
                    for (Object item : (List<Object>) divisionIdsObj) {
                        if (item != null) {
                            divisionIdsList.add(String.valueOf(item));
                        }
                    }
                    filter.divisionIds = divisionIdsList;
                }
            }

            if (filterMap.containsKey('facultyIds')) {
                Object facultyIdsObj = filterMap.get('facultyIds');
                if (facultyIdsObj != null && facultyIdsObj instanceof List<Object>) {
                    List<String> facultyIdsList = new List<String>();
                    for (Object item : (List<Object>) facultyIdsObj) {
                        if (item != null) {
                            facultyIdsList.add(String.valueOf(item));
                        }
                    }
                    filter.facultyIds = facultyIdsList;
                }
            }
            if (filterMap.containsKey('scheduleTypes')) {
                Object scheduleTypesObj = filterMap.get('scheduleTypes');
                if (scheduleTypesObj != null && scheduleTypesObj instanceof List<Object>) {
                    List<String> scheduleTypesList = new List<String>();
                    for (Object item : (List<Object>) scheduleTypesObj) {
                        if (item != null && String.isNotBlank(String.valueOf(item))) {
                            scheduleTypesList.add(String.valueOf(item));
                        }
                    }
                    if (!scheduleTypesList.isEmpty()) {
                        filter.scheduleTypes = scheduleTypesList;
                    }
                }
            }

            if (filterMap.containsKey('startDate')) {
                Object startDateObj = filterMap.get('startDate');
                if (startDateObj != null) {
                    if (startDateObj instanceof String) {
                        String dateStr = (String) startDateObj;
                        try {
                            filter.startDate = Date.valueOf(dateStr);
                        } catch (Exception e) {
                            System.debug('Error parsing startDate: ' + dateStr + ' - ' + e.getMessage());
                        }
                    } else if (startDateObj instanceof Date) {
                        filter.startDate = (Date) startDateObj;
                    }
                    if (filter.startDate != null) {
                        filter.startDate = normalizeDate(filter.startDate);
                    }
                }
            }

            if (filterMap.containsKey('endDate')) {
                Object endDateObj = filterMap.get('endDate');
                if (endDateObj != null) {
                    if (endDateObj instanceof String) {
                        String dateStr = (String) endDateObj;
                        try {
                            filter.endDate = Date.valueOf(dateStr);
                        } catch (Exception e) {
                            System.debug('Error parsing endDate: ' + dateStr + ' - ' + e.getMessage());
                        }
                    } else if (endDateObj instanceof Date) {
                        filter.endDate = (Date) endDateObj;
                    }
                    if (filter.endDate != null) {
                        filter.endDate = normalizeDate(filter.endDate);
                    }
                }
            }

            if (filterMap.containsKey('sendNotifications')) {
                Object sendNotificationsObj = filterMap.get('sendNotifications');
                if (sendNotificationsObj instanceof Boolean) {
                    filter.sendNotifications = (Boolean) sendNotificationsObj;
                }
            }

            return filter;
        } catch (Exception ex) {
            System.debug('Error parsing filter: ' + filterJson + ' - ' + ex.getMessage());
            throw new AuraHandledException('Unable to parse filter criteria. ' + ex.getMessage());
        }
    }

    private static Date normalizeDate(Date inputDate) {
        if (inputDate == null) {
            return null;
        }
        return Date.newInstance(inputDate.year(), inputDate.month(), inputDate.day());
    }

    private static Boolean sessionInfoFieldsExist() {
        return Schema.SObjectType.Session__c.fields.getMap().containsKey('Program__c')
            && Schema.SObjectType.Session__c.fields.getMap().containsKey('Academic_Year__c')
            && Schema.SObjectType.Session__c.fields.getMap().containsKey('Term__c');
    }

    private static List<String> getSessionInfoFieldApiNames() {
        List<String> out = new List<String>();
        Map<String, Schema.SObjectField> fmap = Schema.SObjectType.Session__c.fields.getMap();
        List<String> localNames = new List<String>{ 'Program__c', 'Academic_Year__c', 'Term__c' };
        for (String local : localNames) {
            for (String key : fmap.keySet()) {
                if (fmap.get(key).getDescribe().getLocalName() == local) {
                    out.add(key);
                    break;
                }
            }
        }
        return out;
    }

    private static Map<String, String> getSessionInfoFieldApiNameMap() {
        Map<String, String> out = new Map<String, String>();
        Map<String, Schema.SObjectField> fmap = Schema.SObjectType.Session__c.fields.getMap();
        List<String> localNames = new List<String>{ 'Program__c', 'Batch__c', 'Academic_Year__c', 'Term__c' };
        for (String local : localNames) {
            for (String key : fmap.keySet()) {
                if (fmap.get(key).getDescribe().getLocalName() == local) {
                    out.put(local, key);
                    break;
                }
            }
        }
        return out;
    }

    private static SessionInput parseSessionInput(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new AuraHandledException('Session input is required.');
        }
        try {
            return (SessionInput) JSON.deserialize(requestJson, SessionInput.class);
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to parse session payload. ' + ex.getMessage());
        }
    }

    private static Id resolveLookupId(String candidateValue, String objectApiName) {
        if (String.isBlank(candidateValue) || String.isBlank(objectApiName)) {
            return null;
        }
        Id directId = tryConvertToId(candidateValue);
        if (directId != null) {
            return directId;
        }
        String query = 'SELECT Id FROM ' + objectApiName + ' WHERE Name = \'' +
            String.escapeSingleQuotes(candidateValue) + '\' LIMIT 1';
        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            return null;
        }
        return (Id) records[0].get('Id');
    }

    private static Id tryConvertToId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Id resolveDivisionIdForQuery(String divisionId) {
        if (String.isBlank(divisionId)) {
            return null;
        }
        try {
            return Id.valueOf(divisionId);
        } catch (Exception e) {
            List<Division__c> divs = [SELECT Id FROM Division__c WHERE Name = :divisionId LIMIT 1];
            return divs.isEmpty() ? null : divs[0].Id;
        }
    }

    private static String getLookupObjectApiName(String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            return null;
        }
        Schema.SObjectType sessionType = Schema.getGlobalDescribe().get('Session__c');
        if (sessionType == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = sessionType.getDescribe().fields.getMap();
        Schema.SObjectField field = fieldMap.get(fieldApiName);
        if (field == null) {
            return null;
        }
        List<Schema.SObjectType> references = field.getDescribe().getReferenceTo();
        if (references.isEmpty()) {
            return null;
        }
        return references[0].getDescribe().getName();
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getCourseActivities() {
        List<PicklistOption> options = new List<PicklistOption>();
        try {
            Schema.DescribeFieldResult d = Session__c.Course_Activity__c.getDescribe();
            for (Schema.PicklistEntry entry : d.getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                }
            }
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load Course Activity picklist values: ' + ex.getMessage());
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
public static List<Map<String, String>> getSessionTypes() {
    List<Map<String, String>> options = new List<Map<String, String>>();

    Schema.DescribeFieldResult fieldResult =
        Session__c.Session_Type__c.getDescribe();

    List<Schema.PicklistEntry> picklistValues =
        fieldResult.getPicklistValues();

    for (Schema.PicklistEntry entry : picklistValues) {
        options.add(new Map<String, String>{
            'label' => entry.getLabel(),
            'value' => entry.getValue()
        });
    }

    return options;
}

    @AuraEnabled(cacheable=false)
    public static List<String> getSessionFaculties(Id sessionId) {
        List<String> facultyIds = new List<String>();

        if (sessionId == null) {
            return facultyIds;
        }

        try {
            List<Session_Faculty__c> sessionFaculties = [
                SELECT Session_Faculty__c
                FROM Session_Faculty__c
                WHERE Session__c = :sessionId
                AND Session_Faculty__c != null
            ];

            for (Session_Faculty__c sf : sessionFaculties) {
                facultyIds.add(sf.Session_Faculty__c);
            }
        } catch (Exception ex) {
            System.debug('Error fetching session faculties: ' + ex.getMessage());
            throw new AuraHandledException('Unable to load session faculties: ' + ex.getMessage());
        }

        return facultyIds;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFacultyForCourse(String courseId, String divisionId) {
        List<PicklistOption> options = new List<PicklistOption>();

        if (String.isBlank(courseId)) {
            return options;
        }

        try {
            Id courseLookupId = null;
            if (courseId.contains('|')) {
                String[] parts = courseId.split('\\|');
                if (parts.size() > 1 && String.isNotBlank(parts[1])) {
                    try {
                        courseLookupId = Id.valueOf(parts[1]);
                    } catch (Exception e) {
                        System.debug('Error parsing LearningCourseId: ' + e.getMessage());
                        return options;
                    }
                }
            } else {
                courseLookupId = resolveLookupId(courseId, 'LearningCourse');
            }

            if (courseLookupId == null) {
                return options;
            }

            Set<Id> programCourseIds = new Set<Id>();
            Id divisionResolvedId = resolveDivisionIdForQuery(divisionId);

            if (divisionResolvedId != null) {
                for (DivisionCourse__c dc : [
                    SELECT Course_Offering__r.ProgramCourse__c
                    FROM DivisionCourse__c
                    WHERE Division__c = :divisionResolvedId
                    AND Course_Offering__r.LearningCourseId = :courseLookupId
                    AND Course_Offering__r.ProgramCourse__c != null
                ]) {
                    if (dc.Course_Offering__r != null && dc.Course_Offering__r.ProgramCourse__c != null) {
                        programCourseIds.add(dc.Course_Offering__r.ProgramCourse__c);
                    }
                }
            } else {
                for (Program_Courses__c pc : [
                    SELECT Id
                    FROM Program_Courses__c
                    WHERE Learning_Course__c = :courseLookupId
                ]) {
                    programCourseIds.add(pc.Id);
                }
            }

            if (programCourseIds.isEmpty()) {
                return options;
            }

            Set<Id> facultyIds = new Set<Id>();
            for (Instructor__c row : [
                SELECT Account__c, Account__r.Name
                FROM Instructor__c
                WHERE Program_Course__c IN :programCourseIds
                AND Account__c != null
                ORDER BY Account__r.Name
            ]) {
                if (row.Account__c != null && !facultyIds.contains(row.Account__c)) {
                    facultyIds.add(row.Account__c);
                    options.add(new PicklistOption(row.Account__r.Name, row.Account__c));
                }
            }
        } catch (Exception ex) {
            System.debug('Error fetching faculty for course: ' + ex.getMessage());
            throw new AuraHandledException('Unable to load faculty: ' + ex.getMessage());
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getFacultiesForFilter(String divisionId, List<String> divisionIds) {
        List<PicklistOption> options = new List<PicklistOption>();
        Set<Id> divisionIdSet = new Set<Id>();

        if (divisionIds != null && !divisionIds.isEmpty()) {
            for (String rawId : divisionIds) {
                if (String.isNotBlank(rawId)) {
                    try {
                        divisionIdSet.add(Id.valueOf(rawId));
                    } catch (Exception ignore) {}
                }
            }
        }
        if (divisionIdSet.isEmpty() && String.isNotBlank(divisionId)) {
            try {
                divisionIdSet.add(Id.valueOf(divisionId));
            } catch (Exception e) {
                List<Division__c> divs = [SELECT Id FROM Division__c WHERE Name = :divisionId LIMIT 1];
                if (!divs.isEmpty()) divisionIdSet.add(divs[0].Id);
            }
        }

        if (divisionIdSet.isEmpty()) {
            return options;
        }

        try {
            List<DivisionCourse__c> divisionCourses = [
                SELECT Id, Course_Offering__r.ProgramCourse__c
                FROM DivisionCourse__c
                WHERE Division__c IN :divisionIdSet
                AND Course_Offering__r.ProgramCourse__c != null
            ];
            Set<Id> programCourseIds = new Set<Id>();
            for (DivisionCourse__c dc : divisionCourses) {
                if (dc.Course_Offering__r != null && dc.Course_Offering__r.ProgramCourse__c != null) {
                    programCourseIds.add(dc.Course_Offering__r.ProgramCourse__c);
                }
            }
            if (programCourseIds.isEmpty()) {
                return options;
            }

            Set<Id> facultyIds = new Set<Id>();
            for (Instructor__c row : [
                SELECT Account__c, Account__r.Name
                FROM Instructor__c
                WHERE Program_Course__c IN :programCourseIds
                AND Account__c != null
                ORDER BY Account__r.Name
            ]) {
                if (row.Account__c != null && !facultyIds.contains(row.Account__c)) {
                    facultyIds.add(row.Account__c);
                    options.add(new PicklistOption(row.Account__r.Name, row.Account__c));
                }
            }
        } catch (Exception ex) {
            System.debug('Error fetching faculties for filter: ' + ex.getMessage());
            throw new AuraHandledException('Unable to load faculties: ' + ex.getMessage());
        }
        return options;
    }

    private static void applySessionColorFromDivision(
        SessionInput request,
        Session__c sessionRecord,
        Id divisionLookupId,
        List<Id> divisionIdsToProcess
    ) {
        Id colorDivId = resolveColorSourceDivisionId(request, divisionLookupId, divisionIdsToProcess);
        if (colorDivId != null) {
            List<Division__c> divRows = [
                SELECT Division_Color__c
                FROM Division__c
                WHERE Id = :colorDivId
                LIMIT 1
            ];
            if (!divRows.isEmpty()) {
                String hex = divisionPicklistToDisplayHex(
                    divRows[0].Division_Color__c != null ? String.valueOf(divRows[0].Division_Color__c) : null
                );
                hex = toSessionColorPicklistValue(hex);
                if (String.isNotBlank(hex)) {
                    sessionRecord.Color__c = hex;
                    return;
                }
            }
        }
        if (request != null && String.isNotBlank(request.color) && request.color.trim().startsWith('#')) {
            sessionRecord.Color__c = toSessionColorPicklistValue(request.color.trim());
        } else if (String.isBlank(sessionRecord.Color__c) && request != null && String.isNotBlank(request.color)) {
            sessionRecord.Color__c = toSessionColorPicklistValue(request.color.trim());
        }
        if (String.isBlank(sessionRecord.Color__c)) {
            sessionRecord.Color__c = '#406EA8';
        } else {
            sessionRecord.Color__c = toSessionColorPicklistValue(sessionRecord.Color__c);
        }
    }

    private static String toSessionColorPicklistValue(String hexOrToken) {
        if (String.isBlank(hexOrToken)) {
            return hexOrToken;
        }
        String raw = hexOrToken.trim();
        String upper = raw.toUpperCase();
        if (upper == '#BF4E4E') {
            return '#B44E4E';
        }
        if (upper == '#AAAFAA') {
            return '#AAAFaa';
        }
        if (raw.startsWith('#') && raw.length() == 7) {
            for (String v : divisionColorHexByKey().values()) {
                if (v != null && v.equalsIgnoreCase(raw)) {
                    return v;
                }
            }
            return upper == '#AAAFAA' ? '#AAAFaa' : upper;
        }
        String fromToken = divisionPicklistToDisplayHex(raw);
        return String.isNotBlank(fromToken) ? toSessionColorPicklistValue(fromToken) : raw;
    }

    private static Id resolveColorSourceDivisionId(SessionInput request, Id divisionLookupId, List<Id> divisionIdsToProcess) {
        if (request != null && String.isNotBlank(request.colorSourceDivisionId)) {
            try {
                return Id.valueOf(request.colorSourceDivisionId.trim());
            } catch (Exception e) {
            }
        }
        if (divisionLookupId != null) {
            return divisionLookupId;
        }
        if (divisionIdsToProcess != null && !divisionIdsToProcess.isEmpty()) {
            return divisionIdsToProcess[0];
        }
        return null;
    }

    private static String normalizePicklistColorKey(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        String lower = s.toLowerCase();
        String out = '';
        for (Integer i = 0; i < lower.length(); i++) {
            String ch = lower.substring(i, i + 1);
            if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) {
                out += ch;
            }
        }
        return out;
    }

    private static String divisionPicklistToDisplayHex(String picklistVal) {
        if (String.isBlank(picklistVal)) {
            return null;
        }
        String k = normalizePicklistColorKey(picklistVal);
        Map<String, String> m = divisionColorHexByKey();
        return m.containsKey(k) ? m.get(k) : null;
    }

    private static Map<String, String> divisionColorHexByKey() {
        return new Map<String, String>{
            'softpeachbeige' => '#FAE3D6',
            'lightsagegreen' => '#9EB094',
            'mutedbrown' => '#B58460',
            'brickred' => '#B44E4E',
            'mustardyellow' => '#C99500',
            'teal' => '#54B1AC',
            'paleolive' => '#B2B28D',
            'steelblue' => '#406EA8',
            'lightgray' => '#AAAFAA',
            'limeyellow' => '#C0C600',
            'darkmaroon' => '#7A3000',
            'purple' => '#702B99',
            'blue' => '#406EA8',
            'gray' => '#AAAFAA',
            'grey' => '#AAAFAA',
            'green' => '#9EB094',
            'orange' => '#C99500',
            'red' => '#B44E4E'

        };
    }

    public class SaveSessionResult {
        @AuraEnabled public Id sessionId { get; set; }
        @AuraEnabled public String warningMessage { get; set; }
        @AuraEnabled public List<SessionConflictValidator.StudentSessionConflictDetail> warningDetails { get; set; }
        public SaveSessionResult(Id sessionId, String warningMessage, List<SessionConflictValidator.StudentSessionConflictDetail> warningDetails) {
            this.sessionId = sessionId;
            this.warningMessage = warningMessage;
            this.warningDetails = warningDetails;
        }
    }

    @TestVisible
    private static Integer exercisePrivateHelpersForTests(Id sampleDivisionId, Id sampleSessionId) {
        Integer hit = 0;
        buildSessionStudentName('Title', 'First', 'Last'); hit++;
        buildSessionStudentName('', 'First', ''); hit++;
        buildSessionStudentName('T', '', ''); hit++;
        buildSessionStudentName('', '', ''); hit++;
        buildSessionStudentName(
            'VeryLongTitleThatShouldEventuallyGetTruncatedWhenCombinedWithStudentNameXXXXXXXXXXXX',
            'VeryLongFirstNameXXXX',
            'VeryLongLastNameXXXX'
        ); hit++;

        Session__c existing = new Session__c(
            Session_Date__c = Date.today(),
            Start_Time__c = Datetime.now(),
            End_Time__c = Datetime.now().addHours(1)
        );
        SessionInput req = new SessionInput();
        req.sessionDate = Date.today().addDays(1);
        req.startTime = Datetime.now().addDays(1);
        req.endTime = Datetime.now().addDays(1).addHours(1);
        dateOrTimeChanged(existing, req); hit++;
        dateOrTimeChanged(null, req); hit++;
        dateOrTimeChanged(existing, null); hit++;
        req.sessionDate = existing.Session_Date__c;
        req.startTime = existing.Start_Time__c;
        req.endTime = existing.End_Time__c;
        dateOrTimeChanged(existing, req); hit++;

        isInvalidClassRoomOrRemark(null); hit++;
        isInvalidClassRoomOrRemark('-1'); hit++;
        isInvalidClassRoomOrRemark('Room A'); hit++;
        isInvalidClassRoomOrRemark('abc'); hit++;

        SessionInput nameReq = new SessionInput();
        nameReq.sessionName = 'Primary';
        getSessionName(nameReq); hit++;
        nameReq.sessionName = null;
        nameReq.name = 'Fallback';
        getSessionName(nameReq); hit++;

        formatDateForQuery(Date.today()); hit++;
        formatDateForQuery(null); hit++;
        formatTimeForClient(Datetime.now()); hit++;
        normalizeDate(Date.today()); hit++;
        normalizeDate(null); hit++;

        parseDateFromString(null); hit++;
        parseDateFromString('2026-02-03T00:00:00.000Z'); hit++;
        parseDateFromString('not-a-date'); hit++;
        parseDateTimeFromInput('2026-02-03', '2026-02-03T09:00:00.000Z'); hit++;
        parseDateTimeFromInput('2026-02-03', '09:00'); hit++;
        parseDateTimeFromInput('2026-02-03', '09:00:00'); hit++;
        parseDateTimeFromInput(null, '09:00'); hit++;

        extractStringListFromJson(null); hit++;
        extractStringListFromJson(new List<Object>{ 'a', 1 }); hit++;
        extractStringListFromJson(new List<String>{ 'x' }); hit++;
        serializeProposedContextFromJsonMap(null); hit++;
        serializeProposedContextFromJsonMap(new Map<String, Object>()); hit++;
        serializeProposedContextFromJsonMap(
            new Map<String, Object>{ 'proposedContext' => new Map<String, Object>{ 'courseName' => 'C' } }
        ); hit++;

        for (String k : new List<String>{
            'Steel Blue', 'soft peach beige', 'teal', 'Brick Red', 'xyz', '', null
        }) {
            divisionPicklistToDisplayHex(k);
            normalizePicklistColorKey(k);
            hit++;
        }
        hit += divisionColorHexByKey().size();

        SessionInput colorReq = new SessionInput();
        colorReq.color = '#ABCDEF';
        colorReq.colorSourceDivisionId = sampleDivisionId != null ? String.valueOf(sampleDivisionId) : null;
        applySessionColorFromDivision(
            colorReq,
            new Session__c(),
            sampleDivisionId,
            sampleDivisionId != null ? new List<Id>{ sampleDivisionId } : new List<Id>()
        ); hit++;
        SessionInput colorReq2 = new SessionInput();
        colorReq2.color = 'named-color';
        applySessionColorFromDivision(colorReq2, new Session__c(), null, new List<Id>()); hit++;

        tryConvertToId(null); hit++;
        tryConvertToId('not-an-id'); hit++;
        if (sampleDivisionId != null) {
            tryConvertToId(String.valueOf(sampleDivisionId)); hit++;
            resolveDivisionIdForQuery(String.valueOf(sampleDivisionId)); hit++;
            resolveDivisionIdForQuery('NotAnId'); hit++;
        }
        resolveLookupId(null, 'Account'); hit++;
        resolveLookupId('NoSuchNameXYZ999', 'User'); hit++;
        getLookupObjectApiName('Course__c'); hit++;
        getLookupObjectApiName('OwnerId'); hit++;
        sessionInfoFieldsExist(); hit++;
        getSessionInfoFieldApiNames(); hit++;
        getSessionInfoFieldApiNameMap(); hit++;

        parseFilter(null); hit++;
        parseFilter('{"startDate":"2026-01-01","endDate":"2026-12-31","divisionIds":["x"],"facultyIds":["y"],"scheduleTypes":["Draft","Published"]}'); hit++;

        if (sampleSessionId != null) {
            refreshAttendees(sampleSessionId); hit++;
            refreshAttendees(null); hit++;
        }
        return hit;
    }
}