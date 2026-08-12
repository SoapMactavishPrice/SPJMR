@isTest
private class ConPathDependencyOptionsResultTest {

    @isTest
    static void testComplete(){
        ConfigurablePathDependencyOptionsResult s = new ConfigurablePathDependencyOptionsResult();
        s.loadOk=true;        
        s.loadErrorMessage = 'None';
        List<ConfigurablePathUiModel.OptionRow> options = new  List<ConfigurablePathUiModel.OptionRow>();
        s.options = options;
        s.usePerProgramLayout = true;
        List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> programContexts = new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();
        s.programContexts = programContexts;
        
        system.assert(s!=null);
    }
}