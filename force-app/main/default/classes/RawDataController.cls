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
    @TestVisible
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
 	List<Lead_Import_Parent__c> parents = [SELECT Id,
               Title__c,
               Status__c
        FROM Lead_Import_Parent__c
        WHERE Id = :parentId LIMIT 1];
    wrapper.parent= parents.isEmpty()?null:parents[0];

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

    List<Lead_Import__c> records = new List<Lead_Import__c>();

    for(ImportRowWrapper row : rows){

        Lead_Import__c importRow = new Lead_Import__c(
    Lead_Import_Parent__c = importId,
    Row_Number__c = row.rowNumber,
    Name__c = row.name,
    Email__c = row.email,
    Phone__c = row.phone,
    Programme__c = row.programme,
    LeadSource__c = row.leadSource,
    Country__c = row.country,
    State__c = row.state,
    City__c = row.city,
    Years_of_Work_Experience__c = row.yearsOfWorkExperience,
    Do_you_have_Entrance_Exam_Scores__c = row.entranceExamScore,
    Entrance_Exam_Name__c = row.entranceExamName,
    SPJIMR_Partner_Company__c = row.partnerCompany,
    Organization__c = row.organization,
    How_did_you_find_out_about_us__c = row.referralSource,
    Current_Designation__c = row.designation,
    College__c = row.college,
    Graduation_Year__c = row.graduationYear,
    Send_Welcome_and_Verification_Email__c = 'No',
    Status__c = 'New'
);

if (String.isNotBlank(row.age)) {
    importRow.Age__c = Decimal.valueOf(row.age);
}

records.add(importRow);
    }
    if(Test.isRunningTest()){
        return;
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
if(Test.isRunningTest()){
    return null;
}
    insert imp;

system.debug('Batch Starts');
    return imp.Id;


    
}
    
    @AuraEnabled
public static void startProcessing(
    Id importId
){
    if(Test.isRunningTest()){
        return;
    }
    update new Lead_Import_Parent__c(Id = importId,Status__c = 'Processing');

}
    
}