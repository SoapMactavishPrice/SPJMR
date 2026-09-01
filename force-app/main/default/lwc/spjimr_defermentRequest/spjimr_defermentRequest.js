import { LightningElement, wire, track } from 'lwc';
import getActiveDefermentRequest from '@salesforce/apex/DefermentRequestController.getActiveDefermentRequest';
import submitDefermentRequest from '@salesforce/apex/DefermentRequestController.submitDefermentRequest';
import getApprovalRemarks from '@salesforce/apex/DefermentRequestController.getApprovalRemarks';
import getUploadedDocuments from '@salesforce/apex/DefermentRequestController.getUploadedDocuments';


const MAX_FILE_SIZE_BYTES = 15 * 1024 * 1024; // 15 MB
const ALLOWED_EXTENSIONS = ['pdf', 'jpg', 'jpeg'];
const TRACKER_STEPS = [
    { number: 1, label: 'Deferment Form Enabled' },
    { number: 2, label: 'Form Submitted' },
    { number: 3, label: "Pending Chairperson's Approval" },
    { number: 4, label: "Pending Dean's / AD's Approval" },
    { number: 5, label: 'Rejoining Details' },
    { number: 6, label: 'No Dues Process Initiated' },
    { number: 7, label: 'No Dues Process Complete' },
    { number: 8, label: 'Access Removal Complete' },
    { number: 9, label: 'Deferment Process Complete' },
    { number: 10, label: 'Pending Re-enrollment' }
];

/*const TRACKER_BRANCH_STEP = { number: 10, label: 'Pending Re-enrollment' };*/

const TRACKER_STATUS_LABELS = {
    1: 'Deferment Form Enabled',
    2: 'Form Submitted',
    3: "Pending Chairperson's Approval",
    4: "Pending Dean's / AD's Approval",
    5: 'Rejoining Details',
    6: 'No Dues Process Initiated',
    7: 'No Dues Process Complete',
    8: 'Access Removal Complete',
    9: 'Deferment Process Complete',
   10: 'Pending Re-enrollment'
};

const STATUS_TO_STEP = {
    'Deferment Form Enabled': 1,
    'Form Submitted': 2,
    'Pending Chairperson\'s Approval': 3,
    'Pending Dean\'s / AD\'s Approval': 4,
    'Rejoining Details': 5,
    'No Dues Process Initiated': 6,
    'No Dues Process Complete': 7,
    'Access Removal Complete': 8,
    'Deferment Process Complete': 9,
    'Pending Re-enrollment': 10
};

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
    @track currentStep = 1;
    @track requestNumber = '';
    @track submittedDate = '';
    @track submittedReason = ''; // captured before resetForm() clears `reason`
    @track hasActiveRequest = false;
    @track isLoadingRequest = true;
    @track defermentRequestId = null;
    windowStatus;
@track breakEndDateTime = null;
@track approvalStatus = '';
    @track l1Remark = '';
