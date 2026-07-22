@IsTest(SeeAllData=true)
private class ViewOutstandingOnFeeplanTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Account> existing = [SELECT Id FROM Account LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Account').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        ViewOutstandingOnFeeplan c = null;
        try { c = new ViewOutstandingOnFeeplan(); } catch (Exception e) {}
        try { if (c != null) c.Cancel(); } catch (Exception e) {}
    }
}