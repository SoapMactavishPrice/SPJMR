global without sharing class Batch_SlotMasterImport implements Database.Batchable<ContentVersion>, Database.Stateful {
    private static final List<String> REQUIRED_HEADERS = new List<String>{
        'Program Code', 'Location Code', 'Slot Code', 'Capacity', 'Slot Date', 'Slot Start Time'
    };
    private static final List<String> IMPORT_HEADERS = new List<String>{
        'Program Code', 'Location Code', 'Slot Code', 'Capacity', 'Slot Date', 'Slot Start Time', 'Slot End Time'
    };

    private class SlotMasterImportValidationException extends Exception {
    }

    private class SourceRow {
        Map<String, String> values;

        SourceRow(Map<String, String> values) {
            this.values = values;
        }
    }

    private List<Id> contentVersionIds;
    private Boolean emailErrorReport;
    private Integer successCount = 0;
    private Integer failedCount = 0;
    private List<String> errorRows = new List<String>();
    private Id errorContentDocumentId;

    public Batch_SlotMasterImport(List<Id> contentVersionIds, Boolean emailErrorReport) {
        this.contentVersionIds = contentVersionIds;
        this.emailErrorReport = emailErrorReport;
    }

    global Iterable<ContentVersion> start(Database.BatchableContext bc) {
        return [
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE Id IN :contentVersionIds
            ORDER BY CreatedDate
        ];
    }

    global void execute(Database.BatchableContext bc, List<ContentVersion> scope) {
        initialiseErrorReport();
        Map<String, Id> programMap = getProgramMap();
        Map<String, Id> locationMap = getLocationMap();
        List<SlotMaster__c> slotsToInsert = new List<SlotMaster__c>();
        List<SourceRow> sourceRows = new List<SourceRow>();

        for (ContentVersion version : scope) {
            addSlotsFromFile(version, programMap, locationMap, slotsToInsert, sourceRows);
        }
        saveSlots(slotsToInsert, sourceRows);
    }

    global void finish(Database.BatchableContext bc) {
        Map<String, Object> payload = new Map<String, Object>{
            'status' => 'Completed',
            'successCount' => successCount,
            'failedCount' => failedCount,
            'hasErrors' => failedCount > 0
        };
        if (failedCount > 0) {
            createErrorReport(payload, bc.getJobId());
        }

        try{
            publishCompletionEvent(payload);
            if (emailErrorReport) {
                sendCompletionEmail();
            }
        }finally{
            deleteUploadedFiles();
        }
        
    }

    private void initialiseErrorReport() {
        if (errorRows.isEmpty()) {
            errorRows.add(String.join(IMPORT_HEADERS, ',') + ',Error');
        }
    }

    private static Map<String, Id> getProgramMap() {
        Map<String, Id> programMap = new Map<String, Id>();
        for (Program program : [SELECT Id, Program_Code__c FROM Program WHERE Program_Code__c != NULL]) {
            programMap.put(program.Program_Code__c.trim().toUpperCase(), program.Id);
        }
        return programMap;
    }

    private static Map<String, Id> getLocationMap() {
        Map<String, Id> locationMap = new Map<String, Id>();
        for (LocationMaster__c location : [SELECT Id, Name FROM LocationMaster__c WHERE Name != NULL]) {
            locationMap.put(location.Name.trim().toUpperCase(), location.Id);
        }
        return locationMap;
    }

    private void addSlotsFromFile(
        ContentVersion version,
        Map<String, Id> programMap,
        Map<String, Id> locationMap,
        List<SlotMaster__c> slotsToInsert,
        List<SourceRow> sourceRows
    ) {
        List<String> rows = version.VersionData.toString().replace('\r', '').split('\n');
        if (rows.size() <= 1) {
            addFileError('The uploaded file has no data rows.');
            return;
        }

        String delimiter = getDelimiter(rows[0]);
        if (delimiter == null) {
            addFileError('The uploaded file must be comma- or tab-delimited.');
            return;
        }

        Map<String, Integer> headerIndexes = getHeaderIndexes(splitDelimitedLine(rows[0], delimiter));
        String headerError = getHeaderError(headerIndexes);
        if (headerError != null) {
            addFileError(headerError);
            return;
        }

        for (Integer rowIndex = 1; rowIndex < rows.size(); rowIndex++) {
            if (String.isBlank(rows[rowIndex])) {
                continue;
            }

            SourceRow sourceRow = new SourceRow(
                getMappedValues(splitDelimitedLine(rows[rowIndex], delimiter), headerIndexes)
            );
            try {
                slotsToInsert.add(buildSlot(sourceRow.values, programMap, locationMap));
                sourceRows.add(sourceRow);
            } catch (Exception exp) {
                failedCount++;
                errorRows.add(buildErrorRow(sourceRow, exp.getMessage()));
            }
        }
    }

    private static String getDelimiter(String header) {
        if (header.contains(',')) {
            return ',';
        }
        if (header.contains('\t')) {
            return '\t';
        }
        return null;
    }

    private static List<String> splitDelimitedLine(String line, String delimiter) {
        List<String> values = new List<String>();
        Boolean inQuotes = false;
        String currentValue = '';

        for (Integer index = 0; index < line.length(); index++) {
            String character = line.substring(index, index + 1);
            if (character == '"') {
                if (inQuotes && index + 1 < line.length() && line.substring(index + 1, index + 2) == '"') {
                    currentValue += '"';
                    index++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (character == delimiter && !inQuotes) {
                values.add(currentValue);
                currentValue = '';
            } else {
                currentValue += character;
            }
        }
        values.add(currentValue);
        return values;
    }

    private static Map<String, Integer> getHeaderIndexes(List<String> headers) {
        Map<String, Integer> headerIndexes = new Map<String, Integer>();
        for (Integer index = 0; index < headers.size(); index++) {
            String header = headers[index].trim();
            if (index == 0) {
                header = header.replace('\uFEFF', '');
            }
            if (IMPORT_HEADERS.contains(header) && !headerIndexes.containsKey(header)) {
                headerIndexes.put(header, index);
            }
        }
        return headerIndexes;
    }

    private static String getHeaderError(Map<String, Integer> headerIndexes) {
        List<String> missingHeaders = new List<String>();
        for (String requiredHeader : REQUIRED_HEADERS) {
            if (!headerIndexes.containsKey(requiredHeader)) {
                missingHeaders.add(requiredHeader);
            }
        }
        return missingHeaders.isEmpty()
            ? null
            : 'Missing mandatory header(s): ' + String.join(missingHeaders, ', ') + '.';
    }

    private static Map<String, String> getMappedValues(List<String> columns, Map<String, Integer> headerIndexes) {
        Map<String, String> values = new Map<String, String>();
        for (String header : IMPORT_HEADERS) {
            values.put(header, headerIndexes.containsKey(header) ? getValue(columns, headerIndexes.get(header)) : '');
        }
        return values;
    }

    private static String getValue(List<String> columns, Integer index) {
        return index >= columns.size() ? '' : columns[index].trim();
    }

    private static SlotMaster__c buildSlot(
        Map<String, String> values,
        Map<String, Id> programMap,
        Map<String, Id> locationMap
    ) {
        String slotCode = values.get('Slot Code');
        String programCode = values.get('Program Code');
        String slotDate = values.get('Slot Date');
        String slotStart = values.get('Slot Start Time');
        String capacity = values.get('Capacity');
        String slotEnd = values.get('Slot End Time');
        String location = values.get('Location Code');

        requireValue(slotCode, 'Slot Code');
        requireValue(programCode, 'Program Code');
        requireValue(slotDate, 'Slot Date');
        requireValue(slotStart, 'Slot Start Time');
        requireValue(capacity, 'Capacity');

        if (!programMap.containsKey(programCode.toUpperCase())) {
            throw new SlotMasterImportValidationException('Program Code not found: ' + programCode + '.');
        }
        if (!String.isBlank(location) && !locationMap.containsKey(location.toUpperCase())) {
            throw new SlotMasterImportValidationException('Location not found: ' + location + '.');
        }

        SlotMaster__c slot = new SlotMaster__c(
            Name = slotCode,
            Program_Master__c = programMap.get(programCode.toUpperCase()),
            SlotDate__c = parseDate(slotDate),
            SlotStartTime__c = parseTime(slotStart, 'Slot Start Time'),
            Capacity__c = parseCapacity(capacity),
            Status__c = 'Available',
            Mode__c = 'Offline'
        );
        if (!String.isBlank(slotEnd)) {
            slot.SlotEndtime__c = parseTime(slotEnd, 'Slot End Time');
        }
        if (!String.isBlank(location)) {
            slot.LocationMaster__c = locationMap.get(location.toUpperCase());
        }
        return slot;
    }

    private static void requireValue(String value, String header) {
        if (String.isBlank(value)) {
            throw new SlotMasterImportValidationException(header + ' is mandatory.');
        }
    }

    private static Date parseDate(String value) {
        try {
            if (Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', value)) {
                return Date.valueOf(value);
            }
            if (Pattern.matches('^\\d{2}-\\d{2}-\\d{4}$', value)) {
                List<String> parts = value.split('-');
                return Date.newInstance(Integer.valueOf(parts[2]), Integer.valueOf(parts[1]), Integer.valueOf(parts[0]));
            }
        } catch (Exception exp) {
            // The clear validation message below is returned for parsing errors.
        }
        throw new SlotMasterImportValidationException(
            'Invalid Slot Date "' + value + '". Use DD-MM-YYYY.'
        );
    }

    private static Time parseTime(String value, String fieldLabel) {
        try {
            List<String> parts = value.trim().split(':');
            if (parts.size() < 2 || parts.size() > 3) {
                throw new SlotMasterImportValidationException('Invalid time format.');
            }
            Integer hours = Integer.valueOf(parts[0]);
            Integer minutes = Integer.valueOf(parts[1]);
            Integer seconds = parts.size() == 3 ? Integer.valueOf(parts[2]) : 0;
            if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59 || seconds < 0 || seconds > 59) {
                throw new SlotMasterImportValidationException('Time is outside the valid range.');
            }
            return Time.newInstance(hours, minutes, seconds, 0);
        } catch (Exception exp) {
            throw new SlotMasterImportValidationException(
                'Invalid ' + fieldLabel + ' "' + value + '". Use HH:mm or HH:mm:ss.'
            );
        }
    }

    private static Decimal parseCapacity(String value) {
        Decimal capacity;
        try {
            capacity = Decimal.valueOf(value);
        } catch (Exception exp) {
            throw new SlotMasterImportValidationException('Invalid Capacity "' + value + '". Enter a number.');
        }
        if (capacity < 0) {
            throw new SlotMasterImportValidationException('Capacity cannot be negative.');
        }
        return capacity;
    }

    private void saveSlots(List<SlotMaster__c> slotsToInsert, List<SourceRow> sourceRows) {
        if (slotsToInsert.isEmpty()) {
            return;
        }

        Database.SaveResult[] results = Database.insert(slotsToInsert, false);
        for (Integer index = 0; index < results.size(); index++) {
            if (results[index].isSuccess()) {
                successCount++;
                continue;
            }

            failedCount++;
            List<String> messages = new List<String>();
            for (Database.Error error : results[index].getErrors()) {
                messages.add(error.getMessage());
            }
            errorRows.add(buildErrorRow(sourceRows[index], String.join(messages, '; ')));
        }
    }

    private void addFileError(String message) {
        failedCount++;
        errorRows.add(buildErrorRow(new SourceRow(new Map<String, String>()), message));
    }

    private static String buildErrorRow(SourceRow sourceRow, String message) {
        List<String> values = new List<String>();
        for (String header : IMPORT_HEADERS) {
            values.add(toCsvValue(sourceRow.values.get(header)));
        }
        values.add(toCsvValue(message));
        return String.join(values, ',');
    }

    private static String toCsvValue(String value) {
        return '"' + (value == null ? '' : value.replace('"', '""')) + '"';
    }

    private void createErrorReport(Map<String, Object> payload, Id batchJobId) {
        ContentVersion version = new ContentVersion(
            Title = 'SlotMaster_Import_Error_Report',
            PathOnClient = 'SlotMaster_Import_Error_Report.csv',
            VersionData = Blob.valueOf(String.join(errorRows, '\n'))
        );
        insert version;
        version = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :version.Id LIMIT 1];
        errorContentDocumentId = version.ContentDocumentId;
        insert new Export_Job__c(
            DocumentId__c = errorContentDocumentId,
            JobId__c = batchJobId,
            Name = 'SlotMaster_Import_Error_Report',
            Status__c = 'Completed'
        );
        payload.put('fileName', 'SlotMaster_Import_Error_Report.csv');
        payload.put('contentDocumentId', errorContentDocumentId);
        payload.put('contentVersionId', version.Id);
        payload.put('downloadUrl', URL.getOrgDomainUrl().toExternalForm() +
            '/lightning/r/ContentDocument/' + errorContentDocumentId + '/view');
    }

    private void publishCompletionEvent(Map<String, Object> payload) {
        EventBus.publish(new AdmissionConsoleEvent__e(
            Intent__c = 'SlotMasterImport',
            UserId__c = UserInfo.getUserId(),
            Message__c = JSON.serialize(payload)
        ));
    }

    private void sendCompletionEmail() {
        String body = 'Hello,<br/><br/>Slot Master Import has been completed.<br/><br/>' +
            '<b>Summary</b><br/>Successful Records : ' + successCount + '<br/>' +
            'Failed Records : ' + failedCount + '<br/><br/>';
        if (errorContentDocumentId != null) {
            body += 'Error Report : ' + URL.getOrgDomainUrl().toExternalForm() +
                '/lightning/r/ContentDocument/' + errorContentDocumentId + '/view';
        }

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ UserInfo.getUserEmail() });
        email.setSubject('Slot Master Import Completed');
        email.setHtmlBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ email });
    }


    private void deleteUploadedFiles() {
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            return;
        }

        List<ContentDocument> documentsToDelete = [
            SELECT Id
            FROM ContentDocument
            WHERE Id IN (
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id IN :contentVersionIds
            )
        ];

        if (!documentsToDelete.isEmpty()) {
            delete documentsToDelete;
        }
    }
}