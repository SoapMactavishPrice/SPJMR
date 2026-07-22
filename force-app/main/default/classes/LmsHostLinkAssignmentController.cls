/**
 * LMS host link quick action. Attendee range comes from the {@code ProgramCohort} record, or
 * from the LWC when the client sends all three context values. Eligible hosts use
 * {@code Program_Courses__c.Batch__r} ({@link ProgramCohort}) with a date range that
 * overlaps the attendee batch range.
 */
public with sharing class LmsHostLinkAssignmentController {
    /**
     * @param batchId        Current batch ({@link ProgramCohort}) from the quick action
     * @param batchName      Optional; if blank, loaded from org when the LWC does not send a full set
     * @param rangeStartStr  Optional YYYY-MM-DD
     * @param rangeEndStr    Optional YYYY-MM-DD
     */
    @AuraEnabled
    public static LmsPageData getPageData(
        Id batchId,
        String batchName,
        String rangeStartStr,
        String rangeEndStr
    ) {
        if (batchId == null) {
            throw new AuraHandledException('Batch is required');
        }
        LmsPageData page = new LmsPageData();
        AttendeeContext ctx = new AttendeeContext();
        ctx.batchId = batchId;
        ctx.batchName = batchName;
        DateRange attRange = new DateRange();

        Boolean lwcGaveContext =
            String.isNotBlank(rangeStartStr) && String.isNotBlank(rangeEndStr) && String.isNotBlank(batchName);
        if (lwcGaveContext) {
            attRange.startDate = safeParseDate(rangeStartStr);
            attRange.endDate = safeParseDate(rangeEndStr);
        } else {
            List<ProgramCohort> batches = [
                SELECT Name, StartDate, EndDate, Batch_Start_Date__c
                FROM ProgramCohort
                WHERE Id = :batchId
                LIMIT 1
            ];
            if (!batches.isEmpty()) {
                ProgramCohort b = batches[0];
                if (String.isBlank(ctx.batchName) && b.Name != null) {
                    ctx.batchName = b.Name;
                }
                attRange = buildDateRangeFromProgramCohort(b);
            }
        }

        ctx.rangeStart = attRange.startDate;
        ctx.rangeEnd = attRange.endDate;
        page.context = ctx;
        page.attendeeSections = buildAttendeeSections(batchId, attRange);
        return page;
    }

    @AuraEnabled
    public static void saveLmsHostLinks(List<LmsLinkInput> links) {
        if (links == null || links.isEmpty()) {
            return;
        }
        Map<Id, Id> hostByAttendee = new Map<Id, Id>();
        for (LmsLinkInput l : links) {
            if (l == null || l.attendeeProgramCourseId == null || l.hostProgramCourseId == null) {
                continue;
            }
            hostByAttendee.put(l.attendeeProgramCourseId, l.hostProgramCourseId);
        }
        if (hostByAttendee.isEmpty()) {
            return;
        }
        List<Program_Courses__c> toUp = new List<Program_Courses__c>();
        for (Id attId : hostByAttendee.keySet()) {
            toUp.add(
                new Program_Courses__c(Id = attId, LMS_Course__c = hostByAttendee.get(attId))
            );
        }
        update toUp;
    }
    /*SE-887*/
    /**
     * Search for Programme Courses to populate LMS Course lookup.
     * Returns host Programme Courses that can be linked.
     * 
     * @param searchTerm  Search string (can be empty to return all)
     * @param selectedIds Optional list of already selected IDs to include
     * @return List of Programme Course records for lookup
     */
    @AuraEnabled(cacheable=true)
    public static List<LookupSearchResult> searchProgrammeCourses(String searchTerm, List<String> selectedIds) {
        List<LookupSearchResult> results = new List<LookupSearchResult>();
        
        // Build search pattern
        String searchPattern = String.isBlank(searchTerm) ? '%' : '%' + searchTerm + '%';
        
        // Query host Programme Courses
        List<Program_Courses__c> courses = [
            SELECT 
                Id, 
                Name, 
                Program_Course_Code__c,
                Batch__r.Name,
                Batch__r.Program.Name,
                Batch__r.Program.Program_Code__c,
                Learning_Course__r.Name,
                Learning_Course__r.CourseNumber
            FROM Program_Courses__c
            WHERE 
                Is_Host_Course__c = TRUE
                AND (
                    Name LIKE :searchPattern
                    OR Program_Course_Code__c LIKE :searchPattern
                    OR Batch__r.Name LIKE :searchPattern
                    OR Batch__r.Program.Name LIKE :searchPattern
                    OR Learning_Course__r.Name LIKE :searchPattern
                )
            ORDER BY Name
            LIMIT 50
        ];
        
        // Convert to lookup results
        for (Program_Courses__c pc : courses) {
            LookupSearchResult result = new LookupSearchResult();
            result.id = pc.Id;
            result.title = pc.Name;
            result.subtitle = buildLookupSubtitle(pc);
            result.icon = 'standard:program';
            results.add(result);
        }
        
        return results;
    }

    /**
     * Build subtitle for lookup display showing batch and programme info
     */
    private static String buildLookupSubtitle(Program_Courses__c pc) {
        List<String> parts = new List<String>();
        
        if (pc.Program_Course_Code__c != null) {
            parts.add(pc.Program_Course_Code__c);
        }
        
        if (pc.Batch__r != null && pc.Batch__r.Name != null) {
            parts.add('Batch: ' + pc.Batch__r.Name);
        }
        
        if (pc.Batch__r != null && pc.Batch__r.Program != null && pc.Batch__r.Program.Name != null) {
            parts.add('Program: ' + pc.Batch__r.Program.Name);
        }
        
        if (pc.Learning_Course__r != null && pc.Learning_Course__r.Name != null) {
            parts.add('Course: ' + pc.Learning_Course__r.Name);
        }
        
        return String.join(parts, ' • ');
    }

    /**
     * Lookup result wrapper for custom lookup component
     */
    public class LookupSearchResult {
        @AuraEnabled public String id {get; set;}
        @AuraEnabled public String title {get; set;}
        @AuraEnabled public String subtitle {get; set;}
        @AuraEnabled public String icon {get; set;}
    }
    /*SE-887 ends here*/
    private static Date safeParseDate(String ymd) {
        if (String.isBlank(ymd) || ymd.length() < 8) {
            return null;
        }
        try {
            return Date.valueOf(ymd);
        } catch (Exception e) {
            return null;
        }
    }

    private static List<AttendeeHostSection> buildAttendeeSections(Id batchId, DateRange attRange) {
        List<AttendeeHostSection> out = new List<AttendeeHostSection>();
        List<Program_Courses__c> attendees = [
            SELECT Id, Name, Learning_Course__c, Learning_Course__r.Name, Learning_Course__r.CourseNumber,LMS_Course__c
            FROM Program_Courses__c
            WHERE
                Batch__c = :batchId
                AND (Is_Host_Course__c = FALSE OR Is_Host_Course__c = NULL)
        ];
        if (attendees.isEmpty()) {
            return out;
        }

        Set<Id> learningIds = new Set<Id>();
        for (Program_Courses__c p : attendees) {
            if (p.Learning_Course__c != null) {
                learningIds.add(p.Learning_Course__c);
            }
        }

        Map<Id, List<Program_Courses__c>> hostByLearning = new Map<Id, List<Program_Courses__c>>();
        if (!learningIds.isEmpty()) {
            List<Program_Courses__c> hostCandidates = [
                SELECT
                    Id,
                    Name,
                    Program_Course_Code__c,
                    Learning_Course__c,
                    Batch__c,
                    Batch__r.Name,
                    Batch__r.ProgramId,
                    Batch__r.Program.Name,
                    Batch__r.Program.Program_Code__c,
                    Batch__r.StartDate,
                    Batch__r.EndDate,
                    Batch__r.Batch_Start_Date__c
                FROM Program_Courses__c
                WHERE
                    Is_Host_Course__c = TRUE
                    AND Batch__c != :batchId
                    AND Learning_Course__c IN :learningIds
            ];
            for (Program_Courses__c h : hostCandidates) {
                if (h.Learning_Course__c == null) {
                    continue;
                }
                ProgramCohort hostBatch = h.Batch__r;
                if (!hostBatchDateOverlapsAttendee(hostBatch, attRange)) {
                    continue;
                }
                if (!hostByLearning.containsKey(h.Learning_Course__c)) {
                    hostByLearning.put(h.Learning_Course__c, new List<Program_Courses__c>());
                }
                hostByLearning.get(h.Learning_Course__c).add(h);
            }
        }

        for (Program_Courses__c attPc : attendees) {
            AttendeeHostSection sec = new AttendeeHostSection();
            sec.sectionKey = String.valueOf(attPc.Id);
            sec.attendeeProgramCourseId = attPc.Id;
            sec.attendeeProgramCourseName = attPc.Name;
            if (attPc.Learning_Course__r != null) {
                sec.learningCourseName = attPc.Learning_Course__r.Name;
                sec.courseNumber = attPc.Learning_Course__r.CourseNumber;
            } else {
                sec.learningCourseName = '';
                sec.courseNumber = null;
            }
            sec.hasLearningCourse = attPc.Learning_Course__c != null;
            sec.accordionLabel = buildAccordionLabel(attPc);
            List<HostLinkOption> options = new List<HostLinkOption>();
            if (attPc.Learning_Course__c != null) {
                List<Program_Courses__c> hosts = hostByLearning.get(attPc.Learning_Course__c);
                if (hosts != null) {
                    for (Program_Courses__c hostPc : hosts) {
                        HostLinkOption opt = new HostLinkOption();
                        opt.rowKey = String.valueOf(attPc.Id) + '-' + String.valueOf(hostPc.Id);
                        opt.hostProgramCourseId = hostPc.Id;
                        opt.hostProgramCourseName = hostPc.Name;
                        opt.hostProgramCourseCode = hostPc.Program_Course_Code__c;
                        opt.hostBatchId = hostPc.Batch__c;
                        opt.isSelected = (attPc.LMS_Course__c == hostPc.Id);
                        if (hostPc.Batch__r != null) {
                            opt.hostBatchName = hostPc.Batch__r.Name;
                            opt.hostProgramCode = programCodeFromBatch(hostPc.Batch__r);
                            if (hostPc.Batch__r.Program != null) {
                                opt.hostProgramName = hostPc.Batch__r.Program.Name;
                            }
                        } else {
                            opt.hostBatchName = '';
                            opt.hostProgramCode = null;
                        }
                        options.add(opt);
                    }
                }
            }
            sec.hostOptions = options;
            out.add(sec);
        }
        return out;
    }

    /**
     * {@code Program.Program_Code__c} for the host batch (master–detail to Program).
     *
     * @param b Host {@code ProgramCohort} with {@code Program.Program_Code__c} queried; may be null.
     * @return Programme / program code, or null if missing.
     */
    private static String programCodeFromBatch(ProgramCohort b) {
        if (b == null || b.Program == null) {
            return null;
        }
        return b.Program.Program_Code__c;
    }

    private static String buildAccordionLabel(Program_Courses__c att) {
        String name = att.Name != null ? att.Name : 'Program course';
        if (att.Learning_Course__r == null) {
            return name + ' · (no learning course set)';
        }
        String num =
            att.Learning_Course__r.CourseNumber != null ? att.Learning_Course__r.CourseNumber + ' — ' : '';
        return name + ' · ' + num + (att.Learning_Course__r.Name != null ? att.Learning_Course__r.Name : '');
    }

    /**
     * Includes host when its batch date window overlaps the attendee range (any shared days).
     * Strict "fully inside" would exclude long host batches that extend past the filter end date.
     */
    private static Boolean hostBatchDateOverlapsAttendee(ProgramCohort hostBatch, DateRange attRange) {
        if (hostBatch == null) {
            return false;
        }
        if (attRange == null) {
            return true;
        }
        if (attRange.startDate == null || attRange.endDate == null) {
            return true;
        }
        DateRange hostRange = buildDateRangeFromProgramCohort(hostBatch);
        if (hostRange.startDate == null || hostRange.endDate == null) {
            return true;
        }
        return hostRange.startDate <= attRange.endDate && hostRange.endDate >= attRange.startDate;
    }

    private class DateRange {
        public Date startDate;
        public Date endDate;
    }

    /**
     * Build an attendee/host date window from a {@code ProgramCohort} row. Prefers
     * {@code Batch_Start_Date__c} for start, then {@code StartDate} (date or time).
     */
    private static DateRange buildDateRangeFromProgramCohort(ProgramCohort b) {
        DateRange d = new DateRange();
        if (b == null) {
            return d;
        }
        if (b.Batch_Start_Date__c != null) {
            d.startDate = b.Batch_Start_Date__c;
        } else {
            d.startDate = toDate(b.StartDate);
        }
        d.endDate = toDate(b.EndDate);
        return d;
    }

    private static Date toDate(Object val) {
        if (val == null) {
            return null;
        }
        if (val instanceof Date) {
            return (Date) val;
        }
        if (val instanceof DateTime) {
            return ((DateTime) val).date();
        }
        return null;
    }

    public class LmsPageData {
        @AuraEnabled public AttendeeContext context {get; set;}
        @AuraEnabled public List<AttendeeHostSection> attendeeSections {get; set;}
    }

    public class AttendeeHostSection {
        @AuraEnabled public String sectionKey {get; set;}
        @AuraEnabled public String accordionLabel {get; set;}
        @AuraEnabled public Id attendeeProgramCourseId {get; set;}
        @AuraEnabled public String attendeeProgramCourseName {get; set;}
        @AuraEnabled public String learningCourseName {get; set;}
        @AuraEnabled public String courseNumber {get; set;}
        @AuraEnabled public Boolean hasLearningCourse {get; set;}
        @AuraEnabled public List<HostLinkOption> hostOptions {get; set;}
    }

    public class HostLinkOption {
        @AuraEnabled public String rowKey {get; set;}
        @AuraEnabled public Id hostProgramCourseId {get; set;}
        @AuraEnabled public String hostProgramName {get; set;}
        @AuraEnabled public String hostProgramCourseName {get; set;}
        @AuraEnabled public String hostProgramCourseCode {get; set;}
        @AuraEnabled public Id hostBatchId {get; set;}
        @AuraEnabled public String hostBatchName {get; set;}
        @AuraEnabled public String hostProgramCode {get; set;}
        @AuraEnabled public Boolean isSelected {get; set;}
    }

    public class AttendeeContext {
        @AuraEnabled public Id batchId {get; set;}
        @AuraEnabled public String batchName {get; set;}
        @AuraEnabled public Date rangeStart {get; set;}
        @AuraEnabled public Date rangeEnd {get; set;}
    }

    public class LmsLinkInput {
        @AuraEnabled public Id attendeeProgramCourseId {get; set;}
        @AuraEnabled public Id hostProgramCourseId {get; set;}
    }
}