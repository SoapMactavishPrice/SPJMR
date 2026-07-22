public with sharing class ApplicationNumberFetcher {

    public class AppInfoWrapper {
        @AuraEnabled public String appNumber;
        @AuraEnabled public String programCode;
    }

   // @AuraEnabled(cacheable=true)
    @AuraEnabled
    public static AppInfoWrapper getApplicationNumber(Id recordId) {

        Application__c app = [
            SELECT Name, Program__r.Program_Code__c
            FROM Application__c
            WHERE Id = :recordId
            LIMIT 1  FOR UPDATE
        ];

        AppInfoWrapper w = new AppInfoWrapper();
        w.appNumber = app.Name;
        w.programCode = app.Program__r.Program_Code__c;

        return w;
    }
}