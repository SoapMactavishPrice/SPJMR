import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getCurrentUserRole from '@salesforce/apex/LeaveApprovalActionController.getCurrentUserRole';
import isCurrentUserApprover from '@salesforce/apex/LeaveApprovalActionController.isCurrentUserApprover';
import getApproverActionVisibility from '@salesforce/apex/LeaveApprovalActionController.getApproverActionVisibility';
import processLeaveAction from '@salesforce/apex/LeaveApprovalActionController.processLeaveAction';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class LeaveApprovalActionPanel extends LightningElement {

    _recordId;

    @api
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.initializeComponent();
        }
    }

    get recordId() {
        return this._recordId;
    }

    @api actionName;

    @track role;
    @track routeToDeputy = false;
    @track remarks = '';
    @track isLoading = false;
    @track isAuthorized = false;

    @track eligibleForMakeup = false;
    @track notEligibleForMakeup = false;
    @track isIncompleteAction = false;
    @track isApproveAction = false;
    @track isRejectAction = false;

    @track isPageMode = false;
    @track showApprove = false;
    @track showReject = false;
    @track showIncomplete = false;
    @track panelOpen = false;

    _wiredVisibility;

    @wire(getApproverActionVisibility, { leaveId: '$recordId' })
    wiredVisibility(result) {
        this._wiredVisibility = result;
        const { data, error } = result;
        if (data) {
            this.showApprove = data.showApprove === true;
            this.showReject = data.showReject === true;
            this.showIncomplete = data.showIncomplete === true;
        } else if (error) {
            this.showApprove = false;
            this.showReject = false;
            this.showIncomplete = false;
        }
    }

    get showPageButtons() {
        return this.isPageMode && !this.panelOpen && (this.showApprove || this.showReject || this.showIncomplete);
    }

    get showActionPanel() {
        return this.isPageMode && this.panelOpen && this.isAuthorized;
    }

    initializeComponent() {
        this.isApproveAction = this.actionName === 'Approve';
        this.isRejectAction = this.actionName === 'Reject';
        this.isIncompleteAction = this.actionName === 'Mark_Incomplete';

        const url = window.location.href.toLowerCase();
        if (url.includes('approve')) {
            this.isApproveAction = true;
        }
        if (url.includes('reject')) {
            this.isRejectAction = true;
        }
        if (url.includes('mark_incomplete') || url.includes('/incomplete')) {
            this.isIncompleteAction = true;
        }

        // Record page (no quick-action context) → show gated buttons via Apex
        if (!this.isApproveAction && !this.isRejectAction && !this.isIncompleteAction) {
            this.isPageMode = true;
            this.panelOpen = false;
            return;
        }

        this.isPageMode = false;
        this.verifyApproverThenLoadRole();
    }

    handleSelectApprove() {
        this.openPanel('Approve');
    }

    handleSelectReject() {
        this.openPanel('Reject');
    }

    handleSelectIncomplete() {
        this.openPanel('Mark_Incomplete');
    }

    openPanel(action) {
        this.isApproveAction = action === 'Approve';
        this.isRejectAction = action === 'Reject';
        this.isIncompleteAction = action === 'Mark_Incomplete';
        this.actionName = action;
        this.panelOpen = true;
        this.remarks = '';
        this.routeToDeputy = false;
        this.eligibleForMakeup = false;
        this.notEligibleForMakeup = false;
        this.verifyApproverThenLoadRole();
    }

    handleCancelPanel() {
        this.panelOpen = false;
        this.isApproveAction = false;
        this.isRejectAction = false;
        this.isIncompleteAction = false;
        this.remarks = '';
        if (this._wiredVisibility) {
            refreshApex(this._wiredVisibility);
        }
    }

    verifyApproverThenLoadRole() {
        this.isLoading = true;
        isCurrentUserApprover({ leaveId: this.recordId })
            .then((allowed) => {
                if (!allowed) {
                    this.isAuthorized = false;
                    this.showToast('Error', 'You are not a current approver for this leave application.', 'error');
                    if (this.isPageMode) {
                        this.panelOpen = false;
                    } else {
                        this.dispatchEvent(new CloseActionScreenEvent());
                    }
                    return null;
                }
                this.isAuthorized = true;
                return getCurrentUserRole({ leaveId: this.recordId });
            })
            .then((result) => {
                if (result !== null && result !== undefined) {
                    this.role = result;
                }
            })
            .catch((error) => {
                console.error(error);
                let msg = error?.body?.message || 'Unable to verify approver access';
                this.showToast('Error', msg, 'error');
                if (this.isPageMode) {
                    this.panelOpen = false;
                } else {
                    this.dispatchEvent(new CloseActionScreenEvent());
                }
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get isProgrammeOffice() {
        return this.role && this.role.toLowerCase() === 'programme office';
    }

    get isManager() {
        return this.role && this.role.toLowerCase() === 'manager';
    }

    get isDeputy() {
        return this.role && this.role.toLowerCase() === 'deputy chairperson';
    }

    get showPOApproveUI() {
        return this.isProgrammeOffice && this.isApproveAction;
    }

    get showPORejectUI() {
        return this.isProgrammeOffice && this.isRejectAction;
    }

    get showManagerApproveUI() {
        return this.isManager && this.isApproveAction;
    }

    get showDeputyApproveUI() {
        return this.isDeputy && this.isApproveAction;
    }

    get showManagerRejectUI() {
        return (this.isManager || this.isDeputy) && this.isRejectAction;
    }

    get disableEligible() {
        return this.notEligibleForMakeup;
    }

    get disableNotEligible() {
        return this.eligibleForMakeup;
    }

    get disableDeputy() {
        return false;
    }

    get showIncompleteUI() {
        return this.isIncompleteAction;
    }

    handleEligible(event) {
        this.eligibleForMakeup = event.target.checked;
        if (this.eligibleForMakeup) {
            this.notEligibleForMakeup = false;
        }
    }

    handleNotEligible(event) {
        this.notEligibleForMakeup = event.target.checked;
        if (this.notEligibleForMakeup) {
            this.eligibleForMakeup = false;
        }
    }

    handleDeputy(event) {
        this.routeToDeputy = event.target.checked;
        if (this.isRejectAction) {
            this.routeToDeputy = false;
        }
    }

    handleRemarks(event) {
        this.remarks = event.target.value;
    }

    closeAfterSuccess() {
        if (this.isPageMode) {
            this.panelOpen = false;
            this.isApproveAction = false;
            this.isRejectAction = false;
            this.isIncompleteAction = false;
            if (this._wiredVisibility) {
                refreshApex(this._wiredVisibility);
            }
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                window.location.reload();
            }, 500);
        } else {
            this.dispatchEvent(new CloseActionScreenEvent());
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                window.location.reload();
            }, 500);
        }
    }

    handleProcess() {
        if (this.isLoading) {
            return;
        }
        if (!this.recordId) {
            this.showToast('Error', 'RecordId missing', 'error');
            return;
        }
        if (!this.remarks) {
            this.showToast('Error', 'Remarks are required', 'error');
            return;
        }

        this.isLoading = true;
        let finalDecision;

        if (this.isRejectAction) {
            if (this.notEligibleForMakeup) {
                finalDecision = 'Not Eligible for Makeup';
            } else {
                finalDecision = 'Not Approved';
            }
        } else if (this.eligibleForMakeup) {
            finalDecision = 'Eligible for Makeup';
        } else if (this.notEligibleForMakeup) {
            finalDecision = 'Not Eligible for Makeup';
        } else {
            finalDecision = 'Approved';
        }

        processLeaveAction({
            leaveId: this.recordId,
            decision: finalDecision,
            actionType: this.isRejectAction ? 'Reject' : 'Approve',
            routeToDeputy: this.routeToDeputy,
            remarks: this.remarks
        })
            .then(() => {
                this.showToast('Success', 'Processed successfully', 'success');
                this.closeAfterSuccess();
            })
            .catch((error) => {
                console.error(error);
                let msg = error?.body?.message || 'Processing failed';
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleIncompleteAction() {
        if (this.isLoading) return;
        if (!this.recordId) {
            this.showToast('Error', 'RecordId missing', 'error');
            return;
        }
        if (!this.remarks) {
            this.showToast('Error', 'Remarks are required', 'error');
            return;
        }

        this.isLoading = true;
        processLeaveAction({
            leaveId: this.recordId,
            decision: 'INCOMPLETE',
            routeToDeputy: false,
            remarks: this.remarks
        })
            .then(() => {
                this.showToast('Success', 'Marked as Incomplete', 'success');
                this.closeAfterSuccess();
            })
            .catch((error) => {
                let msg = error?.body?.message || 'Processing failed';
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}