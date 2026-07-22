/**
 * Result of attempting to persist path + dependency values from the configurable path UI.
 */
public with sharing class ConfigurablePathSaveResult {
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String message { get; set; }
}