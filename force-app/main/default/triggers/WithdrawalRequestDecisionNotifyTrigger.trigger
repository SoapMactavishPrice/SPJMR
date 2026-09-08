/**
 * Sends student / approver email and portal bell when Withdrawal Request Status
 * becomes Approved, Rejected, Clearance & Exit, Recalled, Final Approval,
 * Final Rejection, or Withdrawal (email only).
 * Separate from WithdrawalRequestTrigger so existing submit/approval flow is untouched.
 */
trigger WithdrawalRequestDecisionNotifyTrigger on Withdrawal_Request__c (after update) {
    WithdrawalApprovalController.notifyStudentsOnStatusChange(Trigger.new, Trigger.oldMap);
}