import { LightningElement, wire, track, api } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import USER_ID from '@salesforce/user/Id';

// Get AccountId field from User object
import ACCOUNT_ID_FIELD from '@salesforce/schema/User.AccountId';

export default class ApMyProfile extends LightningElement {
    @track applicantRecordTypeId;
    @track accountId;

    @api tableLabel = 'My Profile';

    // Fetch Applicant record type dynamically
    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    handleObjectInfo({ data, error }) {
        if (data) {
            const recordTypes = data.recordTypeInfos;
            for (let rtId in recordTypes) {
                if (recordTypes[rtId].name === 'Applicant') {
                    this.applicantRecordTypeId = rtId;
                    break;
                }
            }
        } else if (error) {
            console.error('Error fetching record type info:', error);
        }
    }

    // Get current user's AccountId
    @wire(getRecord, { recordId: USER_ID, fields: [ACCOUNT_ID_FIELD] })
    wireUser({ error, data }) {
        if (data) {
            this.accountId = data.fields.AccountId.value;
        } else if (error) {
            console.error('Error fetching user AccountId:', error);
        }
    }

    handleSuccess() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Applicant details updated successfully',
                variant: 'success'
            })
        );
    }

    handleReset() {
        const inputFields = this.template.querySelectorAll('lightning-input-field');
        if (inputFields) {
            inputFields.forEach(field => {
                field.reset();
            });
        }
    }

    areDetailsVisible = false;

    handleLoad() {
        this.areDetailsVisible = true;
    }

}