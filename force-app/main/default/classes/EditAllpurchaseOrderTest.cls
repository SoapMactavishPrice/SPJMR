@IsTest
private class EditAllpurchaseOrderTest {
    @IsTest
    static void saveAndCancelReturnRedirect() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        EditAllpurchaseOrder c = new EditAllpurchaseOrder();
        PageReference s = c.Save();
        PageReference x = c.Cancel();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, x);
    }
}