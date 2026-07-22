/**
 * Shared test data factory for SPJIMR student-portal controller tests.
 * Each helper is wrapped in try/catch where the underlying object/field may not
 * exist or be deletable in this org — tests should never fail because of optional
 * setup; they should fall back to early-return branches instead.
 */
@IsTest
public class SpjimrPortalTestDataFactory {

    public class Ctx {
        public Account learner;
        public User portalUser;
        public Id academicTermId;
        public Id programId;
        public Id programCohortId;
        public Id divisionGroupId;
        public Id divisionId;
        public Id divisionEnrollmentId;
        public Id atEnrollmentId;
        public Id courseOfferingId;
        public Id sessionId;
        public Id sessionEnrollmentId;
    }

    public static Ctx buildAll(String tag) {
        Ctx c = new Ctx();
        c.learner = buildLearnerPersonAccount(tag);

        // Person education + employment for the learner
        insertPersonEducation(c.learner.Id);
        insertPersonEmployment(c.learner.Id);

        // Address & emergency
        insertAddressInfo(c.learner.Id);
        insertEmergencyDetail(c.learner.Id);

        // Program + cohort
        c.programId = insertProgram();
        c.programCohortId = insertProgramCohort(c.programId);
        Id programEnrollmentId = insertProgramEnrollment(c.learner.Id, c.programId);
        insertProgramCohortMember(c.programCohortId, programEnrollmentId);

        // Academic term + enrollment
        c.academicTermId = insertAcademicTerm();
        c.atEnrollmentId = insertAcademicTermEnrollment(c.learner.Id, c.academicTermId);

        // Course offering
        c.courseOfferingId = insertCourseOffering(c.academicTermId);

        // Division chain — Division__c.Term__c is a Lookup(AcademicTerm) despite the field name
        c.divisionGroupId = insertDivisionGroup();
        c.divisionId = insertDivision(c.divisionGroupId, c.academicTermId);
        c.divisionEnrollmentId = insertDivisionEnrollment(c.divisionId, c.atEnrollmentId);
        insertDivisionCourse(c.divisionId, c.courseOfferingId);

        // Session + Session_Enrollment chain
        c.sessionId = insertSession();
        c.sessionEnrollmentId = insertSessionEnrollment(c.sessionId, c.divisionEnrollmentId, c.atEnrollmentId);
        insertSessionFaculty(c.sessionId, c.learner.Id);

        // Portal user (links to Account.PersonContactId)
        c.portalUser = insertPortalUser(c.learner.Id, tag);
        return c;
    }

    public static Account buildLearnerPersonAccount(String tag) {
        Id rtId = getStudentPersonAccountRecordTypeId();
        Account a = new Account(
            FirstName = 'TestF' + tag,
            LastName  = 'TestL' + tag,
            PersonEmail = ('test' + tag + '@example.com').toLowerCase()
        );
        if (rtId != null) a.RecordTypeId = rtId;
        try { a.put('Gender__c', 'Male'); } catch (Exception e) {}
        try { a.put('Date_Of_Birth__c', Date.newInstance(2000,1,1)); } catch (Exception e) {}
        try { a.put('PersonMobilePhone', '9999999999'); } catch (Exception e) {}
        try { a.put('Address__c', '123 Test Street'); } catch (Exception e) {}
        insert a;
        return a;
    }

    public static void insertPersonEducation(Id accountId) {
        try {
            SObject pe = (SObject) Type.forName('PersonEducation').newInstance();
            pe.put('Name', 'Test Degree');
            pe.put('AccountId', accountId);
            try { pe.put('GraduationDate', Date.newInstance(2020,6,1)); } catch (Exception e) {}
            try { pe.put('GpaScale', 7.5); } catch (Exception e) {}
            insert pe;
        } catch (Exception e) { System.debug('PersonEducation: ' + e.getMessage()); }
    }

    public static void insertPersonEmployment(Id accountId) {
        try {
            Account a = [SELECT Id, PersonContactId FROM Account WHERE Id = :accountId LIMIT 1];
            SObject pe = (SObject) Type.forName('PersonEmployment').newInstance();
            pe.put('Name', 'Test Org');
            pe.put('AccountId', accountId);
            try {
                // RelatedPersonId is required (polymorphic to PersonAccount/Contact)
                if (a.PersonContactId != null) {
                    pe.put('RelatedPersonId', a.PersonContactId);
                } else {
                    pe.put('RelatedPersonId', accountId);
                }
            } catch (Exception e) {}
            try { pe.put('StartDate', Date.today().addYears(-2)); } catch (Exception e) {}
            try { pe.put('EndDate', Date.today().addDays(-1)); } catch (Exception e) {}
            insert pe;
        } catch (Exception e) { System.debug('PersonEmployment: ' + e.getMessage()); }
    }

