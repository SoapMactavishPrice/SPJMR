trigger ApplicantPasswordResetTrigger on Applicant_Password_Reset__e (after insert) {
	ApplicantPasswordResetHandler.handleAfterInsert(Trigger.New);
}