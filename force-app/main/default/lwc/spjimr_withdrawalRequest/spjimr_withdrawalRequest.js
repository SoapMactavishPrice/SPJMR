import { LightningElement, track } from 'lwc';
import getWithdrawalEligibility from '@salesforce/apex/StudentProfileDashboardController.getWithdrawalEligibility';

// TODO: Uncomment once Apex is available.
// import submitWithdrawalRequest from '@salesforce/apex/WithdrawalRequestController.submitWithdrawalRequest';

const MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024; // 10 MB
const ALLOWED_EXTENSIONS = ['pdf', 'jpg', 'jpeg'];
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_REASONS_FOR_CHOICE = 2;

const WITHDRAWAL_REASON_OPTIONS = [
    { value: 'personal', label: 'Joining other Institute' },
    { value: 'education', label: 'Want to work, before pursuing MBA education' },
    { value: 'financial', label: 'Financial constraints' },
    { value: 'academic', label: 'Want to appear for entrance exams next year to improve my scores' },
    { value: 'other', label: 'Any other' },
    { value: 'career', label: 'Got a promotion at work' }
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

const TRACKER_STEPS = [
    { number: 1, label: 'Applied' },
    { number: 2, label: 'Accepted (PO Review)' },
    { number: 3, label: 'Clearance & Exit' },
    { number: 4, label: 'Final Approval' },
    { number: 5, label: 'Withdrawn' }
];

const TRACKER_STATUS_LABELS = {
    1: 'Applied',
    2: 'Accepted (PO Review)',
    3: 'Clearance & Exit',
    4: 'Final Approval',
    5: 'Withdrawn'
};

export default class Spjimr_withdrawalRequest extends LightningElement {
    // ---- Eligibility / withdrawal window state ----
    @track isCheckingEligibility = true;
    @track isEligible = false;
    @track eligibilityMessage = '';

    connectedCallback() {
        this.loadEligibility();
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

    get showWithdrawalForm() {
        return !this.isCheckingEligibility && this.isEligible;
    }

    get showUnavailableMessage() {
        return !this.isCheckingEligibility && !this.isEligible;
    }

    // ---- Form field state ----
    @track reason = '';
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

    @track currentStep = 0;
    @track requestNumber = '';
    @track submittedDate = '';
    @track submittedName = '';
    @track submittedApplicationId = '';
    @track submittedReason = '';

    // ---- Picklist options ----
    get reasonOptions() {
        return WITHDRAWAL_REASON_OPTIONS;
    }

    get reasonsChoiceOptions() {
        return REASONS_FOR_CHOICE_OPTIONS.map((option) => ({
            ...option,
            isSelected: this.reasonsForChoice.includes(option.value)
        }));
    }

    // ---- Validation ----
    get reasonHasError() {
        return this.submitAttempted && !this.reason;
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
        return (
            this.submitAttempted &&
            (!this.registeredEmail?.trim() || !EMAIL_REGEX.test(this.registeredEmail.trim()))
        );
    }

    get registeredEmailErrorMessage() {
        return this.registeredEmail?.trim()
            ? 'Please enter a valid email address.'
            : 'This field is required.';
    }

    get spjimrEmailHasError() {
        return (
            this.submitAttempted &&
            (!this.spjimrEmail?.trim() || !EMAIL_REGEX.test(this.spjimrEmail.trim()))
        );
    }

    get spjimrEmailErrorMessage() {
        return this.spjimrEmail?.trim()
            ? 'Please enter a valid email address.'
            : 'This field is required.';
    }

    get reasonsChoiceHasError() {
        return this.reasonsForChoice.length > MAX_REASONS_FOR_CHOICE;
    }

    get isFormValid() {
        if (!this.reason) {
            return false;
        }
        if (!this.studentName?.trim()) {
            return false;
        }
        if (!this.applicationId?.trim()) {
            return false;
        }
        if (!this.rollNumber?.trim()) {
            return false;
        }
        if (!this.registeredEmail?.trim() || !EMAIL_REGEX.test(this.registeredEmail.trim())) {
            return false;
        }
        if (!this.spjimrEmail?.trim() || !EMAIL_REGEX.test(this.spjimrEmail.trim())) {
            return false;
        }
        if (this.reasonsChoiceHasError) {
            return false;
        }
        return true;
    }

    // ---- Dynamic classes ----
    get reasonFieldClass() {
        return this.reasonHasError
            ? 'reason-select reason-select_error'
            : 'reason-select';
    }

    get nameFieldClass() {
        return this.nameHasError
            ? 'text-input text-input_error'
            : 'text-input';
    }

    get applicationIdFieldClass() {
        return this.applicationIdHasError
            ? 'text-input text-input_error'
            : 'text-input';
    }

    get rollNumberFieldClass() {
        return this.rollNumberHasError
            ? 'text-input text-input_error'
            : 'text-input';
    }

    get registeredEmailFieldClass() {
        return this.registeredEmailHasError
            ? 'text-input text-input_error'
            : 'text-input';
    }

    get spjimrEmailFieldClass() {
        return this.spjimrEmailHasError
            ? 'text-input text-input_error'
            : 'text-input';
    }

    // ---- Tracker ----
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
        return TRACKER_STATUS_LABELS[Number(this.currentStep)] || 'Not yet applied';
    }

    get trackerStatusBadgeLabel() {
        return this.currentStep > 0 ? this.trackerStatusLabel : '—';
    }

    get trackerRequestNumberDisplay() {
        return this.requestNumber || '—';
    }
    get trackerSubmittedDateDisplay() {
        return this.submittedDate || '—';
    }
    get trackerNameDisplay() {
        return this.submittedName || '—';
    }
    get trackerApplicationIdDisplay() {
        return this.submittedApplicationId || '—';
    }
    get trackerReasonDisplay() {
        return this.submittedReason || '—';
    }
    get trackerApprovedRejectedDisplay() {
        return this.currentStep > 0 ? 'Pending review' : '—';
    }
    get trackerRemarkDisplay() {
        return '—';
    }

    // ---- Input handlers ----
    handleReasonChange(event) {
        this.reason = event.target.value;
        this.submitSuccess = false;
    }

    handleBankDetailsChange(event) {
        this.bankDetails = event.target.value;
    }

    handleNameChange(event) {
        this.studentName = event.target.value;
        this.submitSuccess = false;
    }

    handleApplicationIdChange(event) {
        this.applicationId = event.target.value;
        this.submitSuccess = false;
    }

    handleRollNumberChange(event) {
        this.rollNumber = event.target.value;
        this.submitSuccess = false;
    }

    handleRegisteredEmailChange(event) {
        this.registeredEmail = event.target.value;
        this.submitSuccess = false;
    }

    handleSpjimrEmailChange(event) {
        this.spjimrEmail = event.target.value;
        this.submitSuccess = false;
    }

    handleReasonsChoiceChange(event) {
        const selected = Array.from(event.target.selectedOptions).map(
            (opt) => opt.value
        );

        if (selected.length > MAX_REASONS_FOR_CHOICE) {
            alert(`You can select a maximum of ${MAX_REASONS_FOR_CHOICE} reasons.`);
            // Revert to previous valid selection.
            this.reasonsForChoice = this.reasonsForChoice.slice(0, MAX_REASONS_FOR_CHOICE);
            return;
        }

        this.reasonsForChoice = selected;
    }

    handleOtherInformationChange(event) {
        this.otherInformation = event.target.value;
    }

    handleFileChange(event) {
        const field = event.target.dataset.field;
        const input = event.target;
        const file = input.files && input.files[0]
            ? input.files[0]
            : null;

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
        const fileInput = this.template.querySelector(
            'input[type="file"][data-field="document"]'
        );

        if (fileInput) {
            fileInput.click();
        }
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

    // ---- Submit ----
    handleSubmit() {
        if (!this.isEligible) {
            return;
        }

        this.submitAttempted = true;
        this.submitSuccess = false;

        if (!this.isFormValid) {
            return;
        }

        this.isSubmitting = true;

        // TODO:
        // 1. Convert document file to Base64 (if provided)
        // 2. Call submitWithdrawalRequest Apex
        // 3. Handle successful submission
        // 4. Handle Apex errors

        console.log('Submitting withdrawal request', {
            reason: this.reason,
            bankDetails: this.bankDetails,
            documentFile: this.documentFile?.name,
            studentName: this.studentName,
            applicationId: this.applicationId,
            rollNumber: this.rollNumber,
            registeredEmail: this.registeredEmail,
            spjimrEmail: this.spjimrEmail,
            reasonsForChoice: this.reasonsForChoice,
            otherInformation: this.otherInformation
        });

        // Temporary mock submission
        setTimeout(() => {
            this.isSubmitting = false;
            this.submitSuccess = true;

            this.currentStep = 1;
            this.requestNumber = this.requestNumber || this.generateTempRequestNumber();
            this.submittedDate = this.formatToday();
            this.submittedName = this.studentName;
            this.submittedApplicationId = this.applicationId;
            this.submittedReason = this.getReasonLabel(this.reason);

            this.resetForm();
        }, 600);
    }

    getReasonLabel(value) {
        const match = WITHDRAWAL_REASON_OPTIONS.find((option) => option.value === value);
        return match ? match.label : value;
    }

    // ---- Reset form ----
    resetForm() {
        this.reason = '';
        this.bankDetails = '';
        this.documentFile = null;
        this.studentName = '';
        this.applicationId = '';
        this.rollNumber = '';
        this.registeredEmail = '';
        this.spjimrEmail = '';
        this.reasonsForChoice = [];
        this.otherInformation = '';
        this.submitAttempted = false;

        const fileInputs = this.template.querySelectorAll(
            'input[type="file"]'
        );

        fileInputs.forEach((input) => {
            input.value = '';
        });
    }

    generateTempRequestNumber() {
        return 'WD-' + Math.floor(100000 + Math.random() * 900000);
    }

    formatToday() {
        const d = new Date();
        return d.toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }
}