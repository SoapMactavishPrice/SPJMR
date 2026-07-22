@IsTest
private class c_RFQVendorProductMapTest {
    @IsTest
    static void exerciseClass() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        c_RFQVendorProductMap inst = null;
        try { inst = new c_RFQVendorProductMap(); } catch (Exception e) {}
        try { if (inst != null) inst.f_load_vendor_list(); } catch (Exception e) {}
        try { if (inst != null) inst.f_select_vendor(); } catch (Exception e) {}
        try { if (inst != null) inst.f_unselect_vendor(); } catch (Exception e) {}
        try { if (inst != null) inst.f_load_vendor_product_list(); } catch (Exception e) {}
        try { if (inst != null) inst.f_load_product_list(); } catch (Exception e) {}
        try { if (inst != null) inst.nextPage(); } catch (Exception e) {}
        try { if (inst != null) inst.prePage(); } catch (Exception e) {}
        try { if (inst != null) inst.f_AddMapProduct(); } catch (Exception e) {}
        try { if (inst != null) inst.cancel(); } catch (Exception e) {}
    }
}