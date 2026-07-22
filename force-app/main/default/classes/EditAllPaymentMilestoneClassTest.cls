@IsTest
private class EditAllPaymentMilestoneClassTest {
    @IsTest
    static void saveAndCancelReturnRedirect() {
        Test.setCurrentPage(new PageReference('/apex/x'));
        EditAllPaymentMilestoneClass c = new EditAllPaymentMilestoneClass();
        PageReference s = c.Save();
        PageReference x = c.Cancel();
        System.assertNotEquals(null, s);
        System.assertNotEquals(null, x);
    }
}