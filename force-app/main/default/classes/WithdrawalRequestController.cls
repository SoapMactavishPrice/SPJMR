/**
* WithdrawalRequestController
*
* Determines whether the Withdrawal Request action should be available to the
* currently logged-in student, based on their active ProgramCohort (batch).
*
* Resolution path (per the confirmed enrollment model):
*   User (portal login) -> Contact -> Account (Programme Enrollee / Person Account)
*   -> ProgramCohortMember (Programme Enrollee = this Account)
*   -> ProgramCohort (Batch), filtered to Is_Active__c = true
*   -> compare Date.today() to ProgramCohort.StartDate / EndDate
*
* DEBUG FIELDS: debugNow / debugResolvedAccountId / debugRecordCountIgnoringDatesAndStatus /
* debugRecordCountMatchingFilters / debugRecordSummaries / debugRunningUserId /
* debugCohortRelatedObjectNames are returned on every call (mirroring the existing
* DefermentRequestController diagnostic pattern) so the real resolved values can be
* inspected directly in the browser console instead of guessing. Safe to remove once
* the flow is confirmed working end-to-end.
*
* API VERSION NOTE: this class must be deployed at apiVersion >= the release that
* introduced ProgramCohort/ProgramCohortMember in this org, or SOQL against those
* types fails at runtime through the LWR site's /apex/execute path with
* "sObject type 'ProgramCohortMember' is not supported" - even though the class
* still compiles/saves fine in the Setup Apex editor (which compiles against the
* org's latest version regardless of the class's stored metadata version).
*/
public without sharing class WithdrawalRequestController {
    
    // Allows unit tests to bypass the running-user Contact/Account lookup.
    @TestVisible
    private static Id testAccountIdOverride;
    
    private static final String REQUIRED_WINDOW_MESSAGE =
        'Request Withdrawal button is visible/enabled only when the current date is within '
        + 'the Batch Start Date and Batch End Date for the student\'s program.';
    private static Id getCurrentEnrolleeAccountId() {

    if (Test.isRunningTest() && testAccountIdOverride != null) {
        return testAccountIdOverride;
    }

    List<User> currentUserRows = [
        SELECT Id, ContactId, Contact.AccountId
        FROM User
        WHERE Id = :UserInfo.getUserId()
        LIMIT 1
    ];

    if (currentUserRows.isEmpty() ||
        currentUserRows[0].ContactId == null) {
        return null;
    }

    return currentUserRows[0].Contact.AccountId;
}
   @AuraEnabled(cacheable=true)
public static WithdrawalEligibilityResult getWithdrawalEligibility() {

    WithdrawalEligibilityResult result =
        new WithdrawalEligibilityResult();

    result.debugNow = String.valueOf(DateTime.now());
    result.debugRunningUserId =
        UserInfo.getUserId() + ' / ' + UserInfo.getUserEmail();

    try {

        // 1. Get the logged-in student's Account
        Id enrolleeAccountId = getCurrentEnrolleeAccountId();
        result.debugResolvedAccountId = enrolleeAccountId;

        if (enrolleeAccountId == null) {
            result.isEligible = false;
            result.message =
                'We could not locate your student enrollment record. '
                + 'Please contact your Programme Office for assistance.';
            return result;
        }

        // 2. Get the student's Batch through Program Cohort Member
        List<ProgramCohortMember> cohortMembers = [
            SELECT Id,
                   ProgramCohortId,
                   ProgramCohort.Name,
                   ProgramCohort.Is_Active__c,
                   ProgramCohort.StartDate,
                   ProgramCohort.EndDate
            FROM ProgramCohortMember
            WHERE ProgramEnrolleeId = :enrolleeAccountId
       OR ProgramEnrollment.AccountId = :enrolleeAccountId
            LIMIT 1
        ];

        result.debugRecordCountMatchingFilters =
            cohortMembers.size();

        if (cohortMembers.isEmpty()
            || cohortMembers[0].ProgramCohort == null) {

            result.isEligible = false;
            result.message =
                'We could not locate your active Batch. '
                + 'Please contact your Programme Office.';
            return result;
        }

        // 3. Get the Batch
        ProgramCohort activeCohort =
            cohortMembers[0].ProgramCohort;

        // 4. Get Batch Start and End Dates
        result.startDate = activeCohort.StartDate;
        result.endDate = activeCohort.EndDate;

        // 5. Validate Batch dates
        if (result.startDate == null ||
            result.endDate == null) {

            result.isEligible = false;
            result.message = REQUIRED_WINDOW_MESSAGE;
            return result;
        }

        // 6. Check whether Batch is Active
        if (activeCohort.Is_Active__c != true) {

            result.isEligible = false;
            result.message = REQUIRED_WINDOW_MESSAGE;
            return result;
        }

        // 7. Compare today's date with Batch Start/End Date
        Date today = Date.today();

        if (today >= result.startDate &&
            today <= result.endDate) {

            // Student is within the allowed withdrawal window
            result.isEligible = true;

            result.message =
                'Withdrawal Request is currently open. '
                + 'You can submit your request until '
                + result.endDate.format() + '.';

        } else {

            // Student is outside the allowed withdrawal window
            result.isEligible = false;

            result.message =
                'Withdrawal Request is currently unavailable because '
                + 'the withdrawal window has ended.';
        }

        return result;

    } catch (Exception e) {

        result.isEligible = false;

        result.message =
            'We were unable to verify your withdrawal window right now. '
            + 'Please try again later or contact your Programme Office.';

        result.errorDetail =
            e.getMessage() + ' | ' + e.getStackTraceString();

        return result;
    }
}
    
    /**
* Wrapper returned to the LWC with everything it needs to render the
* enabled/disabled state, the explanatory message, and diagnostic info.
*/
    public class WithdrawalEligibilityResult {
        @AuraEnabled public Boolean isEligible = false;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String message;
        @AuraEnabled public String errorDetail;
        
        // Temporary diagnostics - safe to remove once the flow is verified.
        @AuraEnabled public String debugNow;
        @AuraEnabled public Id debugResolvedAccountId;
        @AuraEnabled public Integer debugRecordCountIgnoringDatesAndStatus;
        @AuraEnabled public Integer debugRecordCountMatchingFilters;
        @AuraEnabled public List<String> debugRecordSummaries;
        @AuraEnabled public String debugRunningUserId;
        @AuraEnabled public List<String> debugCohortRelatedObjectNames;
    }
}