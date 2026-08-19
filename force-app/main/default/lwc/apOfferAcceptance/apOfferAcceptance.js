import { LightningElement, api, track,wire } from 'lwc';
import getEligibleAdmissionDecisions from '@salesforce/apex/ApAccountProgramController.getEligibleAdmissionDecisions'
import { NavigationMixin } from 'lightning/navigation';
import ApDeclineWithdrawalQuestionnaire from 'c/apDeclineWithdrawalQuestionnaire';
import DECLINE_OFFER from '@salesforce/schema/Admission_Decision__c.Offer_Declined__c'
import ACCEPT_OFFER from '@salesforce/schema/Admission_Decision__c.Offer_Accepted__c'
import ACCEPTANCE_DATE from '@salesforce/schema/Admission_Decision__c.Offer_Acceptance_Date__c'
import ID_FIELD from "@salesforce/schema/Admission_Decision__c.Id";
import { updateRecord } from 'lightning/uiRecordApi';
import STAGE_MGMT from '@salesforce/schema/Application__c.Applicant_State_Management__c'
import APPLICATION_ID from '@salesforce/schema/Application__c.Id'
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import Id from '@salesforce/user/Id';
import EMAIL_FIELD from '@salesforce/schema/User.Email'
import FIRST_NAME from '@salesforce/schema/User.FirstName'
import LAST_NAME from '@salesforce/schema/User.LastName'

export default class ApOfferAcceptance extends NavigationMixin(LightningElement) {
    @track offers = [];
    offerRejected = false
    userId = Id;

    isOfferDownloadHidden(offer) {
        const state = offer?.applicantStateManagement || '';
        return state === 'Offer Not Accepted' || state === 'Withdrawn';
    }

    get showActiveOfferDownload() {
        return this.activeOffer && !!this.activeOffer.offerLetterLink && !this.isOfferDownloadHidden(this.activeOffer);
    }
    isDisabled = false
    userEmail = '';
    userName = '';
    showAcceptConfirm = false;
    pendingAcceptAdmissionId = '';
    pendingAcceptApplicationId = '';
    activeOffer = null;
    activeOfferDocStatusReady = false;
    _initialActiveOfferPending = false;

    get isViewingAcceptance() {
        return this.activeOffer !== null;
    }

    get showActivePendingDocuments() {
        if (!this.activeOffer) {
            return false;
        }
        if (!this.activeOfferDocStatusReady) {
            return this._initialActiveOfferPending;
        }
        return this.activeOffer.hasPendingDocuments === true;
    }

    get showActiveWithdraw() {
        return this.activeOffer?.applicantStateManagement === 'Offer Accepted';
    }

    @wire(getRecord, {recordId:'$userId',fields:[EMAIL_FIELD,FIRST_NAME,LAST_NAME]})
    wiredUser({error,data}){
        if(data){
            this.userEmail = getFieldValue(data,EMAIL_FIELD)
            this.userName = getFieldValue(data,FIRST_NAME) +' '+ getFieldValue(data,LAST_NAME)
        }
        else if(error){
            console.log('Hey Error Occured while fetching User Email ',JSON.stringify(error))
        }
    }

    handleAccept(event) {
        this.pendingAcceptAdmissionId = event.currentTarget.dataset.admid
        this.pendingAcceptApplicationId = event.currentTarget.dataset.id
        console.log('Admission Id', this.pendingAcceptAdmissionId)
        this.showAcceptConfirm = true;
    }

    closeAcceptConfirm() {
        this.showAcceptConfirm = false;
        this.pendingAcceptAdmissionId = '';
        this.pendingAcceptApplicationId = '';
    }

    async confirmAcceptOffer() {
        const admId = this.pendingAcceptAdmissionId;
        if (!admId) {
            this.closeAcceptConfirm();
            return;
        }

        this.showAcceptConfirm = false;
        const fields = {};
        fields[ID_FIELD.fieldApiName] = admId;
        fields[ACCEPT_OFFER.fieldApiName] = true;
        fields[DECLINE_OFFER.fieldApiName] = false;
        let today = new Date();
        let formattedDate = `${today.getFullYear()}-${(today.getMonth() + 1).toString().padStart(2, '0')}-${today.getDate().toString().padStart(2, '0')}`;
        fields[ACCEPTANCE_DATE.fieldApiName] = formattedDate;

        try {
            await updateRecord({ fields });
            this.showSuccessToastMessage('Offer Accepted', '');
        } catch (error) {
            console.log('Could not Update Admission record', JSON.stringify(error));
            this.showErrorToastMessage('Could not accept offer', this.getErrorMessage(error));
            this.pendingAcceptAdmissionId = '';
            this.pendingAcceptApplicationId = '';
            return;
        }

        this.offers = this.offers.map((item) => {
            if (item.admissionDecisionId !== admId) {
                return item;
            }
            return {
                ...item,
                selectedAccepted: true,
                selectedRejected: false,
                showButtons: false,
                showWithdrawButton: true,
                offerAccepted: true,
                isOfferAcceptedState: true,
                hasPendingDocuments: false,
                applicantStateManagement: 'Offer Accepted'
            };
        });
        this.activeOffer = this.offers.find((item) => item.admissionDecisionId === admId) || null;
        this._initialActiveOfferPending = this.activeOffer?.hasPendingDocuments === true;
        this.activeOfferDocStatusReady = false;
        this.pendingAcceptAdmissionId = '';
        this.pendingAcceptApplicationId = '';
    }

