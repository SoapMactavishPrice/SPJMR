public class AcademicControllerVerification {


   // Public entry used by ApplicationSectionDataController
    public static Map<String, Object> fetchDynamic(String requestJson) {

        if (String.isBlank(requestJson)) {
            return new Map<String, Object>();
        }

        Map<String, Object> request =
            (Map<String, Object>) JSON.deserializeUntyped(requestJson);

        List<Object> parentsCfg  = (List<Object>) request.get('parents');
        List<Object> childrenCfg = (List<Object>) request.get('children');

        Map<String, Object> response = new Map<String, Object>();

        // Keep parent IDs grouped by logicalName so children can target specific parents
        Map<String, Set<Id>> parentIdsByLogical = new Map<String, Set<Id>>();
        Map<String, Map<String, Object>> parentRowByLogical = new Map<String, Map<String, Object>>();

        /* =====================================================
           1) PARENTS (one query per parent config)
           - Always returns a Map (even if record missing)
           - Includes ALL requested fields (even if null) => LWC sees them
        ====================================================== */
        if (parentsCfg != null) {
            for (Object pObj : parentsCfg) {
                Map<String, Object> p = (Map<String, Object>) pObj;

                String logicalName = (String) p.get('logicalName');
                String sobjectName = (String) p.get('sobject');

                List<String> fields = stringify((List<Object>) p.get('fields'));
                List<Object> filters = (List<Object>) p.get('filters');

                if (String.isBlank(logicalName) || String.isBlank(sobjectName) || fields.isEmpty()) {
                    // always return something to avoid UI crash
                    response.put(logicalName, buildNoRecordsParent(fields));
                    parentIdsByLogical.put(logicalName, new Set<Id>());
                    continue;
                }

                String soql = buildSoql(sobjectName, fields, filters, null);
                List<SObject> rows = safeQuery(soql);

                Set<Id> ids = new Set<Id>();
                Map<String, Object> rowMap;

                if (!rows.isEmpty()) {
                    SObject first = rows[0];
                    if ((Id) first.get('Id') != null) ids.add((Id) first.get('Id'));

                    // IMPORTANT: include ALL requested fields even if null
                    rowMap = sObjectToRequestedFieldMap(first, fields);
                } else {
                    rowMap = buildNoRecordsParent(fields);
                }

                response.put(logicalName, rowMap);
                parentIdsByLogical.put(logicalName, ids);
                parentRowByLogical.put(logicalName, rowMap);
            }
        }

        /* =====================================================
           2) CHILDREN (bulk-safe)
           - Builds parentId set from parentLogicalNames (optional)
           - Runs ONE query per child config using IN :parentIds
           - Returns:
             a) default: Map<key, rowMap>
             b) for semesterMarks: Map<academicId, Map<key,rowMap>> (grouped)
           - Adds "No records found" row when empty
        ====================================================== */
        if (childrenCfg != null) {
            for (Object cObj : childrenCfg) {
                Map<String, Object> c = (Map<String, Object>) cObj;

                String logicalName = (String) c.get('logicalName');
                String sobjectName = (String) c.get('sobject');

                List<String> fields = stringify((List<Object>) c.get('fields'));
                String parentLookupField = (String) c.get('parentLookupField');
                Boolean useSequenceKey = (Boolean) c.get('useSequenceKey');
                String childKeyField = (String) c.get('childKeyField');
                List<Object> filters = (List<Object>) c.get('filters');

                // Optional: only use specific parent logical names
                List<String> parentLogicalNames = stringify((List<Object>) c.get('parentLogicalNames'));

                if (String.isBlank(logicalName) || String.isBlank(sobjectName) || fields.isEmpty() || String.isBlank(parentLookupField)) {
                    response.put(logicalName, buildNoRecordsChildRow());
                    continue;
                }

                Set<Id> parentIds = new Set<Id>();
                if (parentLogicalNames != null && !parentLogicalNames.isEmpty()) {
                    for (String pl : parentLogicalNames) {
                        if (parentIdsByLogical.containsKey(pl)) {
                            parentIds.addAll(parentIdsByLogical.get(pl));
                        }
                    }
                } else {
                    for (Set<Id> ids : parentIdsByLogical.values()) parentIds.addAll(ids);
                }

                // ✅ Guard: if no parent IDs found, return "No records found" row (no crash)
                if (parentIds.isEmpty()) {
                    response.put(logicalName, buildNoRecordsChildRow());
                    continue;
                }

                // Build child SOQL using IN (:parentIds)
                String soql = buildSoql(
                    sobjectName,
                    fields,
                    filters,
                    new InFilter(parentLookupField, parentIds)
                );

                List<SObject> childRows = safeQuery(soql);

                // SPECIAL: semesterMarks should be grouped per Academic_Detail__c (UG only)
                Boolean groupByParentId = (Boolean) c.get('groupByParentId');
                if (groupByParentId == null) groupByParentId = false;

                if (groupByParentId) {
                    // Map<ParentId, Map<Key, Row>>
                    Map<String, Object> grouped = new Map<String, Object>();

                    for (SObject ch : childRows) {
                        Id pid = (Id) ch.get(parentLookupField);
                        if (pid == null) continue;

                        Map<String, Object> rowMap = sObjectToRequestedFieldMap(ch, fields);

                        String key = computeChildKey(ch, useSequenceKey, childKeyField);
                        key = makeUniqueKey(key, (Id) ch.get('Id'));

                        Map<String, Object> bucket =
                            (Map<String, Object>) grouped.get(String.valueOf(pid));

                        if (bucket == null) {
                            bucket = new Map<String, Object>();
                            grouped.put(String.valueOf(pid), bucket);
                        }

                        bucket.put(key, rowMap);
                    }

                    // Add a no-record row if nothing found
                    if (grouped.isEmpty()) {
                        grouped.put('0', buildNoRecordsChildRowInner());
                    }

                    response.put(logicalName, grouped);

                } else {
                    // default: Map<Key, Row>
                    Map<String, Object> childResult = new Map<String, Object>();

                    for (SObject ch : childRows) {
                        Map<String, Object> rowMap = sObjectToRequestedFieldMap(ch, fields);

                        String key = computeChildKey(ch, useSequenceKey, childKeyField);
                        key = makeUniqueKey(key, (Id) ch.get('Id'));

                        childResult.put(key, rowMap);
                    }

                    if (childResult.isEmpty()) {
                        response.put(logicalName, buildNoRecordsChildRow());
                    } else {
                        response.put(logicalName, childResult);
                    }
                }
            }
        }

        return response;
    }

    /* =========================
       SOQL BUILDING (safe-ish)
       - Uses string filters from metadata
       - Escapes single quotes
       - Supports IN filter for parent ids
    ========================== */

    private class InFilter {
        String fieldName;
        Set<Id> ids;
        InFilter(String f, Set<Id> s) { fieldName = f; ids = s; }
    }

    private static String buildSoql(
        String sobjectName,
        List<String> fields,
        List<Object> filters,
        InFilter inFilter
    ) {
        // ensure Id is always selected for keying
        if (!fields.contains('Id')) fields.add('Id');

        String soql = 'SELECT ' + String.join(fields, ',') + ' FROM ' + sobjectName;

        List<String> whereParts = new List<String>();

        if (inFilter != null && inFilter.ids != null && !inFilter.ids.isEmpty()) {
            // bind is not possible via deserializeUntyped; we embed Ids safely
            List<String> idStrs = new List<String>();
            for (Id i : inFilter.ids) idStrs.add('\'' + String.valueOf(i) + '\'');
            whereParts.add(inFilter.fieldName + ' IN (' + String.join(idStrs, ',') + ')');
        }

        if (filters != null && !filters.isEmpty()) {
            for (Object fObj : filters) {
                Map<String, Object> f = (Map<String, Object>) fObj;
                String fieldName = (String) f.get('field');
                Object valueObj = f.get('value');

                if (String.isBlank(fieldName)) continue;

                String val = valueObj == null ? null : String.valueOf(valueObj);
                if (val == null) {
                    whereParts.add(fieldName + ' = NULL');
                } else {
                    whereParts.add(fieldName + ' = \'' + String.escapeSingleQuotes(val) + '\'');
                }
            }
        }

        if (!whereParts.isEmpty()) {
            soql += ' WHERE ' + String.join(whereParts, ' AND ');
        }

        return soql;
    }

    private static List<SObject> safeQuery(String soql) {
        try {
            return Database.query(soql);
        } catch (Exception e) {
            // never crash UI for bad config; return empty
            return new List<SObject>();
        }
    }

    private static Map<String, Object> sObjectToRequestedFieldMap(SObject sob, List<String> fields) {
        Map<String, Object> out = new Map<String, Object>();
        for (String f : fields) {
            out.put(f, sob.get(f));
        }
        return out;
    }

    private static String computeChildKey(SObject ch, Boolean useSequenceKey, String childKeyField) {
        String key;
        if (useSequenceKey == true && !String.isBlank(childKeyField) && ch.get(childKeyField) != null) {
            key = String.valueOf(ch.get(childKeyField));
        } else {
            key = String.valueOf(ch.get('Id'));
        }
        if (String.isBlank(key)) key = 'ROW';
        return key;
    }

    private static String makeUniqueKey(String key, Id idVal) {
        // avoid duplicate keys: "1" can repeat across parents
        if (idVal == null) return key;
        return key + '__' + String.valueOf(idVal).right(5);
    }

    private static Map<String, Object> buildNoRecordsParent(List<String> requestedFields) {
        Map<String, Object> m = new Map<String, Object>();
        // Ensure UI shows something
        m.put('No_Records_Found__c', 'No records found');

        // include all requested fields as null so UI can still list them if needed
        if (requestedFields != null) {
            for (String f : requestedFields) {
                if (!m.containsKey(f)) m.put(f, null);
            }
        }
        return m;
    }

    private static Map<String, Object> buildNoRecordsChildRow() {
        // LWC child expects Map<idx,row>
        Map<String, Object> wrapper = new Map<String, Object>();
        wrapper.put('0', buildNoRecordsChildRowInner());
        return wrapper;
    }

    private static Map<String, Object> buildNoRecordsChildRowInner() {
        Map<String, Object> row = new Map<String, Object>();
        row.put('No_Records_Found__c', 'No records found');
        return row;
    }

    private static List<String> stringify(List<Object> objs) {
        if (objs == null) return new List<String>();
        List<String> out = new List<String>();
        for (Object o : objs) out.add(String.valueOf(o));
        return out;
    }
}