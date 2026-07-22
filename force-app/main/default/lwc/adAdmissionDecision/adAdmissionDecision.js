import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords  } from 'lightning/uiRelatedListApi';
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import STATE_MGMT_FILED from "@salesforce/schema/Application__c.Applicant_State_Management__c";
import { NavigationMixin } from 'lightning/navigation';
import AdAdmissionDecisionCreateModal from 'c/adAdmissionDecisionCreateModal';
import PGM_CODE_FIELD from "@salesforce/schema/Application__c.Program_Code__c";
export default class AdmissionDecision extends NavigationMixin(LightningElement) {

    _recordId;
    //isGMP=false;
    offerAcceptedDate='';
    isAccepted = false;
    isDeclined = false;
    offerDecision = '';
    isDecisionPresent = false;
    isWaitlisted = false
    isNotEligible = false
    admId = ''
    @api
    get recordId(){
        return this._recordId;
    }
    set recordId(value){
        this._recordId = value;
    }

    @wire(getRecord,{recordId:'$recordId',fields:[STATE_MGMT_FILED,PGM_CODE_FIELD]})
    applicationInfo;

    

    get isWithdrawn(){
        if (!this.applicationInfo?.data) return false;
        return getFieldValue(this.applicationInfo.data,STATE_MGMT_FILED) =='Withdrawn'
    }

    get isGmp(){
        if(!this.applicationInfo?.data) return false;
        console.log('PGM Code is ',getFieldValue(this.applicationInfo.data,PGM_CODE_FIELD))
        return getFieldValue(this.applicationInfo.data,PGM_CODE_FIELD) == 'GMP'
    }
        

    @wire(getRelatedListRecords , {
        parentRecordId: '$recordId',
        relatedListId: 'Admission_Decisions__r',
        fields:['Admission_Decision__c.Offer_Acceptance_Date__c','Admission_Decision__c.Result__c','Admission_Decision__c.Name',
            'Admission_Decision__c.Offer_Accepted__c','Admission_Decision__c.Offer_Letter_Date__c',
            'Admission_Decision__c.Offer_Declined__c','Admission_Decision__c.Program_Code__c','Admission_Decision__c.Id'
        ]
    })
    listInfo({ error, data }) {
        if (data) {
            if(data.records.length > 0 && data){
                const record = data.records[0].fields
                this.isDecisionPresent = true;
                //this.isGMP = record.Program_Code__c?.value == 'GMP'?true:false
                this.decisionName = record.Name?.value;
                
                this.offerDecision = record.Result__c?.value
                if(this.offerDecision == 'Waitlisted'){
                    this.isWaitlisted = true
                }
                else if(this.offerDecision == 'Not Eligible'){
                    this.isNotEligible = true
                }
                this.isAccepted = record.Offer_Accepted__c?.value == true?true:false
                this.isDeclined = record.Offer_Declined__c?.value == true?true:false
                this.admId = record.Id.value;
                if(this.isAccepted){
                    this.offerAcceptedDate = record.Offer_Acceptance_Date__c?.value
                }
            }
            console.log('Records:', JSON.stringify(data.records));
            console.log('GMP Value ',this.isGMP)
            
        } else if (error) {
            console.error('Error:', error);
        }

        
    }
    handleDecisionClick(){
            this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.admId,
                actionName: 'view',
            },
        })
        }

        async handleCreateOffer() {
                console.log('Offer Ceration clicked.Values are ',this.isGMP)
        await AdAdmissionDecisionCreateModal.open({
            applicationId: this.recordId,
            isGmp: this.isGmp
        }).then((result)=>{
            console.log('Modal closed',result,'H')
            if(result && result.lenght!=0){
                this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: result,
                actionName: 'view',
            },
        })
            }
        })


        }
}