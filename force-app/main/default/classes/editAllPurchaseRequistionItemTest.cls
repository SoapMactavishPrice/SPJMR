@IsTest
private class editAllPurchaseRequistionItemTest {
    @IsTest
    static void saveAndCancelReturnRedirect() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        editAllPurchaseRequistionItem c = new editAllPurchaseRequistionItem();
        PageReference s = c.Save();
        PageReference x = c.Cancel();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, x);
    }
}