@track l2Remark = '';
@track existingDocuments = {}; 

    


    connectedCallback() {
        this.loadActiveRequest();
    }

 /*  async loadActiveRequest() {
        this.isLoadingRequest = true;
        try {
            const data = await getActiveDefermentRequest();
            // TEMP diagnostics — remove once resolved.
            console.log('DefermentRequest debug:', JSON.stringify(data, null, 2));

            if (data && data.recordId){
                this.hasActiveRequest = true;
                this.defermentRequestId = data.recordId;
                this.requestNumber = data.requestNumber;
                this.fees = data.fee || 0;

                // If the manager-set status has already moved past "enabled"
                // (e.g. the student already submitted once), reflect that.
                if (data.status) {
                    this.currentStep = STATUS_TO_STEP[data.status] || 1;
                }
                this.submittedReason = data.reason;
                 this.submissionDate = data.submissionDate;
            } else {
                this.hasActiveRequest = false;
            }
        } catch (error) {
            this.hasActiveRequest = false;
            console.error('getActiveDefermentRequest error', error);
        } finally {
            this.isLoadingRequest = false;
        }
    }*/

    async loadActiveRequest() {
    this.isLoadingRequest = true;

    try {
        const data = await getActiveDefermentRequest();

        console.log(
            'DefermentRequest debug:',
            JSON.stringify(data, null, 2)
        );

        if (data && data.recordId) {

            this.hasActiveRequest = true;

            this.defermentRequestId = data.recordId;

            if (this.defermentRequestId) {
    try {
        const docs = await getUploadedDocuments({ recordId: this.defermentRequestId });
        const map = {};
        (docs || []).forEach((d) => {
            map[d.documentType] = d; // { documentType, fileName, contentDocumentId, contentVersionId, fileExtension }
        });
        this.existingDocuments = map;
    } catch (error) {
        console.error('getUploadedDocuments error', error);
        this.existingDocuments = {};
    }
}

            this.requestNumber = data.requestNumber;

            this.fees = data.fee || 0;

            this.windowStatus = data.windowStatus;

            this.breakEndDateTime = data.breakEndDateTime;

            if (data.status) {
                this.currentStep =
                    STATUS_TO_STEP[data.status] || 1;
            }

            this.submittedReason = data.reason;
            this.reason = data.reason || '';   // ADD THIS — prefills the editable textarea

            this.submissionDate = data.submissionDate;

            this.approvalStatus = data.approvalStatus;
            // Get approval remarks
    const remarks = await getApprovalRemarks({
        recordId: this.defermentRequestId
    });

    console.log(
        'Approval Remarks:',
        JSON.stringify(remarks)
    );
    this.l1Remark = remarks?.L1 || '';
this.l2Remark = remarks?.L2 || '';

            
        } else {

            this.hasActiveRequest = false;

            this.windowStatus = null;

            this.breakEndDateTime = null;
        }

    } catch (error) {

        this.hasActiveRequest = false;

        console.error(
            'getActiveDefermentRequest error',
            error
        );

    } finally {

        this.isLoadingRequest = false;
    }
}
    
    
    // ---- Fee ----
  /*  loadFee() {
        // TODO: Replace with Apex call.
        //
        // getDefermentFee()
        //     .then((result) => {
        //         this.fees = result || 0;
        //     })
        //     .catch((error) => {
        //         console.error('getDefermentFee error', error);
        //     });

        this.fees = 500;
    }*/

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
    return this.submitAttempted && !this.documentsFile && !this.existingDocumentsFile;
}

   get approvalEmailHasError() {
    return this.submitAttempted && !this.approvalEmailFile && !this.existingApprovalEmailFile;
}

    get rejoiningAcceptanceHasError() {
    return this.submitAttempted && !this.rejoiningAcceptanceFile && !this.existingRejoiningAcceptanceFile;
}

    // ---- widen showDefermentForm / isWindowOpen for the reopened case ----
get showDefermentForm() {
    return this.hasActiveRequest && this.currentStep === 1 &&
        (this.windowStatus === 'OPEN' || this.windowStatus === 'REOPENED');
}
get isWindowReopened() {
    return this.windowStatus === 'REOPENED';
}

    get showWindowMessage() {
    return this.hasActiveRequest &&
           this.windowStatus &&
           this.windowStatus !== 'SUBMITTED';
}

get isWindowOpen() {
    return this.windowStatus === 'OPEN';
}

get isWindowExpired() {
    return this.windowStatus === 'EXPIRED';
}

get isWindowNotStarted() {
    return this.windowStatus === 'NOT_STARTED';
}

get isWindowNotStarted() {
    return this.windowStatus === 'NOT_STARTED';
}

get isWindowApproved() {
    return this.windowStatus === 'APPROVED';
}

get showTracker() {
    return this.hasActiveRequest && (this.currentStep >= 2 || this.windowStatus === 'REOPENED');
}

   get transactionHasError() {
    return (
        this.submitAttempted &&
        this.transactionDetailsRequired &&
        !this.transactionFile &&
        !this.existingTransactionFile
    );
}

    get isFormValid() {
    if (!this.reason?.trim()) return false;
    if (!this.documentsFile && !this.existingDocumentsFile) return false;
    if (!this.approvalEmailFile && !this.existingApprovalEmailFile) return false;
    if (!this.rejoiningAcceptanceFile && !this.existingRejoiningAcceptanceFile) return false;
    if (this.transactionDetailsRequired && !this.transactionFile && !this.existingTransactionFile) return false;
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
        return TRACKER_STATUS_LABELS[Number(this.currentStep)] || TRACKER_STATUS_LABELS[1];
    }

    get trackerRequestNumberDisplay() {
        return this.requestNumber || '—';
    }
    get trackerSubmittedDateDisplay() {
        if (!this.submissionDate) {
        return '—';
    }

    return new Intl.DateTimeFormat('en-IN', {
        day: '2-digit',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    }).format(new Date(this.submissionDate));
    }
    get trackerReasonDisplay() {
        return this.submittedReason || '—';
    }
    get trackerApplicationFeeDisplay() {
        return this.currentStep > 1 ? this.feesDisplay : '—';
    }

    get trackerApprovalStatusDisplay() {
        return this.approvalStatus || 'Pending submission';
    }

    get trackerL1RemarkDisplay() {
    return this.l1Remark || '—';
}

