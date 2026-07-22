public with sharing class LeadConvertFlowAction {

    public class Request {
        @InvocableVariable(required=true)
        public Id leadId;

        @InvocableVariable
        public Boolean doNotCreateOpportunity;

        @InvocableVariable
        public String opportunityName;
    }

    public class Response {
        @InvocableVariable public Boolean success;
        @InvocableVariable public String message;

        @InvocableVariable public Id accountId;
        @InvocableVariable public Id contactId;
        @InvocableVariable public Id opportunityId;
    }

    @InvocableMethod(label='Convert Lead (Flow)')
    public static List<Response> convertLead(List<Request> requests) {

        // ✅ Converted Status must be Partner
        String convertedStatus = 'Partner';

        // ✅ Business Account Record Type Id (Post Update)
        Id businessRtId =
            [SELECT Id FROM RecordType
             WHERE SobjectType='Account'
             AND DeveloperName='Business'
             LIMIT 1].Id;

        List<Response> responses = new List<Response>();

        for(Request req : requests){

            Response res = new Response();

            try{
                Database.LeadConvert lc = new Database.LeadConvert();
                lc.setLeadId(req.leadId);

                // ✅ Always convert with Partner status
                lc.setConvertedStatus(convertedStatus);

                // ✅ Opportunity logic
                if(req.doNotCreateOpportunity == true){
                    lc.setDoNotCreateOpportunity(true);
                } else {
                    lc.setDoNotCreateOpportunity(false);
                    lc.setOpportunityName(
                        String.isBlank(req.opportunityName)
                        ? 'New Opportunity'
                        : req.opportunityName
                    );
                }

                // ✅ Convert Lead
                Database.LeadConvertResult result =
                    Database.convertLead(lc);

                if(result.isSuccess()){

                    res.success = true;
                    res.message = 'Lead Converted Successfully';

                    res.accountId = result.getAccountId();
                    res.contactId = result.getContactId();
                    res.opportunityId = result.getOpportunityId();

                    // ✅ Force Account RecordType = Business after conversion
                    update new Account(
                        Id = res.accountId,
                        RecordTypeId = businessRtId
                    );

                } else {
                    res.success = false;
                    res.message = result.getErrors()[0].getMessage();
                }

            } catch(Exception e){
                res.success = false;
                res.message = 'Error: ' + e.getMessage();
            }

            responses.add(res);
        }

        return responses;
    }
}