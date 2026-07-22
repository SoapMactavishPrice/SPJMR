@IsTest
private class PathConfigurationHubModelsTest {
    @IsTest
    static void snapshotConstructorInitializesLists() {
        PathConfigurationHubModels.Snapshot s = new PathConfigurationHubModels.Snapshot();
        System.assertNotEquals(null, s.wizards);
        System.assertNotEquals(null, s.dependencies);
        System.assertNotEquals(null, s.overrides);
        System.assertNotEquals(null, s.mainStages);
        System.assertEquals(0, s.wizards.size());
    }
    @IsTest
    static void rowDtosAreSettable() {
        PathConfigurationHubModels.WizardRow w = new PathConfigurationHubModels.WizardRow();
        w.developerName = 'x'; w.masterLabel = 'X';
        System.assertEquals('x', w.developerName);

        PathConfigurationHubModels.DependencyRow dr = new PathConfigurationHubModels.DependencyRow();
        dr.valueApi = 'v';
        System.assertEquals('v', dr.valueApi);

        PathConfigurationHubModels.OverrideRow o = new PathConfigurationHubModels.OverrideRow();
        o.developerName = 'o';
        System.assertEquals('o', o.developerName);
    }
}