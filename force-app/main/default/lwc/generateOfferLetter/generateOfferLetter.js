import { LightningElement,api,wire } from 'lwc';
import generateOffer from '@salesforce/apex/OfferLetterGenerator.generateOffer';
import invokeSendEmailFlow from '@salesforce/apex/OfferLetterGenerator.invokeSendEmailFlow';
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; 
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';
export default class GenerateOfferLetter extends NavigationMixin(LightningElement) {
  @api recordId  

    @api invoke() { 
    console.log("Hi, I'm an action.",this.recordId, this._recordId);
    generateOffer({admId:this.recordId})
      .then((result)=>{
          console.log('Result is ',result)
          window.open(result,'_blank');
          const evt = new ShowToastEvent({
          title: 'Offer Letter Generated',
          message: '',
          variant: 'success',
          mode: 'dismissable'
      });
      this.dispatchEvent(evt);
      
       const res = LightningConfirm.open({
            message: 'Send Offer Letter to Applicant?',
            variant: 'headerless', // a red theme intended for error states
            label: 'Send Offer Letter to Applicant?', // this is the header text
        });
        if(res){
            invokeSendEmailFlow({admId:this.recordId})
        }
      this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,   // Record ID of the current page
                objectApiName: 'Admission_Decision__c',  // Object name of the current record
                actionName: 'view'         // Action to perform (view)
            }
        });

        


    })
    .catch((error)=>{
        console.log('Could not create PDF ',JSON.stringify(error));
    })
  }

  



// @api
// get recordId() {
//     return this._recordId;
// }

// set recordId(recordId) {
//     if (recordId !== this._recordId) {
//         this._recordId = recordId;
//    }
// }
    
connectedCallback(){
    console.log("Hi, I'm in conn callnbacl.",this.recordId, this._recordId);
}

   
}