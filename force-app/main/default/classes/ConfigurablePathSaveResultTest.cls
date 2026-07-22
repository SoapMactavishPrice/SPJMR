@IsTest
private class ConfigurablePathSaveResultTest {
    @IsTest
    static void gettersAndSettersWork() {
        ConfigurablePathSaveResult r = new ConfigurablePathSaveResult();
        r.success = true;
        r.message = 'ok';
        System.assertEquals(true, r.success);
        System.assertEquals('ok', r.message);
        r.success = false;
        System.assertEquals(false, r.success);
    }
}