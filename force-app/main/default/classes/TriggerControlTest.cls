@IsTest
private class TriggerControlTest {
    @IsTest
    static void flagDefaultsFalseAndIsMutable() {
        System.assertEquals(false, TriggerControl.skipTermRenumber);
        TriggerControl.skipTermRenumber = true;
        System.assertEquals(true, TriggerControl.skipTermRenumber);
        TriggerControl.skipTermRenumber = false;
    }
}