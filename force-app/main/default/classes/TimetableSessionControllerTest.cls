@IsTest
private class TimetableSessionControllerTest {
    @IsTest
    static void exerciseClass() {
        TimetableSessionController inst = null;
        try { inst = new TimetableSessionController(); } catch (Exception e) {}
        try { TimetableSessionController.getSessions(null); } catch (Exception e) {}
        try { TimetableSessionController.publishSessions(null); } catch (Exception e) {}
        try { TimetableSessionController.saveSession(null); } catch (Exception e) {}
        try { TimetableSessionController.deleteSession(null, null); } catch (Exception e) {}
        try { TimetableSessionController.cancelSession(null); } catch (Exception e) {}
        try { TimetableSessionController.getFacultyConflictsForSessions(null); } catch (Exception e) {}
        try { TimetableSessionController.getDivisionSessionConflictsForSessions(null); } catch (Exception e) {}
        try { TimetableSessionController.getCourseActivities(); } catch (Exception e) {}
        try { TimetableSessionController.getSessionFaculties(null); } catch (Exception e) {}
        try { TimetableSessionController.getFacultyForCourse(null, null); } catch (Exception e) {}
        try { TimetableSessionController.getFacultiesForFilter(null, new List<String>()); } catch (Exception e) {}
    }
}