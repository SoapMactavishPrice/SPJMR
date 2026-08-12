import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getCurrentUserRole from '@salesforce/apex/LeaveApprovalActionController.getCurrentUserRole';
import processLeaveAction from '@salesforce/apex/LeaveApprovalActionController.processLeaveAction';

const APPROVE = 'APPROVE';
const REJECT = 'REJECT';
const INCOMPLETE = 'INCOMPLETE';
const VALID_MODES = [APPROVE, REJECT, INCOMPLETE];

const ROLE_PROGRAMME_OFFICE = 'programme office';
const ROLE_MANAGER = 'manager';
const ROLE_DEPUTY = 'deputy chairperson';

/**
 * Shared approval form for the Leave Application quick actions.
 * is
 * This component never guesses which action launched it. A screen quick action
 * cannot know that — the platform only injects recordId and objectApiName — so
 * the wrapper component (leaveApprovalApprove / leaveApprovalReject /
 * leaveApprovalIncomplete) passes `mode` in explicitly.
 *
 * If the mode or the approval stage is not one we recognise, the form shows an
 * error and refuses to submit. It never falls back to a default decision.
 */
export default class LeaveApprovalAction extends LightningElement {

    _recordId;
    _mode;
    _initDone = false;

    // recordId and mode arrive independently and in no guaranteed order, so
    // both setters funnel through initIfReady() rather than one driving init.
    @api
    set recordId(value) {
        this._recordId = value;
        this.initIfReady();
    }
    get recordId() {
        return this._recordId;
    }

    @api
    set mode(value) {
        this._mode = typeof value === 'string' ? value.trim().toUpperCase() : undefined;
        this.initIfReady();
    }
    get mode() {
        return this._mode;
    }

    role;
    roleLoaded = false;
    loadError;

    remarks = '';
    routeToDeputy = false;
    eligibleForMakeup = false;
    notEligibleForMakeup = false;
    isLoading = false;

    initIfReady() {
        if (this._initDone || !this._recordId || !this.isModeValid) {
            return;
        }
        this._initDone = true;
        this.loadRole();
    }

    loadRole() {
        getCurrentUserRole({ leaveId: this._recordId })
            .then(result => {
                this.role = result;
                this.roleLoaded = true;
            })
            .catch(error => {
                this.loadError =
                    error?.body?.message || 'Unable to load the approval stage for this record.';
            });
    }

    // ================= MODE =================
    get isModeValid() {
        return VALID_MODES.includes(this._mode);
    }
    get isApprove() {
        return this._mode === APPROVE;
    }
    get isReject() {
        return this._mode === REJECT;
    }
    get isIncomplete() {
        return this._mode === INCOMPLETE;
    }

    // ================= ROLE =================
    get normalisedRole() {
        return typeof this.role === 'string' ? this.role.trim().toLowerCase() : '';
    }
    get isProgrammeOffice() {
        return this.normalisedRole === ROLE_PROGRAMME_OFFICE;
    }
    get isManager() {
        return this.normalisedRole === ROLE_MANAGER;
    }
    get isDeputy() {
        return this.normalisedRole === ROLE_DEPUTY;
    }

    // ================= UI CONDITIONS =================
    get showIncompleteUI() {
        return this.isIncomplete;
    }
    get showPOApproveUI() {
        return this.isProgrammeOffice && this.isApprove;
    }
    get showPORejectUI() {
        return this.isProgrammeOffice && this.isReject;
    }
    get showManagerApproveUI() {
        return this.isManager && this.isApprove;
    }
    get showDeputyApproveUI() {
        return this.isDeputy && this.isApprove;
    }
    get showManagerRejectUI() {
        return (this.isManager || this.isDeputy) && this.isReject;
    }
    get showMakeupChoice() {
        return this.showManagerApproveUI || this.showDeputyApproveUI;
    }

    /** True only when mode + approval stage map to a decision we understand. */
    get hasApplicableUI() {
        if (!this.isModeValid) {
            return false;
        }
        if (this.isIncomplete) {
            return true;
        }
        return (
            this.showPOApproveUI ||
            this.showPORejectUI ||
            this.showManagerApproveUI ||
            this.showDeputyApproveUI ||
            this.showManagerRejectUI
        );
    }

    get errorMessage() {
        if (!this.isModeValid) {
            return 'This action could not be identified, so it cannot be processed. Close the window and try again.';
        }
        if (this.loadError) {
            return this.loadError;
        }
        if (this.roleLoaded && !this.hasApplicableUI) {
            const stage = this.role ? ` (current stage: ${this.role})` : '';
            return `This action is not available at the current approval stage${stage}.`;
        }
        return undefined;
    }
    get hasError() {
        return !!this.errorMessage;
    }

    get disableEligible() {
        return this.notEligibleForMakeup;
    }
    get disableNotEligible() {
        return this.eligibleForMakeup;
    }

    get submitLabel() {
        if (this.isIncomplete) {
            return 'Mark Incomplete';
        }
        if (this.isReject) {
            return 'Reject';
        }
        return 'Approve';
    }

    get isSubmitDisabled() {
        return this.isLoading || !this.roleLoaded || this.hasError || !this.hasApplicableUI;
    }

    /**
     * The decision string sent to Apex. Returns undefined for any combination we
     * do not recognise, so an unknown state can never resolve to 'Approved'.
     */
    get decision() {
        if (this.isIncomplete) {
            return 'INCOMPLETE';
        }
        if (this.isReject) {
            return this.notEligibleForMakeup ? 'Not Eligible for Makeup' : 'Not Approved';
        }
        if (this.isApprove) {
            if (this.eligibleForMakeup) {
                return 'Eligible for Makeup';
            }
            if (this.notEligibleForMakeup) {
                return 'Not Eligible for Makeup';
            }
            return 'Approved';
        }
        return undefined;
    }

    get actionType() {
        if (this.isIncomplete) {
            return 'Incomplete';
        }
        return this.isReject ? 'Reject' : 'Approve';
    }

    get successMessage() {
        if (this.isIncomplete) {
            return 'Marked as Incomplete';
        }
        if (this.isReject) {
            return 'Application rejected';
        }
        return 'Application approved';
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
    }

    handleRemarks(event) {
        this.remarks = event.target.value;
    }

    handleCancel() {
        this.close();
    }

    handleSubmit() {
        if (this.isLoading) {
            return;
        }
        if (!this._recordId) {
            this.toast('Error', 'Record Id is missing', 'error');
            return;
        }

        const decision = this.decision;
        if (!this.hasApplicableUI || !decision) {
            this.toast(
                'Error',
                'This action could not be identified, so nothing was submitted.',
                'error'
            );
            return;
        }
        if (!this.remarks || !this.remarks.trim()) {
            this.toast('Error', 'Remarks are required', 'error');
            return;
        }

        this.isLoading = true;

        processLeaveAction({
            leaveId: this._recordId,
            decision,
            actionType: this.actionType,
            routeToDeputy: this.isApprove ? this.routeToDeputy : false,
            remarks: this.remarks
        })
            .then(() => {
                this.toast('Success', this.successMessage, 'success');
                // Refresh the record in place instead of reloading the browser.
                return notifyRecordUpdateAvailable([{ recordId: this._recordId }]).catch(
                    () => undefined
                );
            })
            .then(() => {
                this.close();
            })
            .catch(error => {
                this.toast('Error', error?.body?.message || 'Processing failed', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}