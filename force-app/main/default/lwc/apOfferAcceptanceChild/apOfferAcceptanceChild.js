import { LightningElement, api, wire } from 'lwc';
import getProgramSpecificDocuments from '@salesforce/apex/ApAccountProgramController.getProgramSpecificDocuments';
import checkUploadedDocumentsByCodes from '@salesforce/apex/ApAccountProgramController.checkUploadedDocumentsByCodes';
import getAcceptanceLetterFileUrl from '@salesforce/apex/ApAccountProgramController.getAcceptanceLetterFileUrl';
import getOfferLetterFileUrl from '@salesforce/apex/ApAccountProgramController.getOfferLetterFileUrl';
import getOfferDocumentUploadConfig from '@salesforce/apex/ApAccountProgramController.getOfferDocumentUploadConfig';
import getTShirtSizeConfig from '@salesforce/apex/ApAccountProgramController.getTShirtSizeConfig';
import linkDocumentDetails from '@salesforce/apex/ApAccountProgramController.linkDocumentDetails';
import getPersonalDetailTShirtSize from '@salesforce/apex/ApAccountProgramController.getPersonalDetailTShirtSize';
import savePersonalDetailTShirtSize from '@salesforce/apex/ApAccountProgramController.savePersonalDetailTShirtSize';
import saveAdmissionPaymentDetails from '@salesforce/apex/ApAccountProgramController.saveAdmissionPaymentDetails';
import getAdmissionPaymentDetails from '@salesforce/apex/ApAccountProgramController.getAdmissionPaymentDetails';
import getPaymentSectionFinalSubmitted from '@salesforce/apex/ApAccountProgramController.getPaymentSectionFinalSubmitted';
import setPaymentSectionFinalSubmitted from '@salesforce/apex/ApAccountProgramController.setPaymentSectionFinalSubmitted';
import { NavigationMixin } from 'lightning/navigation';
import getDistributionUrl from '@salesforce/apex/ApAccountProgramController.getDistributionUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import CUSTOM_TITLE from '@salesforce/schema/ContentVersion.Custom_Title_fileupload__c';
import PROGRAM_CODE from '@salesforce/schema/Application__c.Program_Code__c';
import APPLICANT_STATE_FIELD from '@salesforce/schema/Application__c.Applicant_State_Management__c';
import APP_NAME from '@salesforce/schema/Application__c.Name';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import PERSONAL_DETAIL_OBJECT from '@salesforce/schema/Personal_Detail__c';
import TSHIRT_FIELD from '@salesforce/schema/Personal_Detail__c.TShirtSize__c';
import deleteDocument from '@salesforce/apex/ApAccountProgramController.deleteDocument';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import returnPaymentRecord from '@salesforce/apex/RazorpayPaymentHandler.returnPaymentRecord';
import { openInNewTab } from 'c/applicationFormService';

export default class ApOfferAcceptanceChild extends NavigationMixin(LightningElement) {

    // ── private backing fields ──────────────────────────────────────────────
    _applicationId;
    _admissionId;
    _offerLetterUrl = '';
    _isOfferAcceptedState = false;
    _offerAccepted = false;
    _applicantStateManagement = '';

    // ── state ───────────────────────────────────────────────────────────────
    isLoaded = false;
    isUploaded = false;
    isPaymentPending = true;
    isSavingTShirt = false;
    isOfferLetterProcessing = false;
    processingDocCode = null;

    _fetchGeneration = 0;
    _docStatusReady = false;
    _lastReportedPending = null;
    _initialLoadFlags = {
        signedDoc: false,
        importantDocs: false,
        uploadConfig: false,
        offerUrl: false
    };

    tshirtSize = '';
    tshirtSizeBackend = null; // Backend value to check if already saved
    personalDetailId = null;
    pgmCode = '';
    applicantState = '';

    // Payment section — _nextRowId MUST be declared before _paymentRows
    // so it is initialized (= 1) before _emptyPaymentRow() is called
    _nextRowId = 1;
    _applicationName = '';
    _paymentRows = [this._emptyPaymentRow()];
    _existingPaymentRecordCount = 0; // Track count of records from backend
    isSavingPayment = false;
    isPaymentSectionLocked = false;
    isFinalSubmitting = false;

    // Offer letter state
    offerLetterLink = '';
    offerLetterId = '';
    isOfferLetterPresent = false;

    // Static upload config
    showUploadOfferDocuments = false;
    showTShirtSize = true;

    // Dynamic documents from Program_Annexure__mdt
    // Each item: { id, name, url, docCode, displayAsImportantDocument, isUploadSectionRequired,
    //              filterPassed, uploaded, uploadedUrl, uploadedContentDocumentId }
    _importantDocs = [];   // filtered: displayAsImportantDocument === true && filterPassed
    _annexures = [];        // all non-important-doc annexures (for the Annexures card)

