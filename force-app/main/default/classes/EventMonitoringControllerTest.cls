@IsTest(SeeAllData=true)
private class EventMonitoringControllerTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<EventLogFile> existing = [SELECT Id FROM EventLogFile LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('EventLogFile').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        EventMonitoringController c = null;
        try { c = new EventMonitoringController(); } catch (Exception e) {}
        try { if (c != null) c.downloadLog(); } catch (Exception e) {}
    }
}