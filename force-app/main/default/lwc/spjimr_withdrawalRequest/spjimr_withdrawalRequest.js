import { LightningElement, track } from 'lwc';
import getWithdrawalEligibility from '@salesforce/apex/StudentProfileDashboardController.getWithdrawalEligibility';
import getWithdrawalApplicantInfo from '@salesforce/apex/StudentProfileDashboardController.getWithdrawalApplicantInfo';
import submitWithdrawalRequest from '@salesforce/apex/StudentProfileDashboardController.submitWithdrawalRequest';
import getMyWithdrawalRequestStatus from '@salesforce/apex/StudentProfileDashboardController.getMyWithdrawalRequestStatus';

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB
const ALLOWED_EXTENSIONS = ['pdf', 'jpg', 'jpeg'];
const MAX_REASONS_FOR_CHOICE = 2;

// Values that trigger conditional fields.
const REASON_OTHER = 'other';
const REASON_JOINING_OTHER_INSTITUTE = 'personal';
const INSTITUTE_OTHER = 'other_institute';

const WITHDRAWAL_REASON_OPTIONS = [
    { value: 'personal', label: 'Joining other Institute' },
    { value: 'education', label: 'Want to work, before pursuing MBA education' },
    { value: 'financial', label: 'Financial constraints' },
    { value: 'academic', label: 'Want to appear for entrance exams next year to improve my scores' },
    { value: 'other', label: 'Any other' },
    { value: 'career', label: 'Got a promotion at work' }
];

const INSTITUTE_OPTIONS = [
    { value: 'iim_a', label: 'IIM A' },
    { value: 'iim_b', label: 'IIM B' },
    { value: 'iim_c', label: 'IIM C' },
    { value: 'iim_l', label: 'IIM L' },
    { value: 'iim_k', label: 'IIM K' },
    { value: 'iim_i', label: 'IIM I' },
    { value: 'fms', label: 'FMS' },
    { value: 'xlri', label: 'XLRI' },
    { value: 'isb', label: 'ISB' },
    { value: 'mdi', label: 'MDI' },
    { value: 'new_iims', label: 'New IIMs' },
    { value: 'iim_mumbai', label: 'IIM Mumbai' },
    { value: 'abroad', label: 'Going abroad for further studies' },
    { value: 'other_bschool', label: 'Joining some other B-School' },
    { value: 'not_joining_bschool', label: 'Not joining a B-School this year' },
    { value: 'none_above', label: 'None of the above' },
    { value: INSTITUTE_OTHER, label: 'Other' }
];

const REASONS_FOR_CHOICE_OPTIONS = [
    { value: 'brand', label: 'Perceived brand' },
    { value: 'ranking', label: 'Ranking' },
    { value: 'fees', label: 'Lower fees' },
    { value: 'investment', label: 'Better return on investment' },
    { value: 'placements', label: 'Better placements – type of roles being offered' },
    { value: 'flexibility', label: 'Flexibility of choosing specialization/concentration in the 2nd year' },
    { value: 'quality', label: 'Quality of teaching-learning' },
    { value: 'exchange', label: 'Extent and nature of international exchange' }
];

// TRACKER_STEPS: 'label' is the friendly display text; 'value' is the real
// Status__c picklist value it corresponds to (confirmed from the Status
// field's edit dropdown - note the actual value is 'Withdrawal', not
// 'Withdrawn'). Rejected / Rejected with Comments / Recalled are terminal
// outcomes outside this linear sequence, so they don't map to a step number -
// the status pill still shows the real status text via trackerStatusLabel.
const TRACKER_STEPS = [
    { number: 1, label: 'Applied', value: 'Applied' },
    { number: 2, label: 'Accepted (PO Review)', value: 'Accepted (PO Review)' },
    { number: 3, label: 'Clearance & Exit', value: 'Clearance & Exit' },
    { number: 4, label: 'Final Approval', value: 'Final Approval' },
    { number: 5, label: 'Withdrawn', value: 'Withdrawal' }
];

// Terminal statuses that allow a new submission when the batch window is open.
const RESUBMIT_WITHDRAWAL_STATUSES = new Set([
    'Recalled',
    'Rejected',
    'Rejected with Comments'
]);

