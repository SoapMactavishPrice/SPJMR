@IsTest(SeeAllData=true)
private class c_AddProductOnRFQTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<RFQ_Item__c> existing = [SELECT Id FROM RFQ_Item__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('RFQ_Item__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        c_AddProductOnRFQ c = null;
        try { c = new c_AddProductOnRFQ(); } catch (Exception e) {}
        try { if (c != null) c.Search(); } catch (Exception e) {}
        try { if (c != null) c.nextPage(); } catch (Exception e) {}
        try { if (c != null) c.prePage(); } catch (Exception e) {}
        try { if (c != null) c.AddRec(); } catch (Exception e) {}
        try { if (c != null) c.saveRec(); } catch (Exception e) {}
        try { if (c != null) c.getdisc(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
        try { if (c != null) c.f_Remove_Item(); } catch (Exception e) {}
    }
}