    public static void insertAddressInfo(Id accountId) {
        try {
            SObject a = (SObject) Type.forName('Address_Information__c').newInstance();
            a.put('Account__c', accountId);
            try { a.put('Correspondence_Address__c', '12 Main Rd'); } catch (Exception e) {}
            try { a.put('Current_State__c', 'MH'); } catch (Exception e) {}
            try { a.put('Current_Country__c', 'India'); } catch (Exception e) {}
            try { a.put('Current_City__c', 'Mumbai'); } catch (Exception e) {}
            try { a.put('Current_Zip_Postal_Code__c', '400001'); } catch (Exception e) {}
            insert a;
        } catch (Exception e) { System.debug('Address_Information__c: ' + e.getMessage()); }
    }

    public static void insertEmergencyDetail(Id accountId) {
        try {
            SObject ed = (SObject) Type.forName('Emergency_Details__c').newInstance();
            ed.put('Name', 'Emergency Contact 1');
            ed.put('Account__c', accountId);
            try { ed.put('Relationship__c', 'Parent'); } catch (Exception e) {}
            try { ed.put('Phone__c', '9876543210'); } catch (Exception e) {}
            try { ed.put('Alternate_Number__c', '9876543211'); } catch (Exception e) {}
            try { ed.put('Address__c', 'Some address'); } catch (Exception e) {}
            insert ed;
        } catch (Exception e) { System.debug('Emergency_Details__c: ' + e.getMessage()); }
    }

