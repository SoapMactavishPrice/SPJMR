public with sharing class Batch_ApplicationStatusUpdate 
        implements Database.Batchable<String>, Database.Stateful {

    public String csvString;
    public List<String> errorMessages = new List<String>();
    private Integer MAX_ERROR_LOGS = 5000;
    private String headerLine;

    public Batch_ApplicationStatusUpdate(String csvString) {
        this.csvString = csvString
            .replace('\r', '')
            .replace('\uFEFF', '');
    }

    public Iterable<String> start(Database.BatchableContext bc) {
        if (String.isBlank(csvString)) {
            return new List<String>();
        }

        List<String> allLines = csvString.split('\n');

        if (allLines.isEmpty()) {
            return new List<String>();
        }

        headerLine = allLines[0];

        if (allLines.size() <= 1) {
            return new List<String>();
        }

        List<String> dataLines = new List<String>();
        for (Integer i = 1; i < allLines.size(); i++) {
            dataLines.add(allLines[i]);
        }

        return dataLines;
    }

    public void execute(Database.BatchableContext bc, List<String> scope) {

        if (scope == null || scope.isEmpty()) return;

        String chunk = headerLine + '\n' + String.join(scope, '\n');

        List<List<String>> rows = RT_CSVReader.read(chunk);
        if (rows == null || rows.isEmpty()) return;

        List<String> rawHeader = rows[0];
        List<String> header = new List<String>();
        for (String h : rawHeader) {
            header.add(
                h == null ? '' :
                h.trim().replaceAll('[^\\x20-\\x7E]', '')
            );
        }

        Integer idCol     = header.indexOf('Application ID'); 
        Integer numberCol = header.indexOf('Application Number');
        Integer statusCol = header.indexOf('Applicant State Management');
        Integer stageCol  = header.indexOf('Application Stage');

        if (numberCol < 0 || statusCol < 0 || stageCol < 0) {
            throw new AuraHandledException(
                'CSV missing required columns: Application Number, Applicant State Management, or Application Stage'
            );
        }

        Set<String> validStatusValues = getPicklistValues('Applicant_State_Management__c');
        Set<String> validStageValues  = getPicklistValues('Application_Stage__c');

        Set<String> appNumbers = new Set<String>();
        List<Map<String, String>> parsedRows = new List<Map<String, String>>();

        for (Integer i = 1; i < rows.size(); i++) {
            List<String> row = rows[i];
            if (row == null || row.isEmpty()) continue;

            if (row.size() == 1 && String.isBlank(row[0])) continue;

            Integer requiredIndex = Math.max(Math.max(numberCol, statusCol), stageCol);
            if (row.size() <= requiredIndex) {
                logError('Row ' + (i+1) + ' missing columns: ' + row);
                continue;
            }

            String appNumber = row[numberCol] == null ? null : row[numberCol].trim();
            if (String.isBlank(appNumber)) {
                logError('Row ' + (i+1) + ' has blank Application Number. Row: ' + row);
                continue;
            }

            String status = row[statusCol] == null ? null : row[statusCol].trim();
            String stage  = row[stageCol] == null ? null : row[stageCol].trim();

            Map<String, String> parsed = new Map<String, String>{
                'rowIndex' => String.valueOf(i+1),
                'appNumber' => appNumber,
                'status' => status,
                'stage' => stage
            };

            parsedRows.add(parsed);
            appNumbers.add(appNumber);
        }

        if (appNumbers.isEmpty()) {
            return;
        }

        Map<String, Application__c> appNumberToRec = new Map<String, Application__c>();
        for (Application__c a : [
            SELECT Id, Name
            FROM Application__c
            WHERE Name IN :appNumbers
        ]) {
            if (a.Name != null) {
                appNumberToRec.put(a.Name.trim(), a);
            }
        }

        List<Application__c> updates = new List<Application__c>();

        for (Map<String,String> parsed : parsedRows) {

            String rowIdx   = parsed.get('rowIndex');
            String appNumber = parsed.get('appNumber');
            String status   = parsed.get('status');
            String stage    = parsed.get('stage');

            if (!appNumberToRec.containsKey(appNumber)) {
                logError('Row ' + rowIdx + ': No Application found for Application Number: ' + appNumber);
                continue;
            }

            if (!String.isBlank(status) && !validStatusValues.contains(status)) {
                logError('Row ' + rowIdx + ': Invalid Applicant State Management value → "' + status + '"');
                continue;
            }

            if (!String.isBlank(stage) && !validStageValues.contains(stage)) {
                logError('Row ' + rowIdx + ': Invalid Application Stage value → "' + stage + '"');
                continue;
            }

            Application__c toUpdate = new Application__c(
                Id = appNumberToRec.get(appNumber).Id,
                Applicant_State_Management__c = status,
                Application_Stage__c = stage
            );

            updates.add(toUpdate);
        }

        if (!updates.isEmpty()) {
            Database.SaveResult[] results = Database.update(updates, false);

            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                if (!sr.isSuccess()) {
                    for (Database.Error err : sr.getErrors()) {
                        logError('Failed update for Id: ' + sr.getId() + ' → ' + err.getMessage());
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed,
                   TotalJobItems, CreatedBy.Email
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ job.CreatedBy.Email });

        mail.setSubject('Application Status CSV Update – ' + job.Status);

        String body = 'Batch Completed.\n\n' +
                      'Batches: ' + job.TotalJobItems + '\n' +
                      'Processed: ' + job.JobItemsProcessed + '\n' +
                      'Errors: ' + job.NumberOfErrors + '\n\n';

        if (!errorMessages.isEmpty()) {
            body += 'Error Details (first ' + errorMessages.size() + '):\n\n';
            for (String err : errorMessages) {
                body += '- ' + err + '\n';
            }
        } else {
            body += 'No row-level errors. ✔';
        }

        mail.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }

    private void logError(String msg) {
        if (errorMessages.size() < MAX_ERROR_LOGS) {
            errorMessages.add(msg);
        }
    }

    private static Set<String> getPicklistValues(String fieldApiName) {
        Set<String> values = new Set<String>();

        Schema.DescribeFieldResult fieldDescribe =
            Application__c.SObjectType.getDescribe()
            .fields.getMap()
            .get(fieldApiName)
            .getDescribe();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            values.add(entry.getValue());
        }

        return values;
    }
}