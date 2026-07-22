public class ApplicationService {

    public class ApplicationRequest {
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public Id programId;
        public Id accountId;
        public Id userId;
        public String leadSource;
        public String workExperience; // Yes / No
        public String applicationNumber;
    }

    public static Application__c getApplicationRecord(ApplicationRequest req) {
        Application__c app = new Application__c();
        if (req == null) return app;

        app.Applicant__c = req.accountId;
        app.Applicant_State_Management__c = 'Untouched';
        app.Name = req.applicationNumber;
        app.HasWorkExperience__c = req.workExperience == 'Yes' ? 'Yes' : 'No';
        app.Program__c = req.programId;
        app.LeadSource__c = req.leadSource;

        if (req.userId != null) {
            app.OwnerId = req.userId;
        }

        app.First_Name__c = req.firstName;
        app.Last_Name__c = req.lastName;
        app.Phone__c = req.phone;
        app.Email__c = req.email;

        return app;
    }

    public static void createApplicationRelatedObjects(List<Application__c> applicationList) {
        if (applicationList.isEmpty()) return;

        List<Personal_Detail__c> personalDetails = new List<Personal_Detail__c>();
        List<Work_Experience__c> workExperiences = new List<Work_Experience__c>();
        List<Information_Source__c> informationSources = new List<Information_Source__c>();

        for (Application__c app : applicationList) {

            Id ownerIdToUse = app.OwnerId != null ? app.OwnerId : UserInfo.getUserId();

            Personal_Detail__c pd = new Personal_Detail__c();
            pd.Application__c = app.Id;
            pd.First_Name__c = app.First_Name__c;
            pd.Last_Name__c = app.Last_Name__c;
            pd.Primary_E_mail__c = app.Email__c;
            pd.Mobile_Number__c = app.Phone__c;
            pd.OwnerId = ownerIdToUse;
            personalDetails.add(pd);

            Work_Experience__c we = new Work_Experience__c();
            we.Application__c = app.Id;
            we.Do_You_Have_Any_Work_Experience__c =
                app.HasWorkExperience__c == 'Yes' ? 'Yes' : 'No';
            we.OwnerId = ownerIdToUse;
            workExperiences.add(we);

            Information_Source__c isRecord = new Information_Source__c();
            isRecord.Application__c = app.Id;
            isRecord.How_Did_you_get_to_know_about_SPJIMR__c = app.LeadSource__c;
            isRecord.OwnerId = ownerIdToUse;
            informationSources.add(isRecord);
        }

        if (!personalDetails.isEmpty()) insert personalDetails;
        if (!workExperiences.isEmpty()) insert workExperiences;
        if (!informationSources.isEmpty()) insert informationSources;
    }
}