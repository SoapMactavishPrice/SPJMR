/**
 * One allowed dependency value (from {@link Path_Dependency_Value__mdt} or supplied in tests).
 */
public with sharing class PathDependencyValueModel {
    public String programCode { get; set; }
    /** API value of path picklist stage; blank means all stages. */
    public String pathStageValueApi { get; set; }
    public String valueApi { get; set; }
    public String label { get; set; }
    public Decimal sortOrder { get; set; }

    /**
     * Builds a model from a custom metadata row.
     *
     * @param row Dependency value metadata row.
     * @return Model instance, or null when {@code row} is null.
     */
    public static PathDependencyValueModel fromCmdt(Path_Dependency_Value__mdt row) {
        PathDependencyValueModel result = null;
        if (row != null) {
            result = new PathDependencyValueModel();
            result.programCode = row.Program_Code__c;
            result.pathStageValueApi = row.Path_Stage_Value_API__c;
            result.valueApi = row.Value_API__c;
            result.label = String.isNotBlank(row.Label__c) ? row.Label__c : row.Value_API__c;
            result.sortOrder = row.Sort_Order__c;
        }
        return result;
    }
}