const REJECTED_WITHDRAWAL_STATUSES = new Set([
    'Rejected',
    'Rejected with Comments'
]);

export default class Spjimr_withdrawalRequest extends LightningElement {
    // ---- Page-level loading / gating state ----
    @track isCheckingEligibility = true;
    @track isLoadingTracker = true;
    @track isEligible = false;
    @track eligibilityMessage = '';

    // ---- Tracker state (persists independently of the eligibility window) ----
    @track hasSubmittedRequest = false;
    @track trackerRequestNumber = '';
    @track trackerSubmittedDate = '';
    @track trackerName = '';
    @track trackerApplicationId = '';
    @track trackerReason = '';
    @track trackerStatusValue = '';
    @track trackerApprovedRejected = '';
    @track trackerRemark = '';
    @track currentStep = 1;

    connectedCallback() {
        this.loadEligibility();
        this.loadApplicantInfo();
        this.loadTrackerStatus();
    }

    get isLoadingAny() {
        return this.isCheckingEligibility || this.isLoadingTracker;
    }

    loadEligibility() {
        this.isCheckingEligibility = true;

        getWithdrawalEligibility()
            .then((result) => {
                this.isEligible = !!result?.isEligible;
                this.eligibilityMessage = result?.message || '';
            })
            .catch((error) => {
                console.error('getWithdrawalEligibility error', error);
                this.isEligible = false;
                this.eligibilityMessage =
                    'We were unable to verify your withdrawal window right now. '
                    + 'Please try again later or contact your Programme Office.';
            })
            .finally(() => {
                this.isCheckingEligibility = false;
            });
    }

    loadApplicantInfo() {
        getWithdrawalApplicantInfo()
            .then((info) => {
                this.studentName = info?.fullName || '';
                this.applicationId = info?.applicationId || '';
                this.spjimrEmail = info?.spjimrEmail || '';
                this.registeredEmail = info?.registeredEmail || '';
                this.rollNumber = info?.rollNumber || '';
            })
            .catch((error) => {
                console.error('getWithdrawalApplicantInfo error', error);
            });
    }

    loadTrackerStatus() {
        this.isLoadingTracker = true;

        getMyWithdrawalRequestStatus()
            .then((status) => {
                this.hasSubmittedRequest = !!status?.hasRequest;
                if (this.hasSubmittedRequest) {
                    this.trackerRequestNumber = status.requestNumber || '—';
                    this.trackerSubmittedDate = status.submittedDate || '—';
                    this.trackerName = status.studentName || '—';
                    this.trackerApplicationId = status.applicationId || '—';
                    this.trackerReason = status.reason || '—';
                    this.trackerStatusValue = status.status || '';
                    this.trackerApprovedRejected = status.approvedRejected || '—';
                    this.trackerRemark = status.remark || '—';
                    this.currentStep = this.stepNumberForStatus(this.trackerStatusValue);
                }
            })
            .catch((error) => {
                console.error('getMyWithdrawalRequestStatus error', error);
            })
            .finally(() => {
                this.isLoadingTracker = false;
            });
    }

    stepNumberForStatus(statusValue) {
        const match = TRACKER_STEPS.find((s) => s.value === statusValue);
        // Rejected / Rejected with Comments / Recalled aren't part of the
        // linear sequence - default to step 1 so the tracker still renders
        // sensibly; the status pill shows the real status text regardless.
        return match ? match.number : 1;
    }

    get canResubmitWithdrawal() {
        return this.hasSubmittedRequest
            && RESUBMIT_WITHDRAWAL_STATUSES.has(this.trackerStatusValue);
    }

    get showWithdrawalTracker() {
        return this.hasSubmittedRequest && !this.canResubmitWithdrawal;
    }

    get showWithdrawalForm() {
        if (!this.isEligible) {
            return false;
        }
        return !this.hasSubmittedRequest || this.canResubmitWithdrawal;
    }

    get showUnavailableMessage() {
        return !this.isEligible && !this.hasSubmittedRequest;
    }

    get showResubmitUnavailableMessage() {
        return this.canResubmitWithdrawal && !this.isEligible;
    }

