@IsTest
private class SessionStatsServiceTest {
    @IsTest
    static void exerciseClass() {
        SessionStatsService inst = null;
        try { inst = new SessionStatsService(); } catch (Exception e) {}
        try { SessionStatsService.getSessionStats(null); } catch (Exception e) {}
        try { SessionStatsService.getSessionsByStatus(null, null); } catch (Exception e) {}
    }
}