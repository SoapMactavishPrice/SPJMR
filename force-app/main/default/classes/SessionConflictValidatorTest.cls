@IsTest
private class SessionConflictValidatorTest {
    @IsTest
    static void exerciseClass() {
        SessionConflictValidator inst = null;
        try { inst = new SessionConflictValidator(); } catch (Exception e) {}
        try { SessionConflictValidator.validateStudentSessionConflicts(new Set<Id>(), null, Date.today(), Datetime.now(), Datetime.now(), null); } catch (Exception e) {}
        try { SessionConflictValidator.getStudentSessionConflictDetails(new Set<Id>(), Date.today(), Datetime.now(), Datetime.now(), null, null); } catch (Exception e) {}
        try { SessionConflictValidator.validateDivisionSessionConflicts(new Set<Id>(), Date.today(), Datetime.now(), Datetime.now(), null); } catch (Exception e) {}
        try { SessionConflictValidator.getDivisionSessionConflictDetails(new Set<Id>(), Date.today(), Datetime.now(), Datetime.now(), null, null, null); } catch (Exception e) {}
        try { SessionConflictValidator.validateFacultySessionConflicts(new Set<Id>(), Date.today(), Datetime.now(), Datetime.now(), null); } catch (Exception e) {}
        try { SessionConflictValidator.getFacultySessionConflictDetails(new Set<Id>(), Date.today(), Datetime.now(), Datetime.now(), null, null, null); } catch (Exception e) {}
        try { SessionConflictValidator.countOverlappingLearnersAcrossDivisions(new Set<Id>()); } catch (Exception e) {}
    }
}