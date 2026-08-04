@IsTest
private class ConfigurablePathUiModelTest {

    @IsTest
    static void testUiModelProperties() {

        ConfigurablePathUiModel model = new ConfigurablePathUiModel();

        model.loadOk = true;
        model.loadErrorMessage = 'Error';
        model.currentPathValue = 'Hot';
        model.modalTitle = 'Update Status';
        model.pathFieldModalLabel = 'Status';
        model.showPathFieldInModal = true;
        model.dependencyFieldLabel = 'Sub Status';
        model.dependencyMultiSelect = true;
        model.dependencyOptionsByTargetStage = true;
        model.configDeveloperName = 'B2C_Lead_Path';
        model.useClientPathStages = true;
        model.pathRecordTypeId = '012000000000000AAA';
        model.pathObjectApiName = 'Lead';
        model.pathFieldApiName = 'Status';

        ConfigurablePathUiModel.StageRow stage =
            new ConfigurablePathUiModel.StageRow();
        stage.label = 'Hot';
        stage.value = 'Hot';
        stage.isCurrent = true;
        stage.isComplete = false;
        model.stages = new List<ConfigurablePathUiModel.StageRow>{ stage };

        ConfigurablePathUiModel.OptionRow option =
            new ConfigurablePathUiModel.OptionRow();
        option.label = 'Interested';
        option.value = 'Interested';
        model.dependencyOptions =
            new List<ConfigurablePathUiModel.OptionRow>{ option };

        model.selectedDependencyValues =
            new List<String>{ 'Interested' };

        model.fieldsToRefresh =
            new List<String>{ 'Status', 'Sub_Status__c' };

        ConfigurablePathUiModel.StageUiFlags flags =
            new ConfigurablePathUiModel.StageUiFlags();
        flags.showOnPath = true;
        flags.openSubStatusModal = false;
        model.stageUiFlagsByPathValue =
            new Map<String, ConfigurablePathUiModel.StageUiFlags>{
                'Hot' => flags
            };

        model.programScopedMainStageApis =
            new List<String>{ 'Hot' };

        model.mainStageLabelByApi =
            new Map<String, String>{
                'Hot' => 'Hot'
            };

        ConfigurablePathUiModel.LeadProgramSubStatusBlock block =
            new ConfigurablePathUiModel.LeadProgramSubStatusBlock();
        block.leadProgramId = 'a01000000000001AAA';
        block.programName = 'GMP';
        block.programCode = 'GMP';
        block.currentValue = 'Interested';
        block.options =
            new List<ConfigurablePathUiModel.OptionRow>{ option };

        model.usePerProgramDependencyModal = true;
        model.leadProgramSubStatusBlocks =
            new List<ConfigurablePathUiModel.LeadProgramSubStatusBlock>{
                block
            };

        ConfigurablePathUiModel.ProgramSubStatusSaveItem saveItem =
            new ConfigurablePathUiModel.ProgramSubStatusSaveItem();
        saveItem.leadProgramId = 'a01000000000001AAA';
        saveItem.subStatusValue = 'Qualified';

        System.assert(model.loadOk);
        System.assertEquals('Error', model.loadErrorMessage);
        System.assertEquals('Hot', model.currentPathValue);
        System.assertEquals(1, model.stages.size());
        System.assertEquals('Hot', model.stages[0].value);
        System.assertEquals(1, model.dependencyOptions.size());
        System.assertEquals('Interested', model.dependencyOptions[0].value);
        System.assertEquals(1, model.stageUiFlagsByPathValue.size());
        System.assertEquals(true, model.stageUiFlagsByPathValue.get('Hot').showOnPath);
        System.assertEquals(1, model.leadProgramSubStatusBlocks.size());
        System.assertEquals('GMP', model.leadProgramSubStatusBlocks[0].programCode);
        System.assertEquals('Qualified', saveItem.subStatusValue);
    }
}