import { LightningElement, api, track } from 'lwc';
import notifyApplicantApex from '@salesforce/apex/ApplicationVerificationNotifier.notifyApplicant';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class NotifyApplicant extends LightningElement {
    @api recordId;    // Application Verification Id
    @track isLoading = false;

    handleSend() {
        this.isLoading = true;

        notifyApplicantApex({ appVerId: this.recordId })
            .then(result => {

                if (result === 'SUCCESS') {
                    this.showToast('Success', 'Email sent successfully!', 'success');
                } 
                else if (result === 'PENDING_DOCS') {
                    this.showToast('Warning', 'Documents are still pending review!', 'warning');
                }
                else if (result === 'NO_EMAIL') {
                    this.showToast('Error', 'Applicant email not found', 'error');
                }
                else {
                    this.showToast('Error', result, 'error');
                }

                this.isLoading = false;
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}