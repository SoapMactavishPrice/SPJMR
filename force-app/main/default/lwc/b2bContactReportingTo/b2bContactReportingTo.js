import { LightningElement, api, track } from 'lwc';
import getFullHierarchyContactsFromContact from '@salesforce/apex/AccountContactService.getFullHierarchyContactsFromContact';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import CONTACT_ID from '@salesforce/schema/Contact.Id';
import REPORTING_TO from '@salesforce/schema/Contact.ReportsToId';

export default class B2bContactReportingTo extends LightningElement {

    _recordId;

    @track contactOptions = [];
    @track hasOptions = false;
    @track localRecordId;

    selectedContactId;
    error;

    @api
    set recordId(value) {
        console.log('Setter received recordId:', value);

        this._recordId = value;
        this.localRecordId = value;

        if (value) {
            this.loadContacts();
        }
    }

    get recordId() {
        return this._recordId;
    }

    loadContacts() {
        console.log('Calling Apex with:', this.recordId);

        getFullHierarchyContactsFromContact({ contactId: this.recordId })
            .then(data => {
                console.log('Found data:', JSON.stringify(data));

                this.contactOptions = data.map(con => ({
                    label: `${con.Title ? con.Title + ' ' : ''}${con.Name || ''}${con.Designation__c ? ' | ' + con.Designation__c : ''}`,
                    value: con.Id
                }));

                this.hasOptions = this.contactOptions.length > 0;
                this.error = undefined;
            })
            .catch(error => {
                console.error('Error fetching contacts:', error);
                this.error = 'Error fetching contacts';
                this.contactOptions = [];
                this.hasOptions = false;
            });
    }

    handleChange(event) {
        this.selectedContactId = event.detail.value;
    }

    handleSave() {
        if (!this.selectedContactId) {
            this.showToast('Error', 'Please select a contact', 'error');
            return;
        }

        const fields = {};
        fields[CONTACT_ID.fieldApiName] = this.recordId;
        fields[REPORTING_TO.fieldApiName] = this.selectedContactId;

        updateRecord({ fields })
            .then(() => {
                this.showToast('Success', 'Reporting To updated successfully', 'success');
            })
            .catch(error => {
                const message = this.reduceErrors(error);
                this.showToast('Error', message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        }

        if (error.body?.output?.fieldErrors) {
            return Object.values(error.body.output.fieldErrors)
                .flat()
                .map(e => e.message)
                .join(', ');
        }

        if (error.body?.output?.errors) {
            return error.body.output.errors.map(e => e.message).join(', ');
        }

        return error.body?.message || 'Unknown error occurred';
    }
}