import { LightningElement, api } from 'lwc';
import processApproval from '@salesforce/apex/WithdrawalApprovalController.processApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class WithdrawalApprovalAction extends LightningElement {

    @api recordId;
    @api mode;

    comments = '';
    escalateToChairperson = false;
    isLoading = false;

    get isApprove() {
        return this.mode === 'APPROVE';
    }

    get isReject() {
        return this.mode === 'REJECT';
    }

    handleComments(event) {
        this.comments = event.target.value;
    }

    handleEscalateChange(event) {
        this.escalateToChairperson = event.target.checked;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSubmit() {
        if (!this.comments || !this.comments.trim()) {
            const textarea = this.template.querySelector('lightning-textarea');
            if (textarea) {
                textarea.setCustomValidity('Comments are required before you can proceed.');
                textarea.reportValidity();
            }
            return;
        }

        this.isLoading = true;

        try {
            await processApproval({
                recordId: this.recordId,
                action: this.mode,
                comments: this.comments,
                escalateToChairperson: this.isApprove ? this.escalateToChairperson : false
            });

            const successMessage = this.isApprove
                ? (this.escalateToChairperson
                    ? 'Withdrawal Request sent to the Chairperson for second-level approval.'
                    : 'Withdrawal Request approved successfully.')
                : 'Withdrawal Request rejected successfully.';

            this.showToast(this.isApprove ? 'Success' : 'Rejected', successMessage, 'success');

            this.dispatchEvent(new CustomEvent('close'));

        } catch (error) {
            console.error('Full error object:', error);
            let message = error?.body?.message || error?.message || 'No error details received from server.';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}