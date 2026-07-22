@IsTest
private class PathWizardConfigModelTest {
    @IsTest
    static void settersAndGetters() {
        PathWizardConfigModel m = new PathWizardConfigModel();
        m.developerName = 'd';
        m.objectApiName = 'Lead';
        m.pathFieldApiName = 'Status';
        m.dependencyFieldApiName = 'Sub_Status__c';
        m.recordTypeDeveloperName = 'rt';
        m.modalTitle = 'title';
        m.showPathFieldInModal = true;
        m.pathFieldModalLabel = 'lbl';
        m.dependencyFieldLabel = 'depLbl';
        m.dependencyMultiSelect = false;
        System.assertEquals('d', m.developerName);
        System.assertEquals('Lead', m.objectApiName);
        System.assertEquals(true, m.showPathFieldInModal);
        System.assertEquals(false, m.dependencyMultiSelect);
    }
}