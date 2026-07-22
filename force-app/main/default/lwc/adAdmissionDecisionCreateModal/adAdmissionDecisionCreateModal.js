import { api } from 'lwc';
import LightningModal from 'lightning/modal';

import ADMISSION_DECISION_OBJECT from '@salesforce/schema/Admission_Decision__c';
import OFFER_DATE from '@salesforce/schema/Admission_Decision__c.Offer_Letter_Date__c';
import SPECIALISATION from '@salesforce/schema/Admission_Decision__c.Specialisation_Master__c';
import RESULT from '@salesforce/schema/Admission_Decision__c.Result__c';

export default class AdAdmissionDecisionCreateModal extends LightningModal {
    @api applicationId;
    @api isGmp;

    objectApiName = ADMISSION_DECISION_OBJECT;

    // expose fields for template
    offerDate = OFFER_DATE;
    result = RESULT;
    specialisation = SPECIALISATION;

    handleSubmit(event) {
        event.preventDefault();

        const fields = event.detail.fields;
        fields.Application__c = this.applicationId;

        console.log('Submitting fields:', JSON.stringify(fields));

        this.template
            .querySelector('lightning-record-edit-form')
            .submit(fields);
    }

    handleSuccess(event) {
        console.log(JSON.stringify(event.detail))
        this.close(event.detail.id);
    }
}