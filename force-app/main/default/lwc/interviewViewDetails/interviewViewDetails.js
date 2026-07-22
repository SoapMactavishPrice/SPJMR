import { LightningElement,wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
export default class InterviewViewDetails extends LightningElement {

    recordId = ''

     @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            console.log('Page ref Interview View is', currentPageReference)
            this.recordId = currentPageReference.attributes.recordId;
        }
    }
}