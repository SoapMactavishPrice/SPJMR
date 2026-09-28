trigger WithdrawalRequestTrigger on Withdrawal_Request__c (after insert,after update) {
    if (Trigger.isAfter && Trigger.isInsert) {
        // Submit each new 'Applied' request into the standard Approval Process,
        // routed to the Programme Office team. Never throws.
        WithdrawalApprovalService.submitForApproval(Trigger.new);

        // Styled email + custom bell notification to Programme Office and the student.
        WithdrawalRequestNotificationService.sendNotifications(Trigger.new);
    }
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {

        Map<Id, String> newCodes = new Map<Id, String>();
        Map<Id, String> oldCodes = new Map<Id, String>();

        for (Withdrawal_Request__c record : Trigger.new) {
            newCodes.put(
                record.Id,
                record.Program_Code__c
            );
        }

        if (Trigger.isUpdate) {
            for (Withdrawal_Request__c record : Trigger.old) {
                oldCodes.put(
                    record.Id,
                    record.Program_Code__c
                );
            }
        }

        ProgrammeSharingService.shareRecords(
            'Withdrawal_Request__c',
            newCodes,
            Trigger.isUpdate ? oldCodes : null
        );
    }
}