import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ToastExample extends LightningElement {

    connectedCallback() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Request created !',
                message: 'Request added in the queue to be approved',
                variant: 'success'
            })
        );
    }
}