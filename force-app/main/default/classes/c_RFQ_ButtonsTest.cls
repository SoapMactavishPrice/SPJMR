@IsTest
private class c_RFQ_ButtonsTest {
    @IsTest
    static void allButtonMethodsReturnPageReferences() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        c_RFQ_Buttons c = new c_RFQ_Buttons();
        c.v_rid = '00X000000000000';
        System.assertNotEquals(null, c.f_AddProduct());
        System.assertNotEquals(null, c.f_EditProduct());
        System.assertNotEquals(null, c.f_AddEditRFQVendor());
        System.assertNotEquals(null, c.f_VendorProductMap());
        System.assertNotEquals(null, c.f_VendorProductMapEdit());
        System.assertNotEquals(null, c.f_SendMailtoVendor());
        System.assertNotEquals(null, c.f_SendPDF());
        System.assertNotEquals(null, c.f_RFXResponseEditor());
        System.assertNotEquals(null, c.f_AwardRFQtoVendor());
        System.assertNotEquals(null, c.f_RFQApprover());
        System.assertNotEquals(null, c.f_CreatePO());
        System.assertNotEquals(null, c.f_page_call('/apex/y'));
    }
}