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
    
     @IsTest
    static void testAdditional() {
      Path_Wizard_Config__mdt m = [SELECT Id, DeveloperName, MasterLabel, Language, 
          NamespacePrefix, Label, QualifiedApiName, SystemModstamp, Allow_Empty_Lead_Programs__c, 
          Dependency_Field_API_Name__c, Dependency_Field_Label__c, Dependency_Multi_Select__c, 
          Dependency_Required__c, Lead_Program_Object_API_Name__c, Lead_Program_Parent_Lookup_API__c, 
          Modal_Title__c, Object_API_Name__c, Path_Field_API_Name__c, Path_Field_Modal_Label__c, 
          Program_Code_Field_API__c, Program_Lookup_API__c, Program_Relationship_Name__c, 
          Record_Type_Developer_Name__c, Show_Path_Field_In_Modal__c, Use_Client_Record_Type_Picklist__c,
          Program_From_Root_Record__c FROM Path_Wizard_Config__mdt LIMIT 1];
        PathWizardConfigModel s = PathWizardConfigModel.fromCmdt(m);
        system.assert(s!=null);
    }
}