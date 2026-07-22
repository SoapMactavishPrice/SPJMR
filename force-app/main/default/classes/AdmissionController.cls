public without sharing class AdmissionController {


    //Added null check
    @AuraEnabled(cacheable=true)
    public static List<Program> getPrograms() {
        List<Program> programs = [SELECT Id, Name FROM Program ORDER BY Name];
        if(!programs.isEmpty()){
            return programs;
        }
        return null;
    } 

    @AuraEnabled
    public static void submitApplication(String formData) {
        try {
            Map<String, Object> formValues = (Map<String, Object>)JSON.deserializeUntyped(formData);
            Id b2cRecTypeId = Schema.SobjectType.Lead.getRecordTypeInfosByName().get('B2C').getRecordTypeId();
            // Create Lead record
            Lead applicant = new Lead();
            // applicant.Company = 'GMP Applicant';
             applicant.LeadSource = 'Website';
            // applicant.Status = 'New';
            // applicant.Program_Interest__c = 'GMP';
            applicant.RecordTypeId = b2cRecTypeId;
            applicant.FirstName = parseFirstName((String)formValues.get('Name'));
            applicant.LastName = parseLastName((String)formValues.get('Name'));
            applicant.Email = (String)formValues.get('Email');
            applicant.Phone = (String)formValues.get('Phone');
            applicant.XS_State__c = (String)formValues.get('State');
            applicant.XS_City__c = (String)formValues.get('City');
            
            applicant.XS_YearsOfWorkExperience__c = (String)formValues.get('WorkExperience');
           // applicant.XS_CurrentDesigination__c = (String)formValues.get('CurrentDesignation');
            //applicant.Company = (String)formValues.get('Organization');
            // applicant.XS_HaveYouCompletedYourGraduation__c = String.valueOf((Boolean)formValues.get('HasCompletedGraduation'));
            applicant.XS_HaveYouCompletedYourGraduation__c = (string)formValues.get('HasCompletedGraduation');
            applicant.XS_College__c = (String)formValues.get('College');
            
            //applicant.XS_DoYouHaveEntranceExamScore__c = String.valueOf((Boolean)formValues.get('HasEntranceScore'));
            applicant.XS_EntranceExamName__c = (String)formValues.get('EntranceExamName');
            applicant.Others_Exam_Name__c = (String)formValues.get('OthersExamName');
            //applicant.Entrance_Exam_Score__c = (Decimal)formValues.get('EntranceExamScore');
            
            //applicant.XS_HowDidYouFindOutAboutUs__c = (String)formValues.get('ReferralSource');
            applicant.XS_Programme__c = (String)formValues.get('Program');
            //applicant.Comments__c = (String)formValues.get('Query');
            String programCode = (String)formValues.get('Program');
            if (String.isNotBlank(programCode)) {
                Program prog = [
                    SELECT Id 
                    FROM Program 
                    WHERE Program_Code__c = :programCode 
                    LIMIT 1
                ];
                if (prog != null) {
                    applicant.Program_Master__c = prog.Id;
                }
            }
            
            insert applicant;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error submitting application: ' + e.getMessage() + e.getLineNumber());
        }
    }
    
    // private static String parseFirstName(String fullName) {
    //     if (fullName == null) return '';
    //     String[] parts = fullName.split(' ');
    //     return parts.size() > 0 ? parts[0] : '';
    // }
    
    // private static String parseLastName(String fullName) {
    //     if (fullName == null) return '';
    //     String[] parts = fullName.split(' ');
    //     return parts.size() > 1 ? parts[parts.size()-1] : '';
    // }

    private static String parseFirstName(String fullName) {
        if (String.isBlank(fullName)) return '';
        String[] parts = fullName.trim().split(' ');
        return (parts.size() > 1) ? parts[0] : '';
    }

    private static String parseLastName(String fullName) {
        if (String.isBlank(fullName)) return 'Unknown';
        String[] parts = fullName.trim().split(' ');
        return (parts.size() == 1) ? parts[0] : parts[parts.size()-1];
    }
}