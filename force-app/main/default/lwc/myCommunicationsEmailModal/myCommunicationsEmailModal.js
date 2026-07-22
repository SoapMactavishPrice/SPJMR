import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import emailModal from "@salesforce/resourceUrl/emailModal";
import { loadStyle } from "lightning/platformResourceLoader";
export default class MyCommunicationsEmailModal extends LightningModal {
    @api payload;
     connectedCallback() {
        //loadStyle(this,emailModal)
        console.log(this.payload.Body)
        
    }

}