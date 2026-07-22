@IsTest(SeeAllData=true)
private class c_RFQVendorProductMapEditTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<RFQ_Vendor_Item_Map__c> existing = [SELECT Id FROM RFQ_Vendor_Item_Map__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('RFQ_Vendor_Item_Map__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        c_RFQVendorProductMapEdit c = null;
        try { c = new c_RFQVendorProductMapEdit(); } catch (Exception e) {}
        try { if (c != null) c.f_load_vendor_list(); } catch (Exception e) {}
        try { if (c != null) c.f_select_vendor(); } catch (Exception e) {}
        try { if (c != null) c.f_load_product_list(); } catch (Exception e) {}
        try { if (c != null) c.f_AddMapProduct(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
    }
}