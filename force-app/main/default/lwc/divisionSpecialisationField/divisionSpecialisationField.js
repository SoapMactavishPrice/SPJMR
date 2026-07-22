import { LightningElement, api, track, wire } from 'lwc';
import getSpecialisations from '@salesforce/apex/DivisionSpecialisationHandler.getSpecialisations';

export default class SpecialisationLookup extends LightningElement {
    @api recordId; // Division Id
    @track options = [];
    @track selectedValue;

    @wire(getSpecialisations, { divisionId: '$recordId' })
    wiredSpecs({ error, data }) {
        if(data){
            this.options = data;
        } else if(error){
            console.error(error);
        }
    }

    handleChange(event){
        this.selectedValue = event.detail.value;
        // Optional: dispatch value to record edit form
        const changeEvent = new CustomEvent('lookupchange', {
            detail: this.selectedValue
        });
        this.dispatchEvent(changeEvent);
    }
}