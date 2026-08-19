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
import { NavigationMixin } from 'lightning/navigation';
import getDistributionUrl from '@salesforce/apex/ApAccountProgramController.getDistributionUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CUSTOM_TITLE from '@salesforce/schema/ContentVersion.Custom_Title_fileupload__c';
import PROGRAM_CODE from '@salesforce/schema/Application__c.Program_Code__c';
import APPLICANT_STATE_FIELD from '@salesforce/schema/Application__c.Applicant_State_Management__c';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import PERSONAL_DETAIL_OBJECT from '@salesforce/schema/Personal_Detail__c';
import TSHIRT_FIELD from '@salesforce/schema/Personal_Detail__c.TShirtSize__c';
import deleteDocument from '@salesforce/apex/ApAccountProgramController.deleteDocument';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import returnPaymentRecord from '@salesforce/apex/RazorpayPaymentHandler.returnPaymentRecord';

export default class ApOfferAcceptanceChild extends NavigationMixin(LightningElement) {

    // ── private backing fields ──────────────────────────────────────────────
    _applicationId;
    _admissionId;
    _offerLetterUrl = '';
    _isOfferAcceptedState = false;
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
    personalDetailId = null;
    pgmCode = '';
    applicantState = '';

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
        this._isOfferAcceptedState = value === true || value === 'true';
    }
    get isOfferAcceptedState() { return this._isOfferAcceptedState; }

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
        return this.showUploadOfferDocuments && !!this._offerLetterUrl;
    }

    get isSaveTShirtDisabled() {
        return this.isReadOnly || this.isSavingTShirt;
    }

    // ── Wire: application fields ─────────────────────────────────────────────

    @wire(getRecord, {
        recordId: '$applicationId',
        fields: [PROGRAM_CODE, APPLICANT_STATE_FIELD]
    })
    wiredApplication({ error, data }) {
        if (error) {
            console.error('Error fetching Application fields', JSON.stringify(error));
            this._markInitialLoadComplete('uploadConfig');
        } else if (data) {
            this.pgmCode       = data.fields.Program_Code__c.value;
            this.applicantState = data.fields.Applicant_State_Management__c.value;
            if (this.pgmCode) {
                this._loadUploadConfig();
            } else {
                this._markInitialLoadComplete('uploadConfig');
            }
        }
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

                const all = (result.annexures || []);
                const passedFilter = all.filter(a => a.filterCondition !== 'FILTERED_OUT');
                const importantRaw = passedFilter.filter(a => a.displayAsImportantDocument);
                const regularRaw   = passedFilter.filter(a => !a.displayAsImportantDocument);

                this._importantDocs = importantRaw.map((a, idx) => ({
                    id:               idx + 1,
                    name:             a.annexureName,
                    url:              a.annexureUrl,
                    docCode:          a.docCode,
                    isUploadRequired: a.isUploadSectionRequired,
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
                if (!isCurrentFetch()) return;
                this.showUploadOfferDocuments = result === true;
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

    handleSaveTShirtSize() {
        if (!this._applicationId) {
            this.showErrorToast('Unable to save', 'Application not found.');
            return;
        }
        if (!this.tshirtSize) {
            this.showErrorToast('No size selected', 'Please select a T-shirt size before saving.');
            return;
        }
        this.isSavingTShirt = true;
        savePersonalDetailTShirtSize({
            applicationId: this._applicationId,
            tShirtSize: this.tshirtSize
        })
            .then(() => {
                this.isSavingTShirt = false;
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
        }).then(generated => window.open(generated, '_blank'));
    }

    handleDownloadAnnexure(event) {
        const url = event.target.dataset.id;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url }
        }).then(generated => window.open(generated, '_blank'));
    }

    handleDownloadImportantDoc(event) {
        const url = event.currentTarget.dataset.url;
        if (!url) return;
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url }
        }).then(generated => window.open(generated, '_blank'));
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