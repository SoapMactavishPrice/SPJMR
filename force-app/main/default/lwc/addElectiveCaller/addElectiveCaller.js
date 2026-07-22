import { LightningElement, track, api, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
export default class AddElectiveCaller extends LightningElement {
     @api recordId;
    @api objectApiName;
    @track showModal = false;
    connectedCallback() {
        setTimeout(() => {
            this.showModal=true;
        }, 2000);
    }
    

     closeModal(event) {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}