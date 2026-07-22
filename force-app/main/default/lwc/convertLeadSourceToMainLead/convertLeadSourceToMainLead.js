import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { NavigationMixin } from 'lightning/navigation';
import convertLead from '@salesforce/apex/LeadSourceToLeadController.convertLead';

export default class ConvertLeadSourceToMainLead extends NavigationMixin(LightningElement) {

    @api recordId;
    @api objectApiName;
    @track showSpinner = true;
    @track ResponseMessage = '';
    @track errorResponseMessage = '';

    connectedCallback() {
        setTimeout(() => {
            console.log(this.recordId);
            this.handlerConvertToLead();
            // this.showSpinner = false;
            // this.ResponseMessage = this.recordId;
        }, 2000);
    }

    handlerConvertToLead() {
        convertLead({
            lsId: this.recordId
        }).then(result => {
            this.showSpinner = false;
            this.ResponseMessage = result;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Lead Created Successfully',
                variant: 'success'
            }));
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: result,
                    objectApiName: 'Lead', // Replace with your object API name
                    actionName: 'view'        // Use 'view', 'edit', or 'clone'
                }
            });
            // this.dispatchEvent(new CloseActionScreenEvent());
            // this.dispatchEvent(new RefreshEvent("refresh"));
        }).catch(error => {
            this.showSpinner = false;
            this.errorResponseMessage = error.body.message;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: this.errorResponseMessage,
                variant: 'error'
            }));
        });
    }

}