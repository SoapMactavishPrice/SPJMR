import { LightningElement,api } from 'lwc';
import getPaymentDetails from '@salesforce/apex/RazorpayPaymentHandler.getPaymentDetails';
import { updateRecord } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import STATUS_FIELD from "@salesforce/schema/Application__c.Application_Status__c";  
export default class AfPaymentsContainerGMP extends LightningElement {
    successFee = true
    name=''
    email = ''
    phone = ''
    total = '0';
    subtotal = '0';
    applicationFee = '0';
    pgmCode = '';    
    isAcceptance = false
    isPaymentDone = false
    isLoaded = false
    _applicationId;
    
    @api
    set applicationId(value) {
        this._applicationId = value;
          
    }
    
    get applicationId() {
        return this._applicationId;
    }

    

    updateApplication(){
         
        const fields = {}
        fields[STATUS_FIELD.fieldApiName] = 'Paid';
        const recordInput = { fields };
        updateRecord(recordInput)
        .then(() => {
            console.log('Updated Application Successfully')
            this[NavigationMixin.Navigate]({
                            type: 'comm__namedPage',
                            attributes: {
                                name: 'ApplicationList__c'   // developer name of the page
                            },
                            
                        });
        })
        .catch((error) => {
            console.log('Error Updating ',JSON.stringify(error))
        })
    }

    async connectedCallback(){
        console.log('Application Id in payment is ',this._applicationId)
        await getPaymentDetails({applicationId:this._applicationId})
        .then((result) => {
            console.log('Payment Details ',JSON.stringify(result))
    if (result) {
        console.log('Payment Details ',JSON.stringify(result))
        this.name = result.applicantName || '';
        this.email = result.applicantEmail || '';
        this.phone = result.applicantPhone || '';
        this.total = this.subtotal = this.applicationFee = result.applicationFee || '0';
        this.pgmCode = result.programCode;
        this.isPaymentDone = result.paymentStatus == 'paid'?true:false;
        this.isLoaded = true
    }
})

        .catch((error)=>{
            console.log('Error Retrieving ',JSON.stringify(error))
        })
    }
}