    handleViewAcceptance(event) {
        const admId = event.currentTarget.dataset.admid;
        const offer = this.offers.find((item) => item.admissionDecisionId === admId) || null;
        this.activeOffer = offer;
        this._initialActiveOfferPending = offer?.hasPendingDocuments === true;
        this.activeOfferDocStatusReady = false;
    }

    handleBackToOffers() {
        this.activeOffer = null;
        this.activeOfferDocStatusReady = false;
        this._initialActiveOfferPending = false;
    }

    async handleReject(event) {

        const applicationId = event.currentTarget.dataset.id
        const admId = event.currentTarget.dataset.admid
        console.log('Admission Id', applicationId)
        this.offers.forEach((item) => {
            if (item.admissionDecisionId == admId) {
                item.selectedRejected = true
                item.selectedAccepted = false
                item.showButtons = false
            }
        })
        const result = await ApDeclineWithdrawalQuestionnaire.open({
            size: 'large',
            description: 'Decline Questionnaire for Rejection',
            content: {
                applicationId: applicationId,
                type: 'Decline'
            },
        });
        if (result) {
            this.updateApplicationRecord(applicationId, 'decline')
            this.showSuccessToastMessage('Offer Declined','')
           this.updateAdmissionRecord(admId, 'decline')
        } else {
            this.offers = this.offers.map((item) => {
                if (item.admissionDecisionId == admId) {
                    const shouldShowButtons = item.offerDeclined !== true && item.offerAccepted !== true && item.isWithdrawDisabled !== true
                    return {
                        ...item,
                        selectedRejected: false,
                        selectedAccepted: false,
                        showButtons: shouldShowButtons
                    };
                }
                return item;
            });
        }
    }

    handleUpdateAdmissionAccept(event) {
        console.log('Inside UpdateAdmisisonAccept in apOfferAcceptance')
        const admissionId = event.detail.admissionId
        const applicationId = event.detail.applicationId
        console.log('Received Child Id ', admissionId)
        this.updateAdmissionRecord(admissionId, 'accept')
        this.updateApplicationRecord(applicationId, 'accept')
        this.offers.forEach((item) => {
            if (item.admissionDecisionId == admissionId) {
                item.selectedAccepted = false
                item.showButtons = false
                item.showWithdrawButton = true
                item.offerAccepted = true
                item.isOfferAcceptedState = true
                item.hasPendingDocuments = false
                item.applicantStateManagement = 'Offer Accepted'
            }
        })
        if (this.activeOffer && this.activeOffer.admissionDecisionId === admissionId) {
            this.activeOffer = {
                ...this.activeOffer,
                isOfferAcceptedState: true,
                applicantStateManagement: 'Offer Accepted',
                hasPendingDocuments: false
            };
        }
    }
    async handleWithdraw(event) {
        const applicationId = event.currentTarget.dataset.id
            const admId = event.currentTarget.dataset.admid
            const result = await ApDeclineWithdrawalQuestionnaire.open({
                size: 'large',
                description: 'Accessible description of modal\'s purpose',
                content: {
                    applicationId: applicationId,
                    userEmail:this.userEmail,
                    userName: this.userName
                },
            });    
            if(result){
                this.updateApplicationRecord(applicationId, 'withdraw')
                this.updateAdmissionRecord(admId, 'withdraw')
            }
            
           

    }

    showSuccessToastMessage(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success',
            mode: 'dismissable'
        }))
    }

    showErrorToastMessage(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
            mode: 'dismissable'
        }))
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Please try again or contact support.';
    }

    updateApplicationRecord(applicationId, action) {
        const fields = {}
        fields[APPLICATION_ID.fieldApiName] = applicationId
        if (action == 'accept') {
            fields[STAGE_MGMT.fieldApiName] = 'Offer Accepted'
        }

        if (action == 'decline') {
            fields[STAGE_MGMT.fieldApiName] = 'Offer Not Accepted'
        }
        if (action == 'withdraw') {
            fields[STAGE_MGMT.fieldApiName] = 'Withdrawn'
        }
        console.log('Action is ',action, ' Id is',applicationId)
        const recordInput = { fields };
        updateRecord(recordInput)
            .then(() => {
                console.log('Updated Application record')
                if(action=='decline'){
                    this.offers.forEach((item)=>{
                        if(item.applicationId==applicationId){
                            item.applicantStateManagement = 'Offer Not Accepted'
                            item.showDownloadOffer = false
                            item.showWithdrawButton = false
                        }
                    })
                    if (this.activeOffer && this.activeOffer.applicationId === applicationId) {
                        this.activeOffer = {
                            ...this.activeOffer,
                            applicantStateManagement: 'Offer Not Accepted',
                            showDownloadOffer: false
                        };
                    }
                }
                if(action=='withdraw'){
                    this.offers.forEach((item)=>{
                        if(item.applicationId==applicationId){
                            item.isWithdrawDisabled=true
                            item.offerAccepted = false
                            item.isOfferAcceptedState = false
                            item.applicantStateManagement = 'Withdrawn'
                            item.hasPendingDocuments = false
                            item.showDownloadOffer = false
                            item.showWithdrawButton = false
                        }
                    })
                    if (this.activeOffer && this.activeOffer.applicationId === applicationId) {
                        this.activeOffer = {
                            ...this.activeOffer,
                            isWithdrawDisabled: true,
                            offerAccepted: false,
                            isOfferAcceptedState: false,
                            applicantStateManagement: 'Withdrawn',
                            hasPendingDocuments: false,
                            showDownloadOffer: false
                        };
                    }
                    this.showSuccessToastMessage('Success','Offer Withdrawn');
                    this.handleBackToOffers();
                }
            })
            .catch((error) => {
                console.log('Could not Update Application record', JSON.stringify(error))
            })
    }

    updateAdmissionRecord(admissionId, action) {
        const fields = {}
        if (action == 'decline') {
            fields[DECLINE_OFFER.fieldApiName] = true
            fields[ACCEPT_OFFER.fieldApiName] = false
        }
        if (action == 'accept') {
            fields[ACCEPT_OFFER.fieldApiName] = true
            fields[DECLINE_OFFER.fieldApiName] = false
            let today = new Date();
            let formattedDate = `${today.getFullYear()}-${(today.getMonth() + 1).toString().padStart(2, '0')}-${today.getDate().toString().padStart(2, '0')}`; 
            fields[ACCEPTANCE_DATE.fieldApiName] = formattedDate
        }
        if (action == 'withdraw') {
            fields[ACCEPT_OFFER.fieldApiName] = false
            fields[DECLINE_OFFER.fieldApiName] = false
        }
        fields[ID_FIELD.fieldApiName] = admissionId

        const recordInput = { fields };

        updateRecord(recordInput)
            .then(() => {
                console.log('Updated Admission record')
                this.offers.forEach((item) => {
                    if (item.admissionDecisionId == admissionId) {
                        if (action == 'decline') {
                            item.offerDeclined = true
                            item.showWithdrawButton = false
                        }
                        if (action == 'accept') {
                            item.offerAccepted = true
                            item.showWithdrawButton = true
                        }
                        
                        

                    }
                })
            })
            .catch((error) => {
                console.log('Could not Update Admission record', JSON.stringify(error))
            })
    }

    handleDownload(event) {
        var publicUrl = event.currentTarget.dataset.id
        console.log('Offer Link', publicUrl)
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__webPage',
            attributes: {
                url: publicUrl
            },

        }).then(url => {
            window.open(url, "_blank")
        })
    }
    handleDocStatusChange(event) {
        const { applicationId, hasPendingDocuments } = event.detail;
        this.offers = this.offers.map((item) => {
            if (item.applicationId === applicationId) {
                const newHasPending = (item.applicantStateManagement === 'Offer Accepted' || item.applicantStateManagement === 'Withdrawn') ? false : hasPendingDocuments;
                return { ...item, hasPendingDocuments: newHasPending };
            }
            return item;
        });
        if (this.activeOffer && this.activeOffer.applicationId === applicationId) {
            const newHasPending = (this.activeOffer.applicantStateManagement === 'Offer Accepted' || this.activeOffer.applicantStateManagement === 'Withdrawn') ? false : hasPendingDocuments;
            this.activeOffer = { ...this.activeOffer, hasPendingDocuments: newHasPending };
            this.activeOfferDocStatusReady = true;
        }
    }

    connectedCallback() {
        getEligibleAdmissionDecisions()
            .then((result) => {
                console.log('Result is', JSON.stringify(result))
                this.offers = result
                this.offers = this.offers.map((item) => {
                    const applicantState = item.applicantStateManagement || '';
                    const offerDownloadHidden = applicantState === 'Offer Not Accepted' || applicantState === 'Withdrawn';
                    return {
                        ...item,
                        offerDeclined: item.offerDeclined === 'true',
                        offerAccepted: item.offerAccepted === 'true',
                        hasPendingDocuments: (applicantState === 'Offer Accepted' || applicantState === 'Withdrawn') ? false : (item.hasPendingDocuments === true || item.hasPendingDocuments === 'true'),
                        selectedAccepted: false,
                        selectedRejected: false,
                        showButtons: item.offerDeclined != 'true' && item.offerAccepted != 'true' && item.isOfferWithdrawn != 'true',
                        showWithdrawButton: applicantState === 'Offer Accepted',
                        showDownloadOffer: !!item.offerLetterLink && !offerDownloadHidden,
                        isWithdrawDisabled: item.isOfferWithdrawn === 'true',
                        isOfferAcceptedState: applicantState === 'Offer Accepted',
                        applicantStateManagement: applicantState
                    }
                })

                console.log(JSON.stringify('Offers ', JSON.stringify(this.offers)))
            })
            .catch((error) => {
                console.log(JSON.stringify(error))

            })
    }


}