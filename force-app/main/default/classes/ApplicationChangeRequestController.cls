public with sharing class ApplicationChangeRequestController {

    @AuraEnabled(cacheable=true)
    public static Id getApplicationId(Id verificationId) {
        return [
            SELECT Application__c
            FROM Application_Verification__c
            WHERE Id = :verificationId
            LIMIT 1
        ].Application__c;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> fetchExistingRequestKeys(Id applicationId) {
        List<String> keys = new List<String>();

        for (Application_Change_Request__c r : [
            SELECT Section_Label__c, Field_API__c, Row_Index__c
            FROM Application_Change_Request__c
            WHERE Application__c = :applicationId
            AND Status__c != 'Closed'
        ]) {
            Integer idx = r.Row_Index__c == null ? 0 : Integer.valueOf(r.Row_Index__c);
            keys.add(r.Section_Label__c + '|' + r.Field_API__c + '|' + idx);
        }
        return keys;
    }

    @AuraEnabled
    public static void saveChangeRequests(Id verificationId, String requestJson) {

        Id appId = getApplicationId(verificationId);
        if (appId == null) {
            throw new AuraHandledException('Application not found');
        }

        List<ChangeRequestWrapper> reqs =
            (List<ChangeRequestWrapper>) JSON.deserialize(
                requestJson,
                List<ChangeRequestWrapper>.class
            );

        List<Application_Change_Request__c> inserts = new List<Application_Change_Request__c>();

        for (ChangeRequestWrapper w : reqs) {
            inserts.add(new Application_Change_Request__c(
                Application__c        = appId,
                Section_Label__c      = w.sectionLabel,
                Section_Object_API__c = w.sectionObjectApi,
                Field_Label__c        = w.fieldLabel,
                Field_API__c          = w.fieldApi,
                Current_Value__c      = w.currentValue,
                Staff_Remark__c       = w.remark,
                Row_Index__c          = w.rowIndex,
                Status__c             = 'Requested'
            ));
        }

        if (!inserts.isEmpty()) {
            insert inserts;
        }
    }

    public class ChangeRequestWrapper {
        @AuraEnabled public String sectionLabel;
        @AuraEnabled public String sectionObjectApi;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String fieldApi;
        @AuraEnabled public String currentValue;
        @AuraEnabled public String remark;
        @AuraEnabled public Integer rowIndex;
    }
}