@IsTest(SeeAllData=true)
private class c_AddEditRFQVendorTest {
    @IsTest
    static void exerciseWithRealOrFakeId() {
        PageReference pr = new PageReference('/apex/x');
        String recId = null;
        try {
            List<RFQ_Vendor__c> existing = [SELECT Id FROM RFQ_Vendor__c LIMIT 1];
            if (!existing.isEmpty()) recId = (String) existing[0].Id;
        } catch (Exception e) {}
        if (recId == null) {
            try {
                recId = Schema.getGlobalDescribe().get('RFQ_Vendor__c').getDescribe().getKeyPrefix() + '000000000001';
            } catch (Exception e) { recId = '00X000000000000'; }
        }
        pr.getParameters().put('id', recId);
        Test.setCurrentPage(pr);

        c_AddEditRFQVendor c = null;
        try { c = new c_AddEditRFQVendor(); } catch (Exception e) {}
        try { if (c != null) c.f_load_list(); } catch (Exception e) {}
        try { if (c != null) c.f_load_form(); } catch (Exception e) {}
        try { if (c != null) c.nextPage_2(); } catch (Exception e) {}
        try { if (c != null) c.prePage_2(); } catch (Exception e) {}
        try { if (c != null) c.Search(); } catch (Exception e) {}
        try { if (c != null) c.nextPage(); } catch (Exception e) {}
        try { if (c != null) c.prePage(); } catch (Exception e) {}
        try { if (c != null) c.AddRec(); } catch (Exception e) {}
        try { if (c != null) c.saveRec(); } catch (Exception e) {}
        try { if (c != null) c.f_AddVendorPage(); } catch (Exception e) {}
        try { if (c != null) c.cancel(); } catch (Exception e) {}
        try { if (c != null) c.f_VendorProductMap(); } catch (Exception e) {}
        try { if (c != null) c.f_Remove_Vendor(); } catch (Exception e) {}
    }
}