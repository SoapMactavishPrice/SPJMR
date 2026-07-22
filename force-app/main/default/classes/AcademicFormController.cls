public with sharing class AcademicFormController {
    // Lightweight option used by sample/demo methods
    public class PickVal {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PickVal(String l, String v){ label=l; value=v; }
    }
    public class DepMap {
        @AuraEnabled public Map<String, List<PickVal>> controllerToDependents = new Map<String, List<PickVal>>();
    }

    // =========================
    // LWC/Flow DTOs for dynamic picklist catalog
    // =========================
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Boolean defaultValue;
        @AuraEnabled public Boolean active;
        @AuraEnabled public List<Integer> validForIndexes = new List<Integer>();
        @AuraEnabled public String validForBase64; // optional passthrough if upstream provides a string

        public PicklistOption(String label, String value, Boolean isDefault, Boolean isActive, List<Integer> validForIndexes, String validForBase64) {
            this.label = label;
            this.value = value;
            this.defaultValue = isDefault;
            this.active = isActive;
            if (validForIndexes != null) {
                this.validForIndexes.addAll(validForIndexes);
            }
            this.validForBase64 = validForBase64;
        }
    }
    public class FieldPicklistSet {
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String controllingFieldApiName; // null if independent
        @AuraEnabled public Boolean dependent;
        @AuraEnabled public List<PicklistOption> options = new List<PicklistOption>();
        @AuraEnabled public Map<String, Integer> controllerValues = new Map<String, Integer>();
        @AuraEnabled public Map<String, Integer> controllingValueIndexByValue = new Map<String, Integer>();
    }
    public class ObjectPicklistBundle {
        @AuraEnabled public String objectApiName;
        // master/default (no record type specified)
        @AuraEnabled public Map<String, FieldPicklistSet> defaultSet = new Map<String, FieldPicklistSet>(); // key = fieldApiName

        // 🔹 ADDED: recordTypeId -> fieldApiName -> picklist set
        @AuraEnabled public Map<String, Map<String, FieldPicklistSet>> recordTypeSet =
            new Map<String, Map<String, FieldPicklistSet>>();

        @AuraEnabled public String error;

        @AuraEnabled public Map<String, List<CustomDropdownConfig>> customDropdowns = new Map<String, List<CustomDropdownConfig>>();

        @AuraEnabled
        public Map<String, Map<String, CustomDropdownConfig>> customDropdownRecordTypeSet = new Map<String, Map<String, CustomDropdownConfig>>();

    }

    // =========================
    // New Public APIs
    // =========================

    /**
     * Returns, for each object API name provided, all picklist and multipicklist fields' values:
     * - default/master set (no record type)
     * Includes dependency metadata (controller field API name).
     */
    @AuraEnabled
    public static List<ObjectPicklistBundle> getAllPicklistsForObjects(List<String> objectApiNames, Boolean includeInactive, Boolean enforceFls) {
        // Normalize flags
        includeInactive = (includeInactive == null) ? false : includeInactive;
        enforceFls = (enforceFls == null) ? true : enforceFls;

        // Guard: empty input
        if (objectApiNames == null || objectApiNames.isEmpty()) {
            return new List<ObjectPicklistBundle>();
        }

        // Trim and de-duplicate inputs to reduce describes
        Set<String> unique = new Set<String>();
        for (String n : objectApiNames) {
            if (String.isBlank(n)) continue;
            unique.add(n.trim());
        }
        if (unique.isEmpty()) {
            return new List<ObjectPicklistBundle>();
        }

        return buildPicklistBundles(new List<String>(unique), includeInactive, enforceFls);
    }

    // =========================
    // Core resolver
    // =========================
    private static List<ObjectPicklistBundle> buildPicklistBundles(List<String> objectApiNames, Boolean includeInactive, Boolean enforceFls) {
        List<ObjectPicklistBundle> results = new List<ObjectPicklistBundle>();
        if (objectApiNames == null || objectApiNames.isEmpty()) {
            return results;
        }

        Map<String, Schema.SObjectType> globalObj = Schema.getGlobalDescribe();


        for (String objNameRaw : objectApiNames) {
            String objName = String.isBlank(objNameRaw) ? null : objNameRaw.trim();
            ObjectPicklistBundle bundle = new ObjectPicklistBundle();
            bundle.objectApiName = objNameRaw;
            try {
                // Validate object existence early
                Schema.SObjectType sObjType = (String.isBlank(objName)) ? null : globalObj.get(objName);
                if (sObjType == null) {
                    bundle.error = 'Object not found or invalid: ' + objNameRaw;
                    results.add(bundle);
                    continue; // return-early per item
                }

                Schema.DescribeSObjectResult objDescribe = sObjType.getDescribe();
                // CRUD check - require readable
                if (enforceFls && !objDescribe.isAccessible()) {
                    bundle.error = 'No access to object: ' + objName;
                    results.add(bundle);
                    continue;
                }

                Map<String, Schema.SObjectField> fieldsMap = objDescribe.fields.getMap();

                // Iterate once through fields and process only picklist/multipicklist
                for (String fieldName : fieldsMap.keySet()) {
                    Schema.DescribeFieldResult fDes = fieldsMap.get(fieldName).getDescribe();
                    Schema.DisplayType dt = fDes.getType();
                    if (dt != Schema.DisplayType.Picklist && dt != Schema.DisplayType.MultiPicklist) {
                        continue;
                    }
                    // FLS field access check
                    if (enforceFls && !fDes.isAccessible()) {
                        continue;
                    }

                    FieldPicklistSet fps = buildFieldPicklistSetDefault(fDes, includeInactive);
                    fps.fieldApiName = fDes.getName();

                    if (fps.dependent) {
                        populateControllingValueIndexMapDefault(fieldsMap, fDes, fps);
                    }
                    bundle.defaultSet.put(fDes.getName(), fps);
                }

                // 🔹 ADDED: UI API record-type aware picklists (Named Credential)
                if (UserInfo.getUserType() != 'Guest') {
                    for (Schema.RecordTypeInfo rtInfo :
                         objDescribe.getRecordTypeInfos()) {

                        if (!rtInfo.isAvailable()) continue;
                        Id rtId = rtInfo.getRecordTypeId();
                        if (rtId == null) continue;

                        Map<String, FieldPicklistSet> rtFields =
                            fetchPicklistsFromUiApi(objNameRaw, rtId, includeInactive);

                        if (!rtFields.isEmpty()) {
                            bundle.recordTypeSet.put(String.valueOf(rtId), rtFields);
                        }
                    }
                }

                Set<String> resourceNames = new Set<String>();

                List<Dropdown_Field__mdt> configs = [SELECT Dropdown_Object__r.Context__c, Dropdown_Object__r.Target_Object__c, Target_Field__c, Target_Rt__c, Source_Type__c, Options_JSON__c, Source_Value__c FROM Dropdown_Field__mdt WHERE Dropdown_Object__r.Target_Object__c = :objName];

                Map<String,List<String>> configsWithRecordType = new Map<String,List<String>>();

                for (Dropdown_Field__mdt cfg : configs) {
                    if (cfg.Source_Type__c == 'STATIC_RESOURCE') {
                        resourceNames.add(cfg.Source_Value__c);
                    }

                    if(cfg?.Target_Rt__c != null) {
                        if (String.isNotBlank(cfg.Target_Rt__c)) {

                            if (!configsWithRecordType.containsKey(cfg.Dropdown_Object__r.Target_Object__c)) {
                                configsWithRecordType.put(
                                    cfg.Dropdown_Object__r.Target_Object__c,
                                    new List<String>()
                                );
                            }

                            configsWithRecordType
                                .get(cfg.Dropdown_Object__r.Target_Object__c)
                                .add(cfg.Target_Rt__c);
                        }
                    }

                }

                Map<String,RecordTypeInfoDTO> dtoMap = getRecordTypesByNameBulk(configsWithRecordType);

                Map<String, StaticResource> resources =
                    new Map<String, StaticResource>();

                for (
                    StaticResource sr :
                    [
                        SELECT Name, Body
                        FROM StaticResource
                        WHERE Name IN :resourceNames
                    ]
                ) {
                    resources.put(sr.Name, sr);
                }

                System.debug('Resource Names: ' + resourceNames);
                System.debug('Resources Found: ' + resources.keySet());

                for(Dropdown_Field__mdt eachConfig : configs) {

                    if (!bundle.customDropdowns.containsKey(eachConfig.Target_Field__c)) {
                        bundle.customDropdowns.put(
                            eachConfig.Target_Field__c,
                            new List<CustomDropdownConfig>()
                        );
                    }

                    CustomDropdownConfig cfg = new CustomDropdownConfig();

                    cfg.context = eachConfig.Dropdown_Object__r.Context__c;
                    cfg.fieldApiName = eachConfig.Target_Field__c;
                    cfg.sourceType = eachConfig.Source_Type__c;
                    cfg.recordType = eachConfig.Target_Rt__c;

                    if (String.isNotBlank(cfg.recordType)) {

                        RecordTypeInfoDTO dto =
                            dtoMap.get(eachConfig.Dropdown_Object__r.Target_Object__c);

                        if (dto != null) {
                            cfg.recordType =
                                dto.nameToId.get(cfg.recordType);
                        }
                    }

                    if (cfg.sourceType == 'INLINE') {

                        List<Object> raw =
                            (List<Object>)JSON.deserializeUntyped(
                                eachConfig.Options_JSON__c
                            );

                        cfg.options = new List<PicklistOption>();

                        for (Object o : raw) {

                            Map<String,Object> row =
                                (Map<String,Object>)o;

                            PicklistOption opt = new PicklistOption(
                                (String)row.get('label'),
                                (String)row.get('value'),
                                false,
                                true,
                                null,
                                null
                            );

                            cfg.options.add(opt);
                        }
                    }

                    if (cfg.sourceType == 'STATIC_RESOURCE') {

                        StaticResource sr =
                                resources.get(eachConfig.Source_Value__c);

                        System.debug(sr.Body.toString());

                        if (sr != null) {

                            List<Object> raw =
                                (List<Object>)JSON.deserializeUntyped(
                                    sr.Body.toString()
                                );

                            cfg.options = new List<PicklistOption>();

                            for (Object o : raw) {

                                Map<String,Object> row =
                                    (Map<String,Object>)o;

                                cfg.options.add(
                                    new PicklistOption(
                                        (String)row.get('label'),
                                        (String)row.get('value'),
                                        false,
                                        true,
                                        null,
                                        null
                                    )
                                );
                            }
                        }
                    }

                    System.debug(
                        'STATIC RESOURCE OPTIONS => ' +
                        JSON.serialize(cfg.options)
                    );
                    if (String.isBlank(cfg.recordType)) {

                        bundle.customDropdowns
                            .get(eachConfig.Target_Field__c)
                            .add(cfg);

                    } else {

                        if (!bundle.customDropdownRecordTypeSet.containsKey(cfg.recordType)) {
                            bundle.customDropdownRecordTypeSet.put(
                                cfg.recordType,
                                new Map<String, CustomDropdownConfig>()
                            );
                        }

                        bundle.customDropdownRecordTypeSet
                            .get(cfg.recordType)
                            .put(eachConfig.Target_Field__c, cfg);
                    }
                }
                

            } catch (Exception e) {
                bundle.error = 'Failed to build picklists for ' + objNameRaw + ': ' + e.getMessage();
            }
            results.add(bundle);

        }

        return results;
    }

    // Build default/master picklist set for a field
    private static FieldPicklistSet buildFieldPicklistSetDefault(Schema.DescribeFieldResult fDes, Boolean includeInactive) {
        FieldPicklistSet fps = new FieldPicklistSet();
        Schema.SObjectField controllerField = fDes.getController();
        fps.controllingFieldApiName = (controllerField == null) ? null : controllerField.getDescribe().getName();
        fps.dependent = (controllerField != null);

        for (Schema.PicklistEntry pe : fDes.getPicklistValues()) {
            if (!includeInactive && !pe.isActive()) continue;
            fps.options.add(new PicklistOption(
                pe.getLabel(),
                pe.getValue(),
                pe.isDefaultValue(),
                pe.isActive(),
                null,
                null
            ));
        }

        if (controllerField != null) {
            Integer idx = 0;
            for (Schema.PicklistEntry cpe : controllerField.getDescribe().getPicklistValues()) {
                fps.controllerValues.put(cpe.getValue(), idx);
                fps.controllingValueIndexByValue.put(cpe.getValue(), idx);
                idx++;
            }
        }

        return fps;
    }


    // Populate controlling value index map for default/master context
    private static void populateControllingValueIndexMapDefault(Map<String, Schema.SObjectField> fieldsMap, Schema.DescribeFieldResult childFieldDes, FieldPicklistSet target) {
        Schema.SObjectField controllerField = childFieldDes.getController();
        if (controllerField == null) return;

        Integer idx = 0;
        for (Schema.PicklistEntry cpe : controllerField.getDescribe().getPicklistValues()) {
            target.controllerValues.put(cpe.getValue(), idx);
            target.controllingValueIndexByValue.put(cpe.getValue(), idx);
            idx++;
        }
    }

    private static Map<String, Integer> toStringIntegerMap(Object rawMap) {
        Map<String, Integer> out = new Map<String, Integer>();
        if (rawMap == null) {
            return out;
        }

        Map<String, Object> m = (Map<String, Object>) rawMap;
        if (m == null) {
            return out;
        }

        for (String key : m.keySet()) {
            Object rawVal = m.get(key);
            Integer idx;
            if (rawVal instanceof Integer) {
                idx = (Integer) rawVal;
            } else if (rawVal instanceof Long) {
                idx = Integer.valueOf(String.valueOf(rawVal));
            } else if (rawVal instanceof Decimal) {
                idx = Integer.valueOf(String.valueOf(rawVal));
            } else if (rawVal instanceof String && !String.isBlank((String) rawVal)) {
                idx = Integer.valueOf((String) rawVal);
            }
            if (idx != null) {
                out.put(key, idx);
            }
        }
        return out;
    }

    private static List<Integer> toIntegerList(Object rawList) {
        List<Integer> out = new List<Integer>();
        if (rawList == null) {
            return out;
        }

        List<Object> items = (List<Object>) rawList;
        if (items == null) {
            return out;
        }

        for (Object item : items) {
            Integer idx;
            if (item instanceof Integer) {
                idx = (Integer) item;
            } else if (item instanceof Long) {
                idx = Integer.valueOf(String.valueOf(item));
            } else if (item instanceof Decimal) {
                idx = Integer.valueOf(String.valueOf(item));
            } else if (item instanceof String && !String.isBlank((String) item)) {
                idx = Integer.valueOf((String) item);
            }
            if (idx != null) {
                out.add(idx);
            }
        }
        return out;
    }

    // =========================
    // UI API CALLOUT (Named Credential)
    // =========================
    private static Map<String, FieldPicklistSet> fetchPicklistsFromUiApi(
        String objectApiName,
        Id recordTypeId,
        Boolean includeInactive
    ) {
        Map<String, FieldPicklistSet> out =
            new Map<String, FieldPicklistSet>();

        if (String.isBlank(objectApiName) || recordTypeId == null) {
            return out;
        }

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(
            'callout:SalesforceUiApiNc' +
            '/services/data/v59.0/ui-api/object-info/' +
            EncodingUtil.urlEncode(objectApiName, 'UTF-8') +
            '/picklist-values/' +
            String.valueOf(recordTypeId)
        );
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() != 200) return out;

        Map<String, Object> payload =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        Map<String, Object> fieldValues =
            (Map<String, Object>) payload.get('picklistFieldValues');

        if (fieldValues == null) {
            return out;
        }

        for (String fieldApi : fieldValues.keySet()) {
            Map<String, Object> fieldNode =
                (Map<String, Object>) fieldValues.get(fieldApi);

            FieldPicklistSet fps = new FieldPicklistSet();
            fps.fieldApiName = fieldApi;
            fps.controllingFieldApiName = (String) fieldNode.get('controllerName');

            // UI API provides controllerValues for dependent picklists.
            fps.controllerValues = toStringIntegerMap(fieldNode.get('controllerValues'));
            fps.controllingValueIndexByValue.putAll(fps.controllerValues);
            fps.dependent = !String.isBlank(fps.controllingFieldApiName) && !fps.controllerValues.isEmpty();

            List<Object> values = (List<Object>) fieldNode.get('values');
            if (values == null) {
                out.put(fieldApi, fps);
                continue;
            }

            for (Object o : values) {
                Map<String, Object> v = (Map<String, Object>) o;

                if (!includeInactive &&
                    v.containsKey('active') &&
                    v.get('active') == false) {
                    continue;
                }

                List<Integer> validForIndexes = toIntegerList(v.get('validFor'));
                String validForBase64 = (v.containsKey('validFor') && v.get('validFor') instanceof String)
                    ? (String) v.get('validFor')
                    : null;

                fps.options.add(new PicklistOption(
                    (String) v.get('label'),
                    (String) v.get('value'),
                    (Boolean) v.get('defaultValue'),
                    (Boolean) v.get('active'),
                    validForIndexes,
                    validForBase64
                ));
            }

            out.put(fieldApi, fps);
        }

        return out;
    }

    // =========================
    // Record Type helpers
    // =========================

    public class RecordTypeInfoDTO {
        @AuraEnabled public Map<String, Id> nameToId = new Map<String, Id>();
        @AuraEnabled public Map<Id, String> idToName = new Map<Id, String>();
    }

    public class CustomDropdownConfig {

        @AuraEnabled public String context;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String recordType;

        @AuraEnabled public String resourceName;

        @AuraEnabled public List<PicklistOption> options;
    }

    /**
     * Input:
     *  - objectApiName
     *  - list of record type names
     *
     * Output:
     *  - name -> id
     *  - id -> name
     */
    @AuraEnabled(cacheable=true)
    public static RecordTypeInfoDTO getRecordTypesByName(
        String objectApiName,
        List<String> recordTypeNames
    ) {
        RecordTypeInfoDTO dto = new RecordTypeInfoDTO();

        if (String.isBlank(objectApiName) || recordTypeNames == null || recordTypeNames.isEmpty()) {
            return dto;
        }

        for (RecordType rt : [
            SELECT Id, Name
            FROM RecordType
            WHERE SObjectType = :objectApiName
            AND Name IN :recordTypeNames
        ]) {
            dto.nameToId.put(rt.Name, rt.Id);
            dto.idToName.put(rt.Id, rt.Name);
        }

        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String,RecordTypeInfoDTO> getRecordTypesByNameBulk(Map<String,List<String>> recordTypeNamesAgainstObject) {
        Map<String,RecordTypeInfoDTO> dtoMap = new Map<String,RecordTypeInfoDTO>();

        if (recordTypeNamesAgainstObject == null || recordTypeNamesAgainstObject.isEmpty()) {
            return dtoMap;
        }

        Set<String> allRecordTypeNames = new Set<String>();

        for (List<String> names : recordTypeNamesAgainstObject.values()) {
            allRecordTypeNames.addAll(names);
        }

        for (RecordType rt : [SELECT Id, Name, SobjectType FROM RecordType WHERE SObjectType IN :recordTypeNamesAgainstObject.keySet() AND Name IN :allRecordTypeNames]) {
            if(dtoMap.containsKey(rt.SobjectType)){
                if(dtoMap.get(rt.SobjectType) != null) {
                    RecordTypeInfoDTO dto = dtoMap.get(rt.SobjectType);
                    dto.nameToId.put(rt.Name, rt.Id);
                    dto.idToName.put(rt.Id, rt.Name);
                    dtoMap.put(rt.SobjectType, dto);
                } else {
                    RecordTypeInfoDTO dto = new RecordTypeInfoDTO();
                    dto.nameToId.put(rt.Name, rt.Id);
                    dto.idToName.put(rt.Id, rt.Name);
                    dtoMap.put(rt.SobjectType, dto);
                }
            } else {
                RecordTypeInfoDTO dto = new RecordTypeInfoDTO();
                dto.nameToId.put(rt.Name, rt.Id);
                dto.idToName.put(rt.Id, rt.Name);
                dtoMap.put(rt.SobjectType, dto);
            }
            
        }

        return dtoMap;
    }

}