    // Picklist
    _tshirtSizeOptions = [];

    // File upload field name
    fileFieldName = CUSTOM_TITLE.fieldApiName;

    // ── Picklist wires ───────────────────────────────────────────────────────

    @wire(getObjectInfo, { objectApiName: PERSONAL_DETAIL_OBJECT })
    personalDetailObjectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$personalDetailObjectInfo.data.defaultRecordTypeId',
        fieldApiName: TSHIRT_FIELD
    })
    wiredTshirtPicklist({ error, data }) {
        if (data) {
            this._tshirtSizeOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error fetching TShirtSize__c picklist', JSON.stringify(error));
        }
    }

    get tshirtSizeOptions() {
        return this._tshirtSizeOptions;
    }

    // ── @api setters ─────────────────────────────────────────────────────────

    @api
    set offerLetterUrl(value) {
        this._offerLetterUrl = value || '';
    }
    get offerLetterUrl() { return this._offerLetterUrl; }

    @api
    set applicationId(value) {
        this._applicationId = value;
        this._fetchAll();
    }
    get applicationId() { return this._applicationId; }

    @api
    set admissionId(value) {
        this._admissionId = value;
        this._fetchAll();
    }
    get admissionId() { return this._admissionId; }

    @api
    set isOfferAcceptedState(value) {
        const newValue = value === true || value === 'true';
        const changed = this._isOfferAcceptedState !== newValue;
        this._isOfferAcceptedState = newValue;
        if (changed && this.isLoaded) {
            this._refetchProgramDocuments();
        }
    }
    get isOfferAcceptedState() { return this._isOfferAcceptedState; }

    @api
    set offerAccepted(value) {
        const newValue = value === true || value === 'true';
        const changed = this._offerAccepted !== newValue;
        this._offerAccepted = newValue;
        if (changed && this.isLoaded) {
            this._refetchProgramDocuments();
        }
    }
    get offerAccepted() { return this._offerAccepted; }

    @api
    set applicantStateManagement(value) {
        this._applicantStateManagement = value || '';
    }
    get applicantStateManagement() { return this._applicantStateManagement; }

    // ── computed getters ─────────────────────────────────────────────────────

    /** True when Applicant_State_Management__c is 'Offer Accepted' or 'Withdrawn' */
    get isReadOnly() {
        const state = this.applicantState || this._applicantStateManagement;
        return state === 'Offer Accepted' || state === 'Withdrawn';
    }

    /** T-shirt field is read-only if already saved (not null in backend) */
    get isTShirtReadOnly() {
        return this.isReadOnly || (this.tshirtSizeBackend !== null && this.tshirtSizeBackend !== '' && this.tshirtSizeBackend !== undefined);
    }

    get canDeleteDocuments() {
        return !this.isReadOnly;
    }

    get hasAnnexures() { return this._annexures && this._annexures.length > 0; }
    get noAnnexures()  { return !this.hasAnnexures; }

    /** Important documents (displayAsImportantDocument + filterPassed) */
    get importantDocs() { return this._importantDocs; }
    get hasImportantDocs() { return this._importantDocs.length > 0; }

    /** Important documents that require upload (separate section) */
    get importantDocsWithUpload() {
        if (!this.offerAccepted) {
            return [];
        }
        return this._importantDocs
            .filter(d => d.isUploadRequired)
            .map(d => ({
                ...d,
                isProcessing: this.processingDocCode === d.docCode
            }));
    }

    /** Regular annexures list (not displayAsImportantDocument) */
    get annexures() { return this._annexures; }

    get hasOfferLetterDownload() {
        return !!this._offerLetterUrl;
    }

    get showOfferUploadSection() {
        return this.showUploadOfferDocuments && !!this._offerLetterUrl && this.offerAccepted;
    }

    get isSaveTShirtDisabled() {
        return this.isTShirtReadOnly || this.isSavingTShirt;
    }

    get shouldShowTShirtSection() {
        const isWithdrawn = (this.applicantState === 'Withdrawn' || this._applicantStateManagement === 'Withdrawn');
        return this.showTShirtSize && this.offerAccepted && !isWithdrawn;
    }

    /**
     * Payment section is visible only when ALL documents that have
     * IsMandatoryToShowPaymentSection__c = true have been uploaded.
     * If no such documents exist, the section is NOT shown.
     */
    get showPaymentSection() {
        if (!this.offerAccepted) return false;
        const mandatoryDocs = this._importantDocs.filter(d => d.isMandatoryToShowPaymentSection);
        if (mandatoryDocs.length === 0) return false;
        return mandatoryDocs.every(d => d.uploaded);
    }

    get paymentRows() {
        // Inject a fresh 1-based display index on every render so that after
        // adding / removing rows the # column always shows the correct number.
        return this._paymentRows.map((row, idx) => ({
            ...row,
            displayIndex: idx + 1,
            applicationIdText: row.applicationIdText || this._applicationName || '',
            rowClass: this.isPaymentSectionLocked ? 'payment-row-readonly' : 'payment-row'
        }));
    }

    get isLessDisabled() {
        if (this.isPaymentSectionLocked || this.isSavingPayment) return true;
        // Only allow removal of rows beyond the existing record count
        return this._paymentRows.length <= this._existingPaymentRecordCount;
    }

    get isSaveDisabled() {
        return this.isPaymentSectionLocked
            || this.isSavingPayment
            || this.isFinalSubmitting
            || this._paymentRows.length === 0;
    }

    get isFinalSubmitDisabled() {
        return this.isPaymentSectionLocked
            || this.isFinalSubmitting
            || this.isSavingPayment
            || this._paymentRows.length === 0;
    }

    get isMoreDisabled() {
        return this.isPaymentSectionLocked || this.isSavingPayment;
    }

    get maxPaymentDate() {
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        return `${yyyy}-${mm}-${dd}`;
    }

    @wire(getRecord, {
        recordId: '$applicationId',
        fields: [PROGRAM_CODE, APPLICANT_STATE_FIELD, APP_NAME]
    })
    wiredApplication({ error, data }) {
        if (error) {
            console.error('Error fetching Application fields', JSON.stringify(error));
            this._markInitialLoadComplete('uploadConfig');
        } else if (data) {
            this.pgmCode        = data.fields.Program_Code__c.value;
            this.applicantState = data.fields.Applicant_State_Management__c.value;
            const appName       = (data.fields.Name && data.fields.Name.value) || '';
            if (appName) {
                this._setApplicationName(appName);
            }
            if (this.pgmCode) {
                this._loadUploadConfig();
            } else {
                this._markInitialLoadComplete('uploadConfig');
            }
        }
    }

    _setApplicationName(name) {
        if (!name || this._applicationName === name) return;
        this._applicationName = name;
        this._paymentRows = this._paymentRows.map(row =>
            (!row.applicationIdText || row.applicationIdText === '')
                ? { ...row, applicationIdText: name }
                : row
        );
    }

    // ── Wire: Payment related list ───────────────────────────────────────────

    @wire(getRelatedListRecords, {
        parentRecordId: '$applicationId',
        relatedListId: 'Payments__r',
        fields: ['Payment__c.Payment_Type__c', 'Payment__c.Id', 'Payment__c.Status__c']
    })
    paymentInfo({ error, data }) {
        if (data) {
            for (const record of data.records) {
                if (
                    record.fields.Payment_Type__c.value === 'Offer Acceptance Fee'
                    && record.fields.Status__c.value === 'paid'
                ) {
                    this.isPaymentPending = false;
                    break;
                }
            }
        }
    }

    // ── Core fetch orchestrator ──────────────────────────────────────────────

    _fetchAll() {
        if (!this._applicationId || !this._admissionId) return;

        const fetchGeneration = ++this._fetchGeneration;
        this._resetDocStatusTracking();
        const isCurrentFetch = () => fetchGeneration === this._fetchGeneration;

        getAcceptanceLetterFileUrl({ applicationId: this._applicationId })
            .catch(err => console.error(JSON.stringify(err)));

        if (this._offerLetterUrl) {
            this._markInitialLoadComplete('offerUrl');
        } else {
            getOfferLetterFileUrl({ admissionId: this._admissionId })
                .then(result => {
                    if (!isCurrentFetch()) return;
                    this._offerLetterUrl = result || '';
                    this._markInitialLoadComplete('offerUrl');
                })
                .catch(err => {
                    console.error(JSON.stringify(err));
                    if (isCurrentFetch()) {
                        this._markInitialLoadComplete('offerUrl');
                    }
                });
        }

        if (this.pgmCode) {
            this._loadUploadConfig(isCurrentFetch);
        }

        this._fetchSignedDocStatus(isCurrentFetch);
        this._fetchAdmissionPaymentDetails(isCurrentFetch);

        getProgramSpecificDocuments({
            admissionId: this._admissionId,
            applicationId: this._applicationId
        })
            .then(result => {
                if (!isCurrentFetch()) return;

                this.isLoaded = true;
                if (!result) {
                    this._importantDocs = [];
                    this._annexures = [];
                    return Promise.resolve();
                }

                if (result.applicationName) {
                    this._setApplicationName(result.applicationName);
                }

                const all = (result.annexures || []);
                const passedFilter = all.filter(a => a.filterCondition !== 'FILTERED_OUT');
                
                // Filter documents based on acceptance state, withdrawal status, and ShowDocumentsAfterWithdrawal flag
                let visibleDocs;
                const isWithdrawn = (this._applicantStateManagement === 'Withdrawn');
                
                if (isWithdrawn) {
                    // After withdrawal: show only documents with ShowDocumentsAfterWithdrawal = true
                    visibleDocs = passedFilter.filter(a => a.showDocumentsAfterWithdrawal === true);
                } else if (this.offerAccepted) {
                    // After acceptance (but not withdrawn): show all documents that passed the filter
                    visibleDocs = passedFilter;
                } else {
                    // Before acceptance: show only documents with ShowDocumentsBeforeAccept = true
                    visibleDocs = passedFilter.filter(a => a.showDocumentsBeforeAccept === true);
                }
                
                const importantRaw = visibleDocs.filter(a => a.displayAsImportantDocument);
                const regularRaw   = visibleDocs.filter(a => !a.displayAsImportantDocument);

                this._importantDocs = importantRaw.map((a, idx) => ({
                    id:               idx + 1,
                    name:             a.annexureName,
                    url:              a.annexureUrl,
                    docCode:          a.docCode,
                    isUploadRequired: a.isUploadSectionRequired,
                    isMandatoryToShowPaymentSection: a.isMandatoryToShowPaymentSection === true,
                    uploaded:         false,
                    uploadedUrl:      null,
                    uploadedContentDocumentId: null
                }));

                this._annexures = regularRaw.map((a, idx) => ({
                    Id:    idx + 1,
                    name:  a.annexureName,
                    value: a.annexureUrl
                }));

                return this._fetchImportantDocUploadStatus(isCurrentFetch);
            })
            .then(() => {
                if (isCurrentFetch()) {
                    this._markInitialLoadComplete('importantDocs');
                }
            })
            .catch(err => {
                console.error(JSON.stringify(err));
                if (isCurrentFetch()) {
                    this.isLoaded = true;
                    this._markInitialLoadComplete('importantDocs');
                }
            });

        getPersonalDetailTShirtSize({ applicationId: this._applicationId })
            .then(result => {
                if (!isCurrentFetch()) return;
                if (result && result.personalDetailId) {
                    this.personalDetailId = result.personalDetailId;
                    this.tshirtSize = result.tShirtSize || '';
                    // Store backend value separately to check if it was already saved
                    this.tshirtSizeBackend = result.tShirtSize || null;
                }
            })
            .catch(err => console.error('Error fetching Personal Detail T-shirt size', JSON.stringify(err)));
    }

    /** Fetch upload status for signed offer / signed acceptance (legacy codes) */
    _fetchSignedDocStatus(isCurrentFetch = () => true) {
        const codes = ['Signed_OfferLetter', 'Signed_AcceptanceLetter'];
        return checkUploadedDocumentsByCodes({
            applicationId: this._applicationId,
            docCodes: codes
        })
            .then(result => {
                if (!isCurrentFetch()) return;
                const offerResult = result['Signed_OfferLetter'];
                if (offerResult && offerResult.uploaded) {
                    this.isOfferLetterPresent = true;
                    this.offerLetterLink = offerResult.url;
                    this.offerLetterId   = offerResult.contentDocumentId;
                } else {
                    this.isOfferLetterPresent = false;
                    this.offerLetterLink = '';
                    this.offerLetterId   = '';
                }
                this._markInitialLoadComplete('signedDoc');
                this._updateUploadCompletion();
            })
            .catch(err => {
                console.error(JSON.stringify(err));
                if (isCurrentFetch()) {
                    this._markInitialLoadComplete('signedDoc');
                }
            });
    }

    /** Fetch upload status for all important documents */
    _fetchImportantDocUploadStatus(isCurrentFetch = () => true) {
        if (!this._importantDocs.length) return Promise.resolve();
        const codes = this._importantDocs.map(d => d.docCode);

        return checkUploadedDocumentsByCodes({
            applicationId: this._applicationId,
            docCodes: codes
        })
            .then(result => {
                if (!isCurrentFetch()) return;
                this._importantDocs = this._importantDocs.map(doc => {
                    const res = result[doc.docCode];
                    if (res && res.uploaded) {
                        return {
                            ...doc,
                            uploaded: true,
                            uploadedUrl: res.url,
                            uploadedContentDocumentId: res.contentDocumentId
                        };
                    }
                    return doc;
                });
                this._updateUploadCompletion();
            })
            .catch(err => {
                console.error(JSON.stringify(err));
            });
    }

    // ── Upload config loader ─────────────────────────────────────────────────

    _loadUploadConfig(isCurrentFetch = () => true) {
        if (!this.pgmCode) return;
        if (this._initialLoadFlags.uploadConfig) return;

        getOfferDocumentUploadConfig({ programCode: this.pgmCode })
            .then(result => {

                console.log('Upload config result:', result);

                if (!isCurrentFetch()) return;
                this.showUploadOfferDocuments = result === true;

                console.log('Upload config loaded:', this.showUploadOfferDocuments);

                this._markInitialLoadComplete('uploadConfig');
            })
            .catch(err => {
                console.error(JSON.stringify(err));
                if (isCurrentFetch()) {
                    this._markInitialLoadComplete('uploadConfig');
                }
            });

        getTShirtSizeConfig({ programCode: this.pgmCode })
            .then(result => {
                if (!isCurrentFetch()) return;
                this.showTShirtSize = result === true;
            })
            .catch(err => {
                console.error('Error fetching T-shirt size config', JSON.stringify(err));
                if (isCurrentFetch()) {
                    this.showTShirtSize = true;
                }
            });
    }

    _resetDocStatusTracking() {
        this._docStatusReady = false;
        this._lastReportedPending = null;
        this._initialLoadFlags = {
            signedDoc: false,
            importantDocs: false,
            uploadConfig: false,
            offerUrl: false
        };
    }

    _markInitialLoadComplete(flag) {
        if (this._initialLoadFlags[flag]) return;
        this._initialLoadFlags[flag] = true;
        this._tryFinalizeDocStatus();
    }

    _tryFinalizeDocStatus() {
        const flags = this._initialLoadFlags;
        if (!flags.signedDoc || !flags.importantDocs || !flags.uploadConfig || !flags.offerUrl) {
            return;
        }
        this._docStatusReady = true;
        this._updateUploadCompletion(true);
    }

    _refetchProgramDocuments() {
        if (!this._applicationId || !this._admissionId) return;
        
        getProgramSpecificDocuments({
            admissionId: this._admissionId,
            applicationId: this._applicationId
        })
            .then(result => {
                if (!result) {
                    this._importantDocs = [];
                    this._annexures = [];
                    return Promise.resolve();
                }

                if (result.applicationName) {
                    this._setApplicationName(result.applicationName);
                }

                 const all = (result.annexures || []);
                 const passedFilter = all.filter(a => a.filterCondition !== 'FILTERED_OUT');
                 
                 // Filter documents based on acceptance state, withdrawal status, and ShowDocumentsAfterWithdrawal flag
                 let visibleDocs;
                 const isWithdrawn = (this._applicantStateManagement === 'Withdrawn');
                 
                 if (isWithdrawn) {
                     // After withdrawal: show only documents with ShowDocumentsAfterWithdrawal = true
                     visibleDocs = passedFilter.filter(a => a.showDocumentsAfterWithdrawal === true);
                 } else if (this.offerAccepted) {
                     // After acceptance (but not withdrawn): show all documents that passed the filter
                     visibleDocs = passedFilter;
                 } else {
                     // Before acceptance: show only documents with ShowDocumentsBeforeAccept = true
                     visibleDocs = passedFilter.filter(a => a.showDocumentsBeforeAccept === true);
                 }
                 
                 const importantRaw = visibleDocs.filter(a => a.displayAsImportantDocument);
                 const regularRaw   = visibleDocs.filter(a => !a.displayAsImportantDocument);

                 this._importantDocs = importantRaw.map((a, idx) => ({
                     id:               idx + 1,
                     name:             a.annexureName,
                     url:              a.annexureUrl,
                     docCode:          a.docCode,
                     isUploadRequired: a.isUploadSectionRequired,
                     isMandatoryToShowPaymentSection: a.isMandatoryToShowPaymentSection === true,
                     uploaded:         false,
                     uploadedUrl:      null,
                     uploadedContentDocumentId: null
                 }));

                 this._annexures = regularRaw.map((a, idx) => ({
                     Id:    idx + 1,
                     name:  a.annexureName,
                     value: a.annexureUrl
                 }));

                 return this._fetchImportantDocUploadStatus();
             })
             .catch(err => {
                 console.error('Error refetching program documents', JSON.stringify(err));
             });
     }

    // ── Upload completion tracker ────────────────────────────────────────────

    _updateUploadCompletion(forceDispatch = false) {
        const offerComplete = !this.showOfferUploadSection || this.isOfferLetterPresent;
        const pendingImportantDocs = this._importantDocs.filter(
            d => d.isUploadRequired && !d.uploaded
        );

        this.isUploaded = offerComplete && pendingImportantDocs.length === 0;
        const hasPendingDocuments = !this.isUploaded;

        if (!this._docStatusReady && !forceDispatch) {
            return;
        }

        if (!forceDispatch && this._lastReportedPending === hasPendingDocuments) {
            return;
        }

        this._lastReportedPending = hasPendingDocuments;
        this.dispatchEvent(new CustomEvent('docstatuschange', {
            detail: {
                applicationId: this.applicationId,
                hasPendingDocuments
            },
            bubbles: true,
            composed: true
        }));
    }

    // ── T-shirt handlers ──────────────────────────────────────────────────────

    handleShirtSizeChange(event) {
        this.tshirtSize = event.detail.value;
    }

    async handleSaveTShirtSize() {
        if (!this._applicationId) {
            this.showErrorToast('Unable to save', 'Application not found.');
            return;
        }
        if (!this.tshirtSize) {
            this.showErrorToast('No size selected', 'Please select a T-shirt size before saving.');
            return;
        }

        // Show confirmation dialog
        const result = await LightningConfirm.open({
            message: 'Once saved, your T-shirt size cannot be edited. Please confirm that you have selected the correct size.',
            variant: 'header',
            label: 'Confirm T-shirt Size',
            theme: 'warning'
        });

        // If user cancelled, return
        if (!result) {
            return;
        }

        // User confirmed, proceed with save
        this.isSavingTShirt = true;
        savePersonalDetailTShirtSize({
            applicationId: this._applicationId,
            tShirtSize: this.tshirtSize
        })
            .then(() => {
                this.isSavingTShirt = false;
                // Update backend value to mark it as saved
                this.tshirtSizeBackend = this.tshirtSize;
                this.showSuccessToast('T-shirt size saved', '');
            })
            .catch(err => {
                this.isSavingTShirt = false;
                this.showErrorToast('Could not save T-shirt size', this._getErrorMessage(err));
            });
    }

    // ── Important-doc upload handlers ────────────────────────────────────────

    handleImportantDocUpload(event) {
        const docCode = event.currentTarget.dataset.doccode;
        const uploadedFile = event.detail.files[0];
        if (!uploadedFile || !docCode) return;

        const docName = this._importantDocs.find(d => d.docCode === docCode)?.name || docCode;
        const contentVersionId = uploadedFile.contentVersionId;
        const contentDocumentId = uploadedFile.documentId;

        this.processingDocCode = docCode;
        getDistributionUrl({ contentVersionId, entity: docName })
            .then(() => linkDocumentDetails({
                applicationId: this._applicationId,
                contentDocumentId,
                docCode,
                contentVersionId
            }))
            .then(() => this._fetchImportantDocUploadStatus())
            .catch(err => {
                console.error(`Error uploading ${docName}`, JSON.stringify(err));
                this.showErrorToast('Upload failed', this._getErrorMessage(err));
            })
            .finally(() => {
                this.processingDocCode = null;
            });
    }

    async handleImportantDocDelete(event) {
        if (!this.canDeleteDocuments) return;

        const docCode  = event.currentTarget.dataset.doccode;
        const docEntry = this._importantDocs.find(d => d.docCode === docCode);
        if (!docEntry || !docEntry.uploadedContentDocumentId) return;

        this.processingDocCode = docCode;
        try {
            await deleteDocument({
                contentDocumentId: docEntry.uploadedContentDocumentId,
                entity: docCode
            });
            this._importantDocs = this._importantDocs.map(d => {
                if (d.docCode !== docCode) return d;
                return { ...d, uploaded: false, uploadedUrl: null, uploadedContentDocumentId: null };
            });
            this._updateUploadCompletion(true);
        } catch (err) {
            console.error('Error deleting important doc', JSON.stringify(err));
        } finally {
            this.processingDocCode = null;
        }
    }

    // ── Signed offer-letter upload handlers ──────────────────────────────────

    handleOfferUpload(event) {
        const uploadedFile = event.detail.files[0];
        if (!uploadedFile) return;

        const contentVersionId = uploadedFile.contentVersionId;
        const contentDocumentId = uploadedFile.documentId;

        this.isOfferLetterProcessing = true;
        getDistributionUrl({ contentVersionId, entity: 'Offer Letter' })
            .then(() => linkDocumentDetails({
                applicationId: this._applicationId,
                contentDocumentId,
                docCode: 'Signed_OfferLetter',
                contentVersionId
            }))
            .then(() => this._fetchSignedDocStatus())
            .catch(err => {
                console.error('Error uploading offer letter', JSON.stringify(err));
                this.showErrorToast('Upload failed', this._getErrorMessage(err));
            })
            .finally(() => {
                this.isOfferLetterProcessing = false;
            });
    }

    async handleOfferDelete() {
        if (!this.canDeleteDocuments) return;

        this.isOfferLetterProcessing = true;
        try {
            const result = await deleteDocument({
                contentDocumentId: this.offerLetterId,
                entity: 'Offer'
            });
            if (result === 'Offer') {
                this.isOfferLetterPresent = false;
                this.offerLetterLink = '';
                this.offerLetterId   = '';
                // Force notify parent immediately that offer letter is no longer present
                this._updateUploadCompletion(true);
                this._fetchSignedDocStatus();
            }
        } catch (err) {
            console.error('Error deleting Offer Letter', JSON.stringify(err));
        } finally {
            this.isOfferLetterProcessing = false;
        }
    }

    // ── Payment acceptance success (legacy polling) ──────────────────────────

    handleAcceptanceSuccess() {
        const childMsg = {
            admissionId:   this.admissionId,
            applicationId: this.applicationId
        };

        let attempts = 0;
        const intervalMs  = 5000;
        const maxAttempts = 70;

        const intervalId = setInterval(() => {
            attempts++;
            returnPaymentRecord({
                ApplicationId: this._applicationId,
                Type: 'Offer Acceptance Fee'
            })
                .then(result => {
                    if (result) {
                        this.isPaymentPending = false;
                        this.showSuccessToast('Payment Successful!');
                        clearInterval(intervalId);
                        this.dispatchEvent(new CustomEvent('updateadmissionaccept', {
                            detail: childMsg, bubbles: true, composed: true
                        }));
                    }
                    if (attempts >= maxAttempts) {
                        clearInterval(intervalId);
                        this.showErrorToast('Payment Delay',
                            'Your payment is still processing. Please refresh after a few minutes.');
                    }
                })
                .catch(err => console.error('Polling error', err));
        }, intervalMs);
    }

    // ── Download handlers ────────────────────────────────────────────────────

    handleDownloadOfferLetter(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) return;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url }
        }).then(generated => openInNewTab(generated));
    }

    handleDownloadAnnexure(event) {
        const url = event.target.dataset.id;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url }
        }).then(generated => openInNewTab(generated));
    }

    handleDownloadImportantDoc(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) return;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url }
        }).then(generated => openInNewTab(generated));
    }

    // ── Payment section handlers ──────────────────────────────────────────────

    _emptyPaymentRow() {
        return {
            rowId:             this._nextRowId++,
            applicationIdText: this._applicationName || '',
            date:              '',
            amount:            '',
            transactionId:     '',
            accountHolderName: '',
            accountNumber:     '',
            ifscCode:          '',
            nameOfTheBank:     '',
            bankBranch:        ''
        };
    }

    _fetchAdmissionPaymentDetails(isCurrentFetch = () => true) {
        if (!this._applicationId) return;
        
        // Fetch payment section lock status
        getPaymentSectionFinalSubmitted({ applicationId: this._applicationId })
            .then(isLocked => {
                if (!isCurrentFetch()) return;
                this.isPaymentSectionLocked = isLocked === true;
            })
            .catch(err => {
                console.error('Error fetching payment section lock status', JSON.stringify(err));
            });

        getAdmissionPaymentDetails({ applicationId: this._applicationId })
            .then(records => {
                if (!isCurrentFetch()) return;
                if (records && records.length > 0) {
                    this._existingPaymentRecordCount = records.length; // Store the count
                    this._paymentRows = records.map(rec => ({
                        rowId:             this._nextRowId++,
                        recordId:          rec.Id,
                        applicationIdText: rec.Application__r?.Name || this._applicationName || '',
                        date:              rec.Date__c || '',
                        amount:            rec.Amount__c != null ? rec.Amount__c : '',
                        transactionId:     rec.TransactionId__c || '',
                        accountHolderName: rec.AccountHolderName__c || '',
                        accountNumber:     rec.AccountNumber__c || '',
                        ifscCode:          rec.IfscCode__c || '',
                        nameOfTheBank:     rec.NameOfTheBank__c || '',
                        bankBranch:        rec.BankBranch__c || ''
                    }));
                } else {
                    this._existingPaymentRecordCount = 0;
                    this._paymentRows = [this._emptyPaymentRow()];
                }
            })
            .catch(err => {
                console.error('Error fetching admission payment details', JSON.stringify(err));
            });
    }

    handlePaymentFieldChange(event) {
        if (this.isPaymentSectionLocked) return;

        const rowId  = parseInt(event.currentTarget.dataset.rowid, 10);
        const field  = event.currentTarget.dataset.field;
        const value  = event.detail.value;

        if (field === 'date' && value && value > this.maxPaymentDate) {
            this.showErrorToast('Invalid Date', 'Payment date cannot be in the future.');
            event.currentTarget.value = this.maxPaymentDate;
            this._paymentRows = this._paymentRows.map(row =>
                row.rowId === rowId ? { ...row, date: this.maxPaymentDate } : row
            );
            return;
        }

        this._paymentRows = this._paymentRows.map(row =>
            row.rowId === rowId ? { ...row, [field]: value } : row
        );
    }

    handleAddPaymentRow() {
        this._paymentRows = [...this._paymentRows, this._emptyPaymentRow()];
    }

    handleRemovePaymentRow() {
        if (this.isPaymentSectionLocked || this._paymentRows.length <= 1) return;
        this._paymentRows = this._paymentRows.slice(0, -1);
    }

    /** Maps Apex records to the row shape used by the table */
    _mapPaymentRecords(records) {
        return records.map(rec => ({
            rowId:             this._nextRowId++,
            recordId:          rec.Id,
            applicationIdText: rec.Application__r?.Name || this._applicationName || '',
            date:              rec.Date__c || '',
            amount:            rec.Amount__c != null ? rec.Amount__c : '',
            transactionId:     rec.TransactionId__c || '',
            accountHolderName: rec.AccountHolderName__c || '',
            accountNumber:     rec.AccountNumber__c || '',
            ifscCode:          rec.IfscCode__c || '',
            nameOfTheBank:     rec.NameOfTheBank__c || '',
            bankBranch:        rec.BankBranch__c || ''
        }));
    }

    /**
     * Validates and saves the current rows.
     * Returns true on success, false on validation failure or save error.
     * Does NOT show a success toast, so callers decide what to show.
     */
    async _persistPaymentRows() {
        const rowsToSave = this._paymentRows.map(row => ({
            ...row,
            applicationIdText: row.applicationIdText || this._applicationName || ''
        }));

        if (rowsToSave.length === 0) {
            return false;
        }

        const requiredFields = ['applicationIdText','date','amount','transactionId',
                                'accountHolderName','accountNumber','ifscCode',
                                'nameOfTheBank','bankBranch'];

        for (const row of rowsToSave) {
            for (const f of requiredFields) {
                if (!row[f] || String(row[f]).trim() === '') {
                    this.showErrorToast('Validation Error', 'Please fill in all required fields in the payment table before saving.');
                    return false;
                }
            }
            if (row.date > this.maxPaymentDate) {
                this.showErrorToast('Invalid Date', 'Payment date cannot be in the future.');
                return false;
            }
        }

        this.isSavingPayment = true;
        try {
            const allRecords = await saveAdmissionPaymentDetails({
                applicationId: this._applicationId,
                paymentRows: rowsToSave
            });
            if (allRecords && allRecords.length > 0) {
                this._existingPaymentRecordCount = allRecords.length;
                this._paymentRows = this._mapPaymentRecords(allRecords);
            } else {
                this._existingPaymentRecordCount = 0;
                this._paymentRows = [this._emptyPaymentRow()];
            }
            return true;
        } catch (err) {
            this.showErrorToast('Could not save payment details', this._getErrorMessage(err));
            return false;
        } finally {
            this.isSavingPayment = false;
        }
    }

    async handlePaymentSave() {
        const saved = await this._persistPaymentRows();
        if (saved) {
            this.showSuccessToast('Payment details saved successfully!', '');
        }
    }

    async handlePaymentFinalSubmit() {
        if (this._paymentRows.length === 0) {
            this.showErrorToast('No Data', 'Please add at least one payment record before final submission.');
            return;
        }

        // Validate all rows have data
        const requiredFields = ['applicationIdText','date','amount','transactionId',
                                'accountHolderName','accountNumber','ifscCode',
                                'nameOfTheBank','bankBranch'];

        for (const row of this._paymentRows) {
            for (const f of requiredFields) {
                if (!row[f] || String(row[f]).trim() === '') {
                    this.showErrorToast('Validation Error', 'Please ensure all payment records have complete data before final submission.');
                    return;
                }
            }
        }

        const confirmed = await LightningConfirm.open({
            message: 'Any unsaved changes will be saved when you proceed. Once final submitted, the payment section will be locked and no further changes can be made. Are you sure you want to proceed?',
            variant: 'header',
            label: 'Confirm Final Submission',
            theme: 'warning'
        });

        if (!confirmed) {
            return;
        }

        this.isFinalSubmitting = true;
        try {
            // Persist the rows first. If the save fails, abort so we never lock unsaved data.
            const saved = await this._persistPaymentRows();
            if (!saved) {
                return;
            }

            await setPaymentSectionFinalSubmitted({
                applicationId: this._applicationId
            });
            this.isPaymentSectionLocked = true;
            this.showSuccessToast('Payment section finalized', 'The payment section has been locked.');
        } catch (err) {
            this.showErrorToast('Could not finalize payment section', this._getErrorMessage(err));
        } finally {
            this.isFinalSubmitting = false;
        }
    }

    // ── Toast helpers ────────────────────────────────────────────────────────

    showSuccessToast(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title, message: message || '', variant: 'success', mode: 'dismissable'
        }));
    }

    showErrorToast(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title, message: message || '', variant: 'error', mode: 'dismissable'
        }));
    }

    _getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Please try again or contact support.';
    }
}