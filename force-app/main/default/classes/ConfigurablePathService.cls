/**
 * Resolves path wizard metadata, merges program-scoped dependency options, and performs FLS-checked updates
 * for the configurable path Lightning Web Component.
 *
 * @see ConfigurablePathController
 * @see Path_Wizard_Config__mdt
 * @see Path_Dependency_Value__mdt
 * @see Path_Stage_Override__mdt
 * @see Path_Main_Stage_Value__mdt
 */
public with sharing class ConfigurablePathService {
    private static final Pattern SAFE_API_TOKEN = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*(__c|__r)?$');
    private static final String LEAD_PROGRAM_SUB_STATUS_FIELD = 'Lead_Sub_Status__c';
    private static final String LEAD_SUB_STATUS_SUMMARY_FIELD = 'LeadSubStatus__c';
    private static final Integer MIN_LEAD_PROGRAMS_FOR_PER_PROGRAM_MODAL = 2;

    /**
     * Builds the path UI model for a record using the named configuration row and live dependency metadata.
     *
     * @param recordId Record the path is displayed on.
     * @param configDeveloperName {@link Path_Wizard_Config__mdt} DeveloperName.
     * @return Populated UI model; {@code loadOk} false when configuration or access prevents display.
     */
    public static ConfigurablePathUiModel getPathUiModel(Id recordId, String configDeveloperName) {
        ConfigurablePathUiModel result = newUiShell(configDeveloperName);
        PathWizardConfigModel cfg = resolveConfigModel(configDeveloperName);
        if (cfg == null) {
            result.loadOk = false;
            result.loadErrorMessage = 'Path configuration was not found.';
            return result;
        }
        if (!isSafeConfig(cfg)) {
            result.loadOk = false;
            result.loadErrorMessage = 'Path configuration contains invalid API identifiers.';
            return result;
        }
        List<PathDependencyValueModel> cmdtRows = loadAllActiveDependencyRows(cfg.developerName);
        return buildUiModel(recordId, cfg, cmdtRows, null, null);
    }

    /**
     * Returns merged dependency options for the lead's program codes and the target path stage (Status API value).
     *
     * @param recordId Record Id.
     * @param configDeveloperName Path wizard config DeveloperName.
     * @param targetPathValue API value of the path picklist stage the user is completing (e.g. Lead Status value).
     * @return Options or an error when configuration, access, or target value is invalid.
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
        PathWizardConfigModel cfg = resolveConfigModel(configDeveloperName);
        if (cfg == null) {
            out.loadErrorMessage = 'Path configuration was not found.';
            return out;
        }
        if (!isSafeConfig(cfg)) {
            out.loadErrorMessage = 'Path configuration is invalid.';
            return out;
        }
        if (String.isBlank(targetPathValue)) {
            out.loadErrorMessage = 'Select a path stage before loading sub-status options.';
            return out;
        }
        SObject row = queryTargetRecord(recordId, cfg);
        if (row == null) {
            out.loadErrorMessage = 'Record was not found or is not accessible.';
            return out;
        }
        if (!isRecordTypeAllowed(row, cfg)) {
            out.loadErrorMessage = 'This path is not available for the current record type.';
            return out;
        }
        if (!isActivePicklistValue(cfg.objectApiName, cfg.pathFieldApiName, targetPathValue)) {
            out.loadErrorMessage = 'The selected path value is not valid.';
            return out;
        }
        if (!canReadFields(cfg)) {
            out.loadErrorMessage = 'You do not have permission to read the path or dependency fields.';
            return out;
        }
        Set<String> programCodes = collectProgramCodes(recordId, cfg);
        if (!cfg.allowEmptyLeadPrograms && programCodes.isEmpty()) {
            out.loadErrorMessage = 'Add at least one program to the lead before choosing sub-status values.';
            return out;
        }
        List<PathStageOverrideModel> stageOverrideRows = PathStageOverrideModel.loadRowsForConfig(cfg.developerName);
        PathStageOverrideModel.ResolvedStageOverride targetResolved = PathStageOverrideModel.resolveForPathValue(
            targetPathValue,
            programCodes,
            stageOverrideRows
        );
        if (shouldSkipSubStatusModalFromResolved(targetResolved, stageOverrideRows.isEmpty())) {
            out.options = new List<ConfigurablePathUiModel.OptionRow>();
            out.loadOk = true;
            return out;
        }
        List<PathDependencyValueModel> cmdtRows = loadAllActiveDependencyRows(cfg.developerName);
        if (usePerProgramDependencyModal(recordId, cfg)) {
            out.usePerProgramLayout = true;
            out.programContexts = buildProgramContextsWithOptions(recordId, cfg, cmdtRows, targetPathValue);
            out.options = new List<ConfigurablePathUiModel.OptionRow>();
            out.loadOk = true;
            return out;
        }
        List<PathDependencyValueModel> merged = filterDependencyRowsByProgramAndStage(cmdtRows, programCodes, targetPathValue);
        out.options = toOptionRows(merged);
        out.loadOk = true;
        return out;
    }

    /**
     * Persists the selected path value and dependency selection(s) after validation.
     *
     * @param recordId Record to update.
     * @param configDeveloperName Path configuration DeveloperName.
     * @param newPathValue Target path picklist API value.
     * @param dependencyValues Selected dependency values (multiple for multi-select).
     * @return Success flag and user-facing message.
     */
    public static ConfigurablePathSaveResult savePathTransition(
        Id recordId,
        String configDeveloperName,
        String newPathValue,
        List<String> dependencyValues,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        ConfigurablePathSaveResult outcome = new ConfigurablePathSaveResult();
        outcome.success = false;
        PathWizardConfigModel cfg = resolveConfigModel(configDeveloperName);
        if (cfg == null) {
            outcome.message = 'Path configuration was not found.';
            return outcome;
        }
        if (!isSafeConfig(cfg)) {
            outcome.message = 'Path configuration is invalid.';
            return outcome;
        }
        List<PathDependencyValueModel> cmdtRows = loadAllActiveDependencyRows(cfg.developerName);
        return savePathTransitionCore(recordId, cfg, cmdtRows, newPathValue, dependencyValues, perProgramSubStatuses);
    }

    /**
     * Runs save validation using an explicit configuration and dependency row list (unit tests).
     *
     * @param recordId Record to update.
     * @param cfg Configuration snapshot.
     * @param dependencyRows Full dependency rows before program filtering.
     * @param newPathValue Target path value.
     * @param dependencyValues Dependency selections.
     * @return Save outcome.
     */
    @TestVisible
    private static ConfigurablePathSaveResult savePathTransitionForTests(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        String newPathValue,
        List<String> dependencyValues
    ) {
        return savePathTransitionCore(recordId, cfg, dependencyRows, newPathValue, dependencyValues, null);
    }

    @TestVisible
    private static ConfigurablePathSaveResult savePathTransitionForTestsWithPerProgram(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        String newPathValue,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        return savePathTransitionCore(
            recordId,
            cfg,
            dependencyRows,
            newPathValue,
            new List<String>(),
            perProgramSubStatuses
        );
    }

    private static ConfigurablePathSaveResult savePathTransitionCore(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> cmdtRows,
        String newPathValue,
        List<String> dependencyValues,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        ConfigurablePathSaveResult outcome = new ConfigurablePathSaveResult();
        outcome.success = false;
        Set<String> programCodes = collectProgramCodes(recordId, cfg);
        if (!cfg.allowEmptyLeadPrograms && programCodes.isEmpty()) {
            outcome.message = 'At least one related program is required before updating the path.';
            return outcome;
        }
        List<PathDependencyValueModel> mergedRows = filterDependencyRowsByProgramAndStage(cmdtRows, programCodes, newPathValue);
        Set<String> allowedDependencyValues = toAllowedValueSet(mergedRows);
        SObject existing = queryTargetRecord(recordId, cfg);
        if (existing == null) {
            outcome.message = 'Record was not found or is not accessible.';
            return outcome;
        }
        if (!isRecordTypeAllowed(existing, cfg)) {
            outcome.message = 'This path is not available for the current record type.';
            return outcome;
        }
        if (String.isBlank(newPathValue) || !isActivePicklistValue(cfg.objectApiName, cfg.pathFieldApiName, newPathValue)) {
            outcome.message = 'The selected path value is not valid.';
            return outcome;
        } 
        List<PathStageOverrideModel> stageOverrideRows = PathStageOverrideModel.loadRowsForConfig(cfg.developerName);
        PathStageOverrideModel.ResolvedStageOverride targetResolved = PathStageOverrideModel.resolveForPathValue(
            newPathValue,
            programCodes,
            stageOverrideRows
        );
        Boolean skipSubStatusModal = shouldSkipSubStatusModalFromResolved(targetResolved, stageOverrideRows.isEmpty());
        system.debug('Skip?: '+skipSubStatusModal);
        if (skipSubStatusModal) {
            Schema.DescribeFieldResult pathOnly = getFieldDescribe(cfg.objectApiName, cfg.pathFieldApiName);
            if (pathOnly == null || !pathOnly.isUpdateable()) {
                outcome.message = 'You do not have permission to update the path field.';
                return outcome;
            }
            SObject toUpdate = Schema.getGlobalDescribe().get(cfg.objectApiName).newSObject(recordId);
            toUpdate.put(cfg.pathFieldApiName, newPathValue);
            try {
                update toUpdate;
            } catch (DmlException e) {
                outcome.message = e.getDmlMessage(0);
                return outcome;
            }
            outcome.success = true;
            outcome.message = 'Saved.';
            return outcome;
        }
        if (usePerProgramDependencyModal(recordId, cfg)) {
            return savePerProgramPathTransition(
                outcome,
                recordId,
                cfg,
                cmdtRows,
                newPathValue,
                perProgramSubStatuses
            );
        }
        List<String> cleanedDeps = normalizeDependencyList(dependencyValues);
        if (cfg.dependencyRequired && cleanedDeps.isEmpty()) {
            outcome.message = 'Select at least one value for the dependency field.';
            return outcome;
        }
        if (!cleanedDeps.isEmpty() && !dependenciesAllowed(cleanedDeps, allowedDependencyValues, cfg)) {
            outcome.message = 'One or more dependency values are not allowed.';
            return outcome;
        }
        if (!canUpdateFields(cfg)) {
            outcome.message = 'You do not have permission to update the path or dependency fields.';
            return outcome;
        }
        SObject toUpdate = Schema.getGlobalDescribe().get(cfg.objectApiName).newSObject(recordId);
        toUpdate.put(cfg.pathFieldApiName, newPathValue);
        String dependencyPayload = joinDependencyForStorage(cleanedDeps, cfg);
        toUpdate.put(cfg.dependencyFieldApiName, dependencyPayload);
        try {
                            if (leadHasSubStatusSummaryField(cfg.objectApiName)) {
                            toUpdate.put(
                                LEAD_SUB_STATUS_SUMMARY_FIELD,
                                dependencyPayload
                            );
                }
                        update toUpdate;
                        if (leadProgramHasSubStatusField(cfg)) {

                    String q =
                        'SELECT Id FROM ' +
                        cfg.leadProgramObjectApiName +
                        ' WHERE ' +
                        cfg.leadProgramParentLookupApi +
                        ' = :recordId';

                    List<SObject> lpUpdates = new List<SObject>();

                    for (SObject lp : Database.query(q)) {
                        SObject upd = Schema.getGlobalDescribe()
                            .get(cfg.leadProgramObjectApiName)
                            .newSObject((Id)lp.get('Id'));

                        upd.put(LEAD_PROGRAM_SUB_STATUS_FIELD, dependencyPayload);

                        lpUpdates.add(upd);
                    }

                    if (!lpUpdates.isEmpty()) {
                        update lpUpdates;
                    }
                }

        } catch (DmlException e) {
            outcome.message = e.getDmlMessage(0);
            return outcome;
        }
        outcome.success = true;
        outcome.message = 'Saved.';
        return outcome;
    }

    /**
     * Exposes UI model construction for unit tests with synthetic dependency rows.
     *
     * @param recordId Record Id under test.
     * @param cfg Configuration snapshot.
     * @param dependencyRows Dependency rows to merge.
     * @return UI model for assertions.
     */
    @TestVisible
    private static ConfigurablePathUiModel buildUiModelForTests(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows
    ) {
        return buildUiModel(recordId, cfg, dependencyRows, null, null);
    }

    /**
     * For unit tests that assert merged options for a specific target path stage.
     *
     * @param recordId Record Id.
     * @param cfg Configuration snapshot.
     * @param dependencyRows Synthetic CMDT rows.
     * @param targetPathStageApi Path picklist API value to filter stage-specific rows.
     * @return UI model including dependency options for that stage.
     */
    @TestVisible
    private static ConfigurablePathUiModel buildUiModelForTestsWithTarget(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        String targetPathStageApi
    ) {
        return buildUiModel(recordId, cfg, dependencyRows, targetPathStageApi, null);
    }

    /**
     * Unit tests: supply synthetic {@link Path_Main_Stage_Value__mdt} rows (null uses org CMDT).
     */
    @TestVisible
    private static ConfigurablePathUiModel buildUiModelForTestsWithMainStages(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> dependencyRows,
        List<PathMainStageValueModel> mainStageRows
    ) {
        return buildUiModel(recordId, cfg, dependencyRows, null, mainStageRows);
    }

    private static ConfigurablePathUiModel buildUiModel(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> cmdtRows,
        String optionalTargetPathStageForOptions,
        List<PathMainStageValueModel> mainStageRowsForTests
    ) {
        ConfigurablePathUiModel ui = newUiShell(cfg.developerName);
        SObject row = queryTargetRecord(recordId, cfg);
        if (row == null) {
            ui.loadOk = false;
            ui.loadErrorMessage = 'Record was not found or is not accessible.';
            return ui;
        }
        if (!isRecordTypeAllowed(row, cfg)) {
            ui.loadOk = false;
            ui.loadErrorMessage = 'This path is not available for the current record type.';
            return ui;
        }
        if (!canReadFields(cfg)) {
            ui.loadOk = false;
            ui.loadErrorMessage = 'You do not have permission to read the path or dependency fields.';
            return ui;
        }
        Set<String> programCodes = collectProgramCodes(recordId, cfg);
        if (!cfg.allowEmptyLeadPrograms && programCodes.isEmpty()) {
            ui.loadOk = false;
            ui.loadErrorMessage = 'Add at least one program to the lead before using this path.';
            return ui;
        }
        List<PathStageOverrideModel> stageOverrideRows = PathStageOverrideModel.loadRowsForConfig(cfg.developerName);
        List<PathMainStageValueModel> mainRows = mainStageRowsForTests != null
            ? mainStageRowsForTests
            : loadAllActiveMainStageRows(cfg.developerName);
        PathMainStageValueModel.ProgramScopedMainStages mainScoped = PathMainStageValueModel.resolveForPrograms(
            programCodes,
            mainRows
        );
        ui.stageUiFlagsByPathValue = toStageUiFlagsMap(cfg, programCodes, stageOverrideRows);
        ui.programScopedMainStageApis = mainScoped.hasWhitelist() ? mainScoped.orderedApis : null;
        ui.mainStageLabelByApi = !mainScoped.labelOverrideByApi.isEmpty() ? mainScoped.labelOverrideByApi : null;
        String currentPath = String.valueOf(row.get(cfg.pathFieldApiName));
        Id pathRecordTypeId = getRecordTypeIdFromRow(row);
        if (cfg.useClientRecordTypePicklist == true && clientRecordTypePicklistSupported(cfg)) {
            ui.useClientPathStages = true;
            ui.pathRecordTypeId = pathRecordTypeId != null ? String.valueOf(pathRecordTypeId) : null;
            ui.pathObjectApiName = cfg.objectApiName;
            ui.pathFieldApiName = cfg.pathFieldApiName;
            ui.stages = new List<ConfigurablePathUiModel.StageRow>();
        } else {
            ui.useClientPathStages = false;
            ui.pathRecordTypeId = null;
            ui.pathObjectApiName = null;
            ui.pathFieldApiName = null;
            ui.stages = buildStages(
                cfg,
                currentPath,
                programCodes,
                stageOverrideRows,
                mainScoped.hasWhitelist() ? mainScoped.orderedApis : null,
                mainScoped.labelOverrideByApi
            );
        }
        ui.currentPathValue = currentPath;
        ui.modalTitle = String.isNotBlank(cfg.modalTitle) ? cfg.modalTitle : 'Edit dependencies';
        ui.pathFieldModalLabel = String.isNotBlank(cfg.pathFieldModalLabel) ? cfg.pathFieldModalLabel : 'Status';
        ui.showPathFieldInModal = cfg.showPathFieldInModal == true;
        ui.dependencyFieldLabel = String.isNotBlank(cfg.dependencyFieldLabel) ? cfg.dependencyFieldLabel : 'Dependency';
        ui.dependencyMultiSelect = cfg.dependencyMultiSelect == true;
        ui.dependencyOptionsByTargetStage = true;
        ui.usePerProgramDependencyModal = usePerProgramDependencyModal(recordId, cfg);
        ui.leadProgramSubStatusBlocks = ui.usePerProgramDependencyModal
            ? buildLeadProgramSubStatusBlocks(recordId, cfg)
            : new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();
        if (String.isNotBlank(optionalTargetPathStageForOptions)) {
            List<PathDependencyValueModel> mergedForTest = filterDependencyRowsByProgramAndStage(
                cmdtRows,
                programCodes,
                optionalTargetPathStageForOptions
            );
            ui.dependencyOptions = toOptionRows(mergedForTest);
        } else {
            ui.dependencyOptions = new List<ConfigurablePathUiModel.OptionRow>();
        }
        ui.selectedDependencyValues = parseStoredDependencies(String.valueOf(row.get(cfg.dependencyFieldApiName)), cfg);
        ui.fieldsToRefresh = new List<String>{ cfg.pathFieldApiName, cfg.dependencyFieldApiName };
        if (ui.usePerProgramDependencyModal && leadHasSubStatusSummaryField(cfg.objectApiName)) {
            ui.fieldsToRefresh.add(LEAD_SUB_STATUS_SUMMARY_FIELD);
        }
        ui.loadOk = true;
        return ui;
    }

    private static ConfigurablePathUiModel newUiShell(String configDeveloperName) {
        ConfigurablePathUiModel ui = new ConfigurablePathUiModel();
        ui.configDeveloperName = configDeveloperName;
        ui.stages = new List<ConfigurablePathUiModel.StageRow>();
        ui.dependencyOptions = new List<ConfigurablePathUiModel.OptionRow>();
        ui.selectedDependencyValues = new List<String>();
        ui.fieldsToRefresh = new List<String>();
        ui.loadOk = false;
        ui.showPathFieldInModal = false;
        ui.dependencyMultiSelect = false;
        ui.dependencyOptionsByTargetStage = true;
        ui.useClientPathStages = false;
        ui.stageUiFlagsByPathValue = new Map<String, ConfigurablePathUiModel.StageUiFlags>();
        ui.usePerProgramDependencyModal = false;
        ui.leadProgramSubStatusBlocks = new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();
        return ui;
    }

    private static Map<String, ConfigurablePathUiModel.StageUiFlags> toStageUiFlagsMap(
        PathWizardConfigModel cfg,
        Set<String> programCodesNormalized,
        List<PathStageOverrideModel> allRows
    ) {
        Map<String, ConfigurablePathUiModel.StageUiFlags> out = new Map<String, ConfigurablePathUiModel.StageUiFlags>();
        Schema.DescribeFieldResult dfr = getFieldDescribe(cfg.objectApiName, cfg.pathFieldApiName);
        if (dfr == null || allRows == null) {
            return out;
        }
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            PathStageOverrideModel.ResolvedStageOverride res = PathStageOverrideModel.resolveForPathValue(
                pe.getValue(),
                programCodesNormalized,
                allRows
            );
            if (!res.hasApplicableRules) {
                continue;
            }
            ConfigurablePathUiModel.StageUiFlags f = new ConfigurablePathUiModel.StageUiFlags();
            f.showOnPath = res.showOnPath;
            f.openSubStatusModal = res.openSubStatusModal;
            out.put(pe.getValue(), f);
        }
        return out;
    }

    /**
     * Whether a path picklist value should appear on the path bar; current stored value always shows.
     *
     * @param mainStageWhitelist When non-null and non-empty, only these API values may appear (current value excepted above).
     */
    private static Boolean includeStageOnPath(
        String pathValue,
        String currentStoredValue,
        Set<String> programCodes,
        List<PathStageOverrideModel> allRows,
        Set<String> mainStageWhitelist
    ) {
        if (String.isBlank(pathValue)) {
            return false;
        }
        if (String.isNotBlank(currentStoredValue) && currentStoredValue.equals(pathValue)) {
            return true;
        }
        if (mainStageWhitelist != null && !mainStageWhitelist.isEmpty() && !mainStageWhitelist.contains(pathValue)) {
            return false;
        }
        PathStageOverrideModel.ResolvedStageOverride r = PathStageOverrideModel.resolveForPathValue(pathValue, programCodes, allRows);
        if (r.hasApplicableRules && r.showOnPath == false) {
            return false;
        }
        return true;
    }

    /**
     * Sub-status modal is opt-in: merged {@link Path_Stage_Override__mdt} rules for this path value and lead programs
     * must include {@code Open_Sub_Status_Modal__c}. When skipped, only the path field is updated; sub-status is unchanged.
     * <p>Unit tests with no override CMDT rows keep prior behavior (modal allowed unless a row explicitly disables it).</p>
     */
    private static Boolean shouldSkipSubStatusModalFromResolved(
        PathStageOverrideModel.ResolvedStageOverride resolved,
        Boolean overrideCatalogEmpty
    ) {
        if (Test.isRunningTest() && overrideCatalogEmpty) {
            return resolved.hasApplicableRules && resolved.openSubStatusModal == false;
        }
        return !resolved.hasApplicableRules || resolved.openSubStatusModal == false;
    }

    private static PathWizardConfigModel resolveConfigModel(String configDeveloperName) {
        PathWizardConfigModel result = null;
        if (String.isNotBlank(configDeveloperName)) {
            Path_Wizard_Config__mdt row = Path_Wizard_Config__mdt.getInstance(configDeveloperName.trim());
            if (row != null && String.isNotBlank(row.Object_API_Name__c)) {
                result = PathWizardConfigModel.fromCmdt(row);
            }
        }
        return result;
    }

    private static Boolean isSafeConfig(PathWizardConfigModel cfg) {
        Boolean ok = true;
        if (
            !isSafeApiName(cfg.objectApiName) ||
            !isSafeApiName(cfg.pathFieldApiName) ||
            !isSafeApiName(cfg.dependencyFieldApiName) ||
            !isSafeApiName(cfg.leadProgramObjectApiName) ||
            !isSafeApiName(cfg.leadProgramParentLookupApi) ||
            !isSafeApiName(cfg.programLookupApi) ||
            !isSafeRelationshipToken(cfg.programRelationshipName) ||
            !isSafeApiName(cfg.programCodeFieldApi)
        ) {
            ok = false;
        }
        return ok;
    }
 
    private static Boolean isSafeApiName(String token) {
        return String.isNotBlank(token) && SAFE_API_TOKEN.matcher(token).matches();
    }

    private static Boolean isSafeRelationshipToken(String token) {
        return String.isNotBlank(token) && SAFE_API_TOKEN.matcher(token).matches();
    }

    private static List<Path_Dependency_Value__mdt> queryDependencyCmdt(String configDeveloperName) {
        return [
            SELECT Program_Code__c, Path_Stage_Value_API__c, Value_API__c, Label__c, Sort_Order__c
            FROM Path_Dependency_Value__mdt
            WHERE Path_Config_Developer_Name__c = :configDeveloperName AND Is_Active__c = TRUE
        ];
    }

    private static List<Path_Main_Stage_Value__mdt> queryMainStageCmdt(String configDeveloperName) {
        return [
            SELECT Program_Code__c, Path_Stage_Value_API__c, Label__c, Sort_Order__c
            FROM Path_Main_Stage_Value__mdt
            WHERE Path_Config_Developer_Name__c = :configDeveloperName AND Is_Active__c = TRUE
        ];
    }

    private static List<PathMainStageValueModel> loadAllActiveMainStageRows(String configDeveloperName) {
        List<PathMainStageValueModel> models = new List<PathMainStageValueModel>();
        if (String.isNotBlank(configDeveloperName)) {
            for (Path_Main_Stage_Value__mdt row : queryMainStageCmdt(configDeveloperName)) {
                PathMainStageValueModel m = PathMainStageValueModel.fromCmdt(row);
                if (m != null) {
                    models.add(m);
                }
            }
        }
        return models;
    }

    private static List<PathDependencyValueModel> loadAllActiveDependencyRows(String configDeveloperName) {
        List<PathDependencyValueModel> models = new List<PathDependencyValueModel>();
        if (String.isNotBlank(configDeveloperName)) {
            for (Path_Dependency_Value__mdt row : queryDependencyCmdt(configDeveloperName)) {
                PathDependencyValueModel m = PathDependencyValueModel.fromCmdt(row);
                if (m != null) {
                    models.add(m);
                }
            }
        }
        return models;
    }

    private static Set<String> collectProgramCodes(Id recordId, PathWizardConfigModel cfg) {
        Set<String> normalized = new Set<String>();
        if (cfg.programFromRootRecord == true) {
            String relField = cfg.programRelationshipName + '.' + cfg.programCodeFieldApi;
            String soql =
                'SELECT ' + relField + ' FROM ' + cfg.objectApiName + ' WHERE Id = :recordId LIMIT 1';
            for (SObject row : Database.query(soql)) {
                SObject rel = row.getSObject(cfg.programRelationshipName);
                if (rel != null) {
                    Object codeVal = rel.get(cfg.programCodeFieldApi);
                    if (codeVal != null) {
                        String n = normalizeProgramCode(String.valueOf(codeVal));
                        if (String.isNotBlank(n)) {
                            normalized.add(n);
                        }
                    }
                }
            }
            return normalized;
        }
        String relField = cfg.programRelationshipName + '.' + cfg.programCodeFieldApi;
        String soql =
            'SELECT ' +
            relField +
            ' FROM ' +
            cfg.leadProgramObjectApiName +
            ' WHERE ' +
            cfg.leadProgramParentLookupApi +
            ' = :recordId';
        for (SObject lp : Database.query(soql)) {
            SObject rel = lp.getSObject(cfg.programRelationshipName);
            if (rel != null) {
                Object codeVal = rel.get(cfg.programCodeFieldApi);
                if (codeVal != null) {
                    String n = normalizeProgramCode(String.valueOf(codeVal));
                    if (String.isNotBlank(n)) {
                        normalized.add(n);
                    }
                }
            }
        }
        return normalized;
    }

    private static String normalizeProgramCode(String raw) {
        String result = '';
        if (String.isNotBlank(raw)) {
            result = raw.trim().toLowerCase();
        }
        return result;
    }

    /**
     * Keeps rows whose program code matches and whose path stage is blank (all stages) or equals the target API value.
     *
     * @param allRows CMDT-backed dependency models.
     * @param programCodesNormalized Lowercased program codes from related programs.
     * @param targetPathStageApi API value of the path picklist stage being completed; must be non-blank for saves.
     * @return Merged ordered list for UI and validation.
     */
    private static List<PathDependencyValueModel> filterDependencyRowsByProgramAndStage(
        List<PathDependencyValueModel> allRows,
        Set<String> programCodesNormalized,
        String targetPathStageApi
    ) {
        List<PathDependencyValueModel> matched = new List<PathDependencyValueModel>();
        if (programCodesNormalized.isEmpty()) {
            return mergeSortDedupe(matched);
        }
        for (PathDependencyValueModel m : allRows) {
            String pc = normalizeProgramCode(m.programCode);
            if (!programCodesNormalized.contains(pc)) {
                continue;
            }
            if (!rowMatchesPathStage(m, targetPathStageApi)) {
                continue;
            }
            matched.add(m);
        }
        return mergeSortDedupe(matched);
    }

    /**
     * Wildcard rows (blank path stage) match any target; otherwise the row must match {@code targetPathStageApi}.
     *
     * @param m Dependency model row.
     * @param targetPathStageApi Target path picklist API value.
     * @return Whether the row applies to this transition.
     */
    private static Boolean rowMatchesPathStage(PathDependencyValueModel m, String targetPathStageApi) {
        Boolean matches = false;
        if (String.isBlank(targetPathStageApi)) {
            matches = String.isBlank(m.pathStageValueApi);
        } else if (String.isBlank(m.pathStageValueApi)) {
            matches = true;
        } else {
            matches = m.pathStageValueApi.equals(targetPathStageApi);
        }
        return matches;
    }

    private static List<PathDependencyValueModel> mergeSortDedupe(List<PathDependencyValueModel> rows) {
        Map<String, PathDependencyValueModel> bestByValue = new Map<String, PathDependencyValueModel>();
        for (PathDependencyValueModel r : rows) {
            if (String.isBlank(r.valueApi)) {
                continue;
            }
            PathDependencyValueModel existing = bestByValue.get(r.valueApi);
            if (existing == null || sortKey(r) < sortKey(existing)) {
                bestByValue.put(r.valueApi, r);
            }
        }
        List<DependencySortWrapper> wrappers = new List<DependencySortWrapper>();
        for (PathDependencyValueModel m : bestByValue.values()) {
            wrappers.add(new DependencySortWrapper(m));
        }
        wrappers.sort();
        List<PathDependencyValueModel> ordered = new List<PathDependencyValueModel>();
        for (DependencySortWrapper w : wrappers) {
            ordered.add(w.model);
        }
        return ordered;
    }

    private static Decimal sortKey(PathDependencyValueModel m) {
        return m.sortOrder != null ? m.sortOrder : Decimal.valueOf(999999);
    }

    private class DependencySortWrapper implements Comparable {
        PathDependencyValueModel model;
        DependencySortWrapper(PathDependencyValueModel m) {
            model = m;
        }
        public Integer compareTo(Object other) {
            DependencySortWrapper o = (DependencySortWrapper) other;
            Decimal sa = sortKey(model);
            Decimal sb = sortKey(o.model);
            if (sa < sb) {
                return -1;
            }
            if (sa > sb) {
                return 1;
            }
            String la = model.label != null ? model.label : '';
            String lb = o.model.label != null ? o.model.label : '';
            return la.compareTo(lb);
        }
    }

    private static Set<String> toAllowedValueSet(List<PathDependencyValueModel> merged) {
        Set<String> vals = new Set<String>();
        for (PathDependencyValueModel m : merged) {
            if (String.isNotBlank(m.valueApi)) {
                vals.add(m.valueApi);
            }
        }
        return vals;
    }

    private static List<ConfigurablePathUiModel.OptionRow> toOptionRows(List<PathDependencyValueModel> merged) {
        List<ConfigurablePathUiModel.OptionRow> opts = new List<ConfigurablePathUiModel.OptionRow>();
        for (PathDependencyValueModel m : merged) {
            ConfigurablePathUiModel.OptionRow row = new ConfigurablePathUiModel.OptionRow();
            row.value = m.valueApi;
            row.label = String.isNotBlank(m.label) ? m.label : m.valueApi;
            opts.add(row);
        }
        return opts;
    }

    private static SObject queryTargetRecord(Id recordId, PathWizardConfigModel cfg) {
        List<String> parts = new List<String>{ 'Id', cfg.pathFieldApiName, cfg.dependencyFieldApiName };
        if (objectHasFieldApi(cfg.objectApiName, 'RecordTypeId')) {
            parts.add('RecordTypeId');
        }
        if (String.isNotBlank(cfg.recordTypeDeveloperName)) {
            parts.add('RecordType.DeveloperName');
        }
        system.debug('parts: '+parts);
        String soql = 'SELECT ' + String.join(parts, ', ') + ' FROM ' + cfg.objectApiName + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> rows = Database.query(soql);
        SObject result = null;
        system.debug('returning result '+result);
        if (!rows.isEmpty()) {
            result = rows[0];
        }
        return result;
    }

    private static Boolean isRecordTypeAllowed(SObject row, PathWizardConfigModel cfg) {
        Boolean allowed = true;
        if (String.isNotBlank(cfg.recordTypeDeveloperName)) {
            SObject rt = row.getSObject('RecordType');
            String devName = rt != null ? (String) rt.get('DeveloperName') : null;
            allowed = cfg.recordTypeDeveloperName.equalsIgnoreCase(devName);
        }
        return allowed;
    }

    /**
     * LWC resolves record-type–scoped picklist values only for supported object/field pairs (see configurablePath.js).
     */
    private static Boolean clientRecordTypePicklistSupported(PathWizardConfigModel cfg) {
        if (cfg == null) {
            return false;
        }
        if ('Lead'.equalsIgnoreCase(cfg.objectApiName) && 'Status'.equalsIgnoreCase(cfg.pathFieldApiName)) {
            return true;
        }
        return 'Opportunity'.equalsIgnoreCase(cfg.objectApiName) && 'StageName'.equalsIgnoreCase(cfg.pathFieldApiName);
    }

    /**
     * True when {@code val} matches an active entry on the path picklist (global describe).
     * Record-type restrictions for the path bar are applied in the LWC when {@link PathWizardConfigModel#useClientRecordTypePicklist} is enabled.
     *
     * @param objectApi Target object API name.
     * @param fieldApi Path picklist field API name.
     * @param val Picklist API value to verify.
     * @return Whether the value is an active picklist API value.
     */
    private static Boolean isActivePicklistValue(String objectApi, String fieldApi, String val) {
        Boolean found = false;
        if (String.isBlank(val)) {
            return found;
        }
        Schema.DescribeFieldResult dfr = getFieldDescribe(objectApi, fieldApi);
        if (dfr != null) {
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.getValue().equals(val) && pe.isActive()) {
                    found = true;
                    break;
                }
            }
        }
        return found;
    }

    /**
     * Reads {@code RecordTypeId} from the row when the object defines that field.
     *
     * @param row Loaded SObject.
     * @return Record type Id, or null.
     */
    private static Id getRecordTypeIdFromRow(SObject row) {
        Id rtId = null;
        if (row != null) {
            String objectApi = row.getSObjectType().getDescribe().getName();
            if (objectHasFieldApi(objectApi, 'RecordTypeId')) {
                rtId = (Id) row.get('RecordTypeId');
            }
        }
        return rtId;
    }

    /**
     * Whether the object has a field with the given API name (e.g. {@code RecordTypeId}).
     *
     * @param objectApi Object API name.
     * @param fieldApi Field API name.
     * @return True if the field exists on the object describe.
     */
    private static Boolean objectHasFieldApi(String objectApi, String fieldApi) {
        Boolean has = false;
        Schema.SObjectType ot = Schema.getGlobalDescribe().get(objectApi);
        if (ot != null) {
            has = ot.getDescribe().fields.getMap().containsKey(fieldApi);
        }
        return has;
    }

    private static Schema.DescribeFieldResult getFieldDescribe(String objectApi, String fieldApi) {
        Schema.DescribeFieldResult dfr = null;
        Schema.SObjectType ot = Schema.getGlobalDescribe().get(objectApi);
        if (ot != null) {
            Map<String, Schema.SObjectField> fMap = ot.getDescribe().fields.getMap();
            Schema.SObjectField f = fMap.get(fieldApi);
            if (f != null) {
                dfr = f.getDescribe();
            }
        }
        return dfr;
    }

    private static List<String> normalizeDependencyList(List<String> dependencyValues) {
        List<String> out = new List<String>();
        if (dependencyValues != null) {
            for (String v : dependencyValues) {
                if (String.isNotBlank(v)) {
                    out.add(v.trim());
                }
            }
        }
        return out;
    }

    private static Boolean dependenciesAllowed(
        List<String> cleanedDeps,
        Set<String> allowedFromCmdt,
        PathWizardConfigModel cfg
    ) {
        Schema.DescribeFieldResult depDfr = getFieldDescribe(cfg.objectApiName, cfg.dependencyFieldApiName);
        Set<String> picklistActive = null;
        if (depDfr != null) {
            Schema.DisplayType t = depDfr.getType();
            if (t == Schema.DisplayType.Picklist || t == Schema.DisplayType.MultiPicklist) {
                picklistActive = new Set<String>();
                for (Schema.PicklistEntry pe : depDfr.getPicklistValues()) {
                    if (pe.isActive()) {
                        picklistActive.add(pe.getValue());
                    }
                }
            }
        }
        Boolean ok = true;
        for (String v : cleanedDeps) {
            if (!allowedFromCmdt.contains(v)) {
                ok = false;
                break;
            }
            if (picklistActive != null && !picklistActive.contains(v)) {
                ok = false;
                break;
            }
        }
        return ok;
    }

    private static String joinDependencyForStorage(List<String> cleanedDeps, PathWizardConfigModel cfg) {
        String joined = '';
        if (cleanedDeps.isEmpty()) {
            return joined;
        }
        Schema.DescribeFieldResult depDfr = getFieldDescribe(cfg.objectApiName, cfg.dependencyFieldApiName);
        Boolean useSemicolonJoin = false;
        if (depDfr != null && depDfr.getType() == Schema.DisplayType.MultiPicklist) {
            useSemicolonJoin = true;
        }
        if (cfg.dependencyMultiSelect == true) {
            useSemicolonJoin = true;
        }
        if (useSemicolonJoin) {
            joined = String.join(cleanedDeps, ';');
        } else {
            joined = cleanedDeps[0];
        }
        return joined;
    }

    private static List<String> parseStoredDependencies(String stored, PathWizardConfigModel cfg) {
        List<String> out = new List<String>();
        if (String.isBlank(stored)) {
            return out;
        }
        Schema.DescribeFieldResult depDfr = getFieldDescribe(cfg.objectApiName, cfg.dependencyFieldApiName);
        if (depDfr != null && depDfr.getType() == Schema.DisplayType.MultiPicklist) {
            for (String part : stored.split(';')) {
                if (String.isNotBlank(part)) {
                    out.add(part.trim());
                }
            }
        } else if (cfg.dependencyMultiSelect == true) {
            for (String part : stored.split(';')) {
                if (String.isNotBlank(part)) {
                    out.add(part.trim());
                }
            }
        } else {
            out.add(stored.trim());
        }
        return out;
    }

    private static Boolean canReadFields(PathWizardConfigModel cfg) {
        Schema.DescribeFieldResult p = getFieldDescribe(cfg.objectApiName, cfg.pathFieldApiName);
        Schema.DescribeFieldResult d = getFieldDescribe(cfg.objectApiName, cfg.dependencyFieldApiName);
        Boolean ok = p != null && d != null && p.isAccessible() && d.isAccessible();
        return ok;
    }

    private static Boolean canUpdateFields(PathWizardConfigModel cfg) {
        Schema.DescribeFieldResult p = getFieldDescribe(cfg.objectApiName, cfg.pathFieldApiName);
        Schema.DescribeFieldResult d = getFieldDescribe(cfg.objectApiName, cfg.dependencyFieldApiName);
        system.debug('CFG is '+cfg);
        Boolean ok = p != null && d != null && p.isUpdateable() && d.isUpdateable();
        return ok;
    }

    private static List<ConfigurablePathUiModel.StageRow> buildStages(
        PathWizardConfigModel cfg,
        String currentValue,
        Set<String> programCodes,
        List<PathStageOverrideModel> stageOverrideRows,
        List<String> programScopedMainStageOrder,
        Map<String, String> mainStageLabelOverrides
    ) {
        List<ConfigurablePathUiModel.StageRow> stages = new List<ConfigurablePathUiModel.StageRow>();
        Schema.DescribeFieldResult dfr = getFieldDescribe(cfg.objectApiName, cfg.pathFieldApiName);
        if (dfr == null) {
            return stages;
        }
        List<PathStageOverrideModel> rows = stageOverrideRows != null ? stageOverrideRows : new List<PathStageOverrideModel>();
        Set<String> whitelistSet =
            programScopedMainStageOrder != null && !programScopedMainStageOrder.isEmpty()
                ? new Set<String>(programScopedMainStageOrder)
                : null;
        Map<String, Schema.PicklistEntry> byValue = new Map<String, Schema.PicklistEntry>();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            byValue.put(pe.getValue(), pe);
        }
        List<Schema.PicklistEntry> entries = new List<Schema.PicklistEntry>();
        if (programScopedMainStageOrder != null && !programScopedMainStageOrder.isEmpty()) {
            for (String apiVal : programScopedMainStageOrder) {
                Schema.PicklistEntry pe = byValue.get(apiVal);
                if (pe == null) {
                    continue;
                }
                if (!includeStageOnPath(pe.getValue(), currentValue, programCodes, rows, whitelistSet)) {
                    continue;
                }
                entries.add(pe);
            }
        } else {
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (!pe.isActive()) {
                    continue;
                }
                if (!includeStageOnPath(pe.getValue(), currentValue, programCodes, rows, null)) {
                    continue;
                }
                entries.add(pe);
            }
        }
        Integer currentIndex = -1;
        Integer idx = 0;
        for (Schema.PicklistEntry pe : entries) {
            if (pe.getValue().equals(currentValue)) {
                currentIndex = idx;
                break;
            }
            idx++;
        }
        idx = 0;
        Map<String, String> labels = mainStageLabelOverrides != null ? mainStageLabelOverrides : new Map<String, String>();
        for (Schema.PicklistEntry pe : entries) {
            ConfigurablePathUiModel.StageRow row = new ConfigurablePathUiModel.StageRow();
            String v = pe.getValue();
            row.label = labels.containsKey(v) ? labels.get(v) : pe.getLabel();
            row.value = v;
            row.isCurrent = v.equals(currentValue);
            row.isComplete = currentIndex >= 0 && idx < currentIndex;
            stages.add(row);
            idx++;
        }
        return stages;
    }

    private class LeadProgramRow implements Comparable {
        Id id;
        String programCodeRaw;
        String programCodeNormalized;
        String programDisplayName;
        public Integer compareTo(Object other) {
            LeadProgramRow o = (LeadProgramRow) other;
            String a = programDisplayName != null ? programDisplayName : '';
            String b = o.programDisplayName != null ? o.programDisplayName : '';
            return a.compareTo(b);
        }
    }

    private static Integer countLeadPrograms(Id recordId, PathWizardConfigModel cfg) {
        if (cfg.programFromRootRecord == true) {
            return 0;
        }
        String q =
            'SELECT COUNT() FROM ' +
            cfg.leadProgramObjectApiName +
            ' WHERE ' +
            cfg.leadProgramParentLookupApi +
            ' = :recordId';
        return (Integer) Database.countQuery(q);
    }

    private static Boolean leadProgramHasSubStatusField(PathWizardConfigModel cfg) {
        Schema.SObjectType ot = Schema.getGlobalDescribe().get(cfg.leadProgramObjectApiName);
        if (ot == null) {
            return false;
        }
        return ot.getDescribe().fields.getMap().containsKey(LEAD_PROGRAM_SUB_STATUS_FIELD);
    }

    private static Boolean leadHasSubStatusSummaryField(String objectApi) {
        return String.isNotBlank(objectApi) && objectHasFieldApi(objectApi, LEAD_SUB_STATUS_SUMMARY_FIELD);
    }

    private static Boolean usePerProgramDependencyModal(Id recordId, PathWizardConfigModel cfg) {
        return countLeadPrograms(recordId, cfg) >= MIN_LEAD_PROGRAMS_FOR_PER_PROGRAM_MODAL && leadProgramHasSubStatusField(cfg);
    }

    private static Set<String> singleProgramCodeSet(String normalizedCode) {
        Set<String> s = new Set<String>();
        if (String.isNotBlank(normalizedCode)) {
            s.add(normalizedCode);
        }
        return s;
    }

    private static List<SObject> queryLeadProgramSObjects(Id recordId, PathWizardConfigModel cfg) {
        String rel = cfg.programRelationshipName;
        String codeTok = rel + '.' + cfg.programCodeFieldApi;
        String nameTok = rel + '.Name';
        List<String> parts = new List<String>{ 'Id', nameTok, codeTok };
        if (leadProgramHasSubStatusField(cfg)) {
            parts.add(LEAD_PROGRAM_SUB_STATUS_FIELD);
        }
        String fList = String.join(parts, ', ');
        String q =
            'SELECT ' +
            fList +
            ' FROM ' +
            cfg.leadProgramObjectApiName +
            ' WHERE ' +
            cfg.leadProgramParentLookupApi +
            ' = :recordId ORDER BY ' +
            nameTok +
            ' NULLS LAST';
        return Database.query(q);
    }

    private static Map<Id, LeadProgramRow> loadLeadProgramRowMap(Id recordId, PathWizardConfigModel cfg) {
        Map<Id, LeadProgramRow> m = new Map<Id, LeadProgramRow>();
        for (SObject lp : queryLeadProgramSObjects(recordId, cfg)) {
            LeadProgramRow r = new LeadProgramRow();
            r.id = lp.Id;
            SObject prog = lp.getSObject(cfg.programRelationshipName);
            Object codeObj = prog != null ? prog.get(cfg.programCodeFieldApi) : null;
            r.programCodeRaw = codeObj != null ? String.valueOf(codeObj) : '';
            r.programCodeNormalized = normalizeProgramCode(r.programCodeRaw);
            Object nameObj = prog != null ? prog.get('Name') : null;
            String pname = nameObj != null ? String.valueOf(nameObj) : '';
            r.programDisplayName = String.isNotBlank(pname) ? pname : String.valueOf(lp.Id);
            m.put(r.id, r);
        }
        return m;
    }

    private static List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> buildLeadProgramSubStatusBlocks(
        Id recordId,
        PathWizardConfigModel cfg
    ) {
        List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> blocks = new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();
        for (SObject lp : queryLeadProgramSObjects(recordId, cfg)) {
            blocks.add(toSubStatusBlock(lp, cfg, new List<PathDependencyValueModel>()));
        }
        return blocks;
    }

    private static List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> buildProgramContextsWithOptions(
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> cmdtRows,
        String targetPathValue
    ) {
        List<ConfigurablePathUiModel.LeadProgramSubStatusBlock> blocks = new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>();
        for (SObject lp : queryLeadProgramSObjects(recordId, cfg)) {
            SObject prog = lp.getSObject(cfg.programRelationshipName);
            String norm = '';
            if (prog != null) {
                Object c = prog.get(cfg.programCodeFieldApi);
                norm = normalizeProgramCode(c != null ? String.valueOf(c) : '');
            }
            List<PathDependencyValueModel> merged = filterDependencyRowsByProgramAndStage(
                cmdtRows,
                singleProgramCodeSet(norm),
                targetPathValue
            );
            blocks.add(toSubStatusBlock(lp, cfg, merged));
        }
        return blocks;
    }

    private static ConfigurablePathUiModel.LeadProgramSubStatusBlock toSubStatusBlock(
        SObject lp,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> mergedForOptions
    ) {
        ConfigurablePathUiModel.LeadProgramSubStatusBlock b = new ConfigurablePathUiModel.LeadProgramSubStatusBlock();
        b.leadProgramId = String.valueOf(lp.Id);
        SObject prog = lp.getSObject(cfg.programRelationshipName);
        Object nameObj = prog != null ? prog.get('Name') : null;
        String pname = nameObj != null ? String.valueOf(nameObj) : '';
        Object codeObj = prog != null ? prog.get(cfg.programCodeFieldApi) : null;
        String code = codeObj != null ? String.valueOf(codeObj) : '';
        b.programName = String.isNotBlank(pname) ? pname : 'Program';
        b.programCode = code;
        if (leadProgramHasSubStatusField(cfg)) {
            Object cv = lp.get(LEAD_PROGRAM_SUB_STATUS_FIELD);
            b.currentValue = cv != null ? String.valueOf(cv) : '';
        } else {
            b.currentValue = '';
        }
        b.options = toOptionRows(mergedForOptions);
        return b;
    }

    private static Boolean canUpdateMultiProgramPathFields(PathWizardConfigModel cfg) {
        Schema.DescribeFieldResult p = getFieldDescribe(cfg.objectApiName, cfg.pathFieldApiName);
        Schema.DescribeFieldResult lpss = getFieldDescribe(cfg.leadProgramObjectApiName, LEAD_PROGRAM_SUB_STATUS_FIELD);
        if (p == null || lpss == null || !p.isUpdateable() || !lpss.isUpdateable()) {
            return false;
        }
        if (leadHasSubStatusSummaryField(cfg.objectApiName)) {
            Schema.DescribeFieldResult s = getFieldDescribe(cfg.objectApiName, LEAD_SUB_STATUS_SUMMARY_FIELD);
            return s != null && s.isUpdateable();
        }
        return true;
    }

    private static ConfigurablePathSaveResult savePerProgramPathTransition(
        ConfigurablePathSaveResult outcome,
        Id recordId,
        PathWizardConfigModel cfg,
        List<PathDependencyValueModel> cmdtRows,
        String newPathValue,
        List<ConfigurablePathUiModel.ProgramSubStatusSaveItem> perProgramSubStatuses
    ) {
        if (perProgramSubStatuses == null || perProgramSubStatuses.isEmpty()) {
            outcome.message = 'Select a sub-status for each program.';
            return outcome;
        }
        Map<Id, LeadProgramRow> rows = loadLeadProgramRowMap(recordId, cfg);
        if (rows.isEmpty()) {
            outcome.message = 'No lead program rows found.';
            return outcome;
        }
        if (perProgramSubStatuses.size() != rows.size()) {
            outcome.message =
                'Provide exactly one sub-status selection per lead program (' + String.valueOf(rows.size()) + ' required).';
            return outcome;
        }
        Map<Id, String> valueByLpId = new Map<Id, String>();
        for (ConfigurablePathUiModel.ProgramSubStatusSaveItem item : perProgramSubStatuses) {
            if (String.isBlank(item.leadProgramId)) {
                outcome.message = 'Each program selection must include a lead program Id.';
                return outcome;
            }
            Id lpId;
            try {
                lpId = Id.valueOf(item.leadProgramId.trim());
            } catch (Exception e) {
                outcome.message = 'Invalid lead program Id.';
                return outcome;
            }
            if (!rows.containsKey(lpId)) {
                outcome.message = 'Invalid lead program Id for this lead.';
                return outcome;
            }
            valueByLpId.put(lpId, String.isBlank(item.subStatusValue) ? '' : item.subStatusValue.trim());
        }
        for (Id lpId : rows.keySet()) {
            LeadProgramRow lpRow = rows.get(lpId);
            Set<String> allowed = toAllowedValueSet(
                filterDependencyRowsByProgramAndStage(
                    cmdtRows,
                    singleProgramCodeSet(lpRow.programCodeNormalized),
                    newPathValue
                )
            );
            String picked = valueByLpId.get(lpId);
            if (cfg.dependencyRequired && !allowed.isEmpty() && String.isBlank(picked)) {
                outcome.message = 'Select a sub-status for ' + lpRow.programDisplayName + '.';
                return outcome;
            }
            if (String.isNotBlank(picked)) {
                if (!allowed.isEmpty() && !allowed.contains(picked)) {
                    outcome.message = 'Sub-status is not allowed for ' + lpRow.programDisplayName + '.';
                    return outcome;
                }
                List<String> single = new List<String>{ picked };
                if (!dependenciesAllowed(single, allowed, cfg)) {
                    outcome.message = 'Sub-status picklist validation failed for ' + lpRow.programDisplayName + '.';
                    return outcome;
                }
            }
        }
        if (!canUpdateMultiProgramPathFields(cfg)) {
            outcome.message = 'You do not have permission to update path, program sub-status, or summary fields.';
            return outcome;
        }
        List<LeadProgramRow> ordered = new List<LeadProgramRow>();
        for (LeadProgramRow r : rows.values()) {
            ordered.add(r);
        }
        ordered.sort();
        List<SObject> lpUpdates = new List<SObject>();
        List<String> summaryParts = new List<String>();
        Schema.SObjectType lpType = Schema.getGlobalDescribe().get(cfg.leadProgramObjectApiName);
        system.debug('Ordered: '+ordered);
        for (LeadProgramRow lpRow : ordered) {
            String val = valueByLpId.get(lpRow.id);
            SObject lpS = lpType.newSObject(lpRow.id);
            lpS.put(LEAD_PROGRAM_SUB_STATUS_FIELD, String.isNotBlank(val) ? val : null);
            lpUpdates.add(lpS);
            if (String.isNotBlank(val)) {
                String codeRaw = String.isNotBlank(lpRow.programCodeRaw) ? lpRow.programCodeRaw.trim() : '';
                if (String.isNotBlank(codeRaw)) {
                    summaryParts.add(codeRaw + ':' + val);
                } else {
                    summaryParts.add(lpRow.programDisplayName + ':' + val);
                }
            }
        }
        try {
            system.debug('Updating Lps: '+lpUpdates);
            update lpUpdates;
            SObject leadUp = Schema.getGlobalDescribe().get(cfg.objectApiName).newSObject(recordId);
            leadUp.put(cfg.pathFieldApiName, newPathValue);
            if (leadHasSubStatusSummaryField(cfg.objectApiName)) {
                leadUp.put(LEAD_SUB_STATUS_SUMMARY_FIELD, String.join(summaryParts, '; '));
            }
            update leadUp;
        } catch (DmlException e) {
            outcome.message = e.getDmlMessage(0);
            return outcome;
        }
        outcome.success = true;
        outcome.message = 'Saved.';
        return outcome;
    }
}