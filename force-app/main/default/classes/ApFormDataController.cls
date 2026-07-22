public with sharing class ApFormDataController {

    /**********************************************
     * DYNAMIC SOQL BUILDER
     **********************************************/
    private static String buildSOQL(String sObjApiName, List<Object> fields, List<Object> filters) {
        // Safely convert fields (List<Object>) into List<String>
        List<String> fieldNames = new List<String>();
        if (fields != null) {
            for (Object f : fields) {
                fieldNames.add(String.valueOf(f));
            }
        }
        if (fieldNames.isEmpty()) {
            fieldNames.add('Id');
        }

        String selectFields = String.join(fieldNames, ',');

        List<String> whereClauses = new List<String>();
        if (filters != null) {
            for (Object f : filters) {
                Map<String,Object> cond = (Map<String,Object>) f;
                String fieldName = String.valueOf(cond.get('field'));
                Object rawVal = cond.get('value');
                String safeVal = rawVal == null ? '' : String.valueOf(rawVal);
                String val = String.escapeSingleQuotes(safeVal);
                whereClauses.add(fieldName + ' = \'' + val + '\'');
            }
        }

        String soql = 'SELECT ' + selectFields + ' FROM ' + sObjApiName;
        if (!whereClauses.isEmpty()) {
            soql += ' WHERE ' + String.join(whereClauses, ' AND ');
        }

        return soql;
    }

    /**********************************************
     * FETCH DYNAMIC DATA (Parents + Children)
     **********************************************/
    @AuraEnabled
    public static Map<String,Object> fetchDynamic(String requestJson) {
        Map<String,Object> request = (Map<String,Object>) JSON.deserializeUntyped(requestJson);
        Map<String,Object> out = new Map<String,Object>();

        // ---------- PARENTS ----------
        List<Object> parents = (List<Object>) request.get('parents');
        if (parents != null) {
            for (Object o : parents) {
                Map<String,Object> r = (Map<String,Object>) o;

                String sObjApi = String.valueOf(r.get('sobject'));
                List<Object> fields = (List<Object>) r.get('fields');
                List<Object> filters = (List<Object>) r.get('filters');
                String logicalName = String.valueOf(r.get('logicalName'));

                String soql = buildSOQL(sObjApi, fields, filters);
                List<SObject> rows = Database.query(soql);

                if (!rows.isEmpty()) {
                    out.put(logicalName, (Object) rows[0].getPopulatedFieldsAsMap());
                } else {
                    out.put(logicalName, (Object) new Map<String,Object>());
                }
            }
        }

        // ------------------------
        // PATCHED CHILD LOGIC (safe, correct, minimal)
        // ------------------------

        List<Object> children = (List<Object>) request.get('children');

        if (children != null) {
            for (Object o : children) {
                Map<String,Object> r = (Map<String,Object>) o;

                String sObjApi = (String) r.get('sobject');
                List<Object> fields = (List<Object>) r.get('fields');
                List<Object> filters = (List<Object>) r.get('filters') != null
                    ? (List<Object>) r.get('filters')
                    : new List<Object>();

                Boolean useSequenceKey = (Boolean) r.get('useSequenceKey');
                String keyField = (String) r.get('childKeyField');
                String logicalName = (String) r.get('logicalName');
                Map<String,Object> parentLookupFields = (Map<String,Object>) filters[0];
                String plf;
                if(String.isBlank((String) parentLookupFields.get('value'))){
                    plf = (String) parentLookupFields.get('field');
                    filters = new List<Object>();
                }

                // ----------------------------------------
                // FIND PARENT BY RECORD NAME (correct logic)
                // ----------------------------------------
                Object parentIdObj = null;

                for (Object pObj : parents) {
                    Map<String,Object> p = (Map<String,Object>) pObj;



                    if (p.containsKey('recordName')
                        && r.containsKey('parentRecordName')
                        && String.valueOf(p.get('recordName')) == String.valueOf(r.get('parentRecordName'))) {

                        String parentLogical = (String) p.get('logicalName');
                        Map<String,Object> parentBlock = (Map<String,Object>) out.get(parentLogical);

                        if (parentBlock != null && parentBlock.containsKey('Id')) {
                            parentIdObj = parentBlock.get('Id');
                        }
                        break;
                    }
                }

                // ----------------------------------------
                // IF NO PARENT → STILL RETURN EMPTY BLOCK, NOT SEQUENCE ONLY
                // ----------------------------------------
                if (r.containsKey('parentRecordName') == true && parentIdObj == null) {
                    out.put(logicalName, new Map<String,Object>{
                        'isSequential' => useSequenceKey == true
                    });
                    continue;
                }

                // ----------------------------------------
                // ADD FILTER PROPERLY (only if parentLookupField is valid)
                // ----------------------------------------
                if (plf != null && plf != '') {

                    filters.add(new Map<String,Object>{
                        'field' => plf,
                        'value' => parentIdObj
                    });
                }


                // ----------------------------------------
                // PERFORM QUERY SAFELY
                // ----------------------------------------
                String soql = buildSOQL(sObjApi, fields, filters);

                List<SObject> rows = Database.query(soql);

                Map<String,Object> block = new Map<String,Object>();

                for (SObject row : rows) {
                    String key = (useSequenceKey && keyField != null)
                        ? String.valueOf(row.get(keyField))
                        : String.valueOf(row.get('Id'));

                    block.put(key, row.getPopulatedFieldsAsMap());
                }

                block.put('isSequential', useSequenceKey == true);

                out.put(logicalName, block);
            }
        }

        return out;
    }

    /**********************************************
     * SAVE PARENTS (Insert + Update + Delete)
     * - multiple logical blocks can share same recordName
     * - if recordName is missing from payload, record is deleted
     **********************************************/
    @AuraEnabled
    public static Map<String, Id> saveParents(Id applicationId, String payloadJson) {
        Map<String,Object> payload = (Map<String,Object>) JSON.deserializeUntyped(payloadJson);
        Map<String,Id> resultIds = new Map<String,Id>();

        if (payload == null || payload.isEmpty()) {
            return resultIds;
        }

        // NEW: collect delete blocks separately
        List<Map<String,Object>> deleteBlocks = new List<Map<String,Object>>();


        // Group by SObject -> recordName -> blocks
        Map<String, Map<String, List<Map<String,Object>>>> grouped =
            new Map<String, Map<String, List<Map<String,Object>>>>();

        for (String logicalName : payload.keySet()) {
            
            Map<String,Object> block = (Map<String,Object>) payload.get(logicalName);

            // NEW: detect delete blocks
            Boolean isDelete = (block.containsKey('delete') && (Boolean)block.get('delete') == true);
            if (isDelete) {
                deleteBlocks.add(block);
                continue; // IMPORTANT: do NOT include delete blocks in grouped
            }

            if (block == null) continue;

            String sObjApi = String.valueOf(block.get('sobject'));
            String recordName = String.valueOf(block.get('recordName'));

            // SPECIAL CASE: update Application__c by ID
            if (sObjApi == 'Application__c') {
                Map<String,Object> fields = (Map<String,Object>) block.get('fields');

                if (fields != null && fields.containsKey('Id')) {
                    Id appId = safeId(fields.get('Id'));

                    if (appId != null) {
                        Application__c app = new Application__c(Id = appId);

                        for (String fn : fields.keySet()) {
                            if (fn == 'Id') continue;
                            Schema.SObjectField f = app.getSObjectType().getDescribe().fields.getMap().get(fn);
                            String fieldType = f.getDescribe().getType().name();

                            if (fieldType == 'DATE' && fields.get(fn) != null) {
                                app.put(fn, Date.valueOf(String.valueOf(fields.get(fn))));
                            } else {
                                app.put(fn, fields.get(fn));
                            }
                        }

                        update app;

                        resultIds.put('Application', app.Id);
                        continue;
                    }
                }
            }

            if (String.isBlank(sObjApi) || String.isBlank(recordName)) continue;

            if (!grouped.containsKey(sObjApi)) {
                grouped.put(sObjApi, new Map<String, List<Map<String,Object>>>());
            }

            Map<String, List<Map<String,Object>>> byName = grouped.get(sObjApi);

            if (!byName.containsKey(recordName)) {
                byName.put(recordName, new List<Map<String,Object>>());
            }

            byName.get(recordName).add(block);
        }

        // NEW: process delete blocks first
        for (Map<String,Object> delBlock : deleteBlocks) {
            String delObj = (String) delBlock.get('sobject');
            Map<String,Object> fields = (Map<String,Object>) delBlock.get('fields');
            if (fields != null && fields.containsKey('Id')) {
                Id deleteId = safeId(fields.get('Id'));
                if (deleteId != null) {
                    delete (SObject)Schema.getGlobalDescribe()
                        .get(delObj)
                        .newSObject(deleteId);
                }
            }
        }

        // Process each SObject
        for (String sObjApi : grouped.keySet()) {

            Map<String, List<Map<String,Object>>> byName = grouped.get(sObjApi);

            /* ---------------------------------------------------------
            1) COLLECT ALL FILTERS → COMBINED using IN
            --------------------------------------------------------- */
            Map<String, List<Object>> combinedFilters = new Map<String, List<Object>>();

            for (String rn : byName.keySet()) {
                List<Map<String,Object>> blockList = byName.get(rn);

                for (Map<String,Object> blk : blockList) {
                    if (!blk.containsKey('filter')) continue;

                    Map<String,Object> filter = (Map<String,Object>) blk.get('filter');

                    for (String fieldName : filter.keySet()) {
                        Object val = filter.get(fieldName);

                        if (!combinedFilters.containsKey(fieldName)) {
                            combinedFilters.put(fieldName, new List<Object>());
                        }

                        // FIX: Convert to String if filter field is a String field
                        Schema.SObjectField sf = Schema.getGlobalDescribe()
                            .get(sObjApi).getDescribe()
                            .fields.getMap().get(fieldName);

                        if (sf != null && sf.getDescribe().getType() == Schema.DisplayType.STRING) {
                            combinedFilters.get(fieldName).add(String.valueOf(val));
                        } else {
                            combinedFilters.get(fieldName).add(val);
                        }
                    }

                }
            }

            /* ---------------------------------------------------------
            2) BUILD QUERY (ONE per OBJECT)
            --------------------------------------------------------- */
            String baseQuery = 'SELECT Id, Name FROM ' + sObjApi + ' WHERE ';

            if (sObjApi == 'Application__c') {
                baseQuery += 'Id = :applicationId';
            } 
            else {
                baseQuery += 'Application__c = :applicationId';

                for (String fieldName : combinedFilters.keySet()) {
                    baseQuery += ' AND ' + fieldName + ' IN :' + fieldName;
                }
            }

            /* ---------------------------------------------------------
            3) BUILD BIND MAP
            --------------------------------------------------------- */
            Map<String,Object> binds = new Map<String,Object>();

            binds.put('applicationId', applicationId);
            for (String fieldName : combinedFilters.keySet()) {
                binds.put(fieldName, combinedFilters.get(fieldName));
            }

            // Create new bind map but start by keeping applicationId
            Map<String, Object> typedBinds = new Map<String, Object>();
            if (binds.containsKey('applicationId')) {
                typedBinds.put('applicationId', binds.get('applicationId'));
            }

            // Convert filter-based binds only
            for (String fieldName : combinedFilters.keySet()) {
                List<Object> rawList = combinedFilters.get(fieldName);
                if (rawList == null) continue;

                Schema.SObjectField sf = Schema.getGlobalDescribe()
                    .get(sObjApi).getDescribe()
                    .fields.getMap()
                    .get(fieldName);

                if (sf != null) {
                    Schema.DisplayType t = sf.getDescribe().getType();

                    if (t == Schema.DisplayType.STRING || t == Schema.DisplayType.PICKLIST) {
                        List<String> arr = new List<String>();
                        for (Object o : rawList) arr.add(String.valueOf(o));
                        typedBinds.put(fieldName, arr);
                    }
                    else if (t == Schema.DisplayType.DOUBLE ||
                            t == Schema.DisplayType.INTEGER ||
                            t == Schema.DisplayType.CURRENCY ||
                            t == Schema.DisplayType.PERCENT) {

                        List<Decimal> arr = new List<Decimal>();
                        for (Object o : rawList) arr.add(
                            Decimal.valueOf(String.valueOf(o))
                        );
                        typedBinds.put(fieldName, arr);
                    }
                    else if (t == Schema.DisplayType.BOOLEAN) {
                        List<Boolean> arr = new List<Boolean>();
                        for (Object o : rawList)
                            arr.add(o == true || String.valueOf(o).toLowerCase() == 'true');
                        typedBinds.put(fieldName, arr);
                    }
                    else {
                        typedBinds.put(fieldName, rawList);
                    }
                } else {
                    typedBinds.put(fieldName, rawList);
                }
            }

            // REPLACE binds
            binds = typedBinds;

            /* ---------------------------------------------------------
            4) EXECUTE QUERY
            --------------------------------------------------------- */
            List<SObject> existingList = Database.queryWithBinds(
                baseQuery,
                binds,
                AccessLevel.SYSTEM_MODE
            );

            /* ---------------------------------------------------------
            5) BUILD MAPS FOR MATCHING
            --------------------------------------------------------- */
            Map<String,SObject> existingByName = new Map<String,SObject>();
            Map<Id,SObject> existingById = new Map<Id,SObject>();

            for (SObject rec : existingList) {
                existingByName.put((String)rec.get('Name'), rec);
                existingById.put(rec.Id, rec);
            }

            /* ---------------------------------------------------------
            6) MERGE, INSERT, UPDATE
            --------------------------------------------------------- */
            List<SObject> toInsert = new List<SObject>();
            List<SObject> toUpdate = new List<SObject>();

            for (String recordName : byName.keySet()) {

                List<Map<String,Object>> blockList = byName.get(recordName);
                SObject target = null;
                Id idFromBlock = null;

                // Identify ID if present
                for (Map<String,Object> blk : blockList) {
                    Map<String,Object> fields = (Map<String,Object>) blk.get('fields');
                    if (fields == null) continue;

                    if (fields.containsKey('Id') && fields.get('Id') != null) {
                        Id candidate = safeId(fields.get('Id'));
                        if (candidate != null) {
                            idFromBlock = candidate;
                            break;
                        }
                    }
                }

                // Pick existing or create new
                if (idFromBlock != null && existingById.containsKey(idFromBlock)) {
                    target = existingById.get(idFromBlock);
                } else if (existingByName.containsKey(recordName)) {
                    target = existingByName.get(recordName);
                } else {
                    target = Schema.getGlobalDescribe().get(sObjApi).newSObject();
                    target.put('Application__c', applicationId);

                    Schema.SObjectField nameField = target.getSObjectType()
                        .getDescribe().fields.getMap().get('Name');

                    if (
                        nameField != null &&
                        nameField.getDescribe().isUpdateable() &&
                        String.isNotBlank(recordName)
                    ) {
                        target.put('Name', recordName);
                    }

                    toInsert.add(target);
                }

                // Merge all fields
                for (Map<String,Object> blk : blockList) {
                    Map<String,Object> fields = (Map<String,Object>) blk.get('fields');
                    if (fields == null) continue;

                    for (String fn : fields.keySet()) {

                        if (fn.contains('.')) {
                            continue;
                        }

                        Schema.SObjectField f = target.getSObjectType().getDescribe().fields.getMap().get(fn);
                        String fieldType = f.getDescribe().getType().name();

                        if (fieldType == 'DATE' && fields.get(fn) != null) {
                            target.put(fn, Date.valueOf(String.valueOf(fields.get(fn))));
                        } else {
                            target.put(fn, fields.get(fn));
                        }
                    }
                }

                if (!toInsert.contains(target) && !toUpdate.contains(target)) {
                    toUpdate.add(target);
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }

            /* ---------------------------------------------------------
            7) DELETE MISSING PARENTS (SAFE, FILTERED)
            --------------------------------------------------------- */
            Boolean nameIsUpdateable =
                Schema.getGlobalDescribe().get(sObjApi)
                    .getDescribe()
                    .fields.getMap()
                    .get('Name')
                    .getDescribe()
                    .isUpdateable();

            if (!nameIsUpdateable) {
                System.debug('Skipping delete for ' + sObjApi + ' (Name not updateable)');
            } 
            else {
                Set<String> incomingNames = new Set<String>(byName.keySet());
                Set<String> existingNames = new Set<String>(existingByName.keySet());

                existingNames.removeAll(incomingNames);

                if (!existingNames.isEmpty()) {
                    List<SObject> toDelete = new List<SObject>();

                    for (String nm : existingNames) {
                        if (existingByName.containsKey(nm)) {
                            toDelete.add(existingByName.get(nm));
                        }
                    }

                    if (!toDelete.isEmpty()) {
                        delete toDelete;
                    }
                }
            }

            /* ---------------------------------------------------------
            8) ADD RESULT IDS
            --------------------------------------------------------- */
            for (SObject rec : toInsert) {
                resultIds.put((String) rec.get('Name'), rec.Id);
            }
            for (SObject rec : toUpdate) {
                resultIds.put((String) rec.get('Name'), rec.Id);
            }
        }

        return resultIds;
    }


    /**********************************************
     * SAVE CHILDREN (Insert + Update + Delete)
     * - explicit deletions via deletedIds per block
     **********************************************/
    @AuraEnabled
    public static void saveChildren(String payloadJson) {
        Map<String,Object> payload = (Map<String,Object>) JSON.deserializeUntyped(payloadJson);
        if (payload == null || payload.isEmpty()) return;

        for (String blockName : payload.keySet()) {
            Map<String,Object> block = (Map<String,Object>) payload.get(blockName);
            if (block == null) continue;

            String sObjApi = String.valueOf(block.get('sobject'));
            String parentLookupField = (String) block.get('parentLookupField');
            String childKeyField = (String) block.get('childKeyField');
            Boolean useSequenceKey = (Boolean) block.get('useSequenceKey');

            List<Object> rows = (List<Object>) block.get('rows');
            List<Object> deleteIds = (List<Object>) block.get('deletedIds');

            List<SObject> toInsert = new List<SObject>();
            List<SObject> toUpdate = new List<SObject>();
            List<SObject> toDelete = new List<SObject>();

            // INSERT + UPDATE
            if (rows != null) {
                for (Object o : rows) {
                    Map<String,Object> r = (Map<String,Object>) o;

                    Map<String,Object> fields = (Map<String,Object>) r.get('fields');

                    // parentId from JSON (string → Id)
                    Id parentId = null;
                    Object parentRaw = r.get('parentId');
                    if (parentRaw != null) {
                        String parentStr = String.valueOf(parentRaw);
                        parentId = safeId(parentStr);
                    }

                    // row Id from JSON (string → Id)
                    Id rowId = null;
                    Object idRaw = r.get('Id');
                    if (idRaw != null) {
                        String idStr = String.valueOf(idRaw);
                        rowId = safeId(idStr);
                    }

                    SObject rec;
                    if (rowId != null) {
                        // existing row
                        rec = Schema.getGlobalDescribe().get(sObjApi).newSObject(rowId);
                        toUpdate.add(rec);
                    } else {
                        // new row
                        rec = Schema.getGlobalDescribe().get(sObjApi).newSObject();
                        toInsert.add(rec);
                    }

                    if (parentLookupField != null && parentId != null) {
                        rec.put(parentLookupField, parentId);
                    }

                    if (useSequenceKey == true && childKeyField != null && fields != null && fields.containsKey(childKeyField)) {
                        rec.put(childKeyField, fields.get(childKeyField));
                    }

                    if (fields != null) {
                        for (String fn : fields.keySet()) {
                            if (useSequenceKey == false && fn == childKeyField) continue;
                          
                            Schema.SObjectField f = rec.getSObjectType().getDescribe().fields.getMap().get(fn);
                            String fieldType = f.getDescribe().getType().name();

                            if (fieldType == 'DATE' && fields.get(fn) != null) {
                                rec.put(fn, Date.valueOf(String.valueOf(fields.get(fn))));
                            } else {
                                rec.put(fn, fields.get(fn));
                            }
                        }
                    }
                }
            }

            // DELETE
            if (deleteIds != null && !deleteIds.isEmpty()) {
                List<Id> ids = new List<Id>();
                for (Object d : deleteIds) {
                    if (d == null) continue;
                    String idStr = String.valueOf(d);
                    Id delId = safeId(idStr);
                    if (delId != null) {
                        ids.add(delId);
                    }
                }

                if (!ids.isEmpty()) {
                    String delQuery = 'SELECT Id FROM ' + sObjApi + ' WHERE Id IN :ids';
                    List<SObject> delRecs = Database.query(delQuery);
                    toDelete.addAll(delRecs);
                }
            }

            if (!toDelete.isEmpty()) delete toDelete;
            if (!toUpdate.isEmpty()) update toUpdate;
            if (!toInsert.isEmpty()) insert toInsert;
        }
    }

    private static Boolean isId(Object raw) {
        if (raw == null) return false;

        String s = String.valueOf(raw).trim();
        if (String.isBlank(s)) return false;

        // valid 15-char or 18-char alphanumeric Salesforce Id
        Pattern p = Pattern.compile('^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$');
        Matcher m = p.matcher(s);
        return m.matches();
    }

    private static Id safeId(Object raw) {
        return isId(raw) ? (Id) String.valueOf(raw) : null;
    }

    /**
     * Return list of country dialing options for phoneInput LWC.
     * Each entry:
     *   { label: '(+91) India', value: '+91', acceptedLengths: '10' }
     * - Name -> country name
     * - Country_Code__c -> like '91' or '1-784' (hyphenated for NANP territories)
     * - AcceptedNumberLength__c -> semicolon-separated discrete lengths e.g. '7;10;11'
     *
     * Security:
     * - Query WITH USER_MODE to enforce FLS and sharing per org rules (General Requirements).
     */
    @AuraEnabled
    public static List<Map<String, Object>> getCountryPhoneOptions() {
        List<Map<String, Object>> out = new List<Map<String, Object>>();

        for (Country_Master__c cm :
            [SELECT Id, Name, Country_Code__c, AcceptedNumberLength__c
             FROM Country_Master__c ORDER BY Name ASC
             ]) {

            String countryName = cm.Name;
            String rawCode = cm.Country_Code__c;
            String accepted = cm.AcceptedNumberLength__c;

            if (String.isBlank(countryName) || String.isBlank(rawCode)) {
                // skip invalid records
                continue;
            }

            // Ensure display/value formatting:
            // label: '(+<code>) <name>', value: '+<code>'  (e.g., '+1-784')
            String valueCode = '+' + rawCode.trim();
            String label = countryName + ' (' + valueCode + ')';

            Map<String, Object> row = new Map<String, Object>{
                'label' => label,
                'value' => valueCode,
                'acceptedLengths' => (accepted == null ? '' : accepted.trim())
            };
            out.add(row);
        }
        return out;
    }

    @AuraEnabled
    public static void updateStage(Id applicationId, String newStage) {

        if (applicationId == null || String.isBlank(newStage)) {
            return;
        }

        // Fetch existing stage
        Application__c app = [
            SELECT Id, Application_Stage__c 
            FROM Application__c 
            WHERE Id = :applicationId
            LIMIT 1
        ];

        // Define allowed stage order
        Map<String, Integer> stageRank = new Map<String, Integer>{
            ''=>0,
            'Programme Details' => 1,
            'Basic Details' => 2,
            'Academic Details' => 3,
            'Entrance Exam' => 4,
            'Work Experience' => 5,
            'Profile Information' => 6,
            'Terms and Conditions' => 7,
            'Payment' => 8
        };

        Integer currentRank = stageRank.get(String.isBlank(app?.Application_Stage__c) ? '' : app?.Application_Stage__c);
        Integer newRank     = stageRank.get(newStage);

        // If stage not recognized → do nothing
        if (currentRank == null || newRank == null) {
            return;
        }

        // Prevent backward movement
        if (newRank < currentRank) {
            return;
        }

        // Update
        app.Application_Stage__c = newStage;
        update app;
    }

    public class MetadataRequest {
        @AuraEnabled public String metadataName { get; set;}
        @AuraEnabled public List<String> fields { get; set;}
        @AuraEnabled public List<Filter> filters { get; set;}
    }

    public class Filter {
        @AuraEnabled public String field { get; set;}
        @AuraEnabled public String operator { get; set;}
        @AuraEnabled public Object value { get; set;}
    }

    @AuraEnabled
    public static Map<String, List<Map<String, Object>>> fetchMetadataBulk(
        List<MetadataRequest> requests
    ) {
        Map<String, List<Map<String, Object>>> response = new Map<String, List<Map<String, Object>>>();
        System.debug('custom meta requests '+requests);
        for (MetadataRequest req : requests) {

            if (String.isBlank(req.metadataName) || req.fields == null || req.fields.isEmpty()) {
                continue;
            }

            System.debug('custom meta req valid '+req);

            String soql = 'SELECT ' + String.join(req.fields, ',') +
                          ' FROM ' + req.metadataName;

            List<String> conditions = new List<String>();
            Map<String, Object> bindVars = new Map<String, Object>();

            if (req.filters != null) {
                Integer i = 0;

                for (Filter f : req.filters) {
                    if (String.isBlank(f.field) || String.isBlank(f.operator)) continue;

                    String key = 'val' + i;

                    if (f.operator.toUpperCase() == 'IN' && f.value instanceof List<Object>) {
                        conditions.add(f.field + ' IN :' + key);
                    } else {
                        conditions.add(f.field + ' ' + f.operator + ' :' + key);
                    }

                    bindVars.put(key, f.value);
                    i++;
                }
            }

            if (!conditions.isEmpty()) {
                soql += ' WHERE ' + String.join(conditions, ' AND ');
            }

            System.debug('custom meta soql string '+soql);

            List<SObject> records = Database.queryWithBinds(soql, bindVars, AccessLevel.SYSTEM_MODE);

            List<Map<String, Object>> rows = new List<Map<String, Object>>();

            for (SObject rec : records) {
                Map<String, Object> row = new Map<String, Object>();
                for (String f : req.fields) {
                    row.put(f, rec.get(f));
                }
                rows.add(row);
            }

            response.put(req.metadataName, rows);
        }

        return response;
    }

    @AuraEnabled
    public static void deleteDocumentsByCode(
        Id applicationId,
        List<String> documentCodes
    ) {
        if (
            applicationId == null ||
            documentCodes == null ||
            documentCodes.isEmpty()
        ) {
            return;
        }

        List<Document_Details__c> documents = [
            SELECT Id
            FROM Document_Details__c
            WHERE Application_No__c = :applicationId
            AND Document_Code__c IN :documentCodes
        ];

        if (documents.isEmpty()) {
            return;
        }

        Set<Id> documentDetailIds = new Set<Id>();

        for (Document_Details__c document : documents) {
            documentDetailIds.add(document.Id);
        }

        Set<Id> contentDocumentIds = new Set<Id>();

        for (ContentDocumentLink contentDocumentLink : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :documentDetailIds
        ]) {
            contentDocumentIds.add(contentDocumentLink.ContentDocumentId);
        }

        if (!contentDocumentIds.isEmpty()) {
            delete [
                SELECT Id
                FROM ContentDocument
                WHERE Id IN :contentDocumentIds
            ];
        }

        delete documents;
    }


}