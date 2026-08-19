public with sharing class BreakInStudyController {

    @AuraEnabled
    public static Id createDefermentRequest(
        Id programCohortMemberId,
        Datetime startDate,
        Datetime endDate,
        Decimal fee
    ) {
        try {
            if (programCohortMemberId == null) {
                throwError('Program Cohort Member Id is required.');
            }
            if (startDate == null || endDate == null) {
                throwError('Please enter both Start Date and End Date.');
            }
            if (endDate <= startDate) {
                throwError('End Date & Time must be greater than Start Date & Time.');
            }

            ProgramCohortMember pcm = [
                SELECT Id, ProgramCohortId, ProgramEnrolleeId,ProgramCohort.ProgramId
                FROM ProgramCohortMember
                WHERE Id = :programCohortMemberId
                LIMIT 1
            ];

            Deferment_Request__c request = new Deferment_Request__c(
                Program_Cohort_Member__c = pcm.Id,
                Batch__c = pcm.ProgramCohortId,
                Programme__c = pcm.ProgramCohort.ProgramId,
                Account__c = pcm.ProgramEnrolleeId,
                Break_Start_Date_Time__c = startDate,
                Break_End_Date_Time__c = endDate,
                Deferment_Application_Fee__c = fee,
                Status__c = 'Deferment Form Enabled'
            );
            insert request;
            return request.Id;

        } catch (AuraHandledException ex) {
            throw ex;
        } catch (Exception ex) {
            throwError('An unexpected error occurred: ' + ex.getMessage());
            return null;
        }
    }

    private static void throwError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }
}