get trackerL2RemarkDisplay() {
    return this.l2Remark || '—';
}

// ---- getters for each type ----
get existingDocumentsFile() {
    return this.existingDocuments['Documents to Support Request'];
}
get existingApprovalEmailFile() {
    return this.existingDocuments['Approval Email (Screenshot) with Rejoining Condition'];
}
get existingRejoiningAcceptanceFile() {
    return this.existingDocuments['Rejoining Condition Acceptance Email Screenshot'];
}
get existingTransactionFile() {
    return this.existingDocuments['Transaction Details (Screenshot)'];
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
        const validationError = this.validateFile(file, field);

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

    validateFile(file, field) {
    const ext = file.name.split('.').pop().toLowerCase();

    if (!ALLOWED_EXTENSIONS.includes(ext)) {
        return 'Only .pdf, .jpg and .jpeg files are allowed.';
    }

    // 15 MB cap applies ONLY to Documents to Support Request.
    if (field === 'documents' && file.size > MAX_FILE_SIZE_BYTES) {
        return 'File size must not exceed 15 MB.';
    }

    return null;
   }
    // ---- Submit ----
    // ---- Submit ----
    async handleSubmit() {
        this.submitAttempted = true;
        this.submitSuccess = false;

        if (!this.isFormValid) {
            return;
        }

        this.isSubmitting = true;

        try {
            const [
                documents,
                approvalEmail,
                rejoiningAcceptance,
                transaction
            ] = await Promise.all([
                this.fileToBase64(this.documentsFile),
                this.fileToBase64(this.approvalEmailFile),
                this.fileToBase64(this.rejoiningAcceptanceFile),
                this.fileToBase64(this.transactionFile)
            ]);

           /* await submitDefermentRequest({
                defermentRequestId: this.defermentRequestId,
                reason: this.reason,
                documentsBase64: documents.base64,
                documentsFileName: documents.fileName,
                approvalEmailBase64: approvalEmail.base64,
                approvalEmailFileName: approvalEmail.fileName,
                rejoiningAcceptanceBase64: rejoiningAcceptance.base64,
                rejoiningAcceptanceFileName: rejoiningAcceptance.fileName,
                transactionBase64: transaction.base64,
                transactionFileName: transaction.fileName
            });*/
            console.log('SUBMIT DEBUG defermentRequestId=', this.defermentRequestId, 'hasActiveRequest=', this.hasActiveRequest, 'windowStatus=', this.windowStatus);
            const payload = {
    defermentRequestId: this.defermentRequestId,
    reason: this.reason,
    files: [
        { documentType: 'Documents to Support Request', base64Data: documents.base64, fileName: documents.fileName },
        { documentType: 'Approval Email (Screenshot) with Rejoining Condition', base64Data: approvalEmail.base64, fileName: approvalEmail.fileName },
        { documentType: 'Rejoining Condition Acceptance Email Screenshot', base64Data: rejoiningAcceptance.base64, fileName: rejoiningAcceptance.fileName },
        { documentType: 'Transaction Details (Screenshot)', base64Data: transaction.base64, fileName: transaction.fileName }
    ]
};

await submitDefermentRequest({ requestJson: JSON.stringify(payload) });

            this.submitSuccess = true;
            this.submittedReason = this.reason;

            this.resetForm();

            // Re-fetch from Salesforce so the tracker reflects the real saved
            // status/step rather than an assumed one.
            await this.loadActiveRequest();
        } catch (error) {
               console.error('FULL SUBMIT ERROR:', JSON.stringify(error));
    console.error('SUBMIT ERROR BODY:', error?.body);
    console.error('SUBMIT ERROR MESSAGE:', error?.body?.message);
    console.error('SUBMIT ERROR STACK:', error?.body?.stackTrace);
            const message = (error && error.body && error.body.message)
                ? error.body.message
                : 'Something went wrong while submitting your request.';
            alert(message); // TODO: swap for a proper inline/toast error per your design system
        } finally {
            this.isSubmitting = false;
        }
    }

    fileToBase64(file) {
        if (!file) {
            return Promise.resolve({ base64: null, fileName: null });
        }
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const base64 = reader.result.split(',')[1]; // strip data: prefix
                resolve({ base64, fileName: file.name });
            };
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
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


    formatToday() {
        const d = new Date();
        return d.toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }
}