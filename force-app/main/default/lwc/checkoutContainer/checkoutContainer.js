import { LightningElement,wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import {publish, createMessageContext} from 'lightning/messageService';
import LMSCHANNEL from '@salesforce/messageChannel/LWCToVFPage__c'

export default class CheckoutContainer extends LightningElement {
    pageRef;
    messageContext = createMessageContext();
    urlParams = {};
    
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.pageRef = currentPageReference;
            this.urlParams = currentPageReference.state; // Contains key-value pairs of URL query parameters
            // Example: If URL is ...?c__param1=value1&c__param2=value2
            // this.urlParams will be { c__param1: 'value1', c__param2: 'value2' }
        }
        localStorage.setItem('orderId',this.urlParams.orderId)
        localStorage.setItem('amount',this.urlParams.amount)
        localStorage.setItem('payee_name',this.urlParams.payee_name)
        console.log('URL Parameters:', this.urlParams, 'Page Ref:', this.pageRef, 'Page Ref State:', this.pageRef.state)
    }


}