    get isRecalledWithdrawal() {
        return this.trackerStatusValue === 'Recalled';
    }

    get isRejectedWithdrawal() {
        return REJECTED_WITHDRAWAL_STATUSES.has(this.trackerStatusValue);
    }

    get showRecalledStatusNote() {
        return this.canResubmitWithdrawal && this.isRecalledWithdrawal;
    }

    get showRejectedStatusNote() {
        return this.canResubmitWithdrawal && this.isRejectedWithdrawal;
    }

    get hasRejectionRemark() {
        const remark = (this.trackerRemark || '').trim();
        return remark.length > 0 && remark !== '—';
    }

    get rejectionRemarkDisplay() {
        return this.trackerRemark;
    }

    // ---- Form field state ----
    @track reason = '';
    @track otherReasonText = '';
    @track instituteChoice = '';
    @track otherInstituteText = '';
    @track bankDetails = '';
    @track documentFile = null;
    @track studentName = '';
    @track applicationId = '';
    @track rollNumber = '';
    @track registeredEmail = '';
    @track spjimrEmail = '';
    @track reasonsForChoice = [];
    @track otherInformation = '';

    @track isSubmitting = false;
    @track submitAttempted = false;
    @track submitSuccess = false;

    // ---- Picklist options ----
    get reasonOptions() {
        return WITHDRAWAL_REASON_OPTIONS;
    }

    get instituteOptions() {
        return INSTITUTE_OPTIONS;
    }

    get showOtherReasonField() {
        return this.reason === REASON_OTHER;
    }

    get showInstituteField() {
        return this.reason === REASON_JOINING_OTHER_INSTITUTE;
    }

    get showOtherInstituteField() {
        return this.showInstituteField && this.instituteChoice === INSTITUTE_OTHER;
    }

    // ---- Reasons for Choice: chip-based, exactly 2 ----
    get reasonsChoiceChips() {
        return this.reasonsForChoice.map((value) => {
            const match = REASONS_FOR_CHOICE_OPTIONS.find((o) => o.value === value);
            return { value, label: match ? match.label : value };
        });
    }

    get availableReasonsChoiceOptions() {
        return REASONS_FOR_CHOICE_OPTIONS.filter(
            (option) => !this.reasonsForChoice.includes(option.value)
        );
    }

    get reasonsChoiceAtMax() {
        return this.reasonsForChoice.length >= MAX_REASONS_FOR_CHOICE;
    }

    get reasonsChoiceRemainingLabel() {
        const remaining = MAX_REASONS_FOR_CHOICE - this.reasonsForChoice.length;
        return remaining > 0 ? `Select ${remaining} more...` : 'Select a reason to add...';
    }

    // ---- Validation ----
    get reasonHasError() {
        return this.submitAttempted && !this.reason;
    }

    get otherReasonHasError() {
        return this.submitAttempted && this.showOtherReasonField && !this.otherReasonText?.trim();
    }

    get instituteHasError() {
        return this.submitAttempted && this.showInstituteField && !this.instituteChoice;
    }

    get otherInstituteHasError() {
        return this.submitAttempted && this.showOtherInstituteField && !this.otherInstituteText?.trim();
    }

    get nameHasError() {
        return this.submitAttempted && !this.studentName?.trim();
    }

    get applicationIdHasError() {
        return this.submitAttempted && !this.applicationId?.trim();
    }

    get rollNumberHasError() {
        return this.submitAttempted && !this.rollNumber?.trim();
    }

    get registeredEmailHasError() {
        return this.submitAttempted && !this.registeredEmail?.trim();
    }

    get spjimrEmailHasError() {
        return this.submitAttempted && !this.spjimrEmail?.trim();
    }

    get reasonsChoiceHasError() {
        return this.submitAttempted && this.reasonsForChoice.length !== MAX_REASONS_FOR_CHOICE;
    }

