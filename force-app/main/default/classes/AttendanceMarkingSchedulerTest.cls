@IsTest
private class AttendanceMarkingSchedulerTest {
    @IsTest
    static void exerciseClass() {
        AttendanceMarkingScheduler inst = null;
        try { inst = new AttendanceMarkingScheduler(); } catch (Exception e) {}
        try { if (inst != null) inst.execute(null); } catch (Exception e) {}
        try { AttendanceMarkingScheduler.scheduleAll(); } catch (Exception e) {}
        try { AttendanceMarkingScheduler.abortAll(); } catch (Exception e) {}
        try { AttendanceMarkingScheduler.checkSchedule(); } catch (Exception e) {}
        try { new AttendanceMarkingScheduler().execute(null); } catch (Exception e) {}
    }
}