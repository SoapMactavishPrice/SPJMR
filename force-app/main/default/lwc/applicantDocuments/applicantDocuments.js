import { LightningElement, api, wire, track } from 'lwc';
import getApplicantDocuments from '@salesforce/apex/ApplicantDocumentController.getApplicantDocuments';

export default class ApplicantDocuments extends LightningElement {
    @api recordId; // Application__c Id
    @track docs = [];

    @wire(getApplicantDocuments, { applicationId: '$recordId' })
    wiredDocs({ data, error }) {
        if (data) {
            this.docs = data;
        } else if (error) {
            console.error(error);
        }
    }
}