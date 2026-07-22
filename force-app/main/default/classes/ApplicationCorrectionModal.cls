public without sharing class ApplicationCorrectionModal {
   @AuraEnabled(cacheable=true)
public static String getApplicationScriptById(String applicationId) {
    try {
        // Fetch the application and its script reference
        Application__c app = [
            SELECT Id, Script__c, Program__r.Program_Code__c,Email__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];

        // (Optional fallback) Try to fetch from ContentVersion if stored as file
        ContentVersion versions = [
            SELECT Id, Title  ,VersionData
            FROM ContentVersion 
            Where ContentDocumentId =:app.Script__c
        ];

        Blob dataBlob = versions.VersionData;
            return dataBlob.toString();
        

       

    } catch (Exception e) {
        // SystemLogger.logError('ApplicationFormHelper', 'getApplicationScriptById', e, null);
        throw new AuraHandledException('Error retrieving application script: ' + e.getMessage());
    }
}

@AuraEnabled
public static void saveCorrectionRequests(Id appId, String correctionsJson) {
    // Step 1: Deserialize JSON safely
    List<Object> genericList = (List<Object>) JSON.deserializeUntyped(correctionsJson);

    List<Application_Change_Request__c> reqList = new List<Application_Change_Request__c>();

    // Step 2: Iterate over generic items and cast each to a Map
    for (Object o : genericList) {
        Map<String, Object> c = (Map<String, Object>) o;

        reqList.add(new Application_Change_Request__c(
            Application__c = appId,
            Section_Object_API__c = (String) c.get('Section_Object_API__c'),
            Field_API__c = (String) c.get('Field_API__c'),
            Field_Label__c = (String) c.get('Field_Label__c'),
            Section_Label__c = (String) c.get('Section_Label__c'),
            Row_Index__c = (c.containsKey('Row_Index__c') && c.get('Row_Index__c') != null)
                ? Integer.valueOf(c.get('Row_Index__c').toString())
                : null,
            Staff_Remark__c = (String) c.get('Staff_Remark__c'),
            Status__c = 'Open',
            Requested_By__c = UserInfo.getUserId(),
            Requested_On__c = System.now()
        ));
    }

    // Step 3: Insert all records
    if (!reqList.isEmpty()) {
        insert reqList;
    }
}
@AuraEnabled(cacheable=true)
public static Map<String, Object> getApplicationDataWithCorrections(String programCode) {
    Map<String, Object> result = new Map<String, Object>();
    String userEmail = UserInfo.getUserEmail();
    Application__c app = [SELECT Id, Script__c FROM Application__c WHERE Program__r.Program_Code__c=:programCode AND Email__c=:userEmail LIMIT 1];
    List<Application_Change_Request__c> corrections = [
        SELECT Id, Field_API__c, Field_Label__c, Staff_Remark__c, Status__c
        FROM Application_Change_Request__c
        WHERE Application__c=:app.Id AND Status__c='Open'
    ];
    try{
    result.put('application', app);
    result.put('corrections', corrections);
    result.put('status', corrections.size()>0?true:false);
    }catch(Exception e){
        result.put('application', '');
        result.put('corrections', null);
        result.put('status', false);
    }
    return result;
}
}