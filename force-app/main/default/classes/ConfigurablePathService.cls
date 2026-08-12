/**
 * Public entry points for the configurable path Lightning Web Component.
 * All implementation, query, and validation logic lives in ConfigurablePathServiceHelper.
 *
 * @see ConfigurablePathServiceHelper
 * @see ConfigurablePathController
 */
public with sharing class ConfigurablePathService {

    /**
     * Builds the path UI model for a record using the named configuration row and live dependency metadata.
     */
    public static ConfigurablePathUiModel getPathUiModel(Id recordId, String configDeveloperName) {
        ConfigurablePathUiModel result = ConfigurablePathServiceHelper.newUiShell(configDeveloperName);
        PathWizardConfigModel cfg = ConfigurablePathServiceHelper.resolveConfigModel(configDeveloperName);
        if (cfg == null) {
            return ConfigurablePathServiceHelper.setUiLoadError(result, 'Path configuration was not found.');
        }
        if (!ConfigurablePathServiceHelper.isSafeConfig(cfg)) {
            return ConfigurablePathServiceHelper.setUiLoadError(result, 'Path configuration contains invalid API identifiers.');
        }
        List<PathDependencyValueModel> cmdtRows = ConfigurablePathServiceHelper.loadAllActiveDependencyRows(cfg.developerName);
        return ConfigurablePathServiceHelper.buildUiModel(recordId, cfg, cmdtRows, null, null);
    }

    /**
     * Returns merged dependency options for the lead's program codes and the target path stage.
     */
    public static ConfigurablePathDependencyOptionsResult getDependencyOptionsForTarget(
        Id recordId,
        String configDeveloperName,
        String targetPathValue
    ) {
        ConfigurablePathDependencyOptionsResult out = new ConfigurablePathDependencyOptionsResult();
        out.options = new List<ConfigurablePathUiModel.OptionRow>();
        out.loadOk = false;
        out.usePerProgramLayout = false;
        out.programContexts = new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();

        PathWizardConfigModel cfg = ConfigurablePathServiceHelper.resolveConfigModel(configDeveloperName);
        if (cfg == null) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'Path configuration was not found.');
        }
        if (!ConfigurablePathServiceHelper.isSafeConfig(cfg)) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'Path configuration is invalid.');
        }
        if (String.isBlank(targetPathValue)) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'Select a path stage before loading sub-status options.');
        }
        SObject row = ConfigurablePathServiceHelper.queryTargetRecord(recordId, cfg);
        if (row == null) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'Record was not found or is not accessible.');
        }
        if (!ConfigurablePathServiceHelper.isRecordTypeAllowed(row, cfg)) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'This path is not available for the current record type.');
        }
        if (!ConfigurablePathServiceHelper.isActivePicklistValue(cfg.objectApiName, cfg.pathFieldApiName, targetPathValue)) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'The selected path value is not valid.');
        }
        if (!ConfigurablePathServiceHelper.canReadFields(cfg)) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'You do not have permission to read the path or dependency fields.');
        }
        Set<String> programCodes = ConfigurablePathServiceHelper.collectProgramCodes(recordId, cfg);
        if (!cfg.allowEmptyLeadPrograms && programCodes.isEmpty()) {
            return ConfigurablePathServiceHelper.setDependencyLoadError(out, 'Add at least one program to the lead before choosing sub-status values.');
        }
        List<PathStageOverrideModel> stageOverrideRows = PathStageOverrideModel.loadRowsForConfig(cfg.developerName);
        PathStageOverrideModel.ResolvedStageOverride targetResolved = PathStageOverrideModel.resolveForPathValue(
            targetPathValue,
            programCodes,
            stageOverrideRows
        );
        if (ConfigurablePathServiceHelper.shouldSkipSubStatusModalFromResolved(targetResolved, stageOverrideRows.isEmpty())) {
            out.options = new List<ConfigurablePathUiModel.OptionRow>();
            out.loadOk = true;
            return out;
        }
        List<PathDependencyValueModel> cmdtRows = ConfigurablePathServiceHelper.loadAllActiveDependencyRows(cfg.developerName);
        if (ConfigurablePathServiceHelper.usePerProgramDependencyModal(recordId, cfg)) {
            out.usePerProgramLayout = true;
            out.programContexts = ConfigurablePathServiceHelper.buildProgramContextsWithOptions(recordId, cfg, cmdtRows, targetPathValue);
            out.options = new List<ConfigurablePathUiModel.OptionRow>();
            out.loadOk = true;
            return out;
        }
        List<PathDependencyValueModel> merged = ConfigurablePathServiceHelper.filterDependencyRowsByProgramAndStage(
            cmdtRows,
            programCodes,
            targetPathValue
        );
        out.options = ConfigurablePathServiceHelper.toOptionRows(merged);
        out.loadOk = true;
        return out;
    }

    /**
     * Persists the selected path value and dependency selection(s) after validation.
     */
    @TestVisible
    public static ConfigurablePathSaveResult savePathTransition(
        Id recordId,
        String configDeveloperName,
        String newPathValue,
        List<String> dependencyValues,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        ConfigurablePathSaveResult outcome = new ConfigurablePathSaveResult();
        outcome.success = false;
        PathWizardConfigModel cfg = ConfigurablePathServiceHelper.resolveConfigModel(configDeveloperName);
        if (cfg == null) {
            return ConfigurablePathServiceHelper.setOutcomeMessage(outcome, 'Path configuration was not found.');
        }
        if (!ConfigurablePathServiceHelper.isSafeConfig(cfg)) {
            return ConfigurablePathServiceHelper.setOutcomeMessage(outcome, 'Path configuration is invalid.');
        }
        List<PathDependencyValueModel> cmdtRows = ConfigurablePathServiceHelper.loadAllActiveDependencyRows(cfg.developerName);
        return ConfigurablePathServiceHelper.savePathTransitionCore(
            recordId,
            cfg,
            cmdtRows,
            newPathValue,
            dependencyValues,
            perProgramSubStatuses
        );
    }

    // =====================================================================================
    // Thin @TestVisible wrappers — kept here so existing tests that call
    // ConfigurablePathService.xxx(...) directly continue to compile and pass unchanged.
    // =====================================================================================

    @TestVisible
    private static ConfigurablePathSaveResult savePathTransitionForTests(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        String newPathValue,
        List<String> dependencyValues
    ) {
        return ConfigurablePathServiceHelper.savePathTransitionCore(recordId, cfg, dependencyRows, newPathValue, dependencyValues, null);
    }

    @TestVisible
    private static ConfigurablePathSaveResult savePathTransitionForTestsWithPerProgram(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        String newPathValue,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        return ConfigurablePathServiceHelper.savePathTransitionCore(
            recordId,
            cfg,
            dependencyRows,
            newPathValue,
            new List<String>(),
            perProgramSubStatuses
        );
    }

    @TestVisible
    private static ConfigurablePathUiModel buildUiModelForTests(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows
    ) {
        return ConfigurablePathServiceHelper.buildUiModel(recordId, cfg, dependencyRows, null, null);
    }

    @TestVisible
    private static ConfigurablePathUiModel buildUiModelForTestsWithTarget(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        String targetPathStageApi
    ) {
        return ConfigurablePathServiceHelper.buildUiModel(recordId, cfg, dependencyRows, targetPathStageApi, null);
    }

    @TestVisible
    private static ConfigurablePathUiModel buildUiModelForTestsWithMainStages(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        List<PathMainStageValueModel> mainStageRows
    ) {
        return ConfigurablePathServiceHelper.buildUiModel(recordId, cfg, dependencyRows, null, mainStageRows);
    }

    @TestVisible
    private static Boolean isSafeConfig(PathWizardConfigModel cfg) {
        return ConfigurablePathServiceHelper.isSafeConfig(cfg);
    }

    @TestVisible
    private static Set<String> collectProgramCodes(Id recordId, PathWizardConfigModel cfg) {
        return ConfigurablePathServiceHelper.collectProgramCodes(recordId, cfg);
    }

    @TestVisible
    private static Boolean rowMatchesPathStage(PathDependencyValueModel m, String targetPathStageApi) {
        return ConfigurablePathServiceHelper.rowMatchesPathStage(m, targetPathStageApi);
    }

    @TestVisible
    private static Boolean clientRecordTypePicklistSupported(PathWizardConfigModel cfg) {
        return ConfigurablePathServiceHelper.clientRecordTypePicklistSupported(cfg);
    }

    @TestVisible
    private static String joinDependencyForStorage(List<String> cleanedDeps, PathWizardConfigModel cfg) {
        return ConfigurablePathServiceHelper.joinDependencyForStorage(cleanedDeps, cfg);
    }

    @TestVisible
    private static List<String> parseStoredDependencies(String stored, PathWizardConfigModel cfg) {
        return ConfigurablePathServiceHelper.parseStoredDependencies(stored, cfg);
    }
}