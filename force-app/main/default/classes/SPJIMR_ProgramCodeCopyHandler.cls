/**
* @description Copies Program.Program_Code__c onto child objects' Program_code__c (20-char text fields).
* Used from BatchGroup, Academic Term, Program Enrollment, Batch Specialisation, Division, and related triggers.
*/
public without sharing class SPJIMR_ProgramCodeCopyHandler {
    private static final Integer PROGRAM_CODE_MAX_LEN = 20;
    
    private static String truncateProgramCode(String code) {
        if (String.isBlank(code)) {
            return code;
        }
        return code.length() > PROGRAM_CODE_MAX_LEN
            ? code.substring(0, PROGRAM_CODE_MAX_LEN)
            : code;
    }
    
    /**
* AcademicYear: Batch → Program, else Programme Master lookup.
*/
    public static void syncAcademicYear(List<AcademicYear> newList, Map<Id, AcademicYear> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> batchIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        for (AcademicYear ay : newList) {
            if (ay.Batch__c != null) {
                batchIds.add(ay.Batch__c);
            } else if (ay.Program_Master__c != null) {
                programIds.add(ay.Program_Master__c);
            }
        }
        Map<Id, String> programCodeByBatchId = loadProgramCodeByProgramCohortId(batchIds);
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (AcademicYear ay : newList) {
            if (ay.Batch__c != null) {
                String code = programCodeByBatchId.get(ay.Batch__c);
                if (String.isNotBlank(code)) {
                    ay.Program_code__c = truncateProgramCode(code);
                }
            } else if (ay.Program_Master__c != null) {
                String code = programCodeByProgramId.get(ay.Program_Master__c);
                if (String.isNotBlank(code)) {
                    ay.Program_code__c = truncateProgramCode(code);
                }
            }
        }
    }
    
    /**
* AcademicTerm: Batch (ProgramCohort) first, else Academic Year (batch group), else Programme Name lookup.
*
* @param newList Terms in the trigger context.
* @param oldMap Prior values on update; null on insert.
*/
    public static void syncAcademicTerm(List<AcademicTerm> newList, Map<Id, AcademicTerm> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        List<AcademicTerm> termsToSync = new List<AcademicTerm>();
        Set<Id> cohortIds = new Set<Id>();
        Set<Id> academicYearIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        for (AcademicTerm term : newList) {
            AcademicTerm oldTerm = oldMap == null ? null : oldMap.get(term.Id);
            if (!shouldSyncAcademicTermProgramCode(term, oldTerm)) {
                continue;
            }
            termsToSync.add(term);
            if (term.Batch_Name__c != null) {
                cohortIds.add(term.Batch_Name__c);
            }
            if (term.AcademicYearId != null) {
                academicYearIds.add(term.AcademicYearId);
            }
            if (term.Program_Name__c != null) {
                programIds.add(term.Program_Name__c);
            }
        }
        if (termsToSync.isEmpty()) {
            return;
        }
        Map<Id, String> programCodeByCohortId = loadProgramCodeByProgramCohortId(cohortIds);
        Map<Id, String> programCodeByAcademicYearId = loadProgramCodeByAcademicYearId(academicYearIds);
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (AcademicTerm term : termsToSync) {
            String code = null;
            if (term.Batch_Name__c != null) {
                code = programCodeByCohortId.get(term.Batch_Name__c);
            }
            if (String.isBlank(code) && term.AcademicYearId != null) {
                code = programCodeByAcademicYearId.get(term.AcademicYearId);
            }
            if (String.isBlank(code) && term.Program_Name__c != null) {
                code = programCodeByProgramId.get(term.Program_Name__c);
            }
            if (String.isNotBlank(code)) {
                term.Program_code__c = code;
            }
        }
    }
    
    /**
* Division__c: Term → Academic Year → Batch → Program.
*/
    public static void syncDivision(List<Division__c> newList, Map<Id, Division__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> termIds = new Set<Id>();
        for (Division__c d : newList) {
            if (d.Term__c != null) {
                termIds.add(d.Term__c);
            }
        }
        if (termIds.isEmpty()) {
            return;
        }
        Map<Id, String> codeByTermId = new Map<Id, String>();
        for (AcademicTerm t : [
            SELECT Id, AcademicYear.Batch__r.Program.Program_Code__c
            FROM AcademicTerm
            WHERE Id IN :termIds
        ]) {
            if (t.AcademicYear != null
                && t.AcademicYear.Batch__r != null
                && t.AcademicYear.Batch__r.Program != null
                && String.isNotBlank(t.AcademicYear.Batch__r.Program.Program_Code__c)) {
                    codeByTermId.put(
                        t.Id,
                        truncateProgramCode(t.AcademicYear.Batch__r.Program.Program_Code__c)
                    );
                }
        }
        for (Division__c d : newList) {
            if (d.Term__c != null && codeByTermId.containsKey(d.Term__c)) {
                d.Program_code__c = codeByTermId.get(d.Term__c);
            }
        }
    }
    
    /**
* Campus__c: Program_Name__c is the lookup to Program.
*/
    public static void syncCampus(List<Campus__c> newList, Map<Id, Campus__c> oldMap) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> programIds = new Set<Id>();
        for (Campus__c c : newList) {
            if (c.Program_Name__c != null) {
                programIds.add(c.Program_Name__c);
            }
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (Campus__c c : newList) {
            if (c.Program_Name__c != null && programCodeByProgramId.containsKey(c.Program_Name__c)) {
                c.Program_code__c = programCodeByProgramId.get(c.Program_Name__c);
            }
        }
    }
    
    /**
* Division_Group__c: requires Program_Master__c (lookup to Program).
*/
    // public static void syncDivisionGroup(List<Division_Group__c> newList, Map<Id, Division_Group__c> oldMap) {
    //     if (newList == null || newList.isEmpty()) {
    //         return;
    //     }
    //     Set<Id> programIds = new Set<Id>();
    //     for (Division_Group__c dg : newList) {
    //         if (dg.Program_Master__c != null) {
    //             programIds.add(dg.Program_Master__c);
    //         }
    //     }
    //     Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
    //     for (Division_Group__c dg : newList) {
    //         if (dg.Program_Master__c != null && programCodeByProgramId.containsKey(dg.Program_Master__c)) {
    //             dg.Program_code__c = programCodeByProgramId.get(dg.Program_Master__c);
    //         }
    //     }
    // }
    
    /**
* Specialisation_Master__c: requires Program_Master__c (lookup to Program).
*/
    // public static void syncSpecialisationMaster(
    //     List<Specialisation_Master__c> newList,
    //     Map<Id, Specialisation_Master__c> oldMap
    // ) {
    //     if (newList == null || newList.isEmpty()) {
    //         return;
    //     }
    //     Set<Id> programIds = new Set<Id>();
    //     for (Specialisation_Master__c sm : newList) {
    //         if (sm.Program_Master__c != null) {
    //             programIds.add(sm.Program_Master__c);
    //         }
    //     }
    //     Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
    //     for (Specialisation_Master__c sm : newList) {
    //         if (sm.Program_Master__c != null && programCodeByProgramId.containsKey(sm.Program_Master__c)) {
    //             sm.Program_code__c = programCodeByProgramId.get(sm.Program_Master__c);
    //         }
    //     }
    // }
    
    /**
* Session_Faculty__c: Session__c -> Program__c.
*/
    public static void syncSessionFaculty(
        List<Session_Faculty__c> newList,
        Map<Id, Session_Faculty__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> sessionIds = new Set<Id>();
        for (Session_Faculty__c sf : newList) {
            if (sf.Session__c != null) {
                sessionIds.add(sf.Session__c);
            }
        }
        if (sessionIds.isEmpty()) {
            return;
        }
        Set<Id> programIds = new Set<Id>();
        Map<Id, Id> programIdBySessionId = new Map<Id, Id>();
        for (Session__c s : [
            SELECT Id, Program__c
            FROM Session__c
            WHERE Id IN :sessionIds
        ]) {
            if (s.Program__c != null) {
                programIdBySessionId.put(s.Id, s.Program__c);
                programIds.add(s.Program__c);
            }
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (Session_Faculty__c sf : newList) {
            if (sf.Session__c == null) {
                continue;
            }
            Id programId = programIdBySessionId.get(sf.Session__c);
            if (programId != null && programCodeByProgramId.containsKey(programId)) {
                sf.Program_code__c = programCodeByProgramId.get(programId);
            }
        }
    }
    
    /**
* Program_Courses__c: Program_Master__c lookup to Program.
*/
    public static void syncProgramCourses(
        List<Program_Courses__c> newList,
        Map<Id, Program_Courses__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> programIds = new Set<Id>();
        for (Program_Courses__c pc : newList) {
            if (pc.Program_Master__c != null) {
                programIds.add(pc.Program_Master__c);
            }
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (Program_Courses__c pc : newList) {
            if (pc.Program_Master__c != null && programCodeByProgramId.containsKey(pc.Program_Master__c)) {
                pc.Program_code__c = programCodeByProgramId.get(pc.Program_Master__c);
            }
        }
    }
    
    /**
* Specialisation__c (Batch Specialisation): Batch__c → Program__c and Program_code__c;
* Program__c → Program_code__c when batch is not set.
*
* @param newList Batch specialisation rows in the trigger context.
* @param oldMap Prior values on update; null on insert.
*/
    public static void syncBatchSpecialisation(
        List<Specialisation__c> newList,
        Map<Id, Specialisation__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        List<Specialisation__c> specsToSync = new List<Specialisation__c>();
        Set<Id> batchIds = new Set<Id>();
        for (Specialisation__c spec : newList) {
            Specialisation__c oldSpec = oldMap == null ? null : oldMap.get(spec.Id);
            if (!shouldSyncBatchSpecialisation(spec, oldSpec)) {
                continue;
            }
            if (spec.Batch__c == null && spec.Program__c == null) {
                continue;
            }
            specsToSync.add(spec);
            if (spec.Batch__c != null) {
                batchIds.add(spec.Batch__c);
            }
        }
        if (specsToSync.isEmpty()) {
            return;
        }
        Map<Id, Id> programIdByBatchId = loadProgramIdByProgramCohortId(batchIds);
        for (Specialisation__c spec : specsToSync) {
            if (spec.Batch__c != null && programIdByBatchId.containsKey(spec.Batch__c)) {
                spec.Program__c = programIdByBatchId.get(spec.Batch__c);
            }
        }
        Set<Id> programIds = new Set<Id>();
        for (Specialisation__c spec : specsToSync) {
            if (spec.Program__c != null) {
                programIds.add(spec.Program__c);
            }
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        Map<Id, String> programCodeByBatchId = loadProgramCodeByProgramCohortId(batchIds);
        for (Specialisation__c spec : specsToSync) {
            String code = null;
            if (spec.Program__c != null) {
                code = programCodeByProgramId.get(spec.Program__c);
            }
            if (String.isBlank(code) && spec.Batch__c != null) {
                code = programCodeByBatchId.get(spec.Batch__c);
            }
            if (String.isNotBlank(code)) {
                spec.Program_code__c = code;
            }
        }
    }
    
    /**
* ProgramEnrollment: ProgramId → Program, else Batch__c (ProgramCohort).
*
* @param newList Enrollments in the trigger context.
* @param oldMap Prior values on update; null on insert.
*/
    public static void syncProgramEnrollment(
        List<ProgramEnrollment> newList,
        Map<Id, ProgramEnrollment> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        List<ProgramEnrollment> enrollmentsToSync = new List<ProgramEnrollment>();
        Set<Id> programIds = new Set<Id>();
        Set<Id> batchIds = new Set<Id>();
        for (ProgramEnrollment pe : newList) {
            ProgramEnrollment oldPe = oldMap == null ? null : oldMap.get(pe.Id);
            if (!shouldSyncProgramEnrollmentProgramCode(pe, oldPe)) {
                continue;
            }
            enrollmentsToSync.add(pe);
            if (pe.ProgramId != null) {
                programIds.add(pe.ProgramId);
            }
            if (pe.Batch__c != null) {
                batchIds.add(pe.Batch__c);
            }
        }
        if (enrollmentsToSync.isEmpty()) {
            return;
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        Map<Id, String> programCodeByBatchId = loadProgramCodeByProgramCohortId(batchIds);
        for (ProgramEnrollment pe : enrollmentsToSync) {
            String code = null;
            if (pe.ProgramId != null) {
                code = programCodeByProgramId.get(pe.ProgramId);
            }
            if (String.isBlank(code) && pe.Batch__c != null) {
                code = programCodeByBatchId.get(pe.Batch__c);
            }
            if (String.isNotBlank(code)) {
                pe.Program_code__c = code;
            }
        }
    }
    
    /**
* CourseOffering: use Program_code__c from associated Academic Term.
*/
    public static void syncCourseOffering(
        List<CourseOffering> newList,
        Map<Id, CourseOffering> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> termIds = new Set<Id>();
        for (CourseOffering co : newList) {
            if (co.Academic_Term__c != null) {
                termIds.add(co.Academic_Term__c);
            }
        }
        if (termIds.isEmpty()) {
            return;
        }
        Map<Id, String> programCodeByTermId = new Map<Id, String>();
        for (AcademicTerm term : [
            SELECT Id, Program_code__c
            FROM AcademicTerm
            WHERE Id IN :termIds
        ]) {
            if (String.isNotBlank(term.Program_code__c)) {
                programCodeByTermId.put(term.Id, truncateProgramCode(term.Program_code__c));
            }
        }
        for (CourseOffering co : newList) {
            if (co.Academic_Term__c != null && programCodeByTermId.containsKey(co.Academic_Term__c)) {
                co.Program_code__c = programCodeByTermId.get(co.Academic_Term__c);
            }
        }
    }
    
    /**
* ProgramCohortMember: use Program_Code__c from associated Batch (ProgramCohort).
*/
    public static void syncProgramCohortMember(
        List<ProgramCohortMember> newList,
        Map<Id, ProgramCohortMember> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> batchIds = new Set<Id>();
        for (ProgramCohortMember pcm : newList) {
            if (pcm.ProgramCohortId != null) {
                batchIds.add(pcm.ProgramCohortId);
            }
        }
        if (batchIds.isEmpty()) {
            return;
        }
        Map<Id, String> programCodeByBatchId = new Map<Id, String>();
        for (ProgramCohort batch : [
            SELECT Id, Program_Code__c
            FROM ProgramCohort
            WHERE Id IN :batchIds
        ]) {
            if (String.isNotBlank(batch.Program_Code__c)) {
                programCodeByBatchId.put(batch.Id, truncateProgramCode(batch.Program_Code__c));
            }
        }
        for (ProgramCohortMember pcm : newList) {
            if (pcm.ProgramCohortId != null && programCodeByBatchId.containsKey(pcm.ProgramCohortId)) {
                pcm.Program_code__c = programCodeByBatchId.get(pcm.ProgramCohortId);
            }
        }
    }
    
    /**
* AcademicTermEnrollment: use Program_code__c from associated Academic Term.
*/
    public static void syncAcademicTermEnrollment(
        List<AcademicTermEnrollment> newList,
        Map<Id, AcademicTermEnrollment> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> termIds = new Set<Id>();
        for (AcademicTermEnrollment ate : newList) {
            if (ate.AcademicTermId != null) {
                termIds.add(ate.AcademicTermId);
            }
        }
        if (termIds.isEmpty()) {
            return;
        }
        Map<Id, String> programCodeByTermId = new Map<Id, String>();
        for (AcademicTerm term : [
            SELECT Id, Program_code__c
            FROM AcademicTerm
            WHERE Id IN :termIds
        ]) {
            if (String.isNotBlank(term.Program_code__c)) {
                programCodeByTermId.put(term.Id, truncateProgramCode(term.Program_code__c));
            }
        }
        for (AcademicTermEnrollment ate : newList) {
            if (ate.AcademicTermId != null && programCodeByTermId.containsKey(ate.AcademicTermId)) {
                ate.Program_code__c = programCodeByTermId.get(ate.AcademicTermId);
            }
        }
    }
    
    /**
* CampusProgram__c: Program_Master__c lookup to Program.
*
* @param newList Campus program rows in the trigger context.
* @param oldMap Prior values on update; null on insert.
*/
    public static void syncCampusProgram(
        List<CampusProgram__c> newList,
        Map<Id, CampusProgram__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        List<CampusProgram__c> campusProgramsToSync = new List<CampusProgram__c>();
        Set<Id> programIds = new Set<Id>();
        for (CampusProgram__c cp : newList) {
            CampusProgram__c oldCp = oldMap == null ? null : oldMap.get(cp.Id);
            if (!shouldSyncCampusProgramProgramCode(cp, oldCp)) {
                continue;
            }
            if (cp.Program_Master__c == null) {
                continue;
            }
            campusProgramsToSync.add(cp);
            programIds.add(cp.Program_Master__c);
        }
        if (campusProgramsToSync.isEmpty()) {
            return;
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (CampusProgram__c cp : campusProgramsToSync) {
            if (programCodeByProgramId.containsKey(cp.Program_Master__c)) {
                cp.Program_code__c = programCodeByProgramId.get(cp.Program_Master__c);
            }
        }
    }
    
    /**
* Session__c: Program__c lookup to Program.
*/
    public static void syncSession(
        List<Session__c> newList,
        Map<Id, Session__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> programIds = new Set<Id>();
        for (Session__c s : newList) {
            if (s.Program__c != null) {
                programIds.add(s.Program__c);
            }
        }
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (Session__c s : newList) {
            if (s.Program__c != null && programCodeByProgramId.containsKey(s.Program__c)) {
                s.Program_code__c = programCodeByProgramId.get(s.Program__c);
            }
        }
    }
    
    /**
* Session_Division__c: copy program code from parent Session__c (Session.Program_code__c or Programme lookup).
*/
    public static void syncSessionDivision(
        List<Session_Division__c> newList,
        Map<Id, Session_Division__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> sessionIds = new Set<Id>();
        for (Session_Division__c sd : newList) {
            if (sd.Session__c != null) {
                sessionIds.add(sd.Session__c);
            }
        }
        if (sessionIds.isEmpty()) {
            return;
        }
        Map<Id, String> codeBySessionId = new Map<Id, String>();
        for (Session__c sess : [
            SELECT Id, Program_code__c, Program__c, Program__r.Program_Code__c
            FROM Session__c
            WHERE Id IN :sessionIds
        ]) {
            String code;
            if (String.isNotBlank(sess.Program_code__c)) {
                code = truncateProgramCode(sess.Program_code__c);
            } else if (sess.Program__c != null && String.isNotBlank(sess.Program__r.Program_Code__c)) {
                code = truncateProgramCode(sess.Program__r.Program_Code__c);
            }
            if (String.isNotBlank(code)) {
                codeBySessionId.put(sess.Id, code);
            }
        }
        for (Session_Division__c sd : newList) {
            if (sd.Session__c != null && codeBySessionId.containsKey(sd.Session__c)) {
                sd.Program_code__c = codeBySessionId.get(sd.Session__c);
            }
        }
    }
    
    /**
* Session_Enrollment__c: Academic_Term_Enrollment__c → Academic Term program code (or batch → Program fallback).
*/
    public static void syncSessionEnrollment(
        List<Session_Enrollment__c> newList,
        Map<Id, Session_Enrollment__c> oldMap
    ) {
        if (newList == null || newList.isEmpty()) {
            return;
        }
        Set<Id> termEnrollmentIds = new Set<Id>();
        for (Session_Enrollment__c se : newList) {
            if (se.Academic_Term_Enrollment__c != null) {
                termEnrollmentIds.add(se.Academic_Term_Enrollment__c);
            }
        }
        if (termEnrollmentIds.isEmpty()) {
            return;
        }
        Map<Id, String> codeByTermEnrollmentId = new Map<Id, String>();
        for (AcademicTermEnrollment ate : [
            SELECT Id,
            AcademicTerm.Program_code__c,
            AcademicTerm.AcademicYear.Batch__r.Program.Program_Code__c
            FROM AcademicTermEnrollment
            WHERE Id IN :termEnrollmentIds
        ]) {
            String code;
            if (ate.AcademicTerm != null && String.isNotBlank(ate.AcademicTerm.Program_code__c)) {
                code = truncateProgramCode(ate.AcademicTerm.Program_code__c);
            } else if (ate.AcademicTerm != null
                       && ate.AcademicTerm.AcademicYear != null
                       && ate.AcademicTerm.AcademicYear.Batch__r != null
                       && ate.AcademicTerm.AcademicYear.Batch__r.Program != null
                       && String.isNotBlank(ate.AcademicTerm.AcademicYear.Batch__r.Program.Program_Code__c)) {
                           code = truncateProgramCode(ate.AcademicTerm.AcademicYear.Batch__r.Program.Program_Code__c);
                       }
            if (String.isNotBlank(code)) {
                codeByTermEnrollmentId.put(ate.Id, code);
            }
        }
        for (Session_Enrollment__c se : newList) {
            if (se.Academic_Term_Enrollment__c != null
                && codeByTermEnrollmentId.containsKey(se.Academic_Term_Enrollment__c)) {
                    se.Program_code__c = codeByTermEnrollmentId.get(se.Academic_Term_Enrollment__c);
                }
        }
    }
    
    /**
* Whether Program Enrollment parent lookups changed and program code should be refreshed.
*
* @param pe Current enrollment row.
* @param oldPe Prior enrollment row on update; null on insert.
* @return True when program code should be recomputed.
*/
    private static Boolean shouldSyncProgramEnrollmentProgramCode(
        ProgramEnrollment pe,
        ProgramEnrollment oldPe
    ) {
        if (oldPe == null) {
            return true;
        }
        return pe.ProgramId != oldPe.ProgramId || pe.Batch__c != oldPe.Batch__c;
    }
    
    /**
* Whether Batch Specialisation parent lookups changed and programme fields should refresh.
*
* @param spec Current batch specialisation row.
* @param oldSpec Prior row on update; null on insert.
* @return True when Program__c / Program_code__c should be recomputed.
*/
    /**
* Whether Campus Program programme master changed and program code should be refreshed.
*
* @param cp Current campus program row.
* @param oldCp Prior row on update; null on insert.
* @return True when program code should be recomputed.
*/
    private static Boolean shouldSyncCampusProgramProgramCode(
        CampusProgram__c cp,
        CampusProgram__c oldCp
    ) {
        if (oldCp == null) {
            return true;
        }
        return cp.Program_Master__c != oldCp.Program_Master__c;
    }
    
    private static Boolean shouldSyncBatchSpecialisation(
        Specialisation__c spec,
        Specialisation__c oldSpec
    ) {
        if (oldSpec == null) {
            return true;
        }
        return spec.Batch__c != oldSpec.Batch__c || spec.Program__c != oldSpec.Program__c;
    }
    
    /**
* Resolves Program Id per Program Cohort (batch).
*
* @param cohortIds Program cohort Ids referenced on batch specialisations.
* @return Program Id by cohort Id.
*/
    private static Map<Id, Id> loadProgramIdByProgramCohortId(Set<Id> cohortIds) {
        Map<Id, Id> outMap = new Map<Id, Id>();
        if (cohortIds == null || cohortIds.isEmpty()) {
            return outMap;
        }
        for (ProgramCohort pc : [SELECT Id, ProgramId FROM ProgramCohort WHERE Id IN :cohortIds]) {
            if (pc.ProgramId != null) {
                outMap.put(pc.Id, pc.ProgramId);
            }
        }
        return outMap;
    }
    
    /**
* Whether Academic Term parent lookups changed and program code should be refreshed.
*
* @param term Current term row.
* @param oldTerm Prior term row on update; null on insert.
* @return True when program code should be recomputed.
*/
    private static Boolean shouldSyncAcademicTermProgramCode(AcademicTerm term, AcademicTerm oldTerm) {
        if (oldTerm == null) {
            return true;
        }
        return term.Batch_Name__c != oldTerm.Batch_Name__c
            || term.AcademicYearId != oldTerm.AcademicYearId
            || term.Program_Name__c != oldTerm.Program_Name__c;
    }
    
    /**
* Resolves program code per Academic Year: Batch → Program, else Programme Master lookup.
*
* @param academicYearIds Academic year Ids referenced on terms.
* @return Program code by Academic Year Id.
*/
    private static Map<Id, String> loadProgramCodeByAcademicYearId(Set<Id> academicYearIds) {
        Map<Id, String> outMap = new Map<Id, String>();
        if (academicYearIds == null || academicYearIds.isEmpty()) {
            return outMap;
        }
        Set<Id> batchIds = new Set<Id>();
        Set<Id> programIds = new Set<Id>();
        Map<Id, AcademicYear> academicYearById = new Map<Id, AcademicYear>([
            SELECT Id, Batch__c, Program_Master__c
            FROM AcademicYear
            WHERE Id IN :academicYearIds
        ]);
        for (AcademicYear ay : academicYearById.values()) {
            if (ay.Batch__c != null) {
                batchIds.add(ay.Batch__c);
            } else if (ay.Program_Master__c != null) {
                programIds.add(ay.Program_Master__c);
            }
        }
        Map<Id, String> programCodeByBatchId = loadProgramCodeByProgramCohortId(batchIds);
        Map<Id, String> programCodeByProgramId = loadProgramCodeByProgramId(programIds);
        for (AcademicYear ay : academicYearById.values()) {
            String code = null;
            if (ay.Batch__c != null) {
                code = programCodeByBatchId.get(ay.Batch__c);
            }
            if (String.isBlank(code) && ay.Program_Master__c != null) {
                code = programCodeByProgramId.get(ay.Program_Master__c);
            }
            if (String.isNotBlank(code)) {
                outMap.put(ay.Id, code);
            }
        }
        return outMap;
    }
    
    private static Map<Id, String> loadProgramCodeByProgramCohortId(Set<Id> cohortIds) {
        Map<Id, String> outMap = new Map<Id, String>();
        if (cohortIds == null || cohortIds.isEmpty()) {
            return outMap;
        }
        for (ProgramCohort pc : [
            SELECT Id, Program.Program_Code__c
            FROM ProgramCohort
            WHERE Id IN :cohortIds
        ]) {
            if (pc.Program != null && String.isNotBlank(pc.Program.Program_Code__c)) {
                outMap.put(pc.Id, truncateProgramCode(pc.Program.Program_Code__c));
            }
        }
        return outMap;
    }
    
    private static Map<Id, String> loadProgramCodeByProgramId(Set<Id> programIds) {
        Map<Id, String> outMap = new Map<Id, String>();
        if (programIds == null || programIds.isEmpty()) {
            return outMap;
        }
        for (Program p : [SELECT Id, Program_Code__c FROM Program WHERE Id IN :programIds]) {
            if (String.isNotBlank(p.Program_Code__c)) {
                outMap.put(p.Id, truncateProgramCode(p.Program_Code__c));
            }
        }
        return outMap;
    }
  /**
     * @description Prevents deletion of Program Course records that are already assigned
     *              at the Division level.
     *
     *              A Program Course can be assigned to a Term through a Course Offering.
     *              When a Course Offering is further assigned to a Division, a Division Course
     *              record is created. If any Division Course exists for a Program Course,
     *              deletion of that Program Course is restricted.
     *
     * @param programCourses List of Program Course records being deleted.
     */
    public static void preventProgramCourseDelete(List<Program_Courses__c> programCourses) {
        Set<Id> programCourseIds = new Set<Id>();

        for (Program_Courses__c pc : programCourses) {
            programCourseIds.add(pc.Id);
        }

        Map<Id, Id> courseOfferingToProgramCourse = new Map<Id, Id>();

        for (CourseOffering co : [
            SELECT Id, ProgramCourse__c
            FROM CourseOffering
            WHERE ProgramCourse__c IN :programCourseIds
        ]) {
            courseOfferingToProgramCourse.put(
                co.Id,
                co.ProgramCourse__c
            );
        }

        if (courseOfferingToProgramCourse.isEmpty()) {
            return;
        }

        Set<Id> restrictedProgramCourseIds = new Set<Id>();

        for (DivisionCourse__c dc : [
            SELECT Id, Course_Offering__c
            FROM DivisionCourse__c
            WHERE Course_Offering__c IN :courseOfferingToProgramCourse.keySet()
        ]) {
            restrictedProgramCourseIds.add(
                courseOfferingToProgramCourse.get(dc.Course_Offering__c)
            );
        }

        for (Program_Courses__c pc : programCourses) {
            if (restrictedProgramCourseIds.contains(pc.Id)) {
                pc.addError(
                    'This Program Course is assigned at the Division level and cannot be deleted.'
                );
            }
        }
    }
}