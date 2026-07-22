public class RawDataController {
    public class ImportSummaryWrapper {
    @AuraEnabled public Lead_Import_Parent__c parent;
    @AuraEnabled public Integer successCount;
    @AuraEnabled public Integer failedCount;
    @AuraEnabled public List<Lead_Import__c> failedRows;
    @AuraEnabled public String description;
}
    public class ImportRowWrapper {

    @AuraEnabled public Integer rowNumber {get;set;}
    @AuraEnabled public String name {get;set;}
    @AuraEnabled public String email {get;set;}
    @AuraEnabled public String phone {get;set;}
    @AuraEnabled public String programme {get;set;}
    @AuraEnabled public String leadSource {get;set;}
    @AuraEnabled public String country {get;set;}
    @AuraEnabled public String state {get;set;}
    @AuraEnabled public String city {get;set;}
    @AuraEnabled public String yearsOfWorkExperience{get;set;}
    @AuraEnabled public String entranceExamScore{get;set;}
    @AuraEnabled public String entranceExamName{get;set;}
    @AuraEnabled public String partnerCompany{get;set;}
    @AuraEnabled public String organization{get;set;}
    @AuraEnabled public String referralSource{get;set;}
    @AuraEnabled public String designation{get;set;}
    @AuraEnabled public String age{get;set;}
    @AuraEnabled public String college{get;set;}
    @AuraEnabled public String graduationYear{get;set;}
}
    
    private static final List<String> EXPECTED_HEADERS = new List<String>{
    'Name',
    'Email',
    'Phone',
    'Programme',
    'Lead Source',
    'Country',
    'State',
    'City',
    'Years of Work Experience',
    'Do you have Entrance Exam Scores?',
    'Entrance Exam Name',
    'SPJIMR Partner Company',
    'Organization',
    'How did you find out about us?',
    'Current Designation',
    'Age',
    'College',
    'Graduation Year',
    'Send Welcome and Verification Email?'
};

@AuraEnabled(cacheable=true)
public static List<Lead_Import_Parent__c> getImports(){

    return [
        SELECT Id,
               Title__c,
               Description__c,
               Status__c,
               CreatedDate
        FROM Lead_Import_Parent__c
        ORDER BY CreatedDate DESC
    ];
}

@AuraEnabled(cacheable=true)
public static ImportSummaryWrapper getImportSummary(Id parentId){

    ImportSummaryWrapper wrapper =
        new ImportSummaryWrapper();

    wrapper.parent = [
        SELECT Id,
               Title__c,
               Status__c
        FROM Lead_Import_Parent__c
        WHERE Id = :parentId
    ];

    wrapper.successCount = [
        SELECT COUNT()
        FROM Lead_Import__c
        WHERE Lead_Import_Parent__c = :parentId
        AND Status__c = 'Complete'
    ];

    wrapper.failedCount = [
        SELECT COUNT()
        FROM Lead_Import__c
        WHERE Lead_Import_Parent__c = :parentId
        AND Status__c = 'Failed'
    ];
    List<Lead_Import_Parent__c> parentRec =  
    [SELECT Description__c
        FROM Lead_Import_Parent__c
        WHERE Id=:parentId LIMIT 1
    ];
    wrapper.description = parentRec.isEmpty()?'':parentRec[0].Description__c;
       
   

    wrapper.failedRows = [
        SELECT Row_Number__c,
               Name__c,
               Email__c,
               Error_Message__c
        FROM Lead_Import__c
        WHERE Lead_Import_Parent__c = :parentId
        AND Status__c = 'Failed'
        ORDER BY Row_Number__c
    ];

    return wrapper;
}

    @AuraEnabled
public static void insertImportRows(
    Id importId,
    List<ImportRowWrapper> rows
) {

    List<Lead_Import__c> records =
        new List<Lead_Import__c>();

    for(ImportRowWrapper row : rows){

        Lead_Import__c importRow =
            new Lead_Import__c();

        importRow.Lead_Import_Parent__c = importId;
        importRow.Row_Number__c = row.rowNumber;

        importRow.Name__c = row.name;
        importRow.Email__c = row.email;
        importRow.Phone__c = row.phone;
        importRow.Programme__c = row.programme;
        importRow.LeadSource__c = row.leadSource;
        importRow.Country__c = row.country;
        importRow.State__c = row.state;
        importRow.City__c = row.city;
        importRow.Years_of_Work_Experience__c =
            row.yearsOfWorkExperience;

        importRow.Do_you_have_Entrance_Exam_Scores__c =
            row.entranceExamScore;

        importRow.Entrance_Exam_Name__c =
            row.entranceExamName;

        importRow.SPJIMR_Partner_Company__c =
            row.partnerCompany;

        importRow.Organization__c =
            row.organization;

        importRow.How_did_you_find_out_about_us__c =
            row.referralSource;

        importRow.Current_Designation__c =
            row.designation;

        if(String.isNotBlank(row.age)){
            importRow.Age__c =
                Decimal.valueOf(row.age);
        }

        importRow.College__c =
            row.college;

        importRow.Graduation_Year__c =
            row.graduationYear;

        importRow.Send_Welcome_and_Verification_Email__c =
            'No';

        importRow.Status__c = 'New';

        records.add(importRow);
    }

    insert records;
}
    
    @AuraEnabled
public static Id startImport(String fileName,
                              String description) {

    
    Lead_Import_Parent__c imp = new Lead_Import_Parent__c(
        Title__c = fileName,
        Description__c = description,
        Status__c = 'Uploaded'
    );

    insert imp;

system.debug('Batch Starts');
    return imp.Id;


    
}
    
    @AuraEnabled
public static void startProcessing(
    Id importId
){

    update new Lead_Import_Parent__c(
        Id = importId,
        Status__c = 'Processing'
    );

}
    
}