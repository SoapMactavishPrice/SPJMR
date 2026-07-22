/**
 * In-memory snapshot of {@link Path_Wizard_Config__mdt} used by {@link ConfigurablePathService} and unit tests.
 */
public with sharing class PathWizardConfigModel {
    public String developerName { get; set; }
    public String objectApiName { get; set; }
    public String pathFieldApiName { get; set; }
    public String dependencyFieldApiName { get; set; }
    public String recordTypeDeveloperName { get; set; }
    public String modalTitle { get; set; }
    public Boolean showPathFieldInModal { get; set; }
    public String pathFieldModalLabel { get; set; }
    public String dependencyFieldLabel { get; set; }
    public Boolean dependencyMultiSelect { get; set; }
    public String leadProgramObjectApiName { get; set; }
    public String leadProgramParentLookupApi { get; set; }
    public String programLookupApi { get; set; }
    public String programRelationshipName { get; set; }
    public String programCodeFieldApi { get; set; }
    public Boolean allowEmptyLeadPrograms { get; set; }
    public Boolean dependencyRequired { get; set; }
    /**
     * When true, the configurable path LWC loads path picklist options with UI API semantics (per record type).
     */
    public Boolean useClientRecordTypePicklist { get; set; }
    /**
     * When true, program code(s) for path scoping come from the path root row via {@code Program_Relationship_Name__c}
     * (e.g. {@code Opportunity.Program__r.Program_Code__c}). When false, from junction rows using Lead Program object + parent lookup.
     */
    public Boolean programFromRootRecord { get; set; }

    /**
     * Maps a custom metadata row into a mutable model for service logic.
     *
     * @param row Loaded path wizard configuration metadata.
     * @return Populated model, or null when {@code row} is null.
     */
    public static PathWizardConfigModel fromCmdt(Path_Wizard_Config__mdt row) {
        PathWizardConfigModel result = null;
        if (row != null) {
            result = new PathWizardConfigModel();
            result.developerName = String.isNotBlank(row.DeveloperName) ? row.DeveloperName : null;
            result.objectApiName = row.Object_API_Name__c;
            result.pathFieldApiName = row.Path_Field_API_Name__c;
            result.dependencyFieldApiName = row.Dependency_Field_API_Name__c;
            result.recordTypeDeveloperName = row.Record_Type_Developer_Name__c;
            result.modalTitle = row.Modal_Title__c;
            result.showPathFieldInModal = row.Show_Path_Field_In_Modal__c == true;
            result.pathFieldModalLabel = row.Path_Field_Modal_Label__c;
            result.dependencyFieldLabel = row.Dependency_Field_Label__c;
            result.dependencyMultiSelect = row.Dependency_Multi_Select__c == true;
            result.leadProgramObjectApiName = String.isNotBlank(row.Lead_Program_Object_API_Name__c)
                ? row.Lead_Program_Object_API_Name__c
                : 'Lead_Program__c';
            result.leadProgramParentLookupApi = String.isNotBlank(row.Lead_Program_Parent_Lookup_API__c)
                ? row.Lead_Program_Parent_Lookup_API__c
                : 'Lead__c';
            result.programLookupApi = String.isNotBlank(row.Program_Lookup_API__c) ? row.Program_Lookup_API__c : 'Program__c';
            result.programRelationshipName = String.isNotBlank(row.Program_Relationship_Name__c)
                ? row.Program_Relationship_Name__c
                : 'Program__r';
            result.programCodeFieldApi = String.isNotBlank(row.Program_Code_Field_API__c)
                ? row.Program_Code_Field_API__c
                : 'Program_Code__c';
            result.allowEmptyLeadPrograms = row.Allow_Empty_Lead_Programs__c == true;
            result.dependencyRequired = row.Dependency_Required__c != false;
            result.useClientRecordTypePicklist = row.Use_Client_Record_Type_Picklist__c == true;
            result.programFromRootRecord = row.Program_From_Root_Record__c == true;
        }
        return result;
    }
}