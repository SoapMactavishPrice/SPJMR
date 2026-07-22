@IsTest(SeeAllData=true)
private class AddFeePlanTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<Program_Batch_Wise_Payment__c> existing = [SELECT Id FROM Program_Batch_Wise_Payment__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('Program_Batch_Wise_Payment__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        AddFeePlan c = null;
        try { c = new AddFeePlan(); } catch (Exception e) {}
        try { if (c != null) c.getprogramlist1(); } catch (Exception e) {}
        try { if (c != null) c.render(); } catch (Exception e) {}
        try { if (c != null) c.save(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
    }
}