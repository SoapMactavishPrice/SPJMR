import { LightningElement, api, track } from 'lwc';
import getApproverActionVisibility from '@salesforce/apex/DefermentApprovalActionController.getApproverActionVisibility';
import processDefermentAction from '@salesforce/apex/DefermentApprovalActionController.processDefermentAction';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class DefermentApproval extends LightningElement {

    @api recordId;

    @track currentRole;
    @track isApprover = false;
    @track showApprove = false;
    @track showReject = false;

    remarks = '';
    isReject = false;
    isLoading = false;

    connectedCallback() {
        this.loadApprovalDetails();
    }

    async loadApprovalDetails() {

        if (!this.recordId) {
            return;
        }

        this.isLoading = true;

        try {

            const result =
                await getApproverActionVisibility({
                    defermentId: this.recordId
                });

            this.isApprover = result.isApprover;
            this.showApprove = result.showApprove;
            this.showReject = result.showReject;
            this.currentRole = result.currentRole;

        } catch (error) {

            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );

        } finally {

            this.isLoading = false;
        }
    }

    handleRemarksChange(event) {
        this.remarks = event.target.value;
    }

    handleApprove() {

        this.isReject = false;

        this.processAction('Approve');
    }

    handleReject() {

        this.isReject = true;

        if (!this.remarks || !this.remarks.trim()) {

            this.showToast(
                'Validation Error',
                'Please enter remarks before rejecting the Deferment Request.',
                'error'
            );

            return;
        }

        this.processAction('Reject');
    }

    async processAction(action) {

        this.isLoading = true;

        try {

            await processDefermentAction({
                defermentId: this.recordId,
                actionType: action,
                remarks: this.remarks
            });

            this.showToast(
                'Success',
                action === 'Approve'
                    ? 'Deferment Request approved successfully.'
                    : 'Deferment Request rejected successfully.',
                'success'
            );

            /*
             * After the action:
             *
             * Chairperson Approve
             *       ↓
             * Dean/AD becomes current approver
             *
             * Chairperson Reject
             *       ↓
             * Deferment Form Enabled
             *
             * Dean/AD Reject
             *       ↓
             * Deferment Form Enabled
             */

            this.remarks = '';
            this.isReject = false;

            await this.loadApprovalDetails();

        } catch (error) {

            this.showToast(
                'Error',
                this.getErrorMessage(error),
                'error'
            );

        } finally {

            this.isLoading = false;
        }
    }

    getErrorMessage(error) {

        if (error?.body?.message) {
            return error.body.message;
        }

        if (error?.message) {
            return error.message;
        }

        return 'An unexpected error occurred.';
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