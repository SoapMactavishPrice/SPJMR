@IsTest
private class PathMainStageValueModelTest {

    @IsTest
    static void fromCmdt_nullReturnsNull() {
        System.assertEquals(null, PathMainStageValueModel.fromCmdt(null));
    }

    @IsTest
    static void fromCmdt_copiesFields() {
        Path_Main_Stage_Value__mdt row = new Path_Main_Stage_Value__mdt(
            Program_Code__c = 'GMP',
            Path_Stage_Value_API__c = 'STAGE_A',
            Label__c = 'Stage A',
            Sort_Order__c = 10
        );
        PathMainStageValueModel m = PathMainStageValueModel.fromCmdt(row);
        System.assertNotEquals(null, m);
        System.assertEquals('GMP', m.programCode);
        System.assertEquals('STAGE_A', m.pathStageValueApi);
        System.assertEquals('Stage A', m.label);
        System.assertEquals(10, m.sortOrder);
    }

    @IsTest
    static void resolveForPrograms_emptyInputsReturnEmpty() {
        PathMainStageValueModel.ProgramScopedMainStages a =
            PathMainStageValueModel.resolveForPrograms(null, new List<PathMainStageValueModel>());
        System.assertEquals(false, a.hasWhitelist());

        PathMainStageValueModel.ProgramScopedMainStages b =
            PathMainStageValueModel.resolveForPrograms(new Set<String>{ 'gmp' }, null);
        System.assertEquals(false, b.hasWhitelist());

        PathMainStageValueModel.ProgramScopedMainStages c =
            PathMainStageValueModel.resolveForPrograms(new Set<String>(), new List<PathMainStageValueModel>());
        System.assertEquals(false, c.hasWhitelist());
    }

    @IsTest
    static void resolveForPrograms_picksLowestSortAndOrders() {
        PathMainStageValueModel m1 = build('GMP', 'STAGE_A', 'A Label', 20);
        PathMainStageValueModel m2 = build('GMP', 'STAGE_A', 'Better A', 10);  // wins by sort
        PathMainStageValueModel m3 = build('GMP', 'STAGE_B', 'B Label', 5);
        PathMainStageValueModel m4 = build('OTHER', 'STAGE_X', 'X Label', 1);   // filtered out by program

        PathMainStageValueModel.ProgramScopedMainStages result = PathMainStageValueModel.resolveForPrograms(
            new Set<String>{ 'gmp' },
            new List<PathMainStageValueModel>{ m1, m2, m3, m4 }
        );

        System.assertEquals(true, result.hasWhitelist());
        System.assertEquals(2, result.orderedApis.size());
        System.assertEquals('STAGE_B', result.orderedApis[0], 'STAGE_B has lower sort');
        System.assertEquals('STAGE_A', result.orderedApis[1]);
        System.assertEquals('Better A', result.labelOverrideByApi.get('STAGE_A'));
        System.assertEquals('B Label', result.labelOverrideByApi.get('STAGE_B'));
        System.assertEquals(false, result.labelOverrideByApi.containsKey('STAGE_X'));
    }

    @IsTest
    static void resolveForPrograms_skipsBlankStageApiAndHandlesNullSort() {
        PathMainStageValueModel blank = build('GMP', '   ', 'lbl', null);
        PathMainStageValueModel nullSort = build('GMP', 'STAGE_A', null, null);

        PathMainStageValueModel.ProgramScopedMainStages result = PathMainStageValueModel.resolveForPrograms(
            new Set<String>{ 'gmp' },
            new List<PathMainStageValueModel>{ blank, nullSort }
        );
        System.assertEquals(true, result.hasWhitelist());
        System.assertEquals(1, result.orderedApis.size());
        System.assertEquals('STAGE_A', result.orderedApis[0]);
        // Null/blank label means no override stored
        System.assertEquals(false, result.labelOverrideByApi.containsKey('STAGE_A'));
    }

    @IsTest
    static void programScopedMainStages_constructorInitialises() {
        PathMainStageValueModel.ProgramScopedMainStages s = new PathMainStageValueModel.ProgramScopedMainStages();
        System.assertNotEquals(null, s.orderedApis);
        System.assertNotEquals(null, s.labelOverrideByApi);
        System.assertEquals(false, s.hasWhitelist());
    }

    private static PathMainStageValueModel build(String pc, String api, String labelVal, Decimal sortKey) {
        PathMainStageValueModel m = new PathMainStageValueModel();
        m.programCode = pc;
        m.pathStageValueApi = api;
        m.label = labelVal;
        m.sortOrder = sortKey;
        return m;
    }
}