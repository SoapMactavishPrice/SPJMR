/**
 * Sends student email when Withdrawal Request Status becomes Approved or Rejected.
 * Separate from WithdrawalRequestTrigger so existing submit/approval flow is untouched.
 */
trigger WithdrawalRequestDecisionNotifyTrigger on Withdrawal_Request__c (after update) {
    WithdrawalApprovalController.notifyStudentsOnStatusChange(Trigger.new, Trigger.oldMap);
}