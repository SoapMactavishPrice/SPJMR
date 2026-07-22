/**
 * Grants or revokes Manual row-level access for users across a Program and related records in the programme
 * management model (batches, academic structure, campus, sessions, courses, enrollments, team, and other
 * lookups back to Program or to those parents). Runs without sharing so inserts/deletes succeed regardless of
 * the running user’s visibility.
 *
 * <p>Related objects typically use <strong>private</strong> org-wide defaults; this service widens access using
 * <strong>Manual</strong> row cause and <strong>Edit</strong> access level on each parent’s share object when it
 * exists in the org (Education standard objects included).</p>
 *
 * <p>Some object types are capped to avoid governor limits; callers receive {@link AuraHandledException} when
 * a cap is exceeded.</p>
 *
 * @see ProgramHierarchyAccessController
 *
 * <p><strong>Troubleshooting logs:</strong> search debug logs for prefix {@code PHAS}. Logs use
 * {@link LoggingLevel#WARN} so they appear when the running user’s trace flag (or Developer Console) sets
 * <strong>Apex Code</strong> to WARN or finer. LWC calls do not print to Anonymous Apex — open
 * <em>Setup → Debug Logs</em> (or a trace flag on your login) after clicking <strong>Save</strong> on the action.</p>
 */
public without sharing class ProgramHierarchyAccessService {

    private static final String ROW_CAUSE_MANUAL = 'Manual';
    private static final String ACCESS_EDIT = 'Edit';
    private static final Integer MAX_DIVISION_PARENTS = 4000;
    private static final Integer MAX_VOLUME_PARENTS = 10000;
    private static final Integer DML_CHUNK = 200;

    /**
     * Resolves the API name of the share object for a parent sObject API name.
     *
     * <p>{@link Schema#getGlobalDescribe()} keys are often <strong>lowercase</strong>; matching only mixed-case
     * names would skip valid share objects and prevent manual shares under private OWD.</p>
     *
     * @param parentApiName Parent object API name (e.g. {@code Division__c}, {@code Program}).
     * @return Share object API name for dynamic SOQL/DML, or null when not available in this org.
     */
    public static String shareObjectApiNameFromParentApiName(String parentApiName) {
        Schema.SObjectType shareType = resolveShareSObjectType(parentApiName);
        if (shareType == null) {
            return null;
        }
        return shareType.getDescribe().getName();
    }

    /**
     * Locates the share {@link Schema.SObjectType} for a parent API name using exact and lowercase map keys,
     * then a case-insensitive scan of describe names when the share type is absent from the map keys.
     *
     * @param parentApiName Parent object API name (e.g. {@code AcademicYear}, {@code Division__c}).
     * @return Share sObject type, or null if the org has no such share object.
     */
    private static Schema.SObjectType resolveShareSObjectType(String parentApiName) {
        if (String.isBlank(parentApiName)) {
            return null;
        }
        String candidate = parentApiName.endsWith('__c')
            ? parentApiName.substring(0, parentApiName.length() - 3) + '__Share'
            : parentApiName + 'Share';
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        if (gd.containsKey(candidate)) {
            return gd.get(candidate);
        }
        String lower = candidate.toLowerCase();
        if (gd.containsKey(lower)) {
            return gd.get(lower);
        }
        return resolveShareSObjectTypeFromTypeName(candidate);
    }

    /**
     * Resolves a share {@link Schema.SObjectType} when map keys do not match the expected share API name.
     *
     * @param shareApiName Share object API name (e.g. {@code AcademicYearShare}).
     * @return Share sObject type, or null if not found.
     */
    private static Schema.SObjectType resolveShareSObjectTypeFromTypeName(String shareApiName) {
        if (String.isBlank(shareApiName)) {
            return null;
        }
        for (Schema.SObjectType t : Schema.getGlobalDescribe().values()) {
            if (t.getDescribe().getName().equalsIgnoreCase(shareApiName)) {
                return t;
            }
        }
        return null;
    }

    /**
     * Builds rows for the Program access UI: program team (when {@code User__c} exists), users in the program’s
     * access public group ({@code SPJIMR_Program_Access_Group__c}), and users with legacy Manual {@link ProgramShare}
     * rows. {@link ProgramAccessUserRow#hasAccess} is true when the user is in the public group and/or has a manual
     * share on the Program.
     *
     * @param programId Program record Id.
     * @return One row per user with display name and combined access flag.
     */
    public static List<ProgramAccessUserRow> buildAccessRows(Id programId) {
        List<ProgramAccessUserRow> result = new List<ProgramAccessUserRow>();
        if (programId == null) {
            return result;
        }
        Map<Id, User> usersById = new Map<Id, User>();
        Map<Id, Boolean> hasManualShare = new Map<Id, Boolean>();

        for (ProgramShare sh : [
            SELECT UserOrGroupId
            FROM ProgramShare
            WHERE ParentId = :programId
            AND RowCause = :ROW_CAUSE_MANUAL
        ]) {
            if (isUserId(sh.UserOrGroupId)) {
                hasManualShare.put(sh.UserOrGroupId, true);
                usersById.put(sh.UserOrGroupId, null);
            }
        }

        if (Schema.SObjectType.Program_Team_Members__c.fields.getMap().containsKey('User__c')) {
            for (Program_Team_Members__c ptm : [
                SELECT User__c
                FROM Program_Team_Members__c
                WHERE Program_Team__r.Program__c = :programId
                AND User__c != NULL
            ]) {
                usersById.put(ptm.User__c, null);
            }
        }

        Id accessGroupId = ProgramAccessPublicGroupService.getAccessGroupIdForProgram(programId);
        Set<Id> inAccessGroup = ProgramAccessPublicGroupService.loadUserIdsInAccessGroup(accessGroupId);
        for (Id uid : inAccessGroup) {
            usersById.put(uid, null);
        }

        if (!usersById.isEmpty()) {
            for (User u : [
                SELECT Id, Name, Username, Title, SmallPhotoUrl
                FROM User
                WHERE Id IN :usersById.keySet()
                AND IsActive = true
            ]) {
                usersById.put(u.Id, u);
            }
        }

        for (Id userId : usersById.keySet()) {
            User u = usersById.get(userId);
            if (u == null) {
                continue;
            }
            ProgramAccessUserRow row = new ProgramAccessUserRow();
            row.userId = userId;
            row.userName = u.Name;
            row.username = u.Username;
            row.userTitle = u.Title;
            row.photoUrl = u.SmallPhotoUrl;
            Boolean manual = hasManualShare.get(userId) == true;
            Boolean inGroup = accessGroupId != null && inAccessGroup.contains(userId);
            row.hasAccess = manual || inGroup;
            result.add(row);
        }
        result.sort();
        return result;
    }

    private static Boolean isUserId(Id userOrGroupId) {
        if (userOrGroupId == null) {
            return false;
        }
        SObjectType t = userOrGroupId.getSobjectType();
        return t == User.SObjectType;
    }

    /**
     * Grants Manual shares for one user across the Program hierarchy.
     *
     * @param programId Program Id.
     * @param userId User receiving access.
     */
    public static void grantHierarchyAccess(Id programId, Id userId) {
        if (programId == null || userId == null) {
            return;
        }
        System.debug(LoggingLevel.WARN, 'PHAS grantHierarchyAccess begin programId=' + programId + ' userId=' + userId);
        HierarchyParents parents = loadHierarchyParents(programId);
        insertMissingShares(parents, userId);
        System.debug(LoggingLevel.WARN, 'PHAS grantHierarchyAccess end programId=' + programId + ' userId=' + userId);
    }

    /**
     * Removes Manual shares for one user across the Program hierarchy (same scope as grant).
     *
     * @param programId Program Id.
     * @param userId User losing access.
     */
    public static void revokeHierarchyAccess(Id programId, Id userId) {
        if (programId == null || userId == null) {
            return;
        }
        System.debug(LoggingLevel.WARN, 'PHAS revokeHierarchyAccess begin programId=' + programId + ' userId=' + userId);
        HierarchyParents parents = loadHierarchyParents(programId);
        deleteManualShares(parents, userId);
        System.debug(LoggingLevel.WARN, 'PHAS revokeHierarchyAccess end programId=' + programId + ' userId=' + userId);
    }

    /**
     * Grants Manual Edit shares for multiple users across the full Program hierarchy (one hierarchy load).
     *
     * @param programId Program Id.
     * @param userIds Users receiving access (null entries skipped).
     */
    public static void grantHierarchyAccessForUsers(Id programId, List<Id> userIds) {
        if (programId == null || userIds == null || userIds.isEmpty()) {
            return;
        }
        HierarchyParents parents = loadHierarchyParents(programId);
        for (Id userId : userIds) {
            if (userId != null) {
                insertMissingShares(parents, userId);
            }
        }
        Id accessGroupId = ProgramAccessPublicGroupService.getAccessGroupIdForProgram(programId);
        if (accessGroupId != null) {
            insertMissingShares(parents, accessGroupId);
            System.debug(
                LoggingLevel.WARN,
                'PHAS grantHierarchyAccessForUsers accessGroupId=' + accessGroupId
                    + ' academicYearShareParents=' + parents.academicYearIds.size()
            );
        }
        if (parents.academicYearIds.isEmpty()) {
            System.debug(
                LoggingLevel.WARN,
                'PHAS grantHierarchyAccessForUsers no AcademicYear (batch group) Ids for programId=' + programId
            );
        }
    }

    /**
     * Removes Manual shares for multiple users across the full Program hierarchy (one hierarchy load).
     *
     * @param programId Program Id.
     * @param userIds Users losing access (null entries skipped).
     */
    public static void revokeHierarchyAccessForUsers(Id programId, List<Id> userIds) {
        if (programId == null || userIds == null || userIds.isEmpty()) {
            return;
        }
        HierarchyParents parents = loadHierarchyParents(programId);
        for (Id userId : userIds) {
            if (userId != null) {
                deleteManualShares(parents, userId);
            }
        }
    }

    /**
     * Loads all parent record Ids under the Program used for manual share grant/revoke.
     *
     * @param programId Root Program Id.
     * @return Aggregated parent Ids by object type.
     */
    private static HierarchyParents loadHierarchyParents(Id programId) {
        HierarchyParents hp = new HierarchyParents();
        hp.programId = programId;

        loadCohortAcademicStructure(hp);
        loadDivisionsAndGroups(hp);
        loadEnrollmentsCoursesAndMembers(hp);
        loadCampusAndCampusProgram(hp);
        loadProgramTeam(hp);
        loadAcademicTermEnrollments(hp);
        loadDivisionEnrollmentsAndDivisionCourses(hp);
        loadCourseOfferings(hp);
        loadInstructorsAndCourseEnrollments(hp);
        loadStudentSpecialisations(hp);
        loadSessionsAndSessionChildren(hp);
        loadLeaveApplications(hp);
        loadLeadPrograms(hp);
        loadPortalNotifications(hp);

        System.debug(
            LoggingLevel.WARN,
            'PHAS loadHierarchyParents done programId=' + programId
                + ' cohorts=' + hp.cohortIds.size()
                + ' academicYears=' + hp.academicYearIds.size()
                + ' terms=' + hp.termIds.size()
                + ' divisions=' + hp.divisionIds.size()
                + ' programEnrollments=' + hp.programEnrollmentIds.size()
                + ' sessions=' + hp.sessionIds.size()
        );
        return hp;
    }

    /**
     * Collects cohort, batch group (Academic Year), and term Ids for the Program via programme master, batch
     * lookup, and term {@code AcademicYearId} (covers batch groups that are only linked from terms).
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadCohortAcademicStructure(HierarchyParents hp) {
        Id programId = hp.programId;
        System.debug(LoggingLevel.WARN, 'PHAS loadCohortAcademicStructure start programId=' + programId);
        Set<Id> cohortIds = new Set<Id>();
        for (ProgramCohort pc : [SELECT Id FROM ProgramCohort WHERE ProgramId = :programId]) {
            cohortIds.add(pc.Id);
        }
        hp.cohortIds = cohortIds;

        Set<Id> academicYearIds = new Set<Id>();
        Set<Id> termIds = new Set<Id>();

        if (!cohortIds.isEmpty()) {
            for (AcademicTerm t : [
                SELECT Id, AcademicYearId
                FROM AcademicTerm
                WHERE Program_Name__c = :programId OR Batch_Name__c IN :cohortIds
            ]) {
                termIds.add(t.Id);
                if (t.AcademicYearId != null) {
                    academicYearIds.add(t.AcademicYearId);
                }
            }
        } else {
            for (AcademicTerm t : [
                SELECT Id, AcademicYearId
                FROM AcademicTerm
                WHERE Program_Name__c = :programId
            ]) {
                termIds.add(t.Id);
                if (t.AcademicYearId != null) {
                    academicYearIds.add(t.AcademicYearId);
                }
            }
        }

        if (Schema.SObjectType.AcademicYear.fields.getMap().containsKey('Program_Master__c')) {
            for (AcademicYear ay : [SELECT Id FROM AcademicYear WHERE Program_Master__c = :programId]) {
                academicYearIds.add(ay.Id);
            }
        }
        for (AcademicYear ay : [SELECT Id FROM AcademicYear WHERE Batch__r.ProgramId = :programId]) {
            academicYearIds.add(ay.Id);
        }
        if (!cohortIds.isEmpty()) {
            for (AcademicYear ay : [SELECT Id FROM AcademicYear WHERE Batch__c IN :cohortIds]) {
                academicYearIds.add(ay.Id);
            }
            for (AcademicTerm t : [
                SELECT Id, AcademicYearId
                FROM AcademicTerm
                WHERE AcademicYearId IN (SELECT Id FROM AcademicYear WHERE Batch__c IN :cohortIds)
            ]) {
                termIds.add(t.Id);
                if (t.AcademicYearId != null) {
                    academicYearIds.add(t.AcademicYearId);
                }
            }
        }

        if (!academicYearIds.isEmpty()) {
            for (AcademicTerm t : [
                SELECT Id, AcademicYearId
                FROM AcademicTerm
                WHERE AcademicYearId IN :academicYearIds
            ]) {
                termIds.add(t.Id);
            }
        }

        hp.academicYearIds = academicYearIds;
        hp.termIds = termIds;
        System.debug(
            LoggingLevel.WARN,
            'PHAS loadCohortAcademicStructure end programId=' + programId
                + ' cohortIds=' + cohortIds.size()
                + ' academicYearIds=' + academicYearIds.size()
                + ' termIds=' + termIds.size()
                + ' academicYearShareApi='
                + shareObjectApiNameFromParentApiName('AcademicYear')
        );
    }

    /**
     * Collects Division and Division Group Ids from terms (with volume guard on divisions).
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadDivisionsAndGroups(HierarchyParents hp) {
        Id programId = hp.programId;
        Set<Id> termIds = hp.termIds;
        Set<Id> cohortIds = hp.cohortIds;
        Set<Id> divisionIds = new Set<Id>();
        Set<Id> divisionGroupIds = new Set<Id>();

        String divisionSoql = 'SELECT Id, Division_Group__c FROM Division__c WHERE ';
        List<String> divisionFilters = new List<String>();
        if (!termIds.isEmpty()) {
            divisionFilters.add('Term__c IN :termIds');
        }
        if (!cohortIds.isEmpty()) {
            divisionFilters.add('Batch__c IN :cohortIds');
        }
        divisionFilters.add('Term__r.Program_Name__c = :programId');
        divisionSoql += String.join(divisionFilters, ' OR ');

        Integer divCount = Database.countQuery(
            'SELECT COUNT() FROM Division__c WHERE ' + String.join(divisionFilters, ' OR ')
        );
        if (divCount > MAX_DIVISION_PARENTS) {
            throw new AuraHandledException(
                'Too many Division records (' + divCount + ') to share in one operation. Limit is '
                    + MAX_DIVISION_PARENTS + '. Contact an administrator.'
            );
        }
        for (Division__c d : Database.query(divisionSoql)) {
            divisionIds.add(d.Id);
            if (d.Division_Group__c != null) {
                divisionGroupIds.add(d.Division_Group__c);
            }
        }

        hp.divisionIds = divisionIds;
        hp.divisionGroupIds = divisionGroupIds;
    }

    /**
     * Collects program enrollment, program course, and cohort member Ids.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadEnrollmentsCoursesAndMembers(HierarchyParents hp) {
        Id programId = hp.programId;
        Set<Id> cohortIds = hp.cohortIds;

        Set<Id> programEnrollmentIds = new Set<Id>();
        if (cohortIds.isEmpty()) {
            for (ProgramEnrollment pe : [SELECT Id FROM ProgramEnrollment WHERE ProgramId = :programId]) {
                programEnrollmentIds.add(pe.Id);
            }
        } else {
            for (ProgramEnrollment pe : [
                SELECT Id
                FROM ProgramEnrollment
                WHERE ProgramId = :programId
                OR Batch__c IN :cohortIds
            ]) {
                programEnrollmentIds.add(pe.Id);
            }
        }
        hp.programEnrollmentIds = programEnrollmentIds;

        Set<Id> programCourseIds = new Set<Id>();
        if (cohortIds.isEmpty()) {
            for (Program_Courses__c pc : [SELECT Id FROM Program_Courses__c WHERE Program_Master__c = :programId]) {
                programCourseIds.add(pc.Id);
            }
        } else {
            for (Program_Courses__c pc : [
                SELECT Id
                FROM Program_Courses__c
                WHERE Program_Master__c = :programId
                OR Batch__c IN :cohortIds
            ]) {
                programCourseIds.add(pc.Id);
            }
        }
        hp.programCourseIds = programCourseIds;

        Set<Id> cohortMemberIds = new Set<Id>();
        if (!cohortIds.isEmpty()) {
            for (ProgramCohortMember pcm : [
                SELECT Id
                FROM ProgramCohortMember
                WHERE ProgramCohortId IN :cohortIds
            ]) {
                cohortMemberIds.add(pcm.Id);
            }
        }
        hp.cohortMemberIds = cohortMemberIds;
    }

    /**
     * Collects Campus and Campus–Program junction Ids tied to the Program.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadCampusAndCampusProgram(HierarchyParents hp) {
        Id programId = hp.programId;
        Set<Id> campusIds = new Set<Id>();
        for (Campus__c c : [SELECT Id FROM Campus__c WHERE Program_Name__c = :programId]) {
            campusIds.add(c.Id);
        }
        hp.campusIds = campusIds;

        Set<Id> campusProgramIds = new Set<Id>();
        for (CampusProgram__c cp : [SELECT Id FROM CampusProgram__c WHERE Program_Master__c = :programId]) {
            campusProgramIds.add(cp.Id);
        }
        if (!campusIds.isEmpty()) {
            for (CampusProgram__c cp : [
                SELECT Id
                FROM CampusProgram__c
                WHERE Campus__c IN :campusIds
                AND Program_Master__c != :programId
            ]) {
                campusProgramIds.add(cp.Id);
            }
        }
        hp.campusProgramIds = campusProgramIds;
    }

    /**
     * Collects Program Team and Program Team Member Ids.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadProgramTeam(HierarchyParents hp) {
        Id programId = hp.programId;
        Set<Id> programTeamIds = new Set<Id>();
        for (Program_Team__c pt : [SELECT Id FROM Program_Team__c WHERE Program__c = :programId]) {
            programTeamIds.add(pt.Id);
        }
        hp.programTeamIds = programTeamIds;

        Set<Id> programTeamMemberIds = new Set<Id>();
        if (!programTeamIds.isEmpty()) {
            for (Program_Team_Members__c ptm : [
                SELECT Id
                FROM Program_Team_Members__c
                WHERE Program_Team__c IN :programTeamIds
            ]) {
                programTeamMemberIds.add(ptm.Id);
            }
        }
        hp.programTeamMemberIds = programTeamMemberIds;
    }

    /**
     * Collects Academic Term Enrollment Ids from divisions and program enrollments.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadAcademicTermEnrollments(HierarchyParents hp) {
        Set<Id> divisionIds = hp.divisionIds;
        Set<Id> programEnrollmentIds = hp.programEnrollmentIds;
        Set<Id> academicTermEnrollmentIds = new Set<Id>();
        if (!divisionIds.isEmpty()) {
            for (AcademicTermEnrollment ate : [
                SELECT Id
                FROM AcademicTermEnrollment
                WHERE Division__c IN :divisionIds
            ]) {
                academicTermEnrollmentIds.add(ate.Id);
            }
        }
        if (!programEnrollmentIds.isEmpty()) {
            for (AcademicTermEnrollment ate : [
                SELECT Id
                FROM AcademicTermEnrollment
                WHERE Program_Enrolled__c IN :programEnrollmentIds
            ]) {
                academicTermEnrollmentIds.add(ate.Id);
            }
        }
        hp.academicTermEnrollmentIds = academicTermEnrollmentIds;
    }

    /**
     * Collects Division Enrollment and Division Course Ids.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadDivisionEnrollmentsAndDivisionCourses(HierarchyParents hp) {
        Set<Id> divisionIds = hp.divisionIds;
        Set<Id> programEnrollmentIds = hp.programEnrollmentIds;

        Set<Id> divisionEnrollmentIds = new Set<Id>();
        if (!divisionIds.isEmpty()) {
            for (Division_Enrollment__c de : [
                SELECT Id
                FROM Division_Enrollment__c
                WHERE Division__c IN :divisionIds
            ]) {
                divisionEnrollmentIds.add(de.Id);
            }
        }
        hp.divisionEnrollmentIds = divisionEnrollmentIds;

        Set<Id> divisionCourseIds = new Set<Id>();
        if (!divisionIds.isEmpty()) {
            for (DivisionCourse__c dc : [
                SELECT Id
                FROM DivisionCourse__c
                WHERE Division__c IN :divisionIds
            ]) {
                divisionCourseIds.add(dc.Id);
            }
        }
        if (!programEnrollmentIds.isEmpty()) {
            for (DivisionCourse__c dc : [
                SELECT Id
                FROM DivisionCourse__c
                WHERE Program_Enrollment__c IN :programEnrollmentIds
            ]) {
                divisionCourseIds.add(dc.Id);
            }
        }
        hp.divisionCourseIds = divisionCourseIds;
    }

    /**
     * Collects Course Offering Ids from terms and program courses (volume guard).
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadCourseOfferings(HierarchyParents hp) {
        Set<Id> termIds = hp.termIds;
        Set<Id> programCourseIds = hp.programCourseIds;
        Set<Id> courseOfferingIds = new Set<Id>();

        if (!termIds.isEmpty()) {
            for (CourseOffering co : [
                SELECT Id
                FROM CourseOffering
                WHERE Academic_Term__c IN :termIds
                OR Start_Term__c IN :termIds
                OR End_Term__c IN :termIds
            ]) {
                courseOfferingIds.add(co.Id);
            }
        }
        if (!programCourseIds.isEmpty()) {
            for (CourseOffering co : [
                SELECT Id
                FROM CourseOffering
                WHERE ProgramCourse__c IN :programCourseIds
            ]) {
                courseOfferingIds.add(co.Id);
            }
        }

        assertVolumeLimit('Course offering', courseOfferingIds.size());
        hp.courseOfferingIds = courseOfferingIds;
    }

    /**
     * Collects Instructor and Course Enrollment Ids from program courses and enrollments.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadInstructorsAndCourseEnrollments(HierarchyParents hp) {
        Set<Id> programCourseIds = hp.programCourseIds;
        Set<Id> programEnrollmentIds = hp.programEnrollmentIds;

        Set<Id> instructorIds = new Set<Id>();
        if (!programCourseIds.isEmpty()) {
            for (Instructor__c ins : [
                SELECT Id
                FROM Instructor__c
                WHERE Program_Course__c IN :programCourseIds
            ]) {
                instructorIds.add(ins.Id);
            }
        }
        hp.instructorIds = instructorIds;

        Set<Id> courseEnrollmentIds = new Set<Id>();
        if (!programEnrollmentIds.isEmpty()) {
            for (CourseEnrollment__c ce : [
                SELECT Id
                FROM CourseEnrollment__c
                WHERE Program_Enrollment__c IN :programEnrollmentIds
            ]) {
                courseEnrollmentIds.add(ce.Id);
            }
        }
        if (!programCourseIds.isEmpty()) {
            for (CourseEnrollment__c ce : [
                SELECT Id
                FROM CourseEnrollment__c
                WHERE Program_Course__c IN :programCourseIds
            ]) {
                courseEnrollmentIds.add(ce.Id);
            }
        }
        hp.courseEnrollmentIds = courseEnrollmentIds;
    }

    /**
     * Collects Student Specialisation Ids from program enrollments and cohort members.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadStudentSpecialisations(HierarchyParents hp) {
        Set<Id> programEnrollmentIds = hp.programEnrollmentIds;
        Set<Id> cohortMemberIds = hp.cohortMemberIds;
        Set<Id> studentSpecialisationIds = new Set<Id>();

        if (!programEnrollmentIds.isEmpty()) {
            for (Student_Specialisation__c ss : [
                SELECT Id
                FROM Student_Specialisation__c
                WHERE Program_Enrollment__c IN :programEnrollmentIds
            ]) {
                studentSpecialisationIds.add(ss.Id);
            }
        }
        if (!cohortMemberIds.isEmpty()) {
            for (Student_Specialisation__c ss : [
                SELECT Id
                FROM Student_Specialisation__c
                WHERE Program_Cohort_Member__c IN :cohortMemberIds
            ]) {
                studentSpecialisationIds.add(ss.Id);
            }
        }
        hp.studentSpecialisationIds = studentSpecialisationIds;
    }

    /**
     * Collects Session and session-related child Ids (volume guard on sessions).
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadSessionsAndSessionChildren(HierarchyParents hp) {
        Id programId = hp.programId;
        Set<Id> cohortIds = hp.cohortIds;
        Set<Id> termIds = hp.termIds;
        Set<Id> academicYearIds = hp.academicYearIds;
        Set<Id> divisionIds = hp.divisionIds;

        Set<Id> sessionIds = new Set<Id>();
        for (Session__c s : [SELECT Id FROM Session__c WHERE Program__c = :programId]) {
            sessionIds.add(s.Id);
        }
        if (!cohortIds.isEmpty()) {
            for (Session__c s : [SELECT Id FROM Session__c WHERE ProgramBatch__c IN :cohortIds]) {
                sessionIds.add(s.Id);
            }
        }
        if (!termIds.isEmpty()) {
            for (Session__c s : [SELECT Id FROM Session__c WHERE Term__c IN :termIds]) {
                sessionIds.add(s.Id);
            }
        }
        if (!academicYearIds.isEmpty()) {
            for (Session__c s : [SELECT Id FROM Session__c WHERE Academic_Year__c IN :academicYearIds]) {
                sessionIds.add(s.Id);
            }
        }
        if (!divisionIds.isEmpty()) {
            for (Session__c s : [SELECT Id FROM Session__c WHERE Divisions__c IN :divisionIds]) {
                sessionIds.add(s.Id);
            }
        }

        assertVolumeLimit('Session', sessionIds.size());
        hp.sessionIds = sessionIds;

        Set<Id> sessionDivisionIds = new Set<Id>();
        Set<Id> sessionEnrollmentIds = new Set<Id>();
        Set<Id> sessionFacultyIds = new Set<Id>();
        if (!sessionIds.isEmpty()) {
            for (Session_Division__c sd : [
                SELECT Id
                FROM Session_Division__c
                WHERE Session__c IN :sessionIds
            ]) {
                sessionDivisionIds.add(sd.Id);
            }
            for (Session_Enrollment__c se : [
                SELECT Id
                FROM Session_Enrollment__c
                WHERE Session__c IN :sessionIds
            ]) {
                sessionEnrollmentIds.add(se.Id);
            }
            for (Session_Faculty__c sf : [
                SELECT Id
                FROM Session_Faculty__c
                WHERE Session__c IN :sessionIds
            ]) {
                sessionFacultyIds.add(sf.Id);
            }
        }
        hp.sessionDivisionIds = sessionDivisionIds;
        hp.sessionEnrollmentIds = sessionEnrollmentIds;
        hp.sessionFacultyIds = sessionFacultyIds;
    }

    /**
     * Collects Leave Application Ids from term enrollments and cohort members.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadLeaveApplications(HierarchyParents hp) {
        Set<Id> academicTermEnrollmentIds = hp.academicTermEnrollmentIds;
        Set<Id> cohortMemberIds = hp.cohortMemberIds;
        Set<Id> leaveApplicationIds = new Set<Id>();

        if (!academicTermEnrollmentIds.isEmpty()) {
            for (Leave_Application__c la : [
                SELECT Id
                FROM Leave_Application__c
                WHERE Term_Enrollment__c IN :academicTermEnrollmentIds
            ]) {
                leaveApplicationIds.add(la.Id);
            }
        }
        if (!cohortMemberIds.isEmpty()) {
            for (Leave_Application__c la : [
                SELECT Id
                FROM Leave_Application__c
                WHERE Batch_Enrollment__c IN :cohortMemberIds
            ]) {
                leaveApplicationIds.add(la.Id);
            }
        }

        assertVolumeLimit('Leave application', leaveApplicationIds.size());
        hp.leaveApplicationIds = leaveApplicationIds;
    }

    /**
     * Collects Lead Program junction Ids for the Program (volume guard).
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadLeadPrograms(HierarchyParents hp) {
        Id programId = hp.programId;
        Integer lpCount = [SELECT COUNT() FROM Lead_Program__c WHERE Program__c = :programId];
        assertVolumeLimit('Lead program', lpCount);

        Set<Id> leadProgramIds = new Set<Id>();
        for (Lead_Program__c lp : [SELECT Id FROM Lead_Program__c WHERE Program__c = :programId]) {
            leadProgramIds.add(lp.Id);
        }
        hp.leadProgramIds = leadProgramIds;
    }

    /**
     * Collects Portal Notification Ids linked to sessions under the Program.
     *
     * @param hp Mutable hierarchy accumulator.
     */
    private static void loadPortalNotifications(HierarchyParents hp) {
        Set<Id> sessionIds = hp.sessionIds;
        Set<Id> portalNotificationIds = new Set<Id>();
        if (!sessionIds.isEmpty()) {
            for (Portal_Notification__c pn : [
                SELECT Id
                FROM Portal_Notification__c
                WHERE Session__c IN :sessionIds
            ]) {
                portalNotificationIds.add(pn.Id);
            }
        }
        assertVolumeLimit('Portal notification', portalNotificationIds.size());
        hp.portalNotificationIds = portalNotificationIds;
    }

    /**
     * Throws when a non-division parent count exceeds the configured maximum.
     *
     * @param label Human-readable type name for the error message.
     * @param count Number of parent records.
     */
    private static void assertVolumeLimit(String label, Integer count) {
        if (count != null && count > MAX_VOLUME_PARENTS) {
            throw new AuraHandledException(
                'Too many ' + label + ' records (' + count + ') to share in one operation. Limit is '
                    + MAX_VOLUME_PARENTS + '. Contact an administrator.'
            );
        }
    }

    /**
     * Inserts Manual Edit shares for every collected parent type.
     *
     * @param hp Parent Ids by object.
     * @param recipientId User or public Group Id ({@link Group}).
     */
    private static void insertMissingShares(HierarchyParents hp, Id recipientId) {
        System.debug(
            LoggingLevel.WARN,
            'PHAS insertMissingShares begin recipientId=' + recipientId + ' programId=' + hp.programId
        );
        Map<String, ShareParentResult> results = new Map<String, ShareParentResult>();
        results.put('ProgramCohort', insertMissingForParent('ProgramCohort', hp.cohortIds, recipientId));
        results.put('AcademicYear', insertMissingForParent('AcademicYear', hp.academicYearIds, recipientId));
        results.put('AcademicTerm', insertMissingForParent('AcademicTerm', hp.termIds, recipientId));
        results.put('Division__c', insertMissingForParent('Division__c', hp.divisionIds, recipientId));
        results.put('Program', insertMissingForParent('Program', new Set<Id>{ hp.programId }, recipientId));
        insertMissingForParent('Division_Group__c', hp.divisionGroupIds, recipientId);
        insertMissingForParent('Campus__c', hp.campusIds, recipientId);
        insertMissingForParent('CampusProgram__c', hp.campusProgramIds, recipientId);
        insertMissingForParent('Program_Team__c', hp.programTeamIds, recipientId);
        insertMissingForParent('Program_Team_Members__c', hp.programTeamMemberIds, recipientId);
        insertMissingForParent('ProgramEnrollment', hp.programEnrollmentIds, recipientId);
        insertMissingForParent('Program_Courses__c', hp.programCourseIds, recipientId);
        insertMissingForParent('ProgramCohortMember', hp.cohortMemberIds, recipientId);
        insertMissingForParent('AcademicTermEnrollment', hp.academicTermEnrollmentIds, recipientId);
        insertMissingForParent('Division_Enrollment__c', hp.divisionEnrollmentIds, recipientId);
        insertMissingForParent('DivisionCourse__c', hp.divisionCourseIds, recipientId);
        insertMissingForParent('CourseOffering', hp.courseOfferingIds, recipientId);
        insertMissingForParent('Instructor__c', hp.instructorIds, recipientId);
        insertMissingForParent('CourseEnrollment__c', hp.courseEnrollmentIds, recipientId);
        insertMissingForParent('Student_Specialisation__c', hp.studentSpecialisationIds, recipientId);
        insertMissingForParent('Session__c', hp.sessionIds, recipientId);
        insertMissingForParent('Session_Division__c', hp.sessionDivisionIds, recipientId);
        insertMissingForParent('Session_Enrollment__c', hp.sessionEnrollmentIds, recipientId);
        insertMissingForParent('Session_Faculty__c', hp.sessionFacultyIds, recipientId);
        insertMissingForParent('Leave_Application__c', hp.leaveApplicationIds, recipientId);
        insertMissingForParent('Portal_Notification__c', hp.portalNotificationIds, recipientId);
        insertMissingForParent('Lead_Program__c', hp.leadProgramIds, recipientId);
        validateCriticalShareResults(hp, results);
        System.debug(LoggingLevel.WARN, 'PHAS insertMissingShares end recipientId=' + recipientId);
    }

    /**
     * Ensures batch groups, terms, and divisions under the program received manual shares when parent Ids exist.
     *
     * @param hp Collected hierarchy parent Ids.
     * @param results Per-object share insert outcomes for critical types.
     */
    private static void validateCriticalShareResults(
        HierarchyParents hp,
        Map<String, ShareParentResult> results
    ) {
        List<String> problems = new List<String>();

        if (!hp.cohortIds.isEmpty() && hp.academicYearIds.isEmpty()) {
            problems.add(
                'No Academic Year (batch group) records are linked to this program\'s batches. '
                    + 'Link batch groups to batches before granting access.'
            );
        }

        addShareProblem(problems, results.get('AcademicYear'), 'Academic Year (batch group)');
        addShareProblem(problems, results.get('AcademicTerm'), 'Academic Term');
        addShareProblem(problems, results.get('Division__c'), 'Division');
        addShareProblem(problems, results.get('ProgramCohort'), 'Batch (Program Cohort)');

        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, ' '));
        }
    }

    /**
     * Appends a user-facing error when parent records exist but manual sharing could not be applied.
     *
     * @param problems Mutable error list.
     * @param result Share outcome for one parent type.
     * @param label Display name for the object.
     */
    private static void addShareProblem(List<String> problems, ShareParentResult result, String label) {
        if (result == null || result.parentCount == 0) {
            return;
        }
        if (result.shareObjectMissing) {
            problems.add(
                label
                    + ': manual sharing is not available in this org ('
                    + result.parentCount
                    + ' records under this program).'
            );
        } else if (result.insertedCount == 0 && result.existingCount == 0) {
            problems.add(
                label + ': failed to create manual share rows for ' + result.parentCount + ' records.'
            );
        }
    }

    /**
     * Inserts Manual shares for one parent object type when the share object exists in the org.
     *
     * @param parentApiName Parent sObject API name.
     * @param parentIds Parent record Ids (may be empty).
     * @param recipientId User or public Group Id.
     */
    private static ShareParentResult insertMissingForParent(
        String parentApiName,
        Set<Id> parentIds,
        Id recipientId
    ) {
        ShareParentResult outcome = new ShareParentResult();
        if (parentIds == null || parentIds.isEmpty() || recipientId == null) {
            return outcome;
        }
        outcome.parentCount = parentIds.size();
        Schema.SObjectType shareType = resolveShareSObjectType(parentApiName);
        if (shareType == null) {
            outcome.shareObjectMissing = true;
            System.debug(
                LoggingLevel.WARN,
                'PHAS insertMissingForParent skipped parent=' + parentApiName
                    + ' count=' + parentIds.size()
                    + ' reason=noShareObjectInOrg'
            );
            return outcome;
        }
        String shareObject = shareType.getDescribe().getName();
        Set<Id> already = loadExistingParentIds(shareObject, parentIds, recipientId);
        outcome.existingCount = already.size();
        List<SObject> rowsToInsert = new List<SObject>();
        for (Id pid : parentIds) {
            if (pid == null || already.contains(pid)) {
                continue;
            }
            SObject row = shareType.newSObject();
            row.put('ParentId', pid);
            row.put('UserOrGroupId', recipientId);
            row.put('AccessLevel', ACCESS_EDIT);
            row.put('RowCause', ROW_CAUSE_MANUAL);
            rowsToInsert.add(row);
            if (rowsToInsert.size() >= DML_CHUNK) {
                outcome.insertedCount += insertShareRowsPartial(parentApiName, rowsToInsert);
                rowsToInsert.clear();
            }
        }
        if (!rowsToInsert.isEmpty()) {
            outcome.insertedCount += insertShareRowsPartial(parentApiName, rowsToInsert);
        }
        if (outcome.insertedCount > 0) {
            System.debug(
                LoggingLevel.WARN,
                'PHAS insertMissingForParent inserted parent=' + parentApiName
                    + ' shareObject=' + shareObject
                    + ' rows=' + outcome.insertedCount
                    + ' recipientId=' + recipientId
            );
        }
        return outcome;
    }

    /**
     * Inserts share rows with partial success; throws when every row in the chunk fails.
     *
     * @param parentApiName Parent object label for errors.
     * @param rowsToInsert Share rows.
     * @return Number of rows successfully inserted.
     */
    private static Integer insertShareRowsPartial(String parentApiName, List<SObject> rowsToInsert) {
        Database.SaveResult[] saveResults = Database.insert(rowsToInsert, false);
        Integer successCount = 0;
        String firstError;
        for (Database.SaveResult sr : saveResults) {
            if (sr.isSuccess()) {
                successCount++;
            } else if (firstError == null) {
                firstError = sr.getErrors()[0].getMessage();
            }
        }
        if (successCount == 0 && firstError != null) {
            throw new AuraHandledException(
                'Could not grant access on ' + parentApiName + ': ' + firstError
            );
        }
        return successCount;
    }

    /**
     * Loads parent Ids that already have a Manual share for the user.
     *
     * @param shareObject Share object API name.
     * @param parentIds Candidate parent Ids.
     * @param recipientId User or public Group Id.
     * @return Parent Ids that already have Manual access.
     */
    private static Set<Id> loadExistingParentIds(String shareObject, Set<Id> parentIds, Id recipientId) {
        Set<Id> found = new Set<Id>();
        String rowCause = ROW_CAUSE_MANUAL;
        String soql =
            'SELECT ParentId FROM ' + shareObject + ' WHERE ParentId IN :parentIds' +
            ' AND UserOrGroupId = :recipientId AND RowCause = :rowCause';
        for (SObject row : Database.query(soql)) {
            found.add((Id) row.get('ParentId'));
        }
        return found;
    }

    /**
     * Deletes Manual shares for every collected parent type.
     *
     * @param hp Parent Ids by object.
     * @param userId User whose Manual shares are removed.
     */
    private static void deleteManualShares(HierarchyParents hp, Id userId) {
        deleteSharesForParent('Program', new Set<Id>{ hp.programId }, userId);
        deleteSharesForParent('ProgramCohort', hp.cohortIds, userId);
        deleteSharesForParent('AcademicYear', hp.academicYearIds, userId);
        deleteSharesForParent('AcademicTerm', hp.termIds, userId);
        deleteSharesForParent('Division__c', hp.divisionIds, userId);
        deleteSharesForParent('Division_Group__c', hp.divisionGroupIds, userId);
        deleteSharesForParent('Campus__c', hp.campusIds, userId);
        deleteSharesForParent('CampusProgram__c', hp.campusProgramIds, userId);
        deleteSharesForParent('Program_Team__c', hp.programTeamIds, userId);
        deleteSharesForParent('Program_Team_Members__c', hp.programTeamMemberIds, userId);
        deleteSharesForParent('ProgramEnrollment', hp.programEnrollmentIds, userId);
        deleteSharesForParent('Program_Courses__c', hp.programCourseIds, userId);
        deleteSharesForParent('ProgramCohortMember', hp.cohortMemberIds, userId);
        deleteSharesForParent('AcademicTermEnrollment', hp.academicTermEnrollmentIds, userId);
        deleteSharesForParent('Division_Enrollment__c', hp.divisionEnrollmentIds, userId);
        deleteSharesForParent('DivisionCourse__c', hp.divisionCourseIds, userId);
        deleteSharesForParent('CourseOffering', hp.courseOfferingIds, userId);
        deleteSharesForParent('Instructor__c', hp.instructorIds, userId);
        deleteSharesForParent('CourseEnrollment__c', hp.courseEnrollmentIds, userId);
        deleteSharesForParent('Student_Specialisation__c', hp.studentSpecialisationIds, userId);
        deleteSharesForParent('Session__c', hp.sessionIds, userId);
        deleteSharesForParent('Session_Division__c', hp.sessionDivisionIds, userId);
        deleteSharesForParent('Session_Enrollment__c', hp.sessionEnrollmentIds, userId);
        deleteSharesForParent('Session_Faculty__c', hp.sessionFacultyIds, userId);
        deleteSharesForParent('Leave_Application__c', hp.leaveApplicationIds, userId);
        deleteSharesForParent('Portal_Notification__c', hp.portalNotificationIds, userId);
        deleteSharesForParent('Lead_Program__c', hp.leadProgramIds, userId);
    }

    /**
     * Deletes Manual shares for one parent object type when the share object exists in the org.
     *
     * @param parentApiName Parent sObject API name.
     * @param parentIds Parent record Ids (may be empty).
     * @param userId User whose shares are removed.
     */
    private static void deleteSharesForParent(String parentApiName, Set<Id> parentIds, Id userId) {
        if (parentIds == null || parentIds.isEmpty()) {
            return;
        }
        String shareObject = shareObjectApiNameFromParentApiName(parentApiName);
        if (shareObject == null) {
            return;
        }
        String rowCause = ROW_CAUSE_MANUAL;
        String soql =
            'SELECT Id FROM ' + shareObject + ' WHERE ParentId IN :parentIds' +
            ' AND UserOrGroupId = :userId AND RowCause = :rowCause';
        List<SObject> toDelete = new List<SObject>();
        for (SObject row : Database.query(soql)) {
            toDelete.add(row);
            if (toDelete.size() >= DML_CHUNK) {
                delete toDelete;
                toDelete.clear();
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    /**
     * Serializable row for LWC.
     */
    public class ProgramAccessUserRow implements Comparable {
        @AuraEnabled
        public Id userId { get; set; }
        @AuraEnabled
        public String userName { get; set; }
       
        @AuraEnabled
        public String userTitle { get; set; }
        @AuraEnabled
        public String photoUrl { get; set; }
        @AuraEnabled
        public Boolean hasAccess { get; set; }

        public Integer compareTo(Object other) {
            ProgramAccessUserRow o = (ProgramAccessUserRow) other;
            String a = userName != null ? userName : (username != null ? username : '');
            String b = o.userName != null ? o.userName : (o.username != null ? o.username : '');
            return a.compareTo(b);
        }
    }

    private class ShareParentResult {
        Integer parentCount = 0;
        Integer insertedCount = 0;
        Integer existingCount = 0;
        Boolean shareObjectMissing = false;
    }

    private class HierarchyParents {
        Id programId;
        Set<Id> cohortIds = new Set<Id>();
        Set<Id> academicYearIds = new Set<Id>();
        Set<Id> termIds = new Set<Id>();
        Set<Id> divisionIds = new Set<Id>();
        Set<Id> divisionGroupIds = new Set<Id>();
        Set<Id> campusIds = new Set<Id>();
        Set<Id> campusProgramIds = new Set<Id>();
        Set<Id> programTeamIds = new Set<Id>();
        Set<Id> programTeamMemberIds = new Set<Id>();
        Set<Id> programEnrollmentIds = new Set<Id>();
        Set<Id> programCourseIds = new Set<Id>();
        Set<Id> cohortMemberIds = new Set<Id>();
        Set<Id> academicTermEnrollmentIds = new Set<Id>();
        Set<Id> divisionEnrollmentIds = new Set<Id>();
        Set<Id> divisionCourseIds = new Set<Id>();
        Set<Id> courseOfferingIds = new Set<Id>();
        Set<Id> instructorIds = new Set<Id>();
        Set<Id> courseEnrollmentIds = new Set<Id>();
        Set<Id> studentSpecialisationIds = new Set<Id>();
        Set<Id> sessionIds = new Set<Id>();
        Set<Id> sessionDivisionIds = new Set<Id>();
        Set<Id> sessionEnrollmentIds = new Set<Id>();
        Set<Id> sessionFacultyIds = new Set<Id>();
        Set<Id> leaveApplicationIds = new Set<Id>();
        Set<Id> portalNotificationIds = new Set<Id>();
        Set<Id> leadProgramIds = new Set<Id>();
    }
}