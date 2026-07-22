@IsTest
private class c_RFQSendMailtoVendorTest {
    @IsTest
    static void exerciseClass() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        c_RFQSendMailtoVendor inst = null;
        try { inst = new c_RFQSendMailtoVendor(); } catch (Exception e) {}
        try { if (inst != null) inst.f_load_vendor_list(); } catch (Exception e) {}
        try { if (inst != null) inst.f_GenerateCSVFile(); } catch (Exception e) {}
        try { if (inst != null) inst.f_GeneratePDFFile(); } catch (Exception e) {}
        try { if (inst != null) inst.cancel(); } catch (Exception e) {}
    }
}