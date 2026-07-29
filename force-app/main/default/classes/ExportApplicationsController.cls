public with sharing class ExportApplicationsController {

    @AuraEnabled(cacheable=true)
    public static List<ProgramCohort> getCohortsForProgram(Id programId) {
        if (programId == null) return new List<ProgramCohort>();
        return [
            SELECT Id, Name
            FROM ProgramCohort
            WHERE ProgramId = :programId
            ORDER BY Name
        ];
    }

    @AuraEnabled
    public static String exportApplicationsBatch(Id programId, Id cohortId, String applicationStage, String applicationStatus, String applicantStateManagement) {
        if (programId == null) {
            throw new AuraHandledException('Select a program before starting the export.');
        }
        if (cohortId != null && [
            SELECT COUNT()
            FROM ProgramCohort
            WHERE Id = :cohortId AND ProgramId = :programId
        ] == 0) {
            throw new AuraHandledException('The selected cohort does not belong to the selected program.');
        }

        String jobId = Database.executeBatch(
            new ExportApplications(programId, cohortId, applicationStage, applicationStatus, applicantStateManagement),
            2000
        );

        System.debug('Returned Job Id = ' + jobId);
        System.debug('Length = ' + jobId.length());

        return jobId;
    }

    // Retained for existing Apex callers while the LWC uses the ID-based method above.
    public static String exportApplicationsBatch(String programCode) {
        Program selectedProgram = [
            SELECT Id
            FROM Program
            WHERE Program_Code__c = :programCode
            LIMIT 1
        ];
        return exportApplicationsBatch(selectedProgram.Id, null, null, null, null);
    }


    @AuraEnabled
    public static void sendExportEmail(String filesJson){
        if(String.isBlank(filesJson)){
            return;
        }

        List<Object> fileObjects = (List<Object>)JSON.deserializeUntyped(filesJson);

        String htmlBody = 'Hello ' + UserInfo.getName() + '<br/><br/>';
        htmlBody += 'Your Application Export has completed successfully.<br/><br/>';
        htmlBody += '<b>Download Files</b><br/><br/>';

        for(Object obj : fileObjects){

            Map<String,Object> file = (Map<String,Object>)obj;
            String name = String.valueOf(file.get('name'));
            String documentId = String.valueOf(file.get('documentId'));

            String downloadUrl = URL.getOrgDomainUrl().toExternalForm() + '/sfc/servlet.shepherd/document/download/' + documentId;

            htmlBody += '<a href="' + downloadUrl + '">' + name + '</a><br/>';
        }

        Messaging.SingleEmailMessage mail =  new Messaging.SingleEmailMessage();

        mail.setToAddresses(
            new String[]{
                UserInfo.getUserEmail()
            }
        );

        mail.setSubject('Application Export Completed');
        mail.setHtmlBody(htmlBody);
        Messaging.sendEmail( new Messaging.SingleEmailMessage[]{mail});
    }


    @AuraEnabled(cacheable=true)
    public static Integer getApplicationCount(
        Id programId,
        Id cohortId,
        String applicationStage,
        String applicationStatus,
        String applicantStateManagement
    ) {

        Program p = [
            SELECT Name, Program_Code__c
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];

        String programCode = String.isBlank(p.Program_Code__c) ? p.Name : p.Program_Code__c;

        Id recordTypeId = getApplicationRecordTypeId(programId);

        String query =
            'SELECT Count() ' +
            'FROM Application__c ' +
            'WHERE Program__c = :programId ' +
            'AND RecordTypeId = :recordTypeId';

        if (cohortId != null)
            query += ' AND Batch__c = :cohortId';

        if (!String.isBlank(applicationStage))
            query += ' AND Application_Stage__c = :applicationStage';

        if (!String.isBlank(applicationStatus))
            query += ' AND Application_Status__c = :applicationStatus';

        if (!String.isBlank(applicantStateManagement))
            query += ' AND Applicant_State_Management__c = :applicantStateManagement';

        return Database.countQuery(query);
    }


    @AuraEnabled(cacheable=true)
    public static Id getApplicationRecordTypeId(Id programId){
        Program p = [
            SELECT Program_Code__c
            FROM Program
            WHERE Id = :programId
            LIMIT 1
        ];

        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Application__c'
            AND Name = :p.Program_Code__c
            LIMIT 1
        ];

        if (!recordTypes.isEmpty()) {
            return recordTypes[0].Id;
        }

        // Fallback to the running user's default record type
        return getDefaultRecordTypeId();
    }

    private static Id getDefaultRecordTypeId() {

        Schema.DescribeSObjectResult describeResult = Application__c.SObjectType.getDescribe();

        for (Schema.RecordTypeInfo rtInfo : describeResult.getRecordTypeInfos()) {
            if (rtInfo.isDefaultRecordTypeMapping()) {
                return rtInfo.getRecordTypeId();
            }
        }
        return null;
    }
}