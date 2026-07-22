public with sharing class GenericLookupController {

    private static final String PLACEHOLDER_PREFIX = '__CLAUSE_';
    private static final String PLACEHOLDER_SUFFIX = '__';


    /* ============================================================
       Wrapper returned to LWC
       ============================================================ */
    public class LookupPage {
        @AuraEnabled public List<SObject> records;
        @AuraEnabled public Map<String, Object> pageState;
    }

    /* ============================================================
       Operator translation (metadata → SOQL)
       ============================================================ */
    private static String toSoqlOperator(String op) {
        if (op == null) return null;

        switch on op.toLowerCase() {
            when 'eq'       { return '='; }
            when 'ne'       { return '!='; }
            when 'lt'       { return '<'; }
            when 'lte'      { return '<='; }
            when 'gt'       { return '>'; }
            when 'gte'      { return '>='; }
            when 'like'     { return 'LIKE'; }
            when 'nlike'    { return 'NOT LIKE'; }
            when 'in'       { return 'IN'; }
            when 'nin'      { return 'NOT IN'; }
            when 'includes' { return 'INCLUDES'; }
            when 'excludes' { return 'EXCLUDES'; }
            when else       { return null; }
        }
    }

    /* ============================================================
       Safe literal formatter (NO dynamic binds)
       ============================================================ */
    private static String toSoqlLiteral(Object val) {
        if (val == null) return 'NULL';

        if (val instanceof String) {
            return '\'' + String.escapeSingleQuotes((String) val) + '\'';
        }

        if (val instanceof Id) {
            return '\'' + String.valueOf(val) + '\'';
        }

        if (val instanceof Boolean) {
            return ((Boolean) val) ? 'TRUE' : 'FALSE';
        }

        if (val instanceof Date) {
            return ((Date) val).format();
        }

        if (val instanceof Datetime) {
            return ((Datetime) val)
                .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }

        if (val instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object o : (List<Object>) val) {
                parts.add(toSoqlLiteral(o));
            }
            return '(' + String.join(parts, ',') + ')';
        }

        return String.valueOf(val);
    }

    /* ============================================================
       Main search method
       ============================================================ */
    @AuraEnabled
    public static LookupPage search(
        String objectApiName,
        Map<String, Object> displayInfo,
        List<String> sortInfo,
        Map<String, Object> matchingInfo,
        Map<String, Object> filter,
        String searchTerm,
        Boolean allowOther,
        Map<String, Object> pageState,
        Integer pageSize,
        String paginationMode   // 'offset' | 'keyset'
    ) {

        displayInfo = displayInfo == null ? new Map<String, Object>() : displayInfo;
        matchingInfo = matchingInfo == null ? new Map<String, Object>() : matchingInfo;
        filter = filter == null ? new Map<String, Object>() : filter;
        pageState = pageState == null ? new Map<String, Object>() : pageState;

        /* ------------------------------------------------------------
           Object access check
           ------------------------------------------------------------ */
        Schema.SObjectType sType =
            Schema.getGlobalDescribe().get(objectApiName);

        if (sType == null || !sType.getDescribe().isAccessible()) {
            throw new AuraHandledException('No access to object');
        }

        /* ============================================================
           COLLECT SELECT FIELDS
           ============================================================ */
        Set<String> selectFields = new Set<String>{ 'Id' };


        // displayInfo
        if (displayInfo != null) {
            if (displayInfo.containsKey('primaryField')) {
                selectFields.add((String) displayInfo.get('primaryField'));

                if (displayInfo.containsKey('additionalFields')) {
                    List<Object> addl =
                        (List<Object>) JSON.deserializeUntyped(
                            JSON.serialize(displayInfo.get('additionalFields'))
                        );
                    for (Object o : addl) {
                        selectFields.add((String) o);
                    }
                }
            } else {
                selectFields.add('Name');
            }            
        } else {
            selectFields.add('Name');
        }

        // matchingInfo (multi-field)
        List<String> matchingFields = new List<String>();

        if (matchingInfo != null) {

            if (matchingInfo.containsKey('primaryField')) {
                Map<String, Object> pf =
                    (Map<String, Object>) JSON.deserializeUntyped(
                        JSON.serialize(matchingInfo.get('primaryField'))
                    );
                matchingFields.add((String) pf.get('fieldPath'));
            }

            if (matchingInfo.containsKey('additionalFields')) {
                List<Object> addl =
                    (List<Object>) JSON.deserializeUntyped(
                        JSON.serialize(matchingInfo.get('additionalFields'))
                    );
                for (Object o : addl) {
                    Map<String, Object> af = (Map<String, Object>) o;
                    matchingFields.add((String) af.get('fieldPath'));
                }
            }
        }

        selectFields.addAll(matchingFields);

        /* ============================================================
           FILTER CRITERIA (JSON-safe)
           ============================================================ */
        List<Map<String, Object>> criteria = new List<Map<String, Object>>();
        if (filter != null && filter.containsKey('criteria')) {
            List<Object> raw =
                (List<Object>) JSON.deserializeUntyped(
                    JSON.serialize(filter.get('criteria'))
                );
            for (Object o : raw) {
                Map<String, Object> c = (Map<String, Object>) o;
                criteria.add(c);
                selectFields.add((String) c.get('fieldPath'));
            }
        }


        /* ============================================================
           BUILD WHERE CLAUSES
           ============================================================ */
        Map<Integer, String> clauseMap = new Map<Integer, String>();
        Integer idx = 1;

        // filters
        for (Map<String, Object> c : criteria) {

            String field = (String) c.get('fieldPath');
            String rawOp = (String) c.get('operator');
            Object val = c.get('value');

            String soqlOp = toSoqlOperator(rawOp);
            if (soqlOp == null) {
                throw new AuraHandledException(
                    'Unsupported operator: ' + rawOp
                );
            }

            if (val == null) {
                if (rawOp == 'eq') {
                    clauseMap.put(idx, field + ' = null');
                } else if (rawOp == 'ne') {
                    clauseMap.put(idx, field + ' != null');
                } else {
                    throw new AuraHandledException(
                        'Null not supported for operator: ' + rawOp
                    );
                }
            } else {
                clauseMap.put(
                    idx,
                    field + ' ' + soqlOp + ' ' + toSoqlLiteral(val)
                );
            }

            idx++;
        }


        // search (OR across matching fields)
        if (String.isNotBlank(searchTerm)) {

            List<String> likes = new List<String>();
            String likeVal =
                '\'%' + String.escapeSingleQuotes(searchTerm) + '%\'';

            for (String f : matchingFields) {
                likes.add(f + ' LIKE ' + likeVal);
            }

            if (matchingFields.isEmpty()) {
                likes.add('Name LIKE ' + likeVal);
            }

            clauseMap.put(idx, '(' + String.join(likes, ' OR ') + ')');
            if(filter != null && filter.containsKey('filterLogic')){
                filter.put('filterLogic', '('+filter.get('filterLogic')+') AND '+clauseMap.keySet().size());
            }
            idx++;
        }

        Map<Integer, String> indexToPlaceholder = new Map<Integer, String>();
        Map<String, String> placeholderToClause = new Map<String, String>();

        for (Integer idy : clauseMap.keySet()) {
            String placeholder =
                PLACEHOLDER_PREFIX +
                UUID.randomUUID().toString() +
                PLACEHOLDER_SUFFIX;

            indexToPlaceholder.put(idy, placeholder);
            placeholderToClause.put(placeholder, clauseMap.get(idy));
        }

        /* ============================================================
           APPLY filterLogic OR default AND
           ============================================================ */
        String baseWhere = '';

        if (!clauseMap.isEmpty()) {
            if (filter != null && filter.containsKey('filterLogic')) {

                baseWhere = (String) filter.get('filterLogic');

                for (Integer idz : indexToPlaceholder.keySet()) {
                    baseWhere = baseWhere.replaceAll(
                        '\\b' + String.valueOf(idz) + '\\b',
                        indexToPlaceholder.get(idz)
                    );
                }

                for (String placeholder : placeholderToClause.keySet()) {
                    baseWhere = baseWhere.replace(
                        placeholder,
                        '(' + placeholderToClause.get(placeholder) + ')'
                    );
                }


            } else {
                baseWhere =
                    String.join(
                        new List<String>(clauseMap.values()),
                        ' AND '
                    );
            }
        }

        if (allowOther == true) {
            // If client passed an otherField in filter, use it; else default to Name
            String otherField = '';
            if (filter != null && filter.containsKey('otherField')) {
                otherField = (String) filter.get('otherField');
            }
            if (String.isBlank(otherField)) {
                otherField = 'Name';
            }
            baseWhere = '(' + baseWhere + ') OR (' + otherField + ' = \'Other\')';
        }

        /* ============================================================
           PAGINATION (OFFSET / KEYSET)
           ============================================================ */
        // NOTE:
        // sortInfo is only supplied for lookups that support "Other".
        // Other lookups rely on default ordering via displayInfo.primaryField.

        if (sortInfo != null && !sortInfo.isEmpty()) {
            Boolean hasId = false;
            for (String s : sortInfo) {
                if (s != null && s.toLowerCase().startsWith('id ')) {
                    hasId = true;
                    break;
                }
            }
            if (!hasId) {
                sortInfo.add('Id ASC');
            }
        }

        
        /* ============================================================
        ORDER BY + KEYSET COMPATIBILITY
        ============================================================ */
        String orderByClause = '';
        String orderField = '';

        if (sortInfo != null && !sortInfo.isEmpty()) {

            // Example input: "Other_Sort_Order__c ASC"
            String firstSort = sortInfo[0];

            // Extract field name safely
            orderField = firstSort.split('\\s+')[0];

            orderByClause = ' ORDER BY ' + String.join(sortInfo, ', ');

        } else {

            orderField =
                displayInfo != null && displayInfo.containsKey('primaryField')
                    ? (String) displayInfo.get('primaryField')
                    : 'Id';

            orderByClause = ' ORDER BY ' + orderField + ', Id';
        }


        String paginationClause = '';

        if ('keyset'.equalsIgnoreCase(paginationMode) && pageState != null) {
            Object lastValue = pageState.get('lastValue');
            Id lastId = (Id) pageState.get('lastId');

            if (lastValue != null && lastId != null) {
                paginationClause =
                    '(' + orderField + ' > ' + toSoqlLiteral(lastValue) +
                    ' OR (' + orderField + ' = ' +
                    toSoqlLiteral(lastValue) +
                    ' AND Id > ' + toSoqlLiteral(lastId) + '))';
            }
        }

        /* ============================================================
           FINAL WHERE
           ============================================================ */
        List<String> whereParts = new List<String>();
        if (String.isNotBlank(baseWhere)) whereParts.add(baseWhere);
        if (String.isNotBlank(paginationClause)) whereParts.add(paginationClause);

        String finalWhere =
            whereParts.isEmpty()
                ? ''
                : ' WHERE ' + String.join(whereParts, ' AND ');

        /* ============================================================
           SOQL
           ============================================================ */
        Decimal offsetVal = 0;
        if ('offset'.equalsIgnoreCase(paginationMode)) {
            offsetVal =
                pageState != null && pageState.containsKey('offset')
                    ? (Decimal) pageState.get('offset')
                    : 0;
        }

        Decimal maxCount = Database.countQuery(
             'SELECT Count() FROM ' + objectApiName +
            finalWhere
        );

        if(offsetVal == maxCount ||  offsetVal > maxCount || offsetVal > 2000) {
            return new LookupPage();
        }

        offsetVal = offsetVal < 0 ? 0 : offsetVal;

        String soql =
            'SELECT ' + String.join(new List<String>(selectFields), ', ') +
            ' FROM ' + objectApiName +
            finalWhere +
            orderByClause +
            ' LIMIT ' + pageSize;

        if ('offset'.equalsIgnoreCase(paginationMode)) {
            soql += ' OFFSET ' + offsetVal;
        }

        /* ============================================================
           EXECUTE QUERY
           ============================================================ */
        List<SObject> rows = Database.query(soql);

        /* ============================================================
           NEXT PAGE STATE
           ============================================================ */
        Map<String, Object> nextState = new Map<String, Object>();

        if ('offset'.equalsIgnoreCase(paginationMode)) {
            nextState.put('offset', offsetVal + pageSize);
        }

        if ('keyset'.equalsIgnoreCase(paginationMode) && !rows.isEmpty()) {
            SObject last = rows[rows.size() - 1];
            nextState.put('lastValue', last.get(orderField));
            nextState.put('lastId', last.get('Id'));
        }

        LookupPage page = new LookupPage();
        page.records = rows;
        page.pageState = nextState;
        return page;
    }
}