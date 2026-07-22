@IsTest
private class PathStageOverrideModelTest {

    @IsTest
    static void loadRowsForConfig_blankReturnsEmpty() {
        System.assertEquals(0, PathStageOverrideModel.loadRowsForConfig(null).size());
        System.assertEquals(0, PathStageOverrideModel.loadRowsForConfig('').size());
        System.assertEquals(0, PathStageOverrideModel.loadRowsForConfig('   ').size());
    }

    @IsTest
    static void loadRowsForConfig_noMatchingConfigReturnsEmpty() {
        List<PathStageOverrideModel> rows = PathStageOverrideModel.loadRowsForConfig('__unknown_config_for_test__');
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void resolveForPathValue_returnsDefaultsWhenBlankInputs() {
        PathStageOverrideModel.ResolvedStageOverride r1 =
            PathStageOverrideModel.resolveForPathValue(null, new Set<String>(), new List<PathStageOverrideModel>());
        System.assertEquals(false, r1.hasApplicableRules);
        System.assertEquals(true, r1.showOnPath);
        System.assertEquals(false, r1.openSubStatusModal);

        PathStageOverrideModel.ResolvedStageOverride r2 =
            PathStageOverrideModel.resolveForPathValue('STAGE_A', new Set<String>(), null);
        System.assertEquals(false, r2.hasApplicableRules);
    }

    @IsTest
    static void resolveForPathValue_appliesMatchingRowsAndPicksRestrictiveFlags() {
        PathStageOverrideModel hidesRow = new PathStageOverrideModel();
        hidesRow.pathStageValueApi = 'STAGE_A';
        hidesRow.programCode = 'gmp';
        hidesRow.showOnPath = false;
        hidesRow.openSubStatusModal = false;

        PathStageOverrideModel opensModalRow = new PathStageOverrideModel();
        opensModalRow.pathStageValueApi = 'STAGE_A';
        opensModalRow.programCode = null; // matches any program
        opensModalRow.showOnPath = true;
        opensModalRow.openSubStatusModal = true;

        PathStageOverrideModel otherStageRow = new PathStageOverrideModel();
        otherStageRow.pathStageValueApi = 'STAGE_B';
        otherStageRow.programCode = 'gmp';
        otherStageRow.showOnPath = true;
        otherStageRow.openSubStatusModal = true;

        PathStageOverrideModel.ResolvedStageOverride r = PathStageOverrideModel.resolveForPathValue(
            'STAGE_A',
            new Set<String>{ 'gmp' },
            new List<PathStageOverrideModel>{ hidesRow, opensModalRow, otherStageRow }
        );
        System.assertEquals(true, r.hasApplicableRules);
        System.assertEquals(false, r.showOnPath, 'Any hide-row should win');
        System.assertEquals(true, r.openSubStatusModal, 'Any open-modal-row should win');
    }

    @IsTest
    static void resolveForPathValue_programCodeFilterExcludesNonMatching() {
        PathStageOverrideModel row = new PathStageOverrideModel();
        row.pathStageValueApi = 'STAGE_A';
        row.programCode = 'pgdm';
        row.showOnPath = false;
        row.openSubStatusModal = true;

        PathStageOverrideModel.ResolvedStageOverride r = PathStageOverrideModel.resolveForPathValue(
            'STAGE_A',
            new Set<String>{ 'gmp' },
            new List<PathStageOverrideModel>{ row }
        );
        System.assertEquals(false, r.hasApplicableRules);
        System.assertEquals(true, r.showOnPath);
        System.assertEquals(false, r.openSubStatusModal);
    }
}