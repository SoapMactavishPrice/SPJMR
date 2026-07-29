public class ExportApplications implements Database.Batchable<SObject>, Database.Stateful {
    private Id programId;
    private Id cohortId;
    private String applicationStage;
    private String applicationStatus;
    private String programCode;
    private String applicantStateManagement;

    private static final Integer MAX_ROWS_PER_FILE = 5000;
    private List<String> csvRows = new List<String>();
    private Integer currentRowCount = 0;
    private Integer fileNumber = 1;
    private List<GeneratedFile> generatedFiles = new List<GeneratedFile>();
    private Boolean recordsFound = false;
    
    public class GeneratedFile {
        public String name;
        public String documentId;

        public GeneratedFile(String name, String documentId){
            this.name = name;
            this.documentId = documentId;
        }
    }

    public ExportApplications(Id programId, Id cohortId, String applicationStage, String applicationStatus, String applicantStateManagement) {
        this.programId = programId;
        this.cohortId = cohortId;
        this.applicationStage = applicationStage;
        this.applicationStatus = applicationStatus;
        this.applicantStateManagement = applicantStateManagement;
    }

    private static String csvValue(Object value){
        if(value == null){
            return '';
        }
        return String.valueOf(value).replace('"','""');
    }

    // Retained for existing Apex callers while new exports identify a Program by Id.
    public ExportApplications(String programCode) {
        this.programCode = programCode;
    }

    private static Id getDefaultRecordTypeId() {
        for (Schema.RecordTypeInfo rtInfo :
            Application__c.SObjectType.getDescribe().getRecordTypeInfos()) {

            if (rtInfo.isDefaultRecordTypeMapping()) {
                return rtInfo.getRecordTypeId();
            }
        }
        return null;
    }

    public Database.QueryLocator start(Database.BatchableContext bc){

        Program selectedProgram = [SELECT Id, Name, Program_Code__c FROM Program WHERE Id = :programId LIMIT 1];

        programCode = String.isBlank(selectedProgram.Program_Code__c) ? selectedProgram.Name : selectedProgram.Program_Code__c;

        Id recordTypeId = getDefaultRecordTypeId();

        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Application__c'
            AND Name = :programCode
            LIMIT 1
        ];

        if (!recordTypes.isEmpty()) {
            recordTypeId = recordTypes[0].Id;
        }

        csvRows.add(
            'Application Number,' +
            'Applicant Name,' +
            'Applicant State Management,' +
            'Programme Code,' +
            'Application Stage,' +
            'Application Status'
        );

        String query =
            'SELECT ' +
            'Name,' +
            'Applicant__r.Name,' +
            'Applicant_State_Management__c,' +
            'Program__r.Program_Code__c,' +
            'Application_Stage__c,' +
            'Application_Status__c ' +
            'FROM Application__c ' +
            'WHERE Program__c = :programId ' +
            'AND RecordTypeId = :recordTypeId';

        if(cohortId != null){
            query += ' AND Batch__c = :cohortId';
        }

        if(!String.isBlank(applicationStage)){
            query += ' AND Application_Stage__c = :applicationStage';
        }

        if(!String.isBlank(applicationStatus)){
            query += ' AND Application_Status__c = :applicationStatus';
        }

        if(!String.isBlank(applicantStateManagement)){
            query += ' AND Applicant_State_Management__c = :applicantStateManagement';
        }

        return Database.getQueryLocator(query);

    }

    public void execute(Database.BatchableContext bc, List<Application__c> scope){

        if (!scope.isEmpty()) {
            recordsFound = true;
        }

        for(Application__c app : scope){
            csvRows.add(
                '"' +
                csvValue(app.Name) +

                '","' +

                csvValue(app.Applicant__r == null ? null : app.Applicant__r.Name) +

                '","' +

                csvValue(app.Applicant_State_Management__c) +

                '","' +

                csvValue(app.Program__r.Program_Code__c) +

                '","' +

                csvValue(app.Application_Stage__c) +

                '","' +

                csvValue(app.Application_Status__c) +

                '"'

            );

            currentRowCount++;

            if(currentRowCount == MAX_ROWS_PER_FILE){
                createCsvFile();
            }
        }
    }

    private void createCsvFile(){
        if(currentRowCount == 0){
            return;
        }

        String csvContent = String.join(csvRows,'\n');

        String fileName = programCode + '_Applications_Part_' + fileNumber;

        ContentVersion version = new ContentVersion();

        version.Title = fileName;

        version.PathOnClient = fileName + '.csv';

        version.VersionData = Blob.valueOf(csvContent);

        insert version;

        version = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id=:version.Id
        ];

        generatedFiles.add(
            new GeneratedFile(
                fileName + '.csv',
                version.ContentDocumentId
            )
        );

        /*
        * Prepare for next CSV
        */

        csvRows.clear();

        csvRows.add(
            'Application Number,' +
            'Applicant Name,' +
            'Applicant State Management,' +
            'Programme Code,' +
            'Application Stage,' +
            'Application Status'
        );

        currentRowCount = 0;

        fileNumber++;

    }


    private void publishPlatformEvent(){

        Map<String,Object> payload = new Map<String,Object>();

        List<Object> files = new List<Object>();

        for(GeneratedFile f : generatedFiles){
            Map<String,Object> item = new Map<String,Object>();
            item.put('name', f.name);
            item.put('documentId', f.documentId);
            files.add(item);
        }

        if (!recordsFound) {
            payload.put('status', 'NoRecords');
            payload.put('files', new List<Object>());
        } else {
            payload.put('status', 'Completed');
            payload.put('files', files);
        }

        AdmissionConsoleEvent__e eventObj = new AdmissionConsoleEvent__e();
        eventObj.UserId__c = UserInfo.getUserId();
        eventObj.Intent__c = 'ApplicationExport';
        eventObj.Message__c = JSON.serialize(payload);
        EventBus.publish(eventObj);

    }


    public void finish(Database.BatchableContext bc){
        /*
        * Remaining rows
        */
        if(currentRowCount > 0){
            createCsvFile();
        }
        publishPlatformEvent();
    }
}