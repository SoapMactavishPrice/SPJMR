public class SpecializationChangeRequestHandler {

    public static void submitForApproval(List<Specialization_Change_Request__c> records) {

        for( Specialization_Change_Request__c rec : records) {

            Approval.ProcessSubmitRequest req =new Approval.ProcessSubmitRequest();
            req.setObjectId(rec.Id);
            Approval.ProcessResult result = Approval.process(req);
        }
    }
}