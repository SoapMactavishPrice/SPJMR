public with sharing class LeadProgramManagerController {

    @AuraEnabled(cacheable=true)
    public static List<Lead_Sources__c> getLeadSources(Id leadId) {
        return [
            SELECT Id, Program__c, Primary__c
            FROM Lead_Sources__c
            WHERE Lead__c = :leadId
            ORDER BY CreatedDate ASC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Program> getPrograms() {
        return [
            SELECT Id, Name
            FROM Program
            ORDER BY Name
        ];
    }

    @AuraEnabled
    public static void saveLeadSources(Id leadId, List<Lead_Sources__c> rows) {

        if (rows == null || rows.isEmpty()) return;

        for (Lead_Sources__c ls : rows) {
            ls.Lead__c = leadId;
        }

        upsert rows;

        Lead_Sources__c primaryRow;

        for (Lead_Sources__c ls : rows) {
            if (ls.Primary__c == true) {
                primaryRow = ls;
                break;
            }
        }

        if (primaryRow != null && primaryRow.Program__c != null) {
            update new Lead(
                Id = leadId,
                Program_Master__c = primaryRow.Program__c
            );
        }
    }
}