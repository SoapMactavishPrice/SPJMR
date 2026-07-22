@IsTest
private class ConfigPathDepOptResultTest {
    @IsTest
    static void gettersAndSetters() {
        ConfigurablePathDependencyOptionsResult r = new ConfigurablePathDependencyOptionsResult();
        r.loadOk = true;
        r.loadErrorMessage = 'msg';
        r.options = new List<ConfigurablePathUiModel.OptionRow>();
        r.usePerProgramLayout = false;
        r.programContexts = new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();
        System.assertEquals(true, r.loadOk);
        System.assertEquals('msg', r.loadErrorMessage);
        System.assertNotEquals(null, r.options);
        System.assertEquals(false, r.usePerProgramLayout);
        System.assertNotEquals(null, r.programContexts);
    }
}