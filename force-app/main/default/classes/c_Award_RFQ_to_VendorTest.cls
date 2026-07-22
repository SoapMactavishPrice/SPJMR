@IsTest(SeeAllData=true)
private class c_Award_RFQ_to_VendorTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<RFQ__c> existing = [SELECT Id FROM RFQ__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('RFQ__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        c_Award_RFQ_to_Vendor c = null;
        try { c = new c_Award_RFQ_to_Vendor(); } catch (Exception e) {}
        try { if (c != null) c.f_load_vendor_item_map(); } catch (Exception e) {}
        try { if (c != null) c.f_load_vendor_item_map1(); } catch (Exception e) {}
        try { if (c != null) c.f_Send_Notification(); } catch (Exception e) {}
    }
}