    get isFormValid() {
        if (!this.reason) return false;
        if (this.showOtherReasonField && !this.otherReasonText?.trim()) return false;
        if (this.showInstituteField && !this.instituteChoice) return false;
        if (this.showOtherInstituteField && !this.otherInstituteText?.trim()) return false;
        if (!this.studentName?.trim()) return false;
        if (!this.applicationId?.trim()) return false;
        if (!this.rollNumber?.trim()) return false;
        if (!this.registeredEmail?.trim()) return false;
        if (!this.spjimrEmail?.trim()) return false;
        if (this.reasonsForChoice.length !== MAX_REASONS_FOR_CHOICE) return false;
        return true;
    }

    // ---- Dynamic classes ----
    get reasonFieldClass() {
        return this.reasonHasError ? 'reason-select reason-select_error' : 'reason-select';
    }
    get otherReasonFieldClass() {
        return this.otherReasonHasError ? 'text-input text-input_error' : 'text-input';
    }
    get instituteFieldClass() {
        return this.instituteHasError ? 'reason-select reason-select_error' : 'reason-select';
    }
    get otherInstituteFieldClass() {
        return this.otherInstituteHasError ? 'text-input text-input_error' : 'text-input';
    }

    // ---- Tracker display ----
    get trackerSteps() {
        return TRACKER_STEPS.map((step) => {
            const isActive = step.number === Number(this.currentStep);
            const isComplete = step.number < Number(this.currentStep);
            return {
                ...step,
                key: step.number,
                circleClass: this.getTrackerCircleClass(isActive, isComplete),
                labelClass: isActive ? 'step-label step-label_active' : 'step-label'
            };
        });
    }

    getTrackerCircleClass(isActive, isComplete) {
        if (isActive) return 'step-circle step-circle_active';
        if (isComplete) return 'step-circle step-circle_complete';
        return 'step-circle';
    }

    get trackerStatusLabel() {
        const match = TRACKER_STEPS.find((s) => s.number === Number(this.currentStep));
        return this.trackerStatusValue || (match ? match.label : 'Applied');
    }

    get trackerStatusBadgeLabel() {
        return this.trackerStatusLabel;
    }

    get trackerRequestNumberDisplay() {
        return this.trackerRequestNumber || '—';
    }
    get trackerSubmittedDateDisplay() {
        return this.trackerSubmittedDate || '—';
    }
    get trackerNameDisplay() {
        return this.trackerName || '—';
    }
    get trackerApplicationIdDisplay() {
        return this.trackerApplicationId || '—';
    }
    get trackerReasonDisplay() {
        return this.trackerReason || '—';
    }
    get trackerApprovedRejectedDisplay() {
        return this.trackerApprovedRejected || '—';
    }
    get trackerRemarkDisplay() {
        return this.trackerRemark || '—';
    }

    // ---- Input handlers ----
    handleReasonChange(event) {
        this.reason = event.target.value;
        this.submitSuccess = false;
        if (!this.showOtherReasonField) this.otherReasonText = '';
        if (!this.showInstituteField) {
            this.instituteChoice = '';
            this.otherInstituteText = '';
        }
    }

    handleOtherReasonChange(event) {
        this.otherReasonText = event.target.value;
    }

    handleInstituteChange(event) {
        this.instituteChoice = event.target.value;
        if (this.instituteChoice !== INSTITUTE_OTHER) {
            this.otherInstituteText = '';
        }
    }

    handleOtherInstituteChange(event) {
        this.otherInstituteText = event.target.value;
    }

    handleBankDetailsChange(event) {
        this.bankDetails = event.target.value;
    }

    handleReasonsChoiceAdd(event) {
        const value = event.target.value;
        if (!value || this.reasonsChoiceAtMax) return;
        this.reasonsForChoice = [...this.reasonsForChoice, value];
        event.target.value = '';
    }

    handleReasonsChoiceRemove(event) {
        const value = event.currentTarget.dataset.value;
        this.reasonsForChoice = this.reasonsForChoice.filter((v) => v !== value);
    }

    handleOtherInformationChange(event) {
        this.otherInformation = event.target.value;
    }

    handleFileChange(event) {
        const field = event.target.dataset.field;
        const input = event.target;
        const file = input.files && input.files[0] ? input.files[0] : null;

        if (file) {
            const validationError = this.validateFile(file);
            if (validationError) {
                alert(validationError);
                input.value = '';
                return;
            }
        }

        this.submitSuccess = false;
        if (field === 'document') {
            this.documentFile = file;
        }
    }

    handleUploadClick() {
        const fileInput = this.template.querySelector('input[type="file"][data-field="document"]');
        if (fileInput) fileInput.click();
    }

    validateFile(file) {
        const ext = file.name.split('.').pop().toLowerCase();
        if (!ALLOWED_EXTENSIONS.includes(ext)) {
            return 'Only .pdf, .jpg and .jpeg files are allowed.';
        }
        if (file.size > MAX_FILE_SIZE_BYTES) {
            return 'File size must not exceed 10 MB.';
        }
        return null;
    }

    // ---- Label lookups (send Salesforce-matching label text, not internal slugs) ----
    getReasonLabel(value) {
        const match = WITHDRAWAL_REASON_OPTIONS.find((option) => option.value === value);
        return match ? match.label : value;
    }

    getInstituteLabel(value) {
        const match = INSTITUTE_OPTIONS.find((option) => option.value === value);
        return match ? match.label : value;
    }

    getReasonsChoiceLabel(value) {
        const match = REASONS_FOR_CHOICE_OPTIONS.find((option) => option.value === value);
        return match ? match.label : value;
    }

    // ---- Submit ----
    handleSubmit() {
        if (!this.showWithdrawalForm) return;

        this.submitAttempted = true;
        this.submitSuccess = false;

        if (!this.isFormValid) return;

        this.isSubmitting = true;

        if (this.documentFile) {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = (reader.result || '').split(',')[1] || '';
                this.doSubmit(base64, this.documentFile.name);
            };
            reader.onerror = () => {
                this.isSubmitting = false;
                alert('We could not read the selected file. Please try again.');
            };
            reader.readAsDataURL(this.documentFile);
        } else {
            this.doSubmit(null, null);
        }
    }

    doSubmit(documentBase64, documentFileName) {
        const reasonLabel = this.getReasonLabel(this.reason);
        const instituteLabel = this.showInstituteField ? this.getInstituteLabel(this.instituteChoice) : null;
        const reasonsForChoiceLabels = this.reasonsForChoice.map((v) => this.getReasonsChoiceLabel(v));

        submitWithdrawalRequest({
            reasonLabel,
            otherReasonText: this.showOtherReasonField ? this.otherReasonText : null,
            instituteLabel,
            otherInstituteText: this.showOtherInstituteField ? this.otherInstituteText : null,
            bankDetails: this.bankDetails,
            applicationId: this.applicationId,
            rollNumber: this.rollNumber,
            registeredEmail: this.registeredEmail,
            spjimrEmail: this.spjimrEmail,
            reasonsForChoiceLabels,
            otherInformation: this.otherInformation,
            documentBase64,
            documentFileName
        })
            .then((result) => {
                this.isSubmitting = false;
                if (result?.isSuccess) {
                    this.submitSuccess = true;
                    this.resetForm();
                    this.loadTrackerStatus();
                } else {
                    console.error('submitWithdrawalRequest errorDetail:', result?.errorDetail);
                    const detail = result?.errorDetail ? `\n\n(Detail: ${result.errorDetail})` : '';
                    alert((result?.message || 'Failed to submit withdrawal request.') + detail);
                }
            })
            .catch((error) => {
                this.isSubmitting = false;
                console.error('submitWithdrawalRequest error', error);
                alert('We were unable to submit your withdrawal request. Please try again.');
            });
    }

    // ---- Reset form ----
    // Note: studentName/applicationId/rollNumber/registeredEmail/spjimrEmail are
    // auto-populated and read-only, so they are intentionally NOT cleared here.
    resetForm() {
        this.reason = '';
        this.otherReasonText = '';
        this.instituteChoice = '';
        this.otherInstituteText = '';
        this.bankDetails = '';
        this.documentFile = null;
        this.reasonsForChoice = [];
        this.otherInformation = '';
        this.submitAttempted = false;

        const fileInputs = this.template.querySelectorAll('input[type="file"]');
        fileInputs.forEach((input) => {
            input.value = '';
        });
    }
}