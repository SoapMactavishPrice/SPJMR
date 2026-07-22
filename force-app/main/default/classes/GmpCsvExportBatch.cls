/**
 * Batch class to export GMP Application data to CSV format using field catalog
 * Mimics the functionality of export-gmp-final-csv.js
 * 
 * Usage:
 * List<Id> applicationIds = new List<Id>{'a015i000009XXXX', 'a015i000009YYYY'};
 * Database.executeBatch(new GmpCsvExportBatch(applicationIds), 200);
 */
public class GmpCsvExportBatch implements Database.Batchable<Id>, Database.Stateful {
    
    private static final String CATALOG_RESOURCE_NAME = 'Gmp_Metadata';
    
    private List<Id> applicationIds;
    private Map<String, SectionMetadata> sectionIndex;
    private List<OutputMapping> outputMappings;
    private Map<String, QueryPlan> queryPlans;
    private List<HeaderDefinition> headerDefinitions;

    private String csvHeaderLine;

    private Integer filesCreated = 0;
    private Integer processedApplications = 0;
    
    // Constructor
    public GmpCsvExportBatch(List<Id> appIds) {
        this.applicationIds = appIds;
    }
    
    // Load field catalog from static resource
    private void loadFieldCatalog() {
        outputMappings = new List<OutputMapping>();
        Set<String> seenKeys = new Set<String>();

        try {
            StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = :CATALOG_RESOURCE_NAME LIMIT 1];
            List<Object> catalogData = (List<Object>)JSON.deserializeUntyped(sr.Body.toString());
            
            for (Object item : catalogData) {
                Map<String, Object> row = (Map<String, Object>)item;
                
                // Skip if not included in recommendedInclude
                String businessExport = (String)row.get('includeInBusinessExport');
                if (businessExport != 'Yes') {
                    continue;
                }

                String includeFlag = (String)row.get('recommendedInclude');
                if (String.isBlank(includeFlag)) {
                    includeFlag = businessExport;
                }
                if (includeFlag != 'Yes') {
                    continue;
                }
                
                OutputMapping mapping = new OutputMapping();
                mapping.stageOrder = getInteger(row, 'stageOrder');
                mapping.stage = (String)row.get('stage');
                mapping.component = (String)row.get('component');
                mapping.relationType = (String)row.get('relationType');
                mapping.contextLogicalName = (String)row.get('contextLogicalName');
                mapping.recordName = (String)row.get('recordName');
                mapping.objectApiName = (String)row.get('objectApiName');
                mapping.fieldApiName = (String)row.get('fieldApiName');
                mapping.queryFieldPath = (String)row.get('queryFieldPath');
                mapping.outputValuePath = (String)row.get('outputValuePath');
                mapping.label = (String)row.get('label');
                mapping.fieldType = (String)row.get('fieldType');
                mapping.outputKind = (String)row.get('outputKind');
                mapping.quoteMode = (String)row.get('quoteMode');
                mapping.exportCardinality = (String)row.get('exportCardinality');
                mapping.lookupDisplayPath = (String)row.get('lookupDisplayPath');

                mapping.flattenStrategy = (String)row.get('flattenStrategy');
                mapping.inferredMaxSlots = getInteger(row, 'inferredMaxSlots');
                mapping.outputColumnTemplate = (String)row.get('outputColumnTemplate');
                mapping.outputColumnKey = (String)row.get('outputColumnKey');
                mapping.sectionLabel = (String)row.get('sectionLabel');

                mapping.recommendedInclude = (String)row.get('recommendedInclude');

                String dedupeKey = buildDedupeKey(mapping);
                if (seenKeys.contains(dedupeKey)) {
                    continue;
                }
                seenKeys.add(dedupeKey);
                
                outputMappings.add(mapping);
            }
            
            // DO NOT SORT - preserve static resource order exactly
            
            System.debug('Loaded ' + outputMappings.size() + ' output mappings from catalog');
        } catch (Exception e) {
            System.debug('Error loading field catalog: ' + e.getMessage());
            throw e;
        }
    }

    private void resolveHeaderCollisions() {
        Map<String, List<OutputMapping>> headerGroups = new Map<String, List<OutputMapping>>();

        for (OutputMapping mapping : outputMappings) {
            String template = String.isNotBlank(mapping.outputColumnTemplate)
                ? mapping.outputColumnTemplate
                : mapping.label;

            List<String> headers = expandHeaders(template, mapping.inferredMaxSlots);

            for (String header : headers) {
                if (!headerGroups.containsKey(header)) {
                    headerGroups.put(header, new List<OutputMapping>());
                }
                headerGroups.get(header).add(mapping);
            }
        }

        for (String header : headerGroups.keySet()) {
            List<OutputMapping> groupList = headerGroups.get(header);

            if (groupList.size() < 2) {
                continue;
            }

            for (OutputMapping mapping : groupList) {
                mapping.outputColumnTemplate = buildResolvedTemplate(mapping);
            }
        }
    }

    private List<String> expandHeaders(String template, Integer maxSlots) {
        List<String> headers = new List<String>();

        if (String.isBlank(template)) {
            return headers;
        }

        if (!template.contains('<n>')) {
            headers.add(template);
            return headers;
        }

        Integer slots = maxSlots == null ? 0 : maxSlots;

        for (Integer i = 1; i <= slots; i++) {
            String slotStr = String.valueOf(i);
            headers.add(template.replace('<n>', slotStr));
        }

        return headers;
    }

    private String buildResolvedTemplate(OutputMapping mapping) {
        String prefix = prettifyLogicalName(
            String.isNotBlank(mapping.contextLogicalName)
                ? mapping.contextLogicalName
                : String.isNotBlank(mapping.sectionLabel)
                    ? mapping.sectionLabel
                    : String.isNotBlank(mapping.recordName)
                        ? mapping.recordName
                        : 'Section'
        );

        if (mapping.inferredMaxSlots != null
            && mapping.inferredMaxSlots > 0
            && String.isNotBlank(mapping.outputColumnTemplate)
            && mapping.outputColumnTemplate.contains('<n>')) {

            return '<n> - ' + prefix + ' - ' + mapping.label;
        }

        return prefix + ' - ' + mapping.label;
    }

    private String prettifyLogicalName(String value) {
        if (String.isBlank(value)) {
            return '';
        }

        String result = value.replaceAll('([a-z])([A-Z])', '$1 $2');
        result = result.replace('_', ' ');
        result = result.replaceAll('\\s+', ' ').trim();

        List<String> words = result.split(' ');
        List<String> capitalized = new List<String>();

        for (String word : words) {
            if (String.isBlank(word)) {
                continue;
            }

            capitalized.add(
                word.substring(0, 1).toUpperCase() +
                (word.length() > 1 ? word.substring(1).toLowerCase() : '')
            );
        }

        return String.join(capitalized, ' ');
    }

    private String buildDedupeKey(OutputMapping m) {
        // Match Node.js behavior: dedupe by outputColumnKey only
        // This ensures entries with the same business field but different
        return String.isNotBlank(m.outputColumnKey) 
            ? m.outputColumnKey 
            : String.join(new List<String>{
                m.objectApiName,
                m.fieldApiName,
                m.outputColumnTemplate,
                String.valueOf(m.inferredMaxSlots)
            }, '::');
    }
    
    // Build section index for metadata organization
    private void buildSectionIndex() {
        sectionIndex = new Map<String, SectionMetadata>();
        
        for (OutputMapping mapping : outputMappings) {
            String sectionKey = buildSectionKey(mapping);
            
            if (!sectionIndex.containsKey(sectionKey)) {
                SectionMetadata section = new SectionMetadata();
                section.sectionKey = sectionKey;
                section.objectApiName = mapping.objectApiName;
                section.relationType = mapping.relationType;
                section.contextLogicalName = mapping.contextLogicalName;
                section.recordName = mapping.recordName;
                sectionIndex.put(sectionKey, section);
            }
        }
    }
    
    // Build section key (matches JavaScript logic)
    private String buildSectionKey(OutputMapping mapping) {
        List<String> parts = new List<String>{
            mapping.component,
            mapping.relationType,
            mapping.contextLogicalName,
            String.isNotBlank(mapping.recordName) ? mapping.recordName : '',
            mapping.objectApiName
        };
        return String.join(parts, '::');
    }
    
    // Build query plans for each object
    private void buildQueryPlans() {
        queryPlans = new Map<String, QueryPlan>();
        
        // Group mappings by object
        Map<String, List<OutputMapping>> mappingsByObject = new Map<String, List<OutputMapping>>();
        for (OutputMapping mapping : outputMappings) {
            if (!mappingsByObject.containsKey(mapping.objectApiName)) {
                mappingsByObject.put(mapping.objectApiName, new List<OutputMapping>());
            }
            mappingsByObject.get(mapping.objectApiName).add(mapping);
        }
        
        // Create query plan for each object
        for (String objectName : mappingsByObject.keySet()) {
            QueryPlan plan = new QueryPlan();
            plan.objectApiName = objectName;
            plan.selectFields = new Set<String>();
            plan.mappings = mappingsByObject.get(objectName);
            
            // Add support fields
            plan.selectFields.add('Id');
            if (objectName != 'Application__c') {
                plan.selectFields.add('Application__c');
            }

            // Add fields used internally for record matching/filtering
            if (objectName == 'Academic_Detail__c') {
                plan.selectFields.add('Name');
            }

            if (objectName == 'Competitive_Exam_Details__c') {
                plan.selectFields.add('Exam_Name__c');
            }
            
            // Add query fields from mappings
            for (OutputMapping mapping : plan.mappings) {
                String fieldPath = String.isNotBlank(mapping.queryFieldPath)
                    ? mapping.queryFieldPath
                    : mapping.fieldApiName;

                if(mapping.fieldType == 'lookup' && String.isNotBlank(mapping.lookupDisplayPath)) {
                    fieldPath = mapping.lookupDisplayPath;
                }

                // Keep only the actual field path from the catalog
                plan.selectFields.add(fieldPath);
            }

            if (objectName == 'Application__c') {
                plan.selectFields.remove('Application__c');
            }
            
            queryPlans.put(objectName, plan);
        }
    }
    
    // Build header definitions (matches JavaScript buildHeaderDefinitions)
    private void buildHeaderDefinitions() {
        headerDefinitions = new List<HeaderDefinition>();

        Integer i = 0;

        while (i < outputMappings.size()) {
            OutputMapping mapping = outputMappings[i];

            String template = String.isNotBlank(mapping.outputColumnTemplate)
                ? mapping.outputColumnTemplate
                : mapping.label;

            Boolean isSlotBased = mapping.inferredMaxSlots != null
                && mapping.inferredMaxSlots > 0
                && String.isNotBlank(template)
                && template.contains('<n>');

            if (!isSlotBased) {
                HeaderDefinition header = new HeaderDefinition();
                header.headerName = template;
                header.mapping = mapping;
                header.quoteMode = String.isNotBlank(mapping.quoteMode)
                    ? mapping.quoteMode
                    : 'csv_auto';
                header.slotNumber = null;
                headerDefinitions.add(header);
                i++;
                continue;
            }

            List<OutputMapping> slotGroup = new List<OutputMapping>();
            Integer maxSlots = mapping.inferredMaxSlots;

            while (i < outputMappings.size()) {
                OutputMapping candidate = outputMappings[i];

                String candidateTemplate = String.isNotBlank(candidate.outputColumnTemplate)
                    ? candidate.outputColumnTemplate
                    : candidate.label;

                Boolean candidateIsSlotBased = candidate.inferredMaxSlots != null
                    && candidate.inferredMaxSlots > 0
                    && String.isNotBlank(candidateTemplate)
                    && candidateTemplate.contains('<n>');

                if (!candidateIsSlotBased || candidate.inferredMaxSlots != maxSlots) {
                    break;
                }

                slotGroup.add(candidate);
                i++;
            }

            for (Integer slot = 1; slot <= maxSlots; slot++) {
                for (OutputMapping slotMapping : slotGroup) {
                    String slotTemplate = '';
                    if (isSlotBased) {
                        slotTemplate = '<n> - ' + slotMapping.label;
                    } else {
                        slotTemplate = String.isNotBlank(slotMapping.outputColumnTemplate)
                            ? slotMapping.outputColumnTemplate
                            : slotMapping.label;
                    }

                    String sectionName = String.isNotBlank(slotMapping.contextLogicalName)
                        ? slotMapping.contextLogicalName
                        : slotMapping.sectionLabel;

                    String readableSectionName = sectionName.replaceAll('([a-z])([A-Z])', '$1 $2');

                    readableSectionName =
                        readableSectionName.substring(0,1).toUpperCase()
                        + readableSectionName.substring(1);

                    if (String.isNotBlank(sectionName)) {
                        slotTemplate = slotTemplate.replace(
                            '<n> - ',
                            '<n> - ' + readableSectionName + ' - '
                        );
                    }

                    HeaderDefinition header = new HeaderDefinition();
                    header.headerName = slotTemplate.replace('<n>', String.valueOf(slot));
                    header.mapping = slotMapping;
                    header.quoteMode = String.isNotBlank(slotMapping.quoteMode)
                        ? slotMapping.quoteMode
                        : 'csv_auto';
                    header.slotNumber = slot;
                    headerDefinitions.add(header);
                }
            }
        }

        System.debug('Built ' + headerDefinitions.size() + ' CSV headers');
    }
    
    // Start method
    public Iterable<Id> start(Database.BatchableContext bc) {
        loadFieldCatalog();
        resolveHeaderCollisions();
        buildSectionIndex();
        buildQueryPlans();
        buildHeaderDefinitions();
        buildCsvHeaderLine();
        return applicationIds;
    }

    private void buildCsvHeaderLine() {
        List<String> headers = new List<String>();

        for (HeaderDefinition headerDef : headerDefinitions) {
            headers.add(escapeCsvValue(headerDef.headerName, 'csv_auto'));
        }

        csvHeaderLine = String.join(headers, ',');
    }
    
    // Execute method - optimized to query once per object for all applications in scope
    public void execute(Database.BatchableContext bc, List<Id> scope) {

        String csvContent = csvHeaderLine;
        //List<String> lines = new List<String>();
        //lines.add(csvHeaderLine);

        Integer preloadChunkSize = 25;

        List<List<Id>> chunks = splitIds(scope, preloadChunkSize);

        Map<Id, Map<String, List<SObject>>> allData = queryBatchData(scope);

        for (List<Id> chunkIds : chunks) {
            for (Id appId : chunkIds) {
                Map<String, List<SObject>> appData = allData.get(appId);
                csvContent += '\r\n'+flattenToCsvRow(appId, appData);
                //lines.add(flattenToCsvRow(appId, appData));
                allData.remove(appId);
            }                  
        }

       // String csvContent = String.join(lines, '\n');

        // Create ContentVersion
        ContentVersion cv = new ContentVersion();
        cv.Title = 'GMP_Export_' + Datetime.now().format('yyyyMMdd_HHmmss') + '_part_' + String.valueOf(filesCreated + 1);
        cv.PathOnClient = cv.Title + '.csv';
        cv.VersionData = Blob.valueOf('\uFEFF' + csvContent); // UTF-8 BOM
        cv.IsMajorVersion = true;

        

        try {
            insert cv;
            
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            filesCreated++;
            processedApplications+=scope.size();
            System.debug('CSV exported successfully. ContentDocumentId: ' + cv.ContentDocumentId);
            //System.debug('Total rows exported: ' + lines.size());
            
        } catch (Exception e) {
            System.debug('Error creating CSV file: ' + e.getMessage());
        }


        System.debug(
            'END execute | Heap=' + Limits.getHeapSize() +
            '/' + Limits.getLimitHeapSize() +
            ' CPU=' + Limits.getCpuTime() +
            '/' + Limits.getLimitCpuTime()
        );  
    }

    private List<List<Id>> splitIds(List<Id> ids, Integer chunkSize) {
        List<List<Id>> chunks = new List<List<Id>>();

        for (Integer i = 0; i < ids.size(); i += chunkSize) {
            Integer endIndex = Math.min(i + chunkSize, ids.size());

            List<Id> chunk = new List<Id>();

            for (Integer j = i; j < endIndex; j++) {
                chunk.add(ids[j]);
            }

            chunks.add(chunk);
        }

        return chunks;
    }
    
    // Query all data for multiple applications in one query per object
    private Map<Id, Map<String, List<SObject>>> queryBatchData(List<Id> appIds) {
        Map<Id, Map<String, List<SObject>>> result = new Map<Id, Map<String, List<SObject>>>();
        
        // Initialize empty maps for each application
        for (Id appId : appIds) {
            result.put(appId, new Map<String, List<SObject>>());
        }
        
        // Query each object once for all applications
        for (String objectName : queryPlans.keySet()) {
            QueryPlan plan = queryPlans.get(objectName);
            
            // Build SOQL dynamically
            List<String> fieldList = new List<String>(plan.selectFields);
            fieldList.sort();
            
            String soql = 'SELECT ' + String.join(fieldList, ', ') + 
                         ' FROM ' + objectName;
            
            if (objectName == 'Application__c') {
                soql += ' WHERE Id IN :appIds';
            } else {
                soql += ' WHERE Application__c IN :appIds';
            }
            
            // Add ordering for consistent results (matches JavaScript orderRecords)
            if (objectName == 'Work_Experience__c') {
                soql += ' ORDER BY Application__c, Start_Date__c DESC NULLS LAST, End_Date__c DESC NULLS LAST, CreatedDate ASC';
            } else if (objectName == 'CareerBreak__c') {
                soql += ' ORDER BY Application__c, StartDate__c DESC NULLS LAST, EndDate__c DESC NULLS LAST, Id ASC';
            } else if (objectName == 'Professional_Qualification__c') {
                soql += ' ORDER BY Application__c, CreatedDate ASC, Id ASC';
            } else if (objectName == 'Academic_Detail__c') {
                soql += ' ORDER BY Application__c, Name ASC';
            } else if (objectName == 'Competitive_Exam_Details__c') {
                soql += ' ORDER BY Application__c, Exam_Name__c ASC';
            } else if(objectName != 'Application__c') {
                soql += ' ORDER BY Application__c';
            }
            
            try {
                System.debug('query of  '+objectName+': '+soql);
                List<SObject> records = Database.query(soql);
                
                // Group records by Application__c
                for (SObject record : records) {
                    Id appId = objectName == 'Application__c' 
                        ? (Id)record.get('Id') 
                        : (Id)record.get('Application__c');
                    
                    if (!result.containsKey(appId)) {
                        continue; // Skip if not in our scope
                    }
                    
                    Map<String, List<SObject>> appRecords = result.get(appId);
                    if (!appRecords.containsKey(objectName)) {
                        appRecords.put(objectName, new List<SObject>());
                    }
                    appRecords.get(objectName).add(record);
                }
            } catch (Exception e) {
                System.debug('Error querying ' + objectName + ': ' + e.getMessage());
                // Continue with empty records for this object
            }
        }
        
        return result;
    }
    
    private String flattenToCsvRow(Id applicationId, Map<String, List<SObject>> recordsByObject) {
        String row = '';
        Boolean first = true;

        for (HeaderDefinition headerDef : headerDefinitions) {
            OutputMapping mapping = headerDef.mapping;
            String sectionKey = buildSectionKey(mapping);
            SectionMetadata section = sectionIndex.get(sectionKey);

            List<SObject> records = recordsByObject.get(mapping.objectApiName);
            if (records == null) {
                records = new List<SObject>();
            }

            String value = resolveMappingValue(mapping, section, records, headerDef.slotNumber);
            String escaped = escapeCsvValue(value, headerDef.quoteMode);

            if (first) {
                row = escaped;
                first = false;
            } else {
                row += ',' + escaped;
            }
        }

        return row;
    }

    private String getVariantKeyField(String objectApiName) {
        Map<String, String> keyFields = new Map<String, String>{
            'Competitive_Exam_Details__c' => 'Exam_Name__c',
            'Academic_Detail__c' => 'Name'
        };

        return keyFields.get(objectApiName);
    }
    
    // Resolve mapping value (matches JavaScript resolveMappingValue)
    private String resolveMappingValue(
        OutputMapping mapping,
        SectionMetadata section,
        List<SObject> records,
        Integer slotNumber
    ) {
        if (section == null || records.isEmpty()) {
            return '';
        }

        // Use flattenStrategy field from metadata (matches JavaScript switch statement)
        String strategy = String.isNotBlank(mapping.flattenStrategy) 
            ? mapping.flattenStrategy 
            : 'scalar_columns';

        if (strategy == 'scalar_columns') {
            // Scalar: return first record's value
            return extractValue(records[0], mapping);
        } 
        else if (strategy == 'named_variant_columns') {
            // Named variant: find record by matching recordName field
            String keyField = getVariantKeyField(mapping.objectApiName);
            
            if (String.isBlank(keyField) || String.isBlank(mapping.recordName)) {
                return '';
            }

            for (SObject record : records) {
                String recordValue = (String)record.get(keyField);
                
                if (recordValue == mapping.recordName) {
                    return extractValue(record, mapping);
                }
            }

            return '';
        } 
        else if (strategy == 'fixed_slot_columns') {
            // Fixed slot: order records, get record at slot index
            if (slotNumber == null || slotNumber <= 0) {
                return '';
            }

            //List<SObject> orderedRecords = orderRecords(mapping.objectApiName, records);
            List<SObject> orderedRecords = records;
            Integer index = slotNumber - 1;

            if (index >= orderedRecords.size()) {
                return '';
            }

            return extractValue(orderedRecords[index], mapping);
        }

        // Default: return empty string for unknown strategies
        return '';
    }
        
    // Extract value from record based on mapping (matches JavaScript readValue)
    private String extractValue(SObject record, OutputMapping mapping) {
        if (record == null) return '';
        
        String path = mapping.outputValuePath;
        if (String.isBlank(path)) {
            path = mapping.queryFieldPath;
        }
        if (String.isBlank(path)) {
            path = mapping.fieldApiName;
        }

        if(mapping.fieldType == 'lookup' && String.isNotBlank(mapping.lookupDisplayPath)) {
            path = mapping.lookupDisplayPath;
        }
        
        Object value = resolvePath(record, path);
        return formatValue(value, mapping.fieldType, mapping.outputKind);
    }
    
    // Resolve dot-notation path (matches JavaScript getValueAtPath)
    private Object resolvePath(SObject record, String path) {
        if (record == null || String.isBlank(path)) return null;
        
        if (!path.contains('.')) {
            return record.get(path);
        }
        
        List<String> parts = path.split('\\.');
        SObject current = record;
        
        for (Integer i = 0; i < parts.size(); i++) {
            String part = parts[i];
            Boolean isLast = (i == parts.size() - 1);
            
            if (isLast) {
                return current.get(part);
            }
            
            current = current.getSObject(part);
            if (current == null) return null;
        }
        
        return null;
    }
    
    // Format value based on field type (matches JavaScript formatValue)
    private String formatValue(Object value, String fieldType, String outputKind) {
        if (value == null) return '';

        if (fieldType == 'tel' || outputKind == 'nonnumeric') {
            return '="' + String.valueOf(value) + '"';
        }
        
        // JavaScript just converts to string - no special formatting
        // Dates come from Salesforce in ISO format, numbers without trailing zeros
        if (value instanceof Date) {
            Date d = (Date)value;
            return d.year() + '-' + 
                   String.valueOf(d.month()).leftPad(2, '0') + '-' + 
                   String.valueOf(d.day()).leftPad(2, '0');
        }
        
        if (value instanceof Datetime) {
            Datetime dt = (Datetime)value;
            return dt.format('yyyy-MM-dd');
        }
        
        if (value instanceof Decimal) {
            Decimal dec = (Decimal)value;
            // Remove trailing zeros like JavaScript does
            String strValue = String.valueOf(dec);
            if (strValue.contains('.')) {
                strValue = strValue.replaceAll('0+$', '').replaceAll('\\.$', '');
            }
            return strValue;
        }
        
        if (value instanceof Boolean) {
            // JavaScript outputs lowercase boolean
            return String.valueOf(value).toLowerCase();
        }
        
        return String.valueOf(value);
    }
    
    // Escape CSV value (matches JavaScript escapeCsv)
    private String escapeCsvValue(String value, String quoteMode) {
        if (String.isBlank(value)) return '';
        
        String str = String.valueOf(value);
        
        if (quoteMode == 'always') {
            return '"' + str.replace('"', '""') + '"';
        }
        
        // csv_auto mode: quote if contains comma, newline, or quote
        if (str.contains(',') || str.contains('\n') || str.contains('\r') || str.contains('"')) {
            return '"' + str.replace('"', '""') + '"';
        }
        
        return str;
    }
    
    // Finish method - write CSV file
    public void finish(Database.BatchableContext bc) {
        System.debug('Total applications processed: ' + processedApplications);
        System.debug('Total CSV files created: ' + filesCreated);
    }
        
    // Helper to get integer from map
    private static Integer getInteger(Map<String, Object> row, String key) {
        Object value = row.get(key);
        if (value == null) return null;
        if (value instanceof Integer) return (Integer)value;
        if (value instanceof Decimal) return ((Decimal)value).intValue();
        if (value instanceof String) {
            try {
                return Integer.valueOf((String)value);
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }
    
    // Inner classes
    public class OutputMapping {
        public Integer stageOrder;
        public String stage;
        public String component;
        public String relationType;
        public String contextLogicalName;
        public String recordName;
        public String objectApiName;
        public String fieldApiName;
        public String queryFieldPath;
        public String outputValuePath;
        public String label;
        public String fieldType;
        public String outputKind;
        public String quoteMode;
        public String exportCardinality;
        public String lookupDisplayPath;
        
        public String flattenStrategy;
        public Integer inferredMaxSlots;
        public String outputColumnTemplate;
        public String outputColumnKey;
        public String sectionLabel;

        public String recommendedInclude;
    }
    
    public class SectionMetadata {
        public String sectionKey;
        public String objectApiName;
        public String relationType;
        public String contextLogicalName;
        public String recordName;
    }
    
    public class QueryPlan {
        public String objectApiName;
        public Set<String> selectFields;
        public List<OutputMapping> mappings;
    }
    
    public class HeaderDefinition {
        public String headerName;
        public OutputMapping mapping;
        public String quoteMode;
        public Integer slotNumber;
    }
    
}