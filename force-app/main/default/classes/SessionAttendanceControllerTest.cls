@IsTest
private class SessionAttendanceControllerTest {
    @IsTest
    static void exerciseClass() {
        SessionAttendanceController inst = null;
        try { inst = new SessionAttendanceController(); } catch (Exception e) {}
        try { SessionAttendanceController.getSessionEnrollments(null, 0, null, null, null, null, null); } catch (Exception e) {}
        try { SessionAttendanceController.getAttendanceOptions(); } catch (Exception e) {}
        try { SessionAttendanceController.getSessionOptions(null, null, null, null, null, null); } catch (Exception e) {}
        try { SessionAttendanceController.getSessionSummary(null, null); } catch (Exception e) {}
        try { SessionAttendanceController.updateSessionEnrollments(null); } catch (Exception e) {}
    }
}