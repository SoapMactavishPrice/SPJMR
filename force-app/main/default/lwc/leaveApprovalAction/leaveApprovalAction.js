import { LightningElement, api, track } from 'lwc';
import getCurrentUserRole from '@salesforce/apex/LeaveApprovalActionController.getCurrentUserRole';
import processLeaveAction from '@salesforce/apex/LeaveApprovalActionController.processLeaveAction';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class LeaveApprovalActionPanel extends LightningElement {

    // ================= RECORD ID =================
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

    // ================= ACTION NAME =================
    @api actionName;

    // ================= TRACK VARIABLES =================
    @track role;
    @track routeToDeputy = false;
    @track remarks = '';
    @track isLoading = false;

    @track eligibleForMakeup = false;
    @track notEligibleForMakeup = false;
    @track isIncompleteAction = false;
    @track isApproveAction = false;
    @track isRejectAction = false;

    // ================= INIT =================
    initializeComponent() {

        // Preferred method (safe)
        this.isApproveAction = this.actionName === 'Approve';
        this.isRejectAction = this.actionName === 'Reject';
        this.isIncompleteAction = this.actionName === 'Mark_Incomplete';
        

        // Fallback (URL-based)
        const url = window.location.href.toLowerCase();

        if (url.includes('approve')) {
            this.isApproveAction = true;
        }

        if (url.includes('reject')) {
            this.isRejectAction = true;
        }
        if (url.includes('mark_incomplete') || url.includes('incomplete')) {
            this.isIncompleteAction = true;
        }
        this.loadRole();
    }

    // ================= LOAD ROLE =================
    loadRole() {
        getCurrentUserRole({ leaveId: this.recordId })
            .then(result => {
                this.role = result;
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error', 'Unable to load role', 'error');
            });
    }

    // ================= ROLE CHECKS =================
    get isProgrammeOffice() {
        return this.role && this.role.toLowerCase() === 'programme office';
    }

    get isManager() {
        return this.role && this.role.toLowerCase() === 'manager';
    }

    get isDeputy() {
        return this.role && this.role.toLowerCase() === 'deputy chairperson';
    }

    // ================= UI CONDITIONS =================
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
        return false; // or based on your logic
    }
    get showIncompleteUI() {
        return this.isIncompleteAction;
    }
    // ================= HANDLERS =================
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
    
        // ❌ Prevent deputy routing on reject
        if (this.isRejectAction) {
            this.routeToDeputy = false;
        }
    }
    handleRemarks(event) {
        this.remarks = event.target.value;
    }

    // ================= PROCESS =================
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
        
        }
        else if (this.eligibleForMakeup) {
            finalDecision = 'Eligible for Makeup';
        }
        else if (this.notEligibleForMakeup) {
            finalDecision = 'Not Eligible for Makeup';
        }
        else {
            finalDecision = 'Approved';
        }

        console.log('Final Decision:', finalDecision);

        processLeaveAction({
            leaveId: this.recordId,
            decision: finalDecision,
            actionType: this.isRejectAction ? 'Reject' : 'Approve', 
            routeToDeputy: this.routeToDeputy,
            remarks: this.remarks
        })
        .then(() => {
            this.showToast('Success', 'Processed successfully', 'success');

            this.dispatchEvent(new CloseActionScreenEvent());

            setTimeout(() => {
                window.location.reload();
            }, 500);
        })
        .catch(error => {
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
    
            this.dispatchEvent(new CloseActionScreenEvent());
    
            setTimeout(() => {
                window.location.reload();
            }, 500);
        })
        .catch(error => {
            let msg = error?.body?.message || 'Processing failed';
            this.showToast('Error', msg, 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    // ================= TOAST =================
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}