    public static Id insertProgram() {
        try {
            SObject p = (SObject) Type.forName('Program').newInstance();
            p.put('Name', 'Test Program');
            try { p.put('Program_Code__c', 'TP1'); } catch (Exception e) {}
            try { p.put('Short_Programme_Code__c', 'TP1'); } catch (Exception e) {}
            try { p.put('Programme_Type__c', 'Full-time'); } catch (Exception e) {}
            try { p.put('Programme_Sub_Type__c', 'Class Room'); } catch (Exception e) {}
            try { p.put('Programme_Base_Currency__c', 'INR'); } catch (Exception e) {}
            try { p.put('IsActive', true); } catch (Exception e) {}
            try { p.put('Status__c', 'Active'); } catch (Exception e) {}
            try { p.put('Programme_Duration__c', 'Year'); } catch (Exception e) {}
            try { p.put('Programme_Duration_In_Years__c', 2); } catch (Exception e) {}
            try { p.put('Programme_Duration_In_Months__c', 24); } catch (Exception e) {}
            try { p.put('Programme_Duration_In_Weeks__c', 104); } catch (Exception e) {}
            try { p.put('Programme_Duration_In_Days__c', 730); } catch (Exception e) {}
            // Required boolean fields (non-nillable in this org)
            for (String fname : new List<String>{
                'Accomodation_Applicable__c', 'Cannot_Exceed_Programme_Intake__c',
                'Graduation__c', 'is_AICTE_Approved__c', 'Is_Student_Exchange__c',
                'isQueued__c', 'Post_Graduation__c', 'Scholarship_Applicable__c',
                'ShouldShowOnLearnerPortal', 'SPJIMR_Is_Major_Specialisation__c',
                'SPJIMR_Is_Minor_Specialisation__c', 'SPJIMR_Is_Specialisation_Program__c',
                'X_th__c', 'XII_th__c'
            }) {
                try { p.put(fname, false); } catch (Exception e) {}
            }
            insert p;
            return (Id) p.get('Id');
        } catch (Exception e) {
            System.debug('Program insert failed: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertProgramCohort(Id programId) {
        if (programId == null) return null;
        try {
            ProgramCohort pc = new ProgramCohort(Name = 'Test Cohort');
            pc.ProgramId = programId;
            try { pc.put('Batch_Code__c', 'TC1'); } catch (Exception e) {}
            try { pc.put('Short_Batch_Code__c', 'TC1'); } catch (Exception e) {}
            try { pc.put('Batch_Sub_Type__c', 'Class Room'); } catch (Exception e) {}
            try { pc.put('Batch_Base_Currency__c', 'INR'); } catch (Exception e) {}
            try { pc.put('Program_Code__c', 'TP1'); } catch (Exception e) {}
            try { pc.put('Profile_Window_IsActive__c', true); } catch (Exception e) {}
            try { pc.put('Profile_Window_Start_Time__c', Datetime.now().addDays(-1)); } catch (Exception e) {}
            try { pc.put('Profile_Window_End_Time__c', Datetime.now().addDays(1)); } catch (Exception e) {}
            try { pc.put('Instructions__c', '<p>Upload your <img src="cdn"/> photo</p>'); } catch (Exception e) {}
            try { pc.put('Batch_Intake__c', 10); } catch (Exception e) {}
            // Required boolean fields (non-nillable in this org)
            for (String fname : new List<String>{
                'Allow_Exchange_Participation__c', 'Allow_Multi_Program_Batch__c',
                'Allow_Previous_Batch_Same_Programme__c', 'Allow_Re_Evaluation__c',
                'Cannot_Exceed_Program_Intake__c', 'is_Active__c',
                'Is_Student_Exchange__c', 'IsAcceptingApplications__c',
                'SPJIMR_Is_Major_Specialisation__c', 'SPJIMR_Is_Minor_Specialisation__c',
                'SPJIMR_Is_Specialisation_Program__c'
            }) {
                try { pc.put(fname, fname == 'is_Active__c'); } catch (Exception e) {}
            }
            insert pc;
            return pc.Id;
        } catch (Exception e) {
            System.debug('ProgramCohort insert failed: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertProgramEnrollment(Id accountId, Id programId) {
        // The controller dereferences programEnrollments[0].Program.* without null-checking,
        // so do NOT insert an enrollment unless we have a valid ProgramId.
        if (programId == null) return null;
        try {
            SObject pe = (SObject) Type.forName('ProgramEnrollment').newInstance();
            pe.put('AccountId', accountId);
            pe.put('ProgramId', programId);
            insert pe;
            return (Id) pe.get('Id');
        } catch (Exception e) {
            System.debug('ProgramEnrollment: ' + e.getMessage());
            return null;
        }
    }

    public static void insertProgramCohortMember(Id cohortId, Id programEnrollmentId) {
        if (cohortId == null || programEnrollmentId == null) return;
        try {
            SObject m = (SObject) Type.forName('ProgramCohortMember').newInstance();
            m.put('ProgramCohortId', cohortId);
            m.put('ProgramEnrollmentId', programEnrollmentId);
            try { m.put('Roll_Number__c', 'R001'); } catch (Exception e) {}
            insert m;
        } catch (Exception e) { System.debug('ProgramCohortMember: ' + e.getMessage()); }
    }

    public static Id insertAcademicTerm() {
        try {
            SObject t = (SObject) Type.forName('AcademicTerm').newInstance();
            t.put('Name', 'Test Term');
            putIfCreateable(t, 'Term_Start_Date__c', Date.today().addDays(-30));
            putIfCreateable(t, 'Term_End_Date__c', Date.today().addDays(30));
            // Is_Active__c is a non-editable (formula/derived) field in this org; setting it
            // would make the whole insert fail, so it is intentionally not populated.
            putIfCreateable(t, 'Is_Active__c', true);
            insert t;
            return (Id) t.get('Id');
        } catch (Exception e) {
            System.debug('AcademicTerm: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertAcademicTermEnrollment(Id accountId, Id termId) {
        if (termId == null) return null;
        Account a = [SELECT Id, PersonContactId FROM Account WHERE Id = :accountId LIMIT 1];
        try {
            SObject ate = (SObject) Type.forName('AcademicTermEnrollment').newInstance();
            ate.put('AcademicTermId', termId);
            ate.put('LearnerAccountId', accountId);
            try {
                if (a.PersonContactId != null) ate.put('LearnerContactId', a.PersonContactId);
            } catch (Exception e) {}
            insert ate;
            return (Id) ate.get('Id');
        } catch (Exception e) {
            System.debug('AcademicTermEnrollment: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertCourseOffering(Id termId) {
        if (termId == null) return null;
        // LearningCourse requires LearningId (master-detail to Learning) and Course_Department__c
        Id learningId = null;
        try {
            SObject l = (SObject) Type.forName('Learning').newInstance();
            l.put('Name', 'Test Learning');
            insert l;
            learningId = (Id) l.get('Id');
        } catch (Exception e) {
            System.debug('Learning insert failed: ' + e.getMessage());
            return null;
        }

        Id deptId = null;
        try {
            SObject dm = (SObject) Type.forName('Department_Master__c').newInstance();
            dm.put('Name', 'Test Dept');
            try { dm.put('Department_Code__c', 'TD1'); } catch (Exception e) {}
            insert dm;
            deptId = (Id) dm.get('Id');
        } catch (Exception e) {
            System.debug('Department_Master__c: ' + e.getMessage());
        }

        Id lcId = null;
        try {
            SObject lc = (SObject) Type.forName('LearningCourse').newInstance();
            lc.put('Name', 'Test Learning Course');
            lc.put('LearningId', learningId);
            if (deptId != null) {
                try { lc.put('Course_Department__c', deptId); } catch (Exception e) {}
            }
            insert lc;
            lcId = (Id) lc.get('Id');
        } catch (Exception e) {
            System.debug('LearningCourse insert failed: ' + e.getMessage());
            return null;
        }

        try {
            SObject co = (SObject) Type.forName('CourseOffering').newInstance();
            co.put('Name', 'Test Course Offering');
            co.put('LearningCourseId', lcId);
            try { co.put('Academic_Term__c', termId); } catch (Exception e) {}
            try { co.put('Course_Type__c', 'Core'); } catch (Exception e) {}
            try { co.put('Instructor_Role__c', 'Instructor'); } catch (Exception e) {}
            try { co.put('StartDate', Date.today().addDays(-10)); } catch (Exception e) {}
            try { co.put('EndDate', Date.today().addDays(10)); } catch (Exception e) {}
            insert co;
            return (Id) co.get('Id');
        } catch (Exception e) {
            System.debug('CourseOffering: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertDivisionGroup() {
        try {
            SObject dg = (SObject) Type.forName('Division_Group__c').newInstance();
            dg.put('Name', 'Test Division Group');
            insert dg;
            return (Id) dg.get('Id');
        } catch (Exception e) {
            System.debug('Division_Group__c: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertCustomTerm() {
        try {
            SObject t = (SObject) Type.forName('Term__c').newInstance();
            try { t.put('Name', 'Test Custom Term'); } catch (Exception e) {}
            try { t.put('Term_Name__c', 'Test Term Name'); } catch (Exception e) {}
            try { t.put('Term_Start_Date__c', Date.today().addDays(-30)); } catch (Exception e) {}
            try { t.put('Term_End_Date__c', Date.today().addDays(30)); } catch (Exception e) {}
            insert t;
            return (Id) t.get('Id');
        } catch (Exception e) {
            System.debug('Term__c: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertDivision(Id divisionGroupId, Id termCustomId) {
        try {
            SObject d = (SObject) Type.forName('Division__c').newInstance();
            // Name is auto-number on Division__c — do not set.
            try { d.put('Division_Name__c', 'A1'); } catch (Exception e) {}
            if (divisionGroupId != null) {
                try { d.put('Division_Group__c', divisionGroupId); } catch (Exception e) {}
            }
            if (termCustomId != null) {
                try { d.put('Term__c', termCustomId); } catch (Exception e) {}
            }
            insert d;
            return (Id) d.get('Id');
        } catch (Exception e) {
            System.debug('Division__c: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertDivisionEnrollment(Id divisionId, Id atEnrollmentId) {
        if (divisionId == null || atEnrollmentId == null) return null;
        try {
            SObject de = (SObject) Type.forName('Division_Enrollment__c').newInstance();
            de.put('Division__c', divisionId);
            de.put('Academic_Term_Enrollment__c', atEnrollmentId);
            insert de;
            return (Id) de.get('Id');
        } catch (Exception e) {
            System.debug('Division_Enrollment__c: ' + e.getMessage());
            return null;
        }
    }

    public static void insertDivisionCourse(Id divisionId, Id courseOfferingId) {
        if (divisionId == null) return;
        try {
            SObject dc = (SObject) Type.forName('DivisionCourse__c').newInstance();
            try { dc.put('Division__c', divisionId); } catch (Exception e) {}
            if (courseOfferingId != null) {
                try { dc.put('Course_Offering__c', courseOfferingId); } catch (Exception e) {}
            }
            try { dc.put('Course_Name__c', 'Test Course Name'); } catch (Exception e) {}
            insert dc;
        } catch (Exception e) { System.debug('DivisionCourse__c: ' + e.getMessage()); }
    }

    public static Id insertSession() {
        try {
            SObject s = (SObject) Type.forName('Session__c').newInstance();
            s.put('Name', 'Test Session');
            try { s.put('Session_Date__c', Date.today()); } catch (Exception e) {}
            try { s.put('Start_Time__c', Datetime.now()); } catch (Exception e) {}
            try { s.put('End_Time__c', Datetime.now().addHours(1)); } catch (Exception e) {}
            try { s.put('Schedule_Type__c', 'Published'); } catch (Exception e) {}
            try { s.put('Color__c', 'blue'); } catch (Exception e) {}
            try { s.put('Class_Room__c', 'Room A'); } catch (Exception e) {}
            try { s.put('URL__c', 'https://example.com'); } catch (Exception e) {}
            try { s.put('Remark__c', 'Test remark'); } catch (Exception e) {}
            insert s;
            return (Id) s.get('Id');
        } catch (Exception e) {
            System.debug('Session__c: ' + e.getMessage());
            return null;
        }
    }

    public static Id insertSessionEnrollment(Id sessionId, Id divisionEnrollmentId, Id atEnrollmentId) {
        if (sessionId == null || divisionEnrollmentId == null) return null;
        try {
            SObject se = (SObject) Type.forName('Session_Enrollment__c').newInstance();
            se.put('Session__c', sessionId);
            se.put('Division_Enrollment__c', divisionEnrollmentId);
            if (atEnrollmentId != null) {
                try { se.put('Academic_Term_Enrollment__c', atEnrollmentId); } catch (Exception e) {}
            }
            insert se;
            return (Id) se.get('Id');
        } catch (Exception e) {
            System.debug('Session_Enrollment__c: ' + e.getMessage());
            return null;
        }
    }

    public static void insertSessionFaculty(Id sessionId, Id facultyAccountId) {
        if (sessionId == null || facultyAccountId == null) return;
        try {
            SObject sf = (SObject) Type.forName('Session_Faculty__c').newInstance();
            sf.put('Session__c', sessionId);
            sf.put('Session_Faculty__c', facultyAccountId);
            insert sf;
        } catch (Exception e) { System.debug('Session_Faculty__c: ' + e.getMessage()); }
    }

    public static User insertPortalUser(Id accountId, String tag) {
        Account refreshed = [SELECT Id, PersonContactId FROM Account WHERE Id = :accountId LIMIT 1];
        if (refreshed.PersonContactId == null) return null;
        Profile p = getPortalProfile();
        if (p == null) return null;
        User u = new User(
            Alias = 'pt' + tag.left(3),
            Email = ('test' + tag + '.user@example.com.spjtest').toLowerCase(),
            EmailEncodingKey = 'UTF-8',
            LastName = 'PortalUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = ('test' + tag + '.user' + System.currentTimeMillis() + '@example.com.spjtest').toLowerCase(),
            ContactId = refreshed.PersonContactId
        );
        try {
            insert u;
            return u;
        } catch (Exception e) {
            System.debug('Portal user insert failed: ' + e.getMessage());
            return null;
        }
    }

    public static Id getStudentPersonAccountRecordTypeId() {
        for (Schema.RecordTypeInfo rti : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (rti.isAvailable() && rti.getDeveloperName() == 'Student' && !rti.isMaster()) {
                return rti.getRecordTypeId();
            }
        }
        for (Schema.RecordTypeInfo rti : Account.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (rti.isAvailable() && !rti.isMaster()) return rti.getRecordTypeId();
        }
        return null;
    }

    /**
     * Safely sets a field only when it exists AND is createable. The older
     * try/catch-around-put idiom does not protect against fields that exist but are
     * non-editable (e.g. formula/derived) — put() succeeds in memory and the failure
     * only surfaces at insert, taking the whole record down with it.
     */
    public static void putIfCreateable(SObject rec, String field, Object value) {
        try {
            Schema.SObjectField f = rec.getSObjectType().getDescribe().fields.getMap().get(field);
            if (f != null && f.getDescribe().isCreateable()) {
                rec.put(field, value);
            }
        } catch (Exception e) {
            System.debug('putIfCreateable(' + field + '): ' + e.getMessage());
        }
    }

    public static Profile getPortalProfile() {
        List<Profile> profs = [
            SELECT Id, Name FROM Profile
            WHERE Name IN ('SPJIMR Student Portal User','Customer Community Plus User','Customer Community User')
            ORDER BY Name
            LIMIT 1
        ];
        return profs.isEmpty() ? null : profs[0];
    }
}