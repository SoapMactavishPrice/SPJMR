import { LightningElement, api } from 'lwc';
import processApproval from '@salesforce/apex/DefermentApprovalController.processApproval';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DefermentApprovalAction extends LightningElement {

    @api recordId;
    @api mode;


    comments = '';
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

    handleClose() {
        this.dispatchEvent(
            new CustomEvent('close')
        );
    }

    async handleSubmit() {

       // Remarks are mandatory for both Approve and Reject
if (!this.comments || !this.comments.trim()) {
    const textarea =
        this.template.querySelector('lightning-textarea');

    if (textarea) {
        textarea.setCustomValidity(
            'Remarks are required before you can proceed.'
        );
        textarea.reportValidity();
    }

    return;
}

        this.isLoading = true;

        try {

            await processApproval({
                recordId: this.recordId,
                action: this.mode,
                comments: this.comments
            });

            this.showToast(
                this.isApprove ? 'Approved' : 'Rejected',
                this.isApprove
                    ? 'Deferment Request approved successfully.'
                    : 'Deferment Request rejected successfully.',
                'success'
            );

            this.dispatchEvent(
                new CustomEvent('close')
            );

                } catch (error) {

            console.error('=== APPROVAL ERROR ===');
            console.error('Full error:', error);
            console.error('Error body:', error?.body);
            console.error('Error body message:', error?.body?.message);
            console.error('Error message:', error?.message);
            console.error('Error status:', error?.status);

            let message = 'Approval failed.';

            if (error?.body?.message) {
                message = error.body.message;
            } else if (error?.message) {
                message = error.message;
            } else if (
                Array.isArray(error?.body) &&
                error.body.length > 0
            ) {
                message = error.body[0].message;
            }

            this.showToast(
                'Error',
                message,
                'error'
            );

        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}