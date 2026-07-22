import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import APP_NUM from '@salesforce/schema/Application__c.Name';
import Id from '@salesforce/user/Id';
import APP_EMAIL from '@salesforce/schema/User.Email'
import APPLICATION_NUMBER from '@salesforce/schema/Decline_Questionnaire__c.Your_Application_Id__c';
import APPLICATION_ID from '@salesforce/schema/Decline_Questionnaire__c.Application__c';
import REG_EMAIL from '@salesforce/schema/Decline_Questionnaire__c.Your_registered_Email_Id__c';
import INSTITUTE_NAME from '@salesforce/schema/Decline_Questionnaire__c.Which_institute_are_you_joining__c';
import REASON_1 from '@salesforce/schema/Decline_Questionnaire__c.Reason_1__c';
import REASON_2 from '@salesforce/schema/Decline_Questionnaire__c.Reason_2__c';
import OTHER_REASON from '@salesforce/schema/Decline_Questionnaire__c.Other_Reason__c';
import OTHER_INSTITUTE from '@salesforce/schema/Decline_Questionnaire__c.Other_Institute__c';

export default class ApDeclineQuestionnaireModal extends LightningModal {

    @api content; // Application record Id
    userId = Id
    // Field refs
    applicationField = APPLICATION_NUMBER;
    regEmail = REG_EMAIL;
    instituteName = INSTITUTE_NAME;
    reason1 = REASON_1;
    reason2 = REASON_2;
    otherReason = OTHER_REASON;
    otherInstitute = OTHER_INSTITUTE;

    // UI state
    otherInstituteShow = false;
    otherReasonShow = false;
    isSubmitDisabled = true;

    // Prefilled values
    applicationNumberValue = '';
    regEmailValue = '';

    // Fetch Application Number & Email
    @wire(getRecord, {
        recordId: '$content',
        fields: [APP_NUM]
    })
    wiredApplication({ data, error }) {
        if (data) {
            this.applicationNumberValue =
                getFieldValue(data, APP_NUM);
            

            // Re-validate after async render
            requestAnimationFrame(() => {
                this.handleFormChange();
            });
        }
        if (error) {
            console.error(error);
        }
    }

    @wire(getRecord, {
        recordId: '$userId',
        fields: [APP_EMAIL]
    })
    wiredUser({ data, error }) {
        if (data) {
            this.regEmailValue =
                getFieldValue(data, APP_EMAIL);
           
            // Re-validate after async render
            requestAnimationFrame(() => {
                this.handleFormChange();
            });
        }
        if (error) {
            console.error(error);
        }
    }

    // Form-level validation
    handleFormChange() {
        const inputs = this.template.querySelectorAll(
            'lightning-input-field'
        );

        let isValid = true;

        inputs.forEach(input => {
            // Ignore hidden conditional fields
            if (
                (input.fieldName === this.otherReason.fieldApiName && !this.otherReasonShow) ||
                (input.fieldName === this.otherInstitute.fieldApiName && !this.otherInstituteShow)
            ) {
                return;
            }

            if (!input.value) {
                isValid = false;
            }
        });

        this.isSubmitDisabled = !isValid;
    }

    // Conditional logic
    handleReasonChange(event) {
        this.otherReasonShow = event.target.value === 'Other';
        requestAnimationFrame(() => this.handleFormChange());
    }

    handleInstituteChange(event) {
        this.otherInstituteShow = event.target.value === 'Other';
        requestAnimationFrame(() => this.handleFormChange());
    }

    // Submit
    handleSubmit(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        fields[APPLICATION_ID.fieldApiName] = this.content;
        this.template
            .querySelector('lightning-record-edit-form')
            .submit(fields);
    }

    // Success + confirmation
    async handleSuccess(event) {
        const result = await LightningConfirm.open({
            message:
                'Please confirm upon clicking "Ok" you are rejecting this offer',
            variant: 'headerless',
            label: 'Rejection Confirmation'
        });

        if (result) {
            this.close('Submitted');
        }
    }
}