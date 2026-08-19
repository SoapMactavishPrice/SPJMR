import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import shouldShowSpecialization from '@salesforce/apex/AdAdmissionDecisionCreateModalController.shouldShowSpecialization';

import ADMISSION_DECISION_OBJECT from '@salesforce/schema/Admission_Decision__c';
import OFFER_DATE from '@salesforce/schema/Admission_Decision__c.Offer_Letter_Date__c';
import SPECIALISATION from '@salesforce/schema/Admission_Decision__c.Specialisation_Master__c';
import RESULT from '@salesforce/schema/Admission_Decision__c.Result__c';
import LAST_DATE_OF_ACCEPTANCE from '@salesforce/schema/Admission_Decision__c.LastDateOfAcceptance__c';
import SIGNED_LETTER_ETA from '@salesforce/schema/Admission_Decision__c.SignedLetterOfAcceptanceEta__c';
import ACCEPTANCE_FEE_ETA from '@salesforce/schema/Admission_Decision__c.PaymentOfTheAcceptanceFeeEta__c';
import FIRST_INSTALLMENT_ETA from '@salesforce/schema/Admission_Decision__c.PaymentOfTheFirstInstallmentEta__c';
import WAITLIST_NUMBER from '@salesforce/schema/Admission_Decision__c.WaitlistNumber__c';

export default class AdAdmissionDecisionCreateModal extends LightningModal {
    @api applicationId;
    @api programCode;

    objectApiName = ADMISSION_DECISION_OBJECT;
    selectedResult = '';
    showSpecialization = false;

    offerDate = OFFER_DATE;
    result = RESULT;
    specialisation = SPECIALISATION;
    lastDateOfAcceptance = LAST_DATE_OF_ACCEPTANCE;
    signedLetterEta = SIGNED_LETTER_ETA;
    acceptanceFeeEta = ACCEPTANCE_FEE_ETA;
    firstInstallmentEta = FIRST_INSTALLMENT_ETA;
    waitlistNumber = WAITLIST_NUMBER;

    get isEligibleForAdmission() {
        return this.selectedResult === 'Eligible for Admission';
    }

    get isWaitlisted() {
        return this.selectedResult === 'Waitlisted';
    }

    @wire(shouldShowSpecialization, { programCode: '$programCode' })
    wiredSpecializationConfiguration({ data, error }) {
        if (data !== undefined) {
            this.showSpecialization = data;
        } else if (error) {
            this.showSpecialization = false;
            console.error(
                'Unable to load specialization visibility configuration:',
                error
            );
        }
    }

    handleResultChange(event) {
        this.selectedResult = event.detail.value;
    }

    handleSubmit(event) {
        event.preventDefault();

        const fields = event.detail.fields;
        fields.Application__c = this.applicationId;

        this.template
            .querySelector('lightning-record-edit-form')
            .submit(fields);
    }

    handleSuccess(event) {
        this.close(event.detail.id);
    }

    handleCancel() {
        this.close();
    }
}