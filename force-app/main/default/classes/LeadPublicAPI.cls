@RestResource(urlMapping='/createLead')
global class LeadPublicAPI {
    @HttpPost
    global static void createLead() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        Api_Log__c apiLog = new Api_Log__c();
        apiLog.Log_Name__c = 'createLead : ' + String.valueOf(Datetime.now());
        apiLog.Request__c = req.requestBody != null ? req.requestBody.toString() : null;

        try {
            String reqBody = req.requestBody != null ? req.requestBody.toString() : null;
            LeadPublicAPIService.ProcessOutcome outcome = LeadPublicAPIService.execute(reqBody);

            apiLog.Response__c = outcome.responseJson;
            apiLog.Status_Code__c = String.valueOf(outcome.statusCode);
            insert apiLog;

            res.statusCode = outcome.statusCode;
            res.responseBody = Blob.valueOf(outcome.responseJson);
        } catch (Exception e) {
            apiLog.Exception_Description__c = e.getMessage();
            apiLog.Status_Code__c = '400';
            insert apiLog;

            res.statusCode = 400;
            res.responseBody = Blob.valueOf(
                JSON.serialize(
                    new Map<String, Object>{ 'success' => false, 'message' => e.getMessage() }
                )
            );
        }
    }

    global class LeadWrapper {
        public String FirstName;
        public String LastName;
        public String Email;
        public String Phone;
        public String State;
        public String City;
        public String YearsOfWorkExperience;
        public String DoYouHaveEntranceExamScore;
        public String EntranceExamName;
        public String SPJIMR_PartnerCompany;
        public String EnterOrganisation;
        public String Programme;
        public String HowDidYouFindOutAboutUs;
        public String CurrentDesigination;
        public String Age;
        public String College;
        public String Year;
        public String HaveYouCompletedYourGraduation;
        public String CurrentlyStudingIn;
        public String Source;
        public String CampaignId;
        public String UTMParameters;
    }
}