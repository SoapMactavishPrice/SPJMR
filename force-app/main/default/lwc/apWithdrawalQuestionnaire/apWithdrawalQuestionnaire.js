import { api, track, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getRecord, getFieldValue, createRecord } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';

import WITHDRAWAL_OBJECT from '@salesforce/schema/Withdrawal_Questionnaire__c';
import APPLICATION_NAME from '@salesforce/schema/Application__c.Name';

import APPLICATION_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.ApplicationId__c';
import APPLICANT_NAME from '@salesforce/schema/Withdrawal_Questionnaire__c.ApplicantName__c';
import EMAIL_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.RegisteredEmail__c';
import INSTITUTE_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.Which_institute_are_you_joining__c';
import REASON1_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.Reason1__c';
import REASON2_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.Reason2__c';
import OTHER1_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.Other1__c';
import OTHER2_FIELD from '@salesforce/schema/Withdrawal_Questionnaire__c.Other2__c';
import OTHER_INSTITUTE from '@salesforce/schema/Withdrawal_Questionnaire__c.OtherInstitute__c';

export default class ApWithdrawalQuestionnaire extends LightningModal {

    applicationField = APPLICATION_FIELD;
    nameField = APPLICANT_NAME;
    emailField = EMAIL_FIELD;
    instituteField = INSTITUTE_FIELD;
    reason1Field = REASON1_FIELD;
    reason2Field = REASON2_FIELD;
    other1Field = OTHER1_FIELD;
    other2Field = OTHER2_FIELD;
    otherInstituteField = OTHER_INSTITUTE;

    isLoaded = false;
    isSubmitDisabled = true;

    // Values
    applicationId;
    applicationLookupId;
    applicationName;
    applicantName;
    registeredEmail;
    institute;
    reason1;
    reason2;
    other1;
    other2;
    otherInstitute;

    recordTypeId = '';

    isOther1 = false;
    isOther2 = false;
    isOtherInstitute = false;

    reasonValues;
    instituteValues;

    @track fields = [];
    _content;

    // 🔹 Fetch Application Name
    @wire(getRecord, {
        recordId: '$applicationLookupId',
        fields: [APPLICATION_NAME]
    })
    wiredApplication({ data, error }) {
        if (data) {
            this.applicationName = getFieldValue(data, APPLICATION_NAME);
        }
        if (error) {
            console.error('Error fetching Application Name', error);
        }
    }

    // 🔹 Object info
    @wire(getObjectInfo, { objectApiName: WITHDRAWAL_OBJECT })
    wiredObjectInfo({ data }) {
        if (data) {
            const rt = data.recordTypeInfos;
            this.recordTypeId =
                Object.keys(rt).find(rti => rt[rti].name === 'Master');
        }
    }

    // 🔹 Picklists
    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: INSTITUTE_FIELD
    })
    wiredInstituteValues({ data }) {
        if (data) {
            this.instituteValues = data.values.map(v => ({
                label: v.label,
                value: v.value
            }));
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: REASON1_FIELD
    })
    wiredReasonValues({ data }) {
        if (data) {
            this.reasonValues = data.values.map(v => ({
                label: v.label,
                value: v.value
            }));
        }
    }

    // 🔹 Modal input
    @api
    get content() {
        return this._content;
    }

    set content(value) {
        this._content = value;

        // Force reactivity for wire
        this.applicationLookupId = null;
        this.applicationLookupId = value.applicationId;

        this.applicationId = value.applicationId;
        this.applicantName = value.userName;
        this.registeredEmail = value.userEmail;

        this.institute = '';
        this.reason1 = '';
        this.reason2 = '';
        this.other1 = '';
        this.other2 = '';
        this.otherInstitute = '';

        this.isLoaded = true;
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;

        switch (field) {
            case 'institute':
                this.isOtherInstitute =
                    this.institute === 'Other (please specify)';
                break;
            case 'reason1':
                this.isOther1 =
                    this.reason1 === 'Any other (please specify)';
                break;
            case 'reason2':
                this.isOther2 =
                    this.reason2 === 'Any other (please specify)';
                break;
        }

        let isValid =
            this.applicationLookupId &&
            this.applicantName &&
            this.registeredEmail &&
            this.institute &&
            this.reason1 &&
            this.reason2;

        if (this.isOtherInstitute) isValid &&= this.otherInstitute;
        if (this.isOther1) isValid &&= this.other1;
        if (this.isOther2) isValid &&= this.other2;

        this.isSubmitDisabled = !isValid;
    }

    async handleSubmit() {
        const result = await LightningConfirm.open({
            message: 'Are you sure you want to withdraw?',
            variant: 'headerless',
            label: 'Withdraw Confirmation'
        });

        if (!result) return;

        const fields = {
            Application__c: this.applicationLookupId,
            ApplicationId__c: this.applicationId,
            ApplicantName__c: this.applicantName,
            RegisteredEmail__c: this.registeredEmail,
            Which_institute_are_you_joining__c: this.institute,
            Reason1__c: this.reason1,
            Reason2__c: this.reason2,
            Other1__c: this.other1,
            Other2__c: this.other2,
            OtherInstitute__c: this.otherInstitute
        };

        createRecord({
            apiName: 'Withdrawal_Questionnaire__c',
            fields
        })
            .then(() => {
                this.close(true);
            })
            .catch(error => {
                console.error(error);
            });
    }
}