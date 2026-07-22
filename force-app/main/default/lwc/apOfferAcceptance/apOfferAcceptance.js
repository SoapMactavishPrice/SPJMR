import { LightningElement, api, track,wire } from 'lwc';
import getEligibleAdmissionDecisions from '@salesforce/apex/ApAccountProgramController.getEligibleAdmissionDecisions'
import { NavigationMixin } from 'lightning/navigation';
import apDeclineQuestionnaireModal from 'c/apDeclineQuestionnaireModal';
import DECLINE_OFFER from '@salesforce/schema/Admission_Decision__c.Offer_Declined__c'
import ACCEPT_OFFER from '@salesforce/schema/Admission_Decision__c.Offer_Accepted__c'
import ACCEPTANCE_DATE from '@salesforce/schema/Admission_Decision__c.Offer_Acceptance_Date__c'
import ID_FIELD from "@salesforce/schema/Admission_Decision__c.Id";
import { updateRecord } from 'lightning/uiRecordApi';
import STAGE_MGMT from '@salesforce/schema/Application__c.Applicant_State_Management__c'
import APPLICATION_ID from '@salesforce/schema/Application__c.Id'
import ApWithdrawalQuestionnaire from 'c/apWithdrawalQuestionnaire';
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
    isDisabled = false
    userEmail = '';
    userName = '';
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
        const applicationId = event.currentTarget.dataset.id
        const admId = event.currentTarget.dataset.admid
        console.log('Admission Id', admId)
        this.offers.forEach((item) => {
            if (item.admissionDecisionId == admId) {
                item.selectedAccepted = true
                item.selectedRejected = false
                item.showButtons = false
            }
        })

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
        const result = await apDeclineQuestionnaireModal.open({

            size: 'large',
            description: 'Decline Questionnaire for Rejection',
            content: applicationId,
        });
        if (result == 'Submitted') {
            this.updateApplicationRecord(applicationId, 'decline')
            this.showSuccessToastMessage('Offer Rejected','')
           this.updateAdmissionRecord(admId, 'decline')
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
                item.offerAccepted = true
            }
        })
    }
    async handleWithdraw(event) {
        const applicationId = event.currentTarget.dataset.id
            const admId = event.currentTarget.dataset.admid
            const result = await ApWithdrawalQuestionnaire.open({
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
                if(action=='withdraw'){
                    this.offers.forEach((item)=>{
                        if(item.applicationId==applicationId){
                            item.isWithdrawDisabled=true
                            item.offerAccepted = false
                        }
                    })
                    this.showSuccessToastMessage('Success','Offer Withdrawn')
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
                        }
                        if (action == 'accept') {
                            item.offerAccepted = true
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
    connectedCallback() {
        getEligibleAdmissionDecisions()
            .then((result) => {
                console.log('Result is', JSON.stringify(result))
                this.offers = result
                this.offers = this.offers.map((item) => {
                    return {
                        ...item,
                        offerDeclined: item.offerDeclined === 'true',
                        offerAccepted: item.offerAccepted === 'true',
                        selectedAccepted: false,
                        selectedRejected: false,
                        showButtons: item.offerDeclined != 'true' && item.offerAccepted != 'true' && item.isOfferWithdrawn != 'true',
                        isWithdrawDisabled: item.isOfferWithdrawn === 'true'
                    }
                })

                console.log(JSON.stringify('Offers ', JSON.stringify(this.offers)))
            })
            .catch((error) => {
                console.log(JSON.stringify(error))

            })
    }


}