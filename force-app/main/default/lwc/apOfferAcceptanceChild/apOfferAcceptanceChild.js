import { LightningElement, api, wire } from 'lwc';
import getProgramSpecificDocuments from '@salesforce/apex/ApAccountProgramController.getProgramSpecificDocuments'
import checkUploadedDocuments from '@salesforce/apex/ApAccountProgramController.checkUploadedDocuments'
import getAcceptanceLetterFileUrl from '@salesforce/apex/ApAccountProgramController.getAcceptanceLetterFileUrl'
import getOfferLetterFileUrl from '@salesforce/apex/ApAccountProgramController.getOfferLetterFileUrl'
import getOfferUploadConfig from '@salesforce/apex/ApAccountProgramController.getOfferUploadConfig'
import linkDocumentDetails from '@salesforce/apex/ApAccountProgramController.linkDocumentDetails'
import { NavigationMixin } from 'lightning/navigation';
import getDistributionUrl from '@salesforce/apex/ApAccountProgramController.getDistributionUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CUSTOM_TITLE from "@salesforce/schema/ContentVersion.Custom_Title_fileupload__c";
import APPLICANT_FIELD from "@salesforce/schema/Application__c.Applicant__c"
import PROGRAM_CODE from "@salesforce/schema/Application__c.Program_Code__c"
import TSHIRT_FIELD from "@salesforce/schema/Account.TshirtSize__c"
import APPLICANT_STATE_FIELD from "@salesforce/schema/Application__c.Applicant_State_Management__c"
import { getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_ID from '@salesforce/schema/Account.Id'
import { updateRecord } from 'lightning/uiRecordApi'; 
import returnPaymentRecord from '@salesforce/apex/RazorpayPaymentHandler.returnPaymentRecord';
import deleteDocument from '@salesforce/apex/ApAccountProgramController.deleteDocument';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
export default class ApOfferAcceptanceChild extends NavigationMixin(LightningElement) {

    _applicationId;
    _admissionId;
    _offerLetterUrl = '';
    offerLetterLink=''
    acceptanceLetterLink = ''
    isUploaded = false;
    applicantId = '';
    tshirtSize = '';
    isLoaded = false;
    acceptanceLetterUrl = '';
    isAcceptance = true;
    isAcceptanceLetterPresent = false;
    isPaymentPending = true;
    isOfferLetterPresent = false;
    acceptanceLetterId = ''
    offerLetterId = ''
    fileNameOfferLetter = 'Signed Offer Letter';
    fileNameAcceptanceLetter = 'Signed Acceptance Letter';
    fileFieldName = CUSTOM_TITLE.fieldApiName;
    hasAcceptanceLetterDownload = false;
    hasOfferLetterDownload = false;
    showUploadOfferDocuments = false;
    showUploadAcceptDocuments = false;

    annexures = [];
    pgmCode = '';
    applicantState = '';
    sizeField = TSHIRT_FIELD;

    // ---------------- API setters ----------------

    @api
    set offerLetterUrl(value) {
        this._offerLetterUrl = value || '';
        this.hasOfferLetterDownload = !!this._offerLetterUrl;
        this.updateUploadCompletion();
    }
    get offerLetterUrl() {
        return this._offerLetterUrl;
    }

    @api
    set applicationId(value) {
        this._applicationId = value;
        this.getDocuments();
    }
    get applicationId() {
        return this._applicationId;
    }

    @api
    set admissionId(value) {
        this._admissionId = value;
        this.getDocuments();
    }
    get admissionId() {
        return this._admissionId;
    }

    get hasAnnexures() {
        return this.annexures && this.annexures.length > 0;
    }

    get noAnnexures() {
        return !this.hasAnnexures;
    }

    get isReadOnly() {
        return this.applicantState === 'Offer Accepted';
    }

    get canDeleteDocuments() {
        return !this.isReadOnly;
    }

    get showOfferUploadSection() {
        return this.showUploadOfferDocuments && this.hasOfferLetterDownload;
    }

    get showAcceptanceUploadSection() {
        return this.showUploadAcceptDocuments && this.hasAcceptanceLetterDownload;
    }

    // ---------------- Wire Applicant Info ----------------
    

    @wire(getRelatedListRecords, {
    parentRecordId: '$applicationId',
    relatedListId: 'Payments__r',
    fields: ['Payment__c.Payment_Type__c','Payment__c.Id','Payment__c.Status__c'],
  })
  paymentInfo({error,data}){
    if(error){
        console.log('Error retrieving Payment Info')
    }
    else if(data){
        console.log('All Payment Records ',data.records)
        const records = data.records;
        if(records.length > 0){
            console.log('Record length is ',records.length)
            records.forEach((record)=>{
                if(record.fields.Payment_Type__c.value == 'Offer Acceptance Fee' && record.fields.Status__c.value == 'paid'){
                    this.isPaymentPending = false
                    if(this.isOfferLetterPresent && this.isAcceptanceLetterPresent){
                        const childMsg = {
                        admissionId: this.admissionId,
                        applicationId: this.applicationId
                    };
                     this.dispatchEvent(
                    new CustomEvent('updateadmissionaccept', {
                        detail: childMsg,
                        bubbles: true,
                        composed: true
                    })
                );
                this.showSuccessToast('Offer Accepted');

                    }
                    

                }
            })
        }
    }
  }

    @wire(getRecord, {
        recordId: '$applicationId',
        fields: [APPLICANT_FIELD, PROGRAM_CODE, APPLICANT_STATE_FIELD]
    })
    wiredResult({ error, data }) {
        if (error) {
            console.log('Error fetching applicant info');
        } else if (data) {
            console.log('Wired Data '+JSON.stringify(data))
            this.applicantId = data.fields.Applicant__c.value;
            this.pgmCode = data.fields.Program_Code__c.value;
            this.applicantState = data.fields.Applicant_State_Management__c.value;
            this.loadUploadConfig();

            if (this.applicantState === 'Offer Accepted') {
               // this.isPaymentPending = false;
            }
        }
    }

    handleShirtSizeChange(event){
        this.tshirtSize = event.target.value
        
    }

    handleAcceptanceSuccess() {
    
    console.log('Inside Acceptance Success in apOfferAcceptanceChild');

    const childMsg = {
        admissionId: this.admissionId,
        applicationId: this.applicationId
    };

    // -------- POLLING LOGIC FOR UP TO 2 MINUTES --------
    let attempts = 0;
    const intervalMs = 5000;  // poll every 5s
    const maxAttempts = 70;   // 70 × 50s = 350s 

    const intervalId = setInterval(() => {
        attempts++;

        returnPaymentRecord({
            ApplicationId: this._applicationId,
            Type: 'Offer Acceptance Fee'
        })
        .then((result) => {
            console.log(`Polling attempt ${attempts}:`, result);

            if (result) {
                console.log("Payment record found → sending event");
                //Update Account

                
                this.isPaymentPending = false;
                this.showSuccessToast('Payment Successful!');
                clearInterval(intervalId);

                this.dispatchEvent(
                    new CustomEvent('updateadmissionaccept', {
                        detail: childMsg,
                        bubbles: true,
                        composed: true
                    })
                );
            }

            if (attempts >= maxAttempts) {
                clearInterval(intervalId);
                console.error("Payment record not found within 2 minutes.");

                this.showToastError(
                    "Payment Delay",
                    "Your payment is still processing. Please refresh after a few minutes."
                );
            }
        })
        .catch((error) => {
            console.error("Polling error:", error);
        });

    }, intervalMs);

    const fields = {};
                fields[ACCOUNT_ID.fieldApiName] = this.applicantId;
                fields[TSHIRT_FIELD.fieldApiName] = this.tshirtSize;
                const recordInput = { fields };
                updateRecord(recordInput)
        .then(() => {
            console.log('Updated Account Successfully ');
        })
        .catch((error)=>{
            console.log('Error While updating Account ',error)
        })
}


    // ---------------- Upload Handlers ----------------

    async handleAcceptanceUpload(event) {
        this.showSuccessToast('Acceptance Letter Uploaded Successfully', '');
        console.log(JSON.stringify(event.detail.files))
        const uploadedFile = event.detail.files[0];
        const contentVersionId = uploadedFile.contentVersionId;
        const contentDocumentId = uploadedFile.documentId;
       await getDistributionUrl({contentVersionId:contentVersionId,entity:'Acceptance Letter'})
        .then((result)=>{
            if(result){
                return linkDocumentDetails({
                    applicationId: this._applicationId,
                    contentDocumentId: contentDocumentId,
                    docCode: 'SignedAcceptanceLetter',
                    contentVersionId: contentVersionId
                });
            }
        })
        .then(() => {
            this.isLoaded = false;
            this.getDocuments();
        })
        .catch((error)=>{
            console.log(JSON.stringify(error))
        })
        
        this.isAcceptanceLetterPresent = true;
        this.updateUploadCompletion();
    }

   async handleOfferUpload(event) {
        console.log(JSON.stringify(event.detail.files))
        const uploadedFile = event.detail.files[0];
        const contentVersionId = uploadedFile.contentVersionId;
        const contentDocumentId = uploadedFile.documentId;
        this.showSuccessToast('Offer Letter Uploaded Successfully', '');
        await getDistributionUrl({contentVersionId:contentVersionId,entity:'Offer Letter'})
        .then((result)=>{
            if(result){
                return linkDocumentDetails({
                    applicationId: this._applicationId,
                    contentDocumentId: contentDocumentId,
                    docCode: 'SignedOfferLetter',
                    contentVersionId: contentVersionId
                });
            }
        })
        .then(() => {
            this.isLoaded = false;
            this.getDocuments();
        })
        .catch((error)=>{
            console.log(JSON.stringify(error))
        })
        this.isOfferLetterPresent = true;
        this.updateUploadCompletion();
    }



    showSuccessToast(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success',
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }

    // ---------------- Download ----------------

    handleDownloadAnnexure(event) {
        const annexureUrl = event.target.dataset.id;

        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url: annexureUrl }
        }).then((url) => window.open(url, "_blank"));
    }

    handleDownloadAcceptance() {
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: { url: this.acceptanceLetterUrl }
        }).then((url) => window.open(url, "_blank"));
    }

    async handleAcceptanceDelete(){
        console.log('Clicked AcceptanceDelete contentDocumentId ',this.acceptanceLetterId)
        this.isLoaded = false
       await deleteDocument({contentDocumentId:this.acceptanceLetterId,entity:'Acceptance'})
        .then((result)=>{
            console.log('Result ',JSON.stringify(result))
            if(result == 'Acceptance'){
                this.isAcceptanceLetterPresent = false;
                this.acceptanceLetterUrl = '';
                this.showSuccessToast(result+' Letter Removed')
                this.getDocuments();
                this.isLoaded = true
            }
        })
        .catch((error)=>{
            console.log('Error deleting Acceptance Letter ',JSON.stringify(error))
        })
    }

    async handleOfferDelete(){
        console.log('Clicked OfferDelete contentDocumentId ',this.acceptanceLetterId)
        this.isLoaded = false
       await deleteDocument({contentDocumentId:this.offerLetterId,entity:'Offer'})
        .then((result)=>{
            console.log('Result ',JSON.stringify(result))
            if(result == 'Offer'){
                this.isOfferLetterPresent = false;
                this.offerLetterLink = '';
                this.showSuccessToast(result+' Letter Removed')
                this.getDocuments();
                this.isLoaded = true
            }
        })
        .catch((error)=>{
            console.log('Error deleting Acceptance Letter ',JSON.stringify(error))
        })
    }

    getDocuments() {
        if (this._applicationId && this._admissionId) {
            console.log('Fetching Documents for ApplicationId: ', this._applicationId, ' and AdmissionId: ', this._admissionId);
            getAcceptanceLetterFileUrl({ applicationId: this._applicationId })
                .then((result) => {
                    console.log('Acceptance Letter URL ',result);
                    this.acceptanceLetterUrl = result || '';
                    this.hasAcceptanceLetterDownload = !!this.acceptanceLetterUrl;
                    this.updateUploadCompletion();
                })
                .catch((error) => console.log(JSON.stringify(error)));

            if (!this._offerLetterUrl) {
                getOfferLetterFileUrl({ admissionId: this._admissionId })
                    .then((result) => {
                        this._offerLetterUrl = result || '';
                        this.hasOfferLetterDownload = !!this._offerLetterUrl;
                        this.updateUploadCompletion();
                    })
                    .catch((error) => console.log(JSON.stringify(error)));
            }

            getProgramSpecificDocuments({ admissionId: this._admissionId })
                .then((result) => {
                    this.isLoaded = true;

                    if (result) {
                        this.annexures = (result.annexures || []).map((item, index) => ({
                            Id: index + 1,
                            name: item.annexureName,
                            value: item.annexureUrl
                        }));

                    } else {
                        this.annexures = [];
                    }
                })
                .catch((error) => console.log(JSON.stringify(error)));

            checkUploadedDocuments({ applicationId: this._applicationId })
                .then((result) => {
                    console.log('Received Result From Docs ',JSON.stringify(result))
                    this.isOfferLetterPresent = result.offerLetter === 'true';
                    this.isAcceptanceLetterPresent = result.acceptanceLetter === 'true';
                    if(this.isOfferLetterPresent ){
                        this.offerLetterLink = result.offerLetterUrl;
                        this.offerLetterId = result.offerLetterId;
                    }
                    if(this.isAcceptanceLetterPresent ){
                        this.acceptanceLetterLink = result.acceptanceLetterUrl;
                        this.acceptanceLetterId = result.acceptanceLetterId
                    }
                    this.updateUploadCompletion();
                });
        }
    }

    loadUploadConfig() {
        if (!this.pgmCode) {
            return;
        }

        getOfferUploadConfig({ programCode: this.pgmCode })
            .then((result) => {
                this.showUploadOfferDocuments = !!result?.showUploadOfferDocuments;
                this.showUploadAcceptDocuments = !!result?.showUploadAcceptDocuments;
                this.updateUploadCompletion();
            })
            .catch((error) => console.log(JSON.stringify(error)));
    }

    updateUploadCompletion() {
        const offerRequirementComplete = !this.showOfferUploadSection || this.isOfferLetterPresent;
        const acceptanceRequirementComplete = !this.showAcceptanceUploadSection || this.isAcceptanceLetterPresent;
        this.isUploaded = offerRequirementComplete && acceptanceRequirementComplete;

        this.dispatchEvent(new CustomEvent('docstatuschange', {
            detail: {
                applicationId: this.applicationId,
                hasPendingDocuments: !this.isUploaded
            },
            bubbles: true,
            composed: true
        }));
    }

    renderedCallback() {
        if (!this.isUploaded) {
            this.updateUploadCompletion();
        }
    }
}