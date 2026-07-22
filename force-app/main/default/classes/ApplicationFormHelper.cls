/**
 * Helper class to manage dynamic application form operations.
 * Provides methods for:
 * - Retrieving application form fields
 * - Saving form structure
 * - Managing application data
 * - File (ContentVersion) operations
 * - Dynamic record creation from JSON payload
 * 
 * Author:Shashank Mishra
 * Visibility: public without sharing (uses user’s sharing)
 */

public without sharing class ApplicationFormHelper {

/**********************************************************************
     *  METHOD: getApplicationFields
     *  PURPOSE: Returns all custom fields (excluding reference to Application__c)
     *           for a given object including picklist values and lookups.
     **********************************************************************/
@AuraEnabled(cacheable=true)
public static List<Map<String, Object>> getApplicationFields(String objectvar) {
    Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectvar).getDescribe().fields.getMap();
    List<Map<String, Object>> results = new List<Map<String, Object>>();
    System.debug('field sobject '+objectvar);
    for (String key : fields.keySet()) {
        Schema.DescribeFieldResult descs = fields.get(key).getDescribe();

        if (descs.isCustom()) {
            System.debug('field key '+key);
            System.debug('field label '+descs.getLabel());
            // Prepare picklist options if applicable
            List<Map<String, String>> picklistOptions = new List<Map<String, String>>();
            if (descs.getType() == Schema.DisplayType.Picklist) {
                for (Schema.PicklistEntry entry : descs.getPicklistValues()) {
                    picklistOptions.add(new Map<String, String>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    });
                }
            }

            // Handle Lookup/Reference fields
            String referenceTo = null;
            if (descs.getType() == Schema.DisplayType.Reference && !descs.getReferenceTo().isEmpty()) {
                referenceTo = descs.getReferenceTo()[0].getDescribe().getName();
            }
            if(referenceTo!='REFERENCE' && referenceTo !='Application__c'){
                System.debug('returned '+descs.getLabel()+ ' key ' +key);

                Map<String,Object> resultMap = new Map<String, Object>{
                    'label' => descs.getLabel(),
                    'apiName' => key,
                    'type' => String.valueOf(descs.getType()),
                    'isCalculated' => descs.isCalculated(),
                    'options' => picklistOptions,
                    'referenceTo' => referenceTo,
                    'displayField' => (referenceTo != null ? 'Name' : null),
                    'isDocument'=>false,
                    'isSelected'=>false
                };
                if(String.isNotBlank(descs.getInlineHelpText())){
                    resultMap.put('description', descs.getInlineHelpText());
                } else {
                    resultMap.put('description', false);
                }
                results.add(resultMap);
            }
        }
    }

    return results;
}
/**********************************************************************
     *  METHOD: saveForm
     *  PURPOSE: Save or replace form layout (HTML) for a given program.
     **********************************************************************/


    @AuraEnabled
    public static Boolean saveForm(String name,String htmlBody,String programId){
        try {
            List<Application_form__c> af= [SELECT Id, Name, Program__r.Program_Code__c  FROM Application_form__c WHERE Program__c=:programId];
            Map<String,String> docMap = new Map<String,String>();
            if(af.isEmpty()){
                docMap = saveApplicationFormHtmlToFile(htmlBody, [SELECT Program_Code__c from Program WHERE Id=:programId][0].Program_Code__c);
                af.add(new Application_form__c());
            } else {
                docMap = saveApplicationFormHtmlToFile(htmlBody, af[0].Program__r.Program_Code__c);
            }

            System.debug(docMap);
            af[0].Name = name;
            af[0].Form_HTML__c = docMap.get('cdLink');
            af[0].Program__c=programId;
            Upsert af;

            ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = docMap.get('docId'),
                LinkedEntityId = af[0].Id,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            insert cdl;
        } catch (Exception e) {
            SystemLogger.logError('ApplicationFormHelper', 'saveForm', e, null);
            return false;
        }
        return true;
    }

   /**********************************************************************
     *  METHOD: getActiveForm
     *  PURPOSE: Fetches active application form HTML by program code.
     **********************************************************************/

    @AuraEnabled(cacheable=true)
    public static Application_Form__c getActiveForm(String programCode) {
        // return [SELECT Id, Form_HTML__c FROM Application_Form__c WHERE Is_Active__c = true LIMIT 1];
        Application_Form__c app = [SELECT Id, Form_HTML__c,Program__r.Program_Code__c FROM Application_Form__c WHERE Program__r.Program_Code__c=:programCode LIMIT 1];
        return new Application_Form__c(Form_HTML__c=getLatestApplicationFormHtml(app.Form_HTML__c));
    }

    /**********************************************************************
     *  METHOD: getApplicationData
     *  PURPOSE: Retrieve applicant data based on logged-in user and program.
     **********************************************************************/

     @AuraEnabled(cacheable=true)
    public static Application__c getApplicationData(String programCode) {
        // return [SELECT Id, Form_HTML__c FROM Application_Form__c WHERE Is_Active__c = true LIMIT 1];
        try{
            String userEmail = UserInfo.getUserEmail();
            return [SELECT Id, script__c FROM Application__c WHERE Program__r.Program_Code__c=:programCode AND Email__c=:userEmail LIMIT 1];
        }catch(Exception e){
            return null;
        }
    }

/**********************************************************************
     *  METHOD: getActiveFormById
     *  PURPOSE: Get form HTML by program Id directly.
     **********************************************************************/
    @AuraEnabled(cacheable=true)
    public static String getActiveFormById(String programId) {
        // return [SELECT Id, Form_HTML__c FROM Application_Form__c WHERE Is_Active__c = true LIMIT 1];
        Application_Form__c app= [SELECT Id, Form_HTML__c,Program__r.Program_Code__c FROM Application_Form__c WHERE Program__c=:programId LIMIT 1];

        System.debug('cdl count '+[
            SELECT COUNT() FROM
            ContentDocumentLink WHERE LinkedEntityId = :app.Id
        ]);

        return getLatestApplicationFormHtml(app.Form_HTML__c);
    }

/**********************************************************************
     *  JSON SCRIPT STORAGE USING CONTENTVERSION
     **********************************************************************/
    @AuraEnabled
    public static String saveApplicationScriptToFile(String jsonScript, String programCode) {
        try {
            if (String.isBlank(jsonScript)) {
                throw new AuraHandledException('Empty JSON script.');
            }

            String userEmail = UserInfo.getUserEmail();
            String fileName = programCode + '_' + userEmail + '_ApplicationScript.json';

            Blob dataBlob = Blob.valueOf(jsonScript);

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = dataBlob;
            cv.IsMajorVersion = true;
            insert cv;

            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            return cv.ContentDocumentId;
        } catch (Exception e) {
            SystemLogger.logError('ApplicationFormHelper', 'saveApplicationScriptToFile', e, null);
            throw new AuraHandledException('Error saving JSON to ContentVersion: ' + e.getMessage());
        }
    }

    /**********************************************************************
     *  METHOD: getLatestApplicationScript
     *  PURPOSE: Retrieves latest uploaded JSON script for user and program.
     **********************************************************************/

    @AuraEnabled(cacheable=true)
    public static String getLatestApplicationScript(String programCode) {
        try {
            String userEmail = UserInfo.getUserEmail();
            String fileNamePattern = programCode + '_' + userEmail + '_ApplicationScript.json';

            List<ContentVersion> versions = [
                SELECT Id, VersionData, Title
                FROM ContentVersion
                WHERE Title = :fileNamePattern
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (versions.isEmpty()) return null;

            Blob dataBlob = versions[0].VersionData;
            return dataBlob.toString();
        } catch (Exception e) {
            SystemLogger.logError('ApplicationFormHelper', 'getLatestApplicationScript', e, null);
            throw new AuraHandledException('Error retrieving JSON from ContentVersion: ' + e.getMessage());
        }
    }

    /**********************************************************************
     *  JSON SCRIPT STORAGE USING CONTENTVERSION
     **********************************************************************/
    @AuraEnabled
    public static Map<String,String> saveApplicationFormHtmlToFile(String jsonScript, String programCode) {
        try {
            if (String.isBlank(jsonScript)) {
                throw new AuraHandledException('Empty JSON script.');
            }

            String fileName = programCode + '_ApplicationFormHtml.json';

            Blob dataBlob = Blob.valueOf(jsonScript);

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = dataBlob;
            cv.IsMajorVersion = true;
            insert cv;

            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            ContentDistribution cd = new ContentDistribution();
            cd.Name = fileName + ' - Public Link';
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowOriginalDownload = true;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesPasswordRequired = false;
            cd.PreferencesNotifyOnVisit = false;
            insert cd;

            cd = [SELECT Id, ContentDownloadUrl  FROM ContentDistribution WHERE Id = :cd.Id LIMIT 1];

            // Get the public URL
            System.debug('Public URL: ' + cd.ContentDownloadUrl );

            return new Map<String,String> {'docId'=>cv.ContentDocumentId,'cdLink'=>cd.ContentDownloadUrl };
        } catch (Exception e) {
            SystemLogger.logError('ApplicationFormHelper', 'saveApplicationFormHtmlToFile', e, null);
            throw new AuraHandledException('Error saving JSON to ContentVersion: ' + e.getMessage());
        }
    }

    /**********************************************************************
     *  METHOD: getLatestApplicationFormHtml
     *  PURPOSE: Retrieves latest uploaded JSON script for user and program.
     **********************************************************************/

    @AuraEnabled(cacheable=true)
    public static String getLatestApplicationFormHtml(String cdUrl) {
        if(String.isBlank(cdUrl)) return '{"message":"nourlfound"}';
        System.debug('cdUrl: ' + cdUrl);
        try {
            return fetchJsonFromPublicLink(cdUrl);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving JSON from ContentVersion: ' + e.getMessage());
        }
    }

    /**
     * Fetch raw text/blob from a URL that may have been stored in a Rich Text field.
     * - Cleans HTML tags (eg <p>...</p>) and common HTML entities.
     * - Follows redirects up to 5 times.
     * - Requires the domain in Remote Site Settings or use a Named Credential (see notes).
     *
     * @param rawUrl The stored URL (may include HTML tags or entities).
     * @param maxRedirects Max number of redirects to follow (default 5).
     * @return String The response body (raw JSON text, or binary converted to string).
     * @throws CalloutException or custom message on error.
     */
    public static String fetchJsonFromPublicLink(String rawUrl, Integer maxRedirects) {
        if (rawUrl == null) {
            throw new CalloutException('No URL provided');
        }
        if (maxRedirects == null) maxRedirects = 5;

        // 1) Remove HTML tags (if stored in a Rich Text Area)
        String cleaned = rawUrl.replaceAll('<[^>]+>', '');
        cleaned = cleaned.trim();

        // 2) Decode a few common HTML entities (expand if needed)
        cleaned = cleaned.replaceAll('&amp;', '&')
                         .replaceAll('&lt;', '<')
                         .replaceAll('&gt;', '>')
                         .replaceAll('&quot;', '"')
                         .replaceAll('&#39;', '\'');

        // 3) sanity checks
        if (!cleaned.startsWithIgnoreCase('http://') && !cleaned.startsWithIgnoreCase('https://')) {
            throw new CalloutException('Invalid URL protocol. URL must start with http:// or https:// — got: ' + cleaned);
        }

        String currentUrl = cleaned;
        Integer hops = 0;
        Http http = new Http();

        while (true) {
            if (hops > maxRedirects) {
                throw new CalloutException('Too many redirects (' + String.valueOf(hops) + '). Last URL: ' + currentUrl);
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(currentUrl);
            req.setMethod('GET');

            // Ask for JSON if possible; also supply a common user-agent in case the server filters bots
            req.setHeader('Accept', 'application/json, text/plain, */*');
            req.setHeader('User-Agent', 'Salesforce-HttpClient/1.0');

            HttpResponse res;
            try {
                res = http.send(req);
            } catch (Exception e) {
                // Common cause: domain not in Remote Site Settings or Named Credential not configured.
                throw new CalloutException('HTTP callout failed to ' + currentUrl + ' : ' + e.getMessage());
            }

            Integer sc = res.getStatusCode();
            if (sc >= 200 && sc < 300) {
                // success
                return res.getBody();
            } else if (sc >= 300 && sc < 400) {
                // redirect — follow Location header if present
                String loc = res.getHeader('Location');
                if (loc == null) {
                    // some servers embed redirect as meta refresh or in HTML — try to extract a URL from body
                    String body = res.getBody();
                    // attempt a simple extraction of an href or direct URL inside HTML
                    Pattern p = Pattern.compile('https?://[\\\\w\\-.:/?&=%+#]+');
                    Matcher m = p.matcher(body);
                    if (m.find()) {
                        loc = m.group(0);
                    } else {
                        throw new CalloutException('Redirect response received (status ' + sc + ') but no Location header or URL found in body.');
                    }
                }
                // Clean the returned location (strip HTML tags/entities if any)
                loc = loc.replaceAll('<[^>]+>', '').replaceAll('&amp;', '&').trim();
                // If location is relative, try to resolve to absolute base (simplest case)
                if (loc.startsWith('/')) {
                    // derive base from currentUrl
                    try {
                        // extract protocol + host
                        Integer idx = currentUrl.indexOf('/', currentUrl.indexOf('://') + 3);
                        String base = (idx > -1) ? currentUrl.substring(0, idx) : currentUrl;
                        loc = base + loc;
                    } catch (Exception e) {
                        // If anything fails, throw
                        throw new CalloutException('Unable to resolve relative redirect location: ' + loc);
                    }
                }
                currentUrl = loc;
                hops++;
                continue; // follow redirect
            } else if (sc == 401 || sc == 403) {
                throw new CalloutException('Unauthorized (status ' + sc + ') when calling ' + currentUrl + '. Ensure file is public or callout is authenticated.');
            } else if (sc == 404) {
                throw new CalloutException('Not found (404) at ' + currentUrl + '. The file may have been deleted or the URL is invalid.');
            } else {
                throw new CalloutException('Unexpected response status ' + sc + ' from ' + currentUrl + '. Response body (first 500 chars): ' + res.getBody().substring(0, Math.min(500, res.getBody().length())));
            }
        }
        return '';
    }

    // convenience overload
    public static String fetchJsonFromPublicLink(String rawUrl) {
        return fetchJsonFromPublicLink(rawUrl, 5);
    }



/**********************************************************************
     *  METHOD: createApplication
     *  PURPOSE: Main entry point for form submission.
     *           Dynamically parses JSON payload and inserts related records.
     **********************************************************************/
@AuraEnabled
public static String createApplication(String payload, String programCode, String datascript) {
    try {
        String currentYear = Datetime.now().format('yyyy');
        Program prog = [
            SELECT Id, Name 
            FROM Program 
            WHERE Program_Code__c = :programCode 
            LIMIT 1
        ];

        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(payload);

        // 🔍 Step 1: Extract Primary Email from Personal_Detail__c (if present)
        String primaryEmail;
        if (data.containsKey('Personal_Detail__c')) {
            List<Object> pdList = (List<Object>) data.get('Personal_Detail__c');
            if (!pdList.isEmpty()) {
                Map<String, Object> pdMap = (Map<String, Object>) pdList[0];
                if (pdMap.containsKey('primary_e_mail__c')) {
                    Map<String, Object> fieldData = (Map<String, Object>) pdMap.get('primary_e_mail__c');
                    if (fieldData != null && fieldData.get('value') != null) {
                        primaryEmail = String.valueOf(fieldData.get('value'));
                    }
                }
            }
        }

        // 🔍 Step 2: Search for existing Application by Program Code + Email
        List<Application__c> existingApps = new List<Application__c>();
        if (String.isNotBlank(primaryEmail)) {
            existingApps = [
                SELECT Id, Application_Number__c, Email__c
                FROM Application__c
                WHERE Program__r.Program_Code__c = :programCode
                AND Email__c = :primaryEmail
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }
        if (!existingApps.isEmpty()) {
            Id appIdToDelete = existingApps[0].Id;
            for (String objApiName : data.keySet()) {
                if (objApiName == 'Application__c') continue;
                Schema.SObjectType sObjType = Schema.getGlobalDescribe().get(objApiName);
                if (sObjType == null) continue;
                Map<String, Schema.SObjectField> fieldsMap = sObjType.getDescribe().fields.getMap();
                if (fieldsMap.containsKey('Application__c')) {
                    String soql = 'SELECT Id FROM ' + objApiName + ' WHERE Application__c = :appIdToDelete';
                    List<SObject> childRecords = Database.query(soql);
                    if (!childRecords.isEmpty()) {
                        delete childRecords;
                    }
                }
            }
            //delete existingApps;
        }

        // Fresh Application
        Application__c app = new Application__c();
         if (!existingApps.isEmpty()) {
             app.Id=existingApps[0].Id;
             app.Name=existingApps[0].Application_Number__c;
         }else{
            app.Application_Number__c=generateApplicationNumberFromSequence(programCode);
            app.Name=app.Application_Number__c;
         }
        app.Program__c = prog.Id;
        //app.script__c = datascript;
        // 🔐 store file reference instead of JSON field
        String fileId = saveApplicationScriptToFile(datascript, programCode);
        app.script__c = fileId; // create this field (Text, 255) on Application__c
       
    
        if (data.containsKey('Application__c')) {
            List<Object> appListRaw = (List<Object>) data.get('Application__c');
            if (!appListRaw.isEmpty()) {
                Map<String, Object> appMap = (Map<String, Object>) appListRaw[0];
                for (String key : appMap.keySet()) {
                    Map<String, Object> fieldData = (Map<String, Object>) appMap.get(key);
                    if (fieldData == null) continue;
                    String dataType = (String) fieldData.get('dataType');
                    Object rawVal   = fieldData.get('value');
                    if (rawVal == null) continue;
                    String valStr = String.valueOf(rawVal);
                    if (valStr.contains('https://')) continue;
                    app.put(key, castValue(dataType, valStr, rawVal));
                }
            }
        } 
        UPSERT app;

        // Track inserted parents for child linking
        Map<String, List<SObject>> insertedParentsByObject = new Map<String, List<SObject>>();

        // Documents
        List<Document_Details__c> docsToInsert = new List<Document_Details__c>();

        // ✅ Mapping for Application Stage values
        // ✅ Define mapping of object API name → Stage Label
        Map<String, String> stageMapping = new Map<String, String>{
        'Application__c'                           => 'Application__c',
        'Personal_Summary__c'                      => 'Personal_Summary__c',
        'Personal_Detail__c'                       => 'Personal_Detail__c',
        'Program_Detail__c'                        => 'Program_Detail__c',
        'Address_Information_Application__c'       => 'Address_Information_Application__c',
        'Professional_Qualification__c'            => 'Professional_Qualification__c',
        'Academic_Detail__c'                       => 'Academic_Detail__c',
        'Graduation_Details_Semester_wise__c'      => 'Graduation_Details_Semester_wise__c',
        'Competitive_Exam_Details__c'              => 'Competitive_Exam_Details__c',
        'Competitive_Exam_GMAT_Focus_Edition__c'   => 'Competitive_Exam_GMAT_Focus_Edition__c',
        'Work_Experience__c'                       => 'Work_Experience__c',
        'Functional_Areas_That_You_Have_Worked_In__c' => 'Functional_Areas_That_You_Have_Worked_In__c',
        'General_Detail__c'                        => 'General_Detail__c',
        'Venture__c'                               => 'Venture__c',
        'Family__c'                                => 'Family__c',
        'Family_Background__c'                     => 'Family_Background__c',
        'Family_Business_Company_Details_Sales__c' => 'Family_Business_Company_Details_Sales__c',
        'Information_Source__c'                    => 'Information_Source__c',
        'Mentor_Details__c'                        => 'Mentor_Details__c',
        'Document__c'                              => 'Document__c'
        };



        // Handle child objects
        for (String objApiName : data.keySet()) {
            if (objApiName == 'Application__c') continue;

            List<Object> rawRecords = (List<Object>) data.get(objApiName);
            if (rawRecords == null) continue;

            List<SObject> recordsToInsert = new List<SObject>();

            for (Object recObj : rawRecords) {
                Map<String, Object> fieldMap = (Map<String, Object>) recObj;
                SObject record ;
                String parentObjApi = (String) fieldMap.get('__parent__'); // from JS payload
                if(Schema.getGlobalDescribe().get(objApiName)!=null){
                     record = Schema.getGlobalDescribe().get(objApiName).newSObject();
                }else{
                     record = Schema.getGlobalDescribe().get(parentObjApi).newSObject();
                }

                for (String key : fieldMap.keySet()) {
                    if (key == '__parent__') continue;

                    Map<String, Object> fieldData = (Map<String, Object>) fieldMap.get(key);
                    if (fieldData == null) continue;

                    String dataType = (String) fieldData.get('dataType');
                    Object rawVal   = fieldData.get('value');
                    if (rawVal == null) continue;
                    String valStr = String.valueOf(rawVal);

                    if (valStr.contains('https://')) {
                        Document_Details__c doc = new Document_Details__c();
                        doc.Document_URL__c = valStr;
                        doc.Application_No__c = app.Id;
                        doc.Name = key;
                        doc.Document_Code__c = key;
                        docsToInsert.add(doc);
                    } else {
                        record.put(key, castValue(dataType, valStr, rawVal));
                    }
                }

                // Always link to Application
                record.put('Application__c', app.Id);

                // If a parent is defined, link to it
                // 🔗 If the record has a parent reference (__parent__), find the correct lookup field
                if (String.isNotBlank(parentObjApi) && insertedParentsByObject.containsKey(parentObjApi)) {
                    List<SObject> parentRecords = insertedParentsByObject.get(parentObjApi);
                    Id parentId;

                    // Try to match parent using qualification type
                    String qualificationType = fieldMap.containsKey('__qualificationType__')
                        ? String.valueOf(fieldMap.get('__qualificationType__'))
                        : null;

                    if (String.isNotBlank(qualificationType)) {
                        for (SObject parentRec : parentRecords) {
                            if (String.valueOf(parentRec.get('Qualifications__c')) == qualificationType) {
                                parentId = parentRec.Id;
                                break;
                            }
                        }
                    }

                    // Fallback to first Academic_Detail__c if match not found
                    if (parentId == null && !parentRecords.isEmpty()) {
                        parentId = parentRecords[0].Id;
                    }

                    // Find lookup field dynamically
                    Map<String, Schema.SObjectField> childFields = record.getSObjectType().getDescribe().fields.getMap();
                    for (String fldName : childFields.keySet()) {
                    Schema.DescribeFieldResult fldDesc = childFields.get(fldName).getDescribe();
                    if (fldDesc.getType() == Schema.DisplayType.REFERENCE) {
                        List<Schema.SObjectType> refObjects = fldDesc.getReferenceTo();
                        for (Schema.SObjectType refType : refObjects) {
                            String refName = refType.getDescribe().getName();
                            if (refName == parentObjApi) {
                                record.put(fldName, parentId);
                                break;
                            }
                        }
                    }
                }
                }

                recordsToInsert.add(record);
            }

            if (!recordsToInsert.isEmpty()) {
                insert recordsToInsert;

                // ✅ Update Application Stage dynamically
                if (stageMapping.containsKey(objApiName)) {
                    app.Application_Stage__c = stageMapping.get(objApiName);
                }

                // ✅ If this is Personal_Details__c, copy key fields to Application
                if (objApiName == 'Personal_Detail__c') {
                    SObject pd = recordsToInsert[0]; // first record
                    Map<String, Schema.SObjectField> pdFields = pd.getSObjectType().getDescribe().fields.getMap();

                    if (pdFields.containsKey('First_Name__c')) {
                        app.put('First_Name__c', pd.get('First_Name__c'));
                    }
                    if (pdFields.containsKey('Last_Name__c')) {
                        app.put('Last_Name__c', pd.get('Last_Name__c'));
                    }
                    if (pdFields.containsKey('Primary_E_mail__c')) {
                        app.put('Email__c', pd.get('Primary_E_mail__c'));
                    }
                    if (pdFields.containsKey('Mobile_Number__c')) {
                        app.put('Phone__c', pd.get('Mobile_Number__c'));
                    }
                    
                }

                // Save parent references
                if (!data.containsKey('__parent__')) {
                    insertedParentsByObject.put(objApiName, recordsToInsert);
                }
                
                // ✅ Persist Application updates if needed
                app.Application_Status__c = 'Submitted';
                update app;
                System.debug('AppId:'+app.Id);
                System.debug('AppId:'+app.script__c);
            }
        }

        if (!docsToInsert.isEmpty()) {
            insert docsToInsert;
        }
        return 'true';
    } catch (Exception ex) {
        SystemLogger.logError('ApplicationFormHelper', 'createApplication', ex, null);
        return ex.getMessage();

    }
}




/**
 * Utility: Cast values from JSON into correct Apex types
 */
private static Object castValue(String dataType, String valStr, Object rawVal) {
    if (String.isBlank(dataType)) {
        return rawVal; // fallback
    }

    if (String.isBlank(valStr)) {
        return null; // skip empty
    }

    try {
        switch on dataType.toUpperCase() {
            when 'DATE' {
                return Date.valueOf(valStr);
            }
            when 'DATETIME' {
                return Datetime.valueOf(valStr);
            }
            when 'BOOLEAN' {
                // Accept "1"/"0", "true"/"false", "Yes"/"No"
                if (valStr.equalsIgnoreCase('1') || valStr.equalsIgnoreCase('true') || valStr.equalsIgnoreCase('yes')) {
                    return true;
                }
                if (valStr.equalsIgnoreCase('0') || valStr.equalsIgnoreCase('false') || valStr.equalsIgnoreCase('no')) {
                    return false;
                }
                return Boolean.valueOf(valStr);
            }
            when 'DOUBLE' {
                // Handle numbers given as string ("1998") or real number (1998)
                return Decimal.valueOf(String.valueOf(rawVal));
            }
            when 'INTEGER' {
                return Integer.valueOf(String.valueOf(rawVal));
            }
            when 'PERCENT' {
                return Decimal.valueOf(String.valueOf(rawVal));
            }
            when else {
                // System.debug('else rawVal '+rawVal);
                // TEXT, PICKLIST, EMAIL, PHONE etc.
                return String.valueOf(rawVal);
            }
        }
    } catch (Exception ex) {
        // Instead of breaking, just log and skip
        //System.debug('castValue failed → dataType=' + dataType + ', value=' + valStr + ', error=' + ex.getMessage());
        SystemLogger.logError('ApplicationFormHelper', 'castValue', ex, null);
        return null;
    }
}

/**********************************************************************
     *  FILE UPLOAD / DELETE HANDLERS (ContentVersion + Distribution)
     **********************************************************************/
@AuraEnabled
    public static String uploadFile(String fileData) {
        try {
            FileDataWrapper fd = (FileDataWrapper) JSON.deserialize(fileData, FileDataWrapper.class);
            // Insert ContentVersion
            ContentVersion contentVersion = new ContentVersion();
            contentVersion.Title = fd.name;
            contentVersion.PathOnClient = fd.name;
            contentVersion.VersionData = EncodingUtil.base64Decode(fd.base64);
            contentVersion.IsMajorVersion = true;
            insert contentVersion;

            // Get ContentDocumentId
            contentVersion = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersion.Id LIMIT 1];

            // Create ContentDistribution
            ContentDistribution contentDistribution = new ContentDistribution();
            contentDistribution.ContentVersionId = contentVersion.Id;
            contentDistribution.Name = fd.name;
            contentDistribution.PreferencesAllowViewInBrowser = true;
            contentDistribution.PreferencesLinkLatestVersion = true;
            contentDistribution.PreferencesNotifyOnVisit = false;
            contentDistribution.PreferencesPasswordRequired = false;
            contentDistribution.PreferencesAllowOriginalDownload = true;
            insert contentDistribution;

            // Get Public URL
            contentDistribution = [SELECT DistributionPublicUrl FROM ContentDistribution WHERE Id = :contentDistribution.Id LIMIT 1];
            String publicUrl = contentDistribution.DistributionPublicUrl;
            return publicUrl+'_'+contentVersion.ContentDocumentId;
        } catch (Exception e) {
            SystemLogger.logError('ApplicationFormHelper', 'uploadFile', e, null);
            throw new AuraHandledException('Error uploading file: ' + e.getMessage());
        }
    }

    public class FileDataWrapper {
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String base64 { get; set; }
    }

    @AuraEnabled
    public static void deleteFile(String fileId) {
        try {
            // First delete ContentDistribution records
            List<ContentDistribution> distributions = [
                SELECT Id FROM ContentDistribution 
                WHERE ContentDocumentId = :fileId
            ];
            
            if (!distributions.isEmpty()) {
                delete distributions;
            }

            // Then delete ContentDocument (this automatically deletes ContentDocumentLink and ContentVersion)
            ContentDocument document = new ContentDocument(Id = fileId);
            delete document;

        } catch (Exception e) {
            SystemLogger.logError('ApplicationFormHelper', 'deleteFile', e, null);
            throw new AuraHandledException('Error deleting file: ' + e.getMessage());
        }
    }

    /**********************************************************************
         *  METHOD: getDocumentList
     *  PURPOSE: Returns all available document templates for upload.
     **********************************************************************/
    @AuraEnabled
    public static List<Map<String, Object>> getDocumentList(){
        try {
            List<Map<String, Object>> objectDetails = new List<Map<String, Object>>();

            List<Document__c> docList=[SELECT Id, Name , Document_Code__c, Document_Type__c FROM Document__c];
            for (Document__c row : docList) {

                objectDetails.add(new Map<String, Object>{
                    'label' => row.Name,
                    'type'=> 'Document',
                    'isCalculated' => false,
                    'apiName' => row.Document_Code__c,
                    'description'=>row.Document_Code__c,
                    'isDocument'=>true,
                    'isSelected'=>false
                });
            }

            return objectDetails;
            
        } catch (Exception e) {
             SystemLogger.logError('ApplicationFormHelper', 'getDocumentList', e, null);
            throw new AuraHandledException(e.getMessage());
        }
    }
/**********************************************************************
     *  METHOD: searchLookup
     *  PURPOSE: Generic lookup search for LWC/Aura lookup components.
     **********************************************************************/
@AuraEnabled(cacheable=true)
public static List<SObject> searchLookup(String searchKey, String objectApi, String displayField) {
    searchKey = '%' + searchKey + '%'; // Modify the variable before binding
    String query = 'SELECT Id, ' + displayField + 
               ' FROM ' + objectApi + 
               ' WHERE ' + displayField + ' LIKE :searchKey';
    return Database.query(query);   
}

/**********************************************************************
     *  METHOD: getProgramList
     *  PURPOSE: Returns all available programs.
     **********************************************************************/
@AuraEnabled(cacheable=true)
public static List<Program> getProgramList(){
    try {
        List<Program> programList=[SELECT Id, Name,Program_Code__c FROM Program];
        return programList;
    } catch (Exception e) {
        throw new AuraHandledException(e.getMessage());
    }
}

/**********************************************************************
     *  SEQUENCE GENERATION METHODS
     **********************************************************************/
public static String generateApplicationNumberFromSequence(String programCode) {
    String intakeYear = String.valueOf(Date.today().year());
    Sequence_Master__c seqRecord;

    // Try to find existing sequence record for this Program + Year
    List<Sequence_Master__c> seqList = [
        SELECT Id, Last_Used_Number__c, Program_Code__c, Year__c
        FROM Sequence_Master__c
        WHERE Program_Code__c = :programCode
        AND Year__c = :intakeYear
        LIMIT 1
    ];

    if (seqList.isEmpty()) {
        // Create new record if not found
        seqRecord = new Sequence_Master__c();
           seqRecord.Name = programCode + '-' + intakeYear;
           seqRecord.Program_Code__c = programCode;
           seqRecord.Year__c = intakeYear;
           seqRecord.Last_Used_Number__c = 1;
        insert seqRecord;
    } else {
        seqRecord = seqList[0];
        seqRecord.Last_Used_Number__c = seqRecord.Last_Used_Number__c + 1;
        update seqRecord;
    }

    Decimal seqNum = seqRecord.Last_Used_Number__c;
    String paddedNum = leftPadNumber(seqNum, 5);

    return programCode + intakeYear + paddedNum;
}

// ✅ Safe padding helper for Apex
public static String leftPadNumber(Decimal num, Integer length) {
    if (num == null) num = 0;
    String numStr = String.valueOf(num);
    while (numStr.length() < length) {
        numStr = '0' + numStr;
    }
    return numStr;
}


    
}