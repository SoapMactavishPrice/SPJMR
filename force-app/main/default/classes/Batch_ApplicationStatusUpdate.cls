public with sharing class Batch_ApplicationStatusUpdate 
        implements Database.Batchable<SObject>, Database.Stateful {

    public List<String> errorMessages = new List<String>();
    public List<String> resultRows = new List<String>();
    private final String RESULT_HEADER ='Application Number,Applicant State Management,Application Stage,Application Status,Status,Message';

    private Integer MAX_ERROR_LOGS = 5000;

    private List<Id> contentVersionIds;
    private Boolean notifyShortlistedApplicants;
    private Boolean emailErrorReport;

    public class PlatformEventPayload {
        @AuraEnabled
        public String status;

        @AuraEnabled
        public Boolean hasErrors;

        @AuraEnabled
        public Integer errorCount;

        @AuraEnabled
        public String fileName;

        @AuraEnabled
        public String contentDocumentId;

        @AuraEnabled
        public String downloadUrl;

    }

    private final Set<String> validStatusValues = getPicklistValues('Applicant_State_Management__c');
    private final Set<String> validStageValues = getPicklistValues('Application_Stage__c');
    private final Set<String> validApplicationStatusValues = getPicklistValues('Application_Status__c');

    public Batch_ApplicationStatusUpdate(List<Id> contentVersionIds, Boolean notifyShortlistedApplicants, Boolean emailErrorReport) {
        this.contentVersionIds = contentVersionIds;
        this.notifyShortlistedApplicants = notifyShortlistedApplicants;
        this.emailErrorReport = emailErrorReport;
        resultRows.add(RESULT_HEADER);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE Id IN :contentVersionIds
            ORDER BY Title
        ]);
    }

    public void execute(Database.BatchableContext bc, List<ContentVersion> scope) {

        if (scope == null || scope.isEmpty()) return;
        List<String> updateApplicationNumbers = new List<String>();

        for (ContentVersion cv : scope) {
            try{
                String csvString = cv.VersionData.toString();
                List<List<String>> rows = RT_CSVReader.read(csvString);
                if(rows == null || rows.isEmpty()){
                    continue;
                }

                List<String> rawHeader = rows[0];
                List<String> header = new List<String>();
                for (String h : rawHeader) {
                    header.add(
                        h == null ? '' :
                        h.trim().replaceAll('[^\\x20-\\x7E]', '')
                    );
                }

                Integer numberCol = header.indexOf('Application Number');
                Integer statusCol = header.indexOf('Applicant State Management');
                Integer stageCol = header.indexOf('Application Stage');
                Integer applicationStatusCol = header.indexOf('Application Status');

                if (numberCol < 0) {
                    throw new AuraHandledException('CSV must contain Application Number column.');
                }

                Set<String> appNumbers = new Set<String>();
                List<Map<String, String>> parsedRows = new List<Map<String, String>>();

                for (Integer i = 1; i < rows.size(); i++) {
                    List<String> row = rows[i];
                    if (row == null || row.isEmpty()) continue;

                    if (row.size() == 1 && String.isBlank(row[0])) continue;

                    Integer requiredIndex = numberCol;

                    if(statusCol >= 0){
                        requiredIndex = Math.max(requiredIndex,statusCol);
                    }

                    if(stageCol >= 0){
                        requiredIndex = Math.max(requiredIndex,stageCol);
                    }

                    if(applicationStatusCol >= 0){
                        requiredIndex = Math.max(requiredIndex,applicationStatusCol);
                    }

                    if (row.size() <= requiredIndex) {
                        logError('Row ' + (i+1) + ' missing columns: ' + row);
                        continue;
                    }

                    String appNumber = row[numberCol] == null ? null : row[numberCol].trim();

                    String status = null;
                    if(statusCol >= 0){
                        status = row[statusCol] == null ? null : row[statusCol].trim();
                    }

                    String stage = null;
                    if(stageCol >= 0){
                        stage = row[stageCol] == null ? null : row[stageCol].trim();
                    }

                    String applicationStatus = null;
                    if(applicationStatusCol >= 0){
                        applicationStatus = row[applicationStatusCol] == null ? null : row[applicationStatusCol].trim();
                    }

                    if (String.isBlank(appNumber)) {
                        logError('Row ' + (i+1) + ' has blank Application Number. Row: ' + row);
                        resultRows.add( ',' + status + ',' + stage + ',' + applicationStatus + ',Failed,' + 'Blank Application Number');
                        continue;
                    }

                    Map<String,String> parsed = new Map<String,String>{
                        'rowIndex' => String.valueOf(i+1),
                        'appNumber' => appNumber,
                        'status' => status,
                        'stage' => stage,
                        'applicationStatus' => applicationStatus
                    };

                    parsedRows.add(parsed);
                    appNumbers.add(appNumber);
                }

                if (appNumbers.isEmpty()) {
                    continue;
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
                    String applicationStatus =  parsed.get('applicationStatus');

                    if (!appNumberToRec.containsKey(appNumber)) {
                        logError('Row ' + rowIdx + ': No Application found for Application Number: ' + appNumber);
                        resultRows.add( appNumber + ',' + status + ',' + stage + ',' + applicationStatus + ',Failed,' +'Application Not Found');
                        continue;
                    }

                    if(statusCol >= 0 && !String.isBlank(status) && !validStatusValues.contains(status)) {
                        logError('Row ' + rowIdx + ': Invalid Applicant State Management value → "' + status + '"');
                        resultRows.add( appNumber + ',' + status + ',' + stage + ',' + applicationStatus + ',Failed,' +'Invalid Applicant State Management');
                        continue;
                    }

                    if(stageCol >= 0 && !String.isBlank(stage) && !validStageValues.contains(stage)){
                        logError('Row ' + rowIdx + ': Invalid Application Stage value → "' + stage + '"');
                        resultRows.add( appNumber + ',' + status + ',' + stage + ',' + applicationStatus + ',Failed,' +'Invalid Application Stage');
                        continue;
                    }

                    if(applicationStatusCol >= 0 && !String.isBlank(applicationStatus) && !validApplicationStatusValues.contains(applicationStatus)){
                        logError('Row ' + rowIdx + ': Invalid Application Status value -> "' + applicationStatus + '"');
                        resultRows.add( appNumber + ',' + status + ',' + stage + ',' + applicationStatus + ',Failed,' +'Invalid Application Status');
                        continue;
                    }

                    Application__c toUpdate = new Application__c(Id = appNumberToRec.get(appNumber).Id);

                    if(statusCol >= 0){
                        toUpdate.Applicant_State_Management__c = status;
                    }

                    if(stageCol >= 0){
                        toUpdate.Application_Stage__c = stage;
                    }

                    if(applicationStatusCol >= 0){
                        toUpdate.Application_Status__c = applicationStatus;
                    }

                    updates.add(toUpdate);
                    updateApplicationNumbers.add(appNumber);
                }

                if (!updates.isEmpty()) {
                    Database.SaveResult[] results = Database.update(updates, false);

                    // for (Integer i = 0; i < results.size(); i++) {
                    //     Database.SaveResult sr = results[i];
                    //     if(sr.isSuccess()){
                    //         Application__c updatedRec = updates[i];
                    //         resultRows.add(appNumberToRec.values()[i].Name + ',' + updatedRec.Applicant_State_Management__c +',' + updatedRec.Application_Stage__c +',' +
                    //             updatedRec.Application_Status__c + ',Success,' + 'Updated Successfully');
                    //     }
                    // }

                    for (Integer i = 0; i < results.size(); i++) {
                        Database.SaveResult sr = results[i];
                        if (!sr.isSuccess()) {
                            for (Database.Error err : sr.getErrors()) {
                                logError('Failed update for Id: ' + sr.getId() + ' → ' + err.getMessage());
                                Application__c failedRec = updates[i];
                                resultRows.add( updateApplicationNumbers[i] + ',' + failedRec.Applicant_State_Management__c + ',' + failedRec.Application_Stage__c +',' + failedRec.Application_Status__c +
                                    ',Failed,' + err.getMessage());
                            }
                        }
                    }
                }
            } catch(Exception e){
                logError( 'Error processing file ' + cv.Title  + ' : ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {

        if(notifyShortlistedApplicants){

        }

        ContentVersion cv;
        String downloadLink = '';

        PlatformEventPayload payload = new PlatformEventPayload();

        if(resultRows.size() > 1){
            String csvResult = String.join(resultRows,'\n');
            cv = new ContentVersion();
            cv.Title = 'Application_Import_Error_Report_' + DateTime.now().format('yyyyMMdd_HHmmss');
            cv.PathOnClient = cv.Title + '.csv';
            cv.VersionData = Blob.valueOf(csvResult);
            insert cv;

            cv = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE Id=:cv.Id];
            downloadLink = URL.getOrgDomainUrl().toExternalForm() + '/' + cv.ContentDocumentId;

            payload.status = 'Completed';
            payload.hasErrors = true;
            payload.errorCount = resultRows.size() - 1;
            payload.fileName = cv.Title + '.csv';
            payload.contentDocumentId = cv.ContentDocumentId;
            payload.downloadUrl = downloadLink;
        }else{
            payload.status = 'Completed';
            payload.hasErrors = false;
            payload.errorCount = 0;
        }

        AdmissionConsoleEvent__e appEvent = new AdmissionConsoleEvent__e();
        appEvent.UserId__c = UserInfo.getUserId();
        appEvent.Intent__c = 'ApplicationImport';
        appEvent.Message__c = JSON.serialize(payload);
        Database.SaveResult publishResult = EventBus.publish(appEvent);

        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed,
                   TotalJobItems, CreatedBy.Email
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];

        if(emailErrorReport){
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[]{ job.CreatedBy.Email });

            mail.setSubject('Application Status CSV Update – ' + job.Status);

            String body = 'Batch Completed.\n\n' +
                        'Batches: ' + job.TotalJobItems + '\n' +
                        'Processed: ' + job.JobItemsProcessed + '\n' +
                        'Errors: ' + job.NumberOfErrors + '\n\n';

            if(!String.isBlank(downloadLink)){
                body += '\nError CSV Download Link: ' + downloadLink + '\n';
            }

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
    }

    private void logError(String msg) {
        if (errorMessages.size() < MAX_ERROR_LOGS) {
            errorMessages.add(msg);
        }
    }

    private static Set<String> getPicklistValues(String fieldApiName) {
        Set<String> values = new Set<String>();

        Schema.DescribeFieldResult fieldDescribe = Application__c.SObjectType.getDescribe().fields.getMap().get(fieldApiName).getDescribe();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            values.add(entry.getValue());
        }

        return values;
    }
}