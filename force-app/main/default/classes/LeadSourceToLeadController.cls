public class LeadSourceToLeadController {
    
    @AuraEnabled
    public static string convertLead(String lsId){
        try {

            Lead_Sources__c exLeadSource = [
                SELECT Id, Name, Email__c, Phone__c, Lead__c, Source__c, Program__c, Source_Date_Time__c, Program_Code__c
                FROM Lead_Sources__c 
                WHERE Id =: lsId
            ];

            Lead exLead = [
                SELECT Id, Email, Phone, FirstName, LastName, Company, XS_Source__c, XS_CurrentlyStudingIn__c, XS_Age__c,
                XS_Year__c, XS_State__c, XS_City__c, XS_YearsOfWorkExperience__c, XS_DoYouHaveEntranceExamScore__c,
                XS_EntranceExamName__c, XS_SPJIMR_PartnerCompany__c, XS_EnterOrganisation__c, XS_Programme__c, XS_HowDidYouFindOutAboutUs__c,
                XS_CurrentDesigination__c, XS_College__c, XS_HaveYouCompletedYourGraduation__c, Status
                FROM Lead 
                WHERE Id =: exLeadSource.Lead__c
            ];

            // Lead originalLead = exLead;
            // Lead clonedLead = originalLead.clone(false, true, false, false);
            // clonedLead.Converted_From__c = exLeadSource.Id;
            // insert clonedLead;

            Lead newLead = new Lead();
            newLead.FirstName = exLead.FirstName;
            newLead.LastName = exLead.LastName;
            newLead.Email = exLeadSource.Email__c;
            newLead.Phone = exLeadSource.Phone__c;
            newLead.XS_Source__c = exLeadSource.Source__c;
            newLead.XS_Programme__c = exLeadSource.Program_Code__c;
            newLead.Converted_From__c = exLeadSource.Id;
            System.debug(newLead);
            insert newLead;

            Lead_Sources__c newLeadSrc = new Lead_Sources__c();
            newLeadSrc.Email__c = exLeadSource.Email__c;
            newLeadSrc.Phone__c = exLeadSource.Phone__c;
            newLeadSrc.Lead__c = newLead.Id;
            newLeadSrc.Source__c = exLeadSource.Source__c;
            newLeadSrc.Program__c = exLeadSource.Program__c;
            newLeadSrc.Source_Date_Time__c = exLeadSource.Source_Date_Time__c;

            insert newLeadSrc;

            return newLead.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
}