trigger WithdrawalRequestTrigger on Withdrawal_Request__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        // Submit each new 'Applied' request into the standard Approval Process,
        // routed to the Programme Office team. Never throws.
        WithdrawalApprovalService.submitForApproval(Trigger.new);

        // Styled email + custom bell notification to the Programme Office approvers.
        WithdrawalRequestNotificationService.sendNotifications(Trigger.new);
    }
}