import { LightningElement, track, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import LOGO from '@salesforce/resourceUrl/SPJIMR_RGB';

const USER_FIELDS = [
    'User.Name',
    'User.Account.FirstName',
    'User.Account.MiddleName',
    'User.Contact.FirstName',
    'User.Contact.MiddleName',
    'User.Contact.LastName',
    'User.Account.LastName'
];

export default class ApCltHeader extends LightningElement {

    @track userName = '';
    logoUrl = LOGO;

    @wire(getRecord, { recordId: USER_ID, fields: USER_FIELDS })
    wireUser({ error, data }) {
        if (data) {
            const fallbackName = data.fields?.Name?.value;
            const accountFields = data.fields?.Account?.value?.fields;
            const contactFields = data.fields?.Contact?.value?.fields;

            const accountFirstName = accountFields?.FirstName?.value;
            const accountMiddleName = accountFields?.MiddleName?.value;
            const accountLastName = accountFields?.LastName?.value;
            const contactFirstName = contactFields?.FirstName?.value;
            const contactMiddleName = contactFields?.MiddleName?.value;
            const contactLastName = contactFields?.LastName?.value;

            const personAccountName = [
                accountFirstName,
                accountMiddleName,
                accountLastName
            ].filter((part) => part && part.trim());

            const businessAccountContactName = [
                contactFirstName,
                contactMiddleName,
                contactLastName
            ].filter(
                (part) => part && part.trim()
            );

            this.userName = personAccountName.length
                ? personAccountName.join(' ')
                : businessAccountContactName.length
                    ? businessAccountContactName.join(' ')
                : (fallbackName && fallbackName.trim()) || 'Guest User';
        } else if (error) {
            this.userName = 'Guest User';
            console.error('Error fetching user person account name:', error);
        }
    }

    toggleMenu() {
        // dispatch event for the Aura template to listen
        this.dispatchEvent(new CustomEvent('hamburgertoggle', { bubbles: true }));
    }


}