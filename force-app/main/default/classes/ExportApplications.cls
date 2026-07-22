public class ExportApplications implements Database.Batchable<SObject>, Database.Stateful {

    String programCode;
    String csvData = ''; // Apex does not support StringBuilder

    public ExportApplications(String programCode) {
        this.programCode = programCode;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {

        // CSV Header
        csvData +=
    'Application Number,' +
    'Applicant Name,' +
    'Applicant State Management,' +
    'Programme Code,' +
    'Application Stage,' +
    'Application Status\n';

        // Dynamic SOQL
        return Database.getQueryLocator([
            SELECT Id,
                   Applicant_State_Management__c,
                   Name,
                   Applicant__r.Name,
                   Program__r.Program_Code__c,
                   Application_Stage__c,
                   Application_Status__c
            FROM Application__c
            WHERE Program__r.Program_Code__c = :programCode
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Application__c> scope) {
        for (Application__c app : scope) {
           csvData +=
    '"' + (app.Name != null ? app.Name : '') + '",' +
    '"' + (app.Applicant__r != null ? app.Applicant__r.Name : '') + '",' +
    '"' + (app.Applicant_State_Management__c != null ? app.Applicant_State_Management__c : '') + '",' +
    '"' + (app.Program__r != null ? app.Program__r.Program_Code__c : '') + '",' +
    '"' + (app.Application_Stage__c != null ? app.Application_Stage__c : '') + '",' +
    '"' + (app.Application_Status__c != null ? app.Application_Status__c : '') + '"\n';
        }
    }

    public void finish(Database.BatchableContext bc) {

        Blob csvBlob = Blob.valueOf(csvData);

        String fileName = programCode + '_Applications_' + Date.today().format() + '.csv';

        ContentVersion cv = new ContentVersion(
            Title = programCode + '_Applications_' + Date.today().format(),
            PathOnClient = fileName,
            VersionData = csvBlob
        );
        insert cv;
        List<ContentVersion> listCV = [SELECT Id,ContentDocumentId FROM ContentVersion WHERE Id=:cv.Id LIMIT 1];

        Export_Job__c job =  new Export_Job__c(DocumentId__c = listCV[0]?.ContentDocumentId,Name = programCode + '_Applications_' + Date.today().format(),
        JobId__c = bc.getJobId(),Status__c = 'Completed');
        insert job;

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { UserInfo.getUserEmail() });
        email.setSubject(programCode + ' Applications CSV Export');
        email.setPlainTextBody('Follow the Link to get the CSV: ' + cv.VersionDataUrl );
        

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
    }
}