/**
 * Aura-enabled entry points for {@link ConfigurablePathService} used by the {@code configurablePath} LWC.
 * 
 * @see ConfigurablePathService
 */
public with sharing class ConfigurablePathController {
    /**
     * Returns path stages, modal configuration, and merged dependency options for the record.
     *
     * @param recordId Record Id displayed on the page.
     * @param configDeveloperName {@link Path_Wizard_Config__mdt} DeveloperName.
     * @return UI model for the path component.
     */
    @AuraEnabled(cacheable = true)
    public static ConfigurablePathUiModel getPathUiModel(Id recordId, String configDeveloperName) {
        ConfigurablePathUiModel result;
        try {
            result = ConfigurablePathService.getPathUiModel(recordId, configDeveloperName);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
        return result;
    }

    /**
     * Loads sub-status options for the selected path stage and the lead's program codes.
     *
     * @param recordId Record Id.
     * @param configDeveloperName Path wizard config DeveloperName.
     * @param targetPathValue Path picklist API value for the stage being completed.
     * @return Options payload or error message.
     */
    @AuraEnabled
    public static ConfigurablePathDependencyOptionsResult getDependencyOptionsForTarget(
        Id recordId,
        String configDeveloperName,
        String targetPathValue
    ) {
        ConfigurablePathDependencyOptionsResult result;
        try {
            result = ConfigurablePathService.getDependencyOptionsForTarget(recordId, configDeveloperName, targetPathValue);
        } catch (Exception e) {
            return dependencyErrorResult(e.getMessage());
        }
        return result;
    }

    /**
     * Updates the path picklist and dependency field after server-side validation.
     *
     * @param recordId Record to update.
     * @param configDeveloperName Path configuration DeveloperName.
     * @param newPathValue Target path picklist value.
     * @param dependencyValues Dependency selections (multi when configured).
     * @return Save outcome with a user-facing message.
     */
    @AuraEnabled
    public static ConfigurablePathSaveResult savePathTransition(
        Id recordId,
        String configDeveloperName,
        String newPathValue,
        List<String> dependencyValues,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        ConfigurablePathSaveResult result;
        try {
             result = ConfigurablePathService.savePathTransition(
                 recordId,
                 configDeveloperName,
                 newPathValue,
                 dependencyValues,
                 perProgramSubStatuses
            );
        } catch (Exception e) {
            return saveErrorResult(e.getMessage());
        }
        return result;
    }
  @TestVisible
private static ConfigurablePathDependencyOptionsResult dependencyErrorResult(String message) {
    ConfigurablePathDependencyOptionsResult result =
        new ConfigurablePathDependencyOptionsResult();
    result.loadOk = false;
    result.loadErrorMessage = message;
    result.options = new List<ConfigurablePathUiModel.OptionRow>();
    return result;
}

@TestVisible
private static ConfigurablePathSaveResult saveErrorResult(String message) {
    ConfigurablePathSaveResult result = new ConfigurablePathSaveResult();
    result.success = false;
    result.message = message;
    return result;
}
}