import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getApproverActionVisibility from '@salesforce/apex/WithdrawalApprovalController.getApproverActionVisibility';
import isCurrentUserApprover from '@salesforce/apex/WithdrawalApprovalController.isCurrentUserApprover';
import processApproval from '@salesforce/apex/WithdrawalApprovalController.processApproval';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class WithdrawalApprovalPanel extends LightningElement {

    @api recordId;

    @track comments = '';
    @track escalateToChairperson = false;
    @track isLoading = false;
    @track panelOpen = false;
    @track isApproveAction = false;
    @track isRejectAction = false;
    @track isRecallAction = false;
    @track showEscalateOption = false;

    @track showApprove = false;
    @track showReject = false;
    @track showRecall = false;

    _wiredVisibility;

    @wire(getApproverActionVisibility, { recordId: '$recordId' })
    wiredVisibility(result) {
        this._wiredVisibility = result;
        const { data, error } = result;
        if (data) {
            this.showApprove = data.showApprove === true;
            this.showReject = data.showReject === true;
            this.showRecall = data.showRecall === true;
            this.showEscalateOption = data.showEscalateOption === true;
        } else if (error) {
            this.showApprove = false;
            this.showReject = false;
            this.showRecall = false;
            this.showEscalateOption = false;
        }
    }

    get showPageButtons() {
        return !this.panelOpen && (this.showApprove || this.showReject || this.showRecall);
    }

    get panelTitle() {
        if (this.isRecallAction) {
            return 'Withdrawal Recall';
        }
        return 'Withdrawal Approval';
    }

    get showActionPanel() {
        return this.panelOpen;
    }

    handleSelectApprove() {
        this.openPanel('APPROVE');
    }

    handleSelectReject() {
        this.openPanel('REJECT');
    }

    handleSelectRecall() {
        this.openPanel('RECALL');
    }

    openPanel(action) {
        this.isApproveAction = action === 'APPROVE';
        this.isRejectAction = action === 'REJECT';
        this.isRecallAction = action === 'RECALL';
        this.panelOpen = true;
        this.comments = '';
        this.escalateToChairperson = false;
        this.verifyApprover();
    }

    handleCancelPanel() {
        this.panelOpen = false;
        this.isApproveAction = false;
        this.isRejectAction = false;
        this.isRecallAction = false;
        this.comments = '';
        this.escalateToChairperson = false;
        if (this._wiredVisibility) {
            refreshApex(this._wiredVisibility);
        }
    }

    verifyApprover() {
        this.isLoading = true;
        isCurrentUserApprover({ recordId: this.recordId })
            .then((allowed) => {
                if (!allowed) {
                    this.showToast('Error', 'You are not a current approver for this withdrawal request.', 'error');
                    this.handleCancelPanel();
                }
            })
            .catch((error) => {
                const msg = error?.body?.message || 'Unable to verify approver access';
                this.showToast('Error', msg, 'error');
                this.handleCancelPanel();
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleComments(event) {
        this.comments = event.target.value;
    }

    handleEscalateChange(event) {
        this.escalateToChairperson = event.target.checked;
    }

    async handleSubmit() {
        if (!this.comments || !this.comments.trim()) {
            const textarea = this.template.querySelector('lightning-textarea');
            if (textarea) {
                const message = this.isRecallAction
                    ? 'Recall remarks are required before you can proceed.'
                    : 'Comments are required before you can proceed.';
                textarea.setCustomValidity(message);
                textarea.reportValidity();
            }
            return;
        }

        this.isLoading = true;
        let action = 'REJECT';
        if (this.isApproveAction) {
            action = 'APPROVE';
        } else if (this.isRecallAction) {
            action = 'RECALL';
        }

        try {
            await processApproval({
                recordId: this.recordId,
                action,
                comments: this.comments,
                escalateToChairperson: this.isApproveAction ? this.escalateToChairperson : false
            });

            let successMessage = 'Withdrawal Request rejected successfully.';
            let toastTitle = 'Rejected';
            if (this.isApproveAction) {
                successMessage = this.escalateToChairperson
                    ? 'Withdrawal Request sent to the Chairperson for second-level approval.'
                    : 'Withdrawal Request approved successfully.';
                toastTitle = 'Success';
            } else if (this.isRecallAction) {
                successMessage = 'Withdrawal Request recalled successfully.';
                toastTitle = 'Recalled';
            }

            this.showToast(toastTitle, successMessage, 'success');
            this.handleCancelPanel();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                window.location.reload();
            }, 500);
        } catch (error) {
            const message = error?.body?.message || error?.message || 'Processing failed';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}