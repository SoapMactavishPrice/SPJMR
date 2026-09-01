public with sharing class BreakInStudyController {

    private static final String PROGRAMME_MANAGER_ROLE = 'Manager';

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
            // A negative fee used to save. It then showed the student a
            // negative amount while, because the form only treats a fee above
            // zero as payable, quietly waiving the Transaction Details
            // screenshot. Section 8.2 allows a fee or zero, never less.
            if (fee != null && fee < 0) {
                throwError(
                    'The Deferment Application Fee cannot be a negative amount. ' +
                    'Enter 0 if no fee applies to this programme.'
                );
            }
            

            ProgramCohortMember pcm = [
                SELECT Id, ProgramCohortId, ProgramEnrolleeId, ProgramCohort.ProgramId
                FROM ProgramCohortMember
                WHERE Id = :programCohortMemberId
                LIMIT 1
            ];

            // NEW: only the Programme Manager for this specific Programme
            // may create a Deferment Request (Break in Study) record.
            if (!isCurrentUserProgrammeManager(pcm.ProgramCohort.ProgramId)) {
                throwError(
                    'You are not authorized to create a Break in Study / Deferment Request. ' +
                    'Only the Programme Manager for this Programme can perform this action.'
                );
            }
            if (hasExistingDefermentRequest(pcm.Id)) {
    		throwError(
        			'A Break in Study / Deferment Request already exists for this student. ' +
        			'Only one Deferment Request is allowed per student.'
    			);
			}

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

    /**
     * Returns true only if the running user has a Program_Team_Members__c
     * record with Role__c = 'Manager' for the given Programme (via
     * Program_Team__r.Program__c). This is the same
     * Programme -> Program Team -> Program Team Members path already used
     * elsewhere (e.g. DefermentRequestController.getProgrammeApprovers).
     */
    private static Boolean isCurrentUserProgrammeManager(Id programmeId) {
        if (programmeId == null) {
            return false;
        }

        List<Program_Team_Members__c> managerRecords = [
            SELECT Id
            FROM Program_Team_Members__c
            WHERE Role__c = :PROGRAMME_MANAGER_ROLE
            AND User__c = :UserInfo.getUserId()
            AND Program_Team__r.Program__c = :programmeId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        return !managerRecords.isEmpty();
    }

    private static void throwError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }
    /**
 * Returns true if a Deferment_Request__c already exists for this
 * ProgramCohortMember, regardless of its current status. A student is
 * only ever allowed ONE deferment request, ever.
 */
	private static Boolean hasExistingDefermentRequest(Id programCohortMemberId) {
    List<Deferment_Request__c> existing = [
        SELECT Id
        FROM Deferment_Request__c
        WHERE Program_Cohort_Member__c = :programCohortMemberId
        WITH SYSTEM_MODE
        LIMIT 1
    ];
    return !existing.isEmpty();
}
}