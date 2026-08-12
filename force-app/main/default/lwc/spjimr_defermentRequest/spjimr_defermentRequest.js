import { LightningElement, track } from 'lwc';

// TODO: Uncomment once Apex is available.
// import getDefermentFee from '@salesforce/apex/DefermentRequestController.getDefermentFee';
// import submitDefermentRequest from '@salesforce/apex/DefermentRequestController.submitDefermentRequest';

const MAX_FILE_SIZE_BYTES = 15 * 1024 * 1024; // 15 MB
const ALLOWED_EXTENSIONS = ['pdf', 'jpg', 'jpeg'];

export default class Spjimr_defermentRequest extends LightningElement {
    // ---- Form field state ----
    @track reason = '';
    @track documentsFile = null;
    @track approvalEmailFile = null;
    @track rejoiningAcceptanceFile = null;
    @track transactionFile = null;

    @track fees = 0;

    @track isSubmitting = false;
    @track submitAttempted = false;
    @track submitSuccess = false;

    connectedCallback() {
        this.loadFee();
    }

    // ---- Fee ----
    loadFee() {
        // TODO: Replace with Apex call.
        //
        // getDefermentFee()
        //     .then((result) => {
        //         this.fees = result || 0;
        //     })
        //     .catch((error) => {
        //         console.error('getDefermentFee error', error);
        //     });

        this.fees = 0;
    }

    get feesDisplay() {
        const numeric = Number(this.fees) || 0;
        return numeric.toFixed(2);
    }

    get isFeeApplicable() {
        return Number(this.fees) > 0;
    }

    get transactionDetailsRequired() {
        return this.isFeeApplicable;
    }

    // ---- Validation ----
    get reasonHasError() {
        return this.submitAttempted && !this.reason?.trim();
    }

    get documentsHasError() {
        return this.submitAttempted && !this.documentsFile;
    }

    get approvalEmailHasError() {
        return this.submitAttempted && !this.approvalEmailFile;
    }

    get rejoiningAcceptanceHasError() {
        return this.submitAttempted && !this.rejoiningAcceptanceFile;
    }

    get transactionHasError() {
        return (
            this.submitAttempted &&
            this.transactionDetailsRequired &&
            !this.transactionFile
        );
    }

    get isFormValid() {
        if (!this.reason?.trim()) {
            return false;
        }

        if (!this.documentsFile) {
            return false;
        }

        if (!this.approvalEmailFile) {
            return false;
        }

        if (!this.rejoiningAcceptanceFile) {
            return false;
        }

        if (this.transactionDetailsRequired && !this.transactionFile) {
            return false;
        }

        return true;
    }

    // ---- Dynamic classes ----
    get reasonFieldClass() {
        return this.reasonHasError
            ? 'reason-textarea reason-textarea_error'
            : 'reason-textarea';
    }

    get documentsBoxClass() {
        return this.documentsHasError
            ? 'upload-box upload-box_error'
            : 'upload-box';
    }

    get approvalEmailBoxClass() {
        return this.approvalEmailHasError
            ? 'upload-box upload-box_error'
            : 'upload-box';
    }

    get rejoiningAcceptanceBoxClass() {
        return this.rejoiningAcceptanceHasError
            ? 'upload-box upload-box_error'
            : 'upload-box';
    }

    get transactionBoxClass() {
        return this.transactionHasError
            ? 'transaction-box transaction-box_error'
            : 'transaction-box';
    }

    // ---- Input handlers ----
    handleReasonChange(event) {
        this.reason = event.target.value;
        this.submitSuccess = false;
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

        switch (field) {
            case 'documents':
                this.documentsFile = file;
                break;

            case 'approvalEmail':
                this.approvalEmailFile = file;
                break;

            case 'rejoiningAcceptance':
                this.rejoiningAcceptanceFile = file;
                break;

            case 'transaction':
                this.transactionFile = file;
                break;

            default:
                break;
        }
    }

    validateFile(file) {
        const ext = file.name.split('.').pop().toLowerCase();

        if (!ALLOWED_EXTENSIONS.includes(ext)) {
            return 'Only .pdf, .jpg and .jpeg files are allowed.';
        }

        if (file.size > MAX_FILE_SIZE_BYTES) {
            return 'File size must not exceed 15 MB.';
        }

        return null;
    }

    // ---- Submit ----
    handleSubmit() {
        this.submitAttempted = true;
        this.submitSuccess = false;

        if (!this.isFormValid) {
            return;
        }

        this.isSubmitting = true;

        // TODO:
        // 1. Convert files to Base64
        // 2. Call submitDefermentRequest Apex
        // 3. Handle successful submission
        // 4. Handle Apex errors

        console.log('Submitting deferment request', {
            reason: this.reason,
            fees: this.fees,
            documentsFile: this.documentsFile?.name,
            approvalEmailFile: this.approvalEmailFile?.name,
            rejoiningAcceptanceFile: this.rejoiningAcceptanceFile?.name,
            transactionFile: this.transactionFile?.name
        });

        // Temporary mock submission
        setTimeout(() => {
            this.isSubmitting = false;
            this.submitSuccess = true;
            this.resetForm();

            // Temporary page refresh.
            // Remove this when actual Apex submission is implemented.
            setTimeout(() => {
                window.location.reload();
            }, 1000);

        }, 600);
    }

    // ---- Reset form ----
    resetForm() {
        this.reason = '';
        this.documentsFile = null;
        this.approvalEmailFile = null;
        this.rejoiningAcceptanceFile = null;
        this.transactionFile = null;
        this.submitAttempted = false;

        const fileInputs = this.template.querySelectorAll(
            'input[type="file"]'
        );

        fileInputs.forEach((input) => {
            input.value = '';
        });
    }
}