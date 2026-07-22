/**
 * Controller for Department Master typeahead used by the
 * createlearningCourse LWC.
 */
public with sharing class DepartmentMasterController {

    private static final Integer SEARCH_LIMIT = 15;

    public class DepartmentOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
    }

    @AuraEnabled(cacheable=false)
    public static List<DepartmentOption> searchDepartmentMasters(String searchTerm) {
        List<DepartmentOption> options = new List<DepartmentOption>();
        String raw = String.isBlank(searchTerm) ? '' : String.escapeSingleQuotes(searchTerm.trim());
        String term = String.isBlank(raw) ? '%' : '%' + raw + '%';
        for (Department_Master__c d : [
            SELECT Id, Name
            FROM Department_Master__c
            WHERE Name LIKE :term
               OR Department_Code__c LIKE :term
            ORDER BY Name
            LIMIT :SEARCH_LIMIT
        ]) {
            DepartmentOption o = new DepartmentOption();
            o.label = d.Name;
            o.value = d.Id;
            options.add(o);
        }
        return options;
    }
}