/**
 * Dependency picklist options for a specific target path stage, returned to {@code configurablePath}.
 */
public with sharing class ConfigurablePathDependencyOptionsResult {
    @AuraEnabled
    public Boolean loadOk { get; set; }
    @AuraEnabled
    public String loadErrorMessage { get; set; }
    @AuraEnabled
    public List<ConfigurablePathUiModel.OptionRow> options { get; set; }
    /**
     * When true, use {@code programContexts} (one block per Lead Program) instead of merged {@code options}.
     */
    @AuraEnabled
    public Boolean usePerProgramLayout { get; set; }
    @AuraEnabled
    public List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> programContexts { get; set; }
}