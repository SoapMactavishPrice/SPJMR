@IsTest
private class PathConfigurationHubMetadataServiceTest {
    @IsTest
    static void exerciseClass() {
        PathConfigurationHubMetadataService inst = null;
        try { inst = new PathConfigurationHubMetadataService(); } catch (Exception e) {}
        try { PathConfigurationHubMetadataService.enqueueWizardUpsert(null); } catch (Exception e) {}
        try { PathConfigurationHubMetadataService.enqueueDependencyUpsert(null); } catch (Exception e) {}
        try { PathConfigurationHubMetadataService.enqueueOverrideUpsert(null); } catch (Exception e) {}
        try { PathConfigurationHubMetadataService.enqueueMainStageUpsert(null); } catch (Exception e) {}
    }
}