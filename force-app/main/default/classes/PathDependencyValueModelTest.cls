@IsTest
private class PathDependencyValueModelTest {
    @IsTest
    static void fromCmdtNullReturnsNull() {
        System.assertEquals(null, PathDependencyValueModel.fromCmdt(null));
    }
    @IsTest
    static void fromCmdt_buildsFromMetadataRow() {
        // Construct a CMDT instance via JSON deserialize so we can pass to fromCmdt
        // and exercise the success-branch body.
        Path_Dependency_Value__mdt row = (Path_Dependency_Value__mdt) JSON.deserialize(
            '{"attributes":{"type":"Path_Dependency_Value__mdt"},' +
            '"Program_Code__c":"PGP","Path_Stage_Value_API__c":"Stage1",' +
            '"Value_API__c":"V1","Label__c":"My Label","Sort_Order__c":10}',
            Path_Dependency_Value__mdt.class
        );
        PathDependencyValueModel m = PathDependencyValueModel.fromCmdt(row);
        System.assertNotEquals(null, m);
        System.assertEquals('PGP', m.programCode);
        System.assertEquals('My Label', m.label);

        // Blank label falls back to valueApi
        Path_Dependency_Value__mdt row2 = (Path_Dependency_Value__mdt) JSON.deserialize(
            '{"attributes":{"type":"Path_Dependency_Value__mdt"},' +
            '"Value_API__c":"V2","Label__c":""}',
            Path_Dependency_Value__mdt.class
        );
        PathDependencyValueModel m2 = PathDependencyValueModel.fromCmdt(row2);
        System.assertEquals('V2', m2.label);
    }
    @IsTest
    static void gettersSetters() {
        PathDependencyValueModel m = new PathDependencyValueModel();
        m.programCode = 'P'; m.pathStageValueApi = 'S'; m.valueApi = 'V';
        m.label = 'L'; m.sortOrder = 5;
        System.assertEquals('P', m.programCode);
        System.assertEquals(5, m.sortOrder);
    }
}