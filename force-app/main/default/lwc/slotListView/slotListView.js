import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSlotMasterList from '@salesforce/apex/FacultyPortal.getSlotMasterList';

export default class SlotListView extends NavigationMixin(LightningElement) {

    data = [];

    formatSalesforceTime(sfTimeValue) {
        if (sfTimeValue === null || sfTimeValue === undefined || sfTimeValue === '') return '';
        try {
            let dateObj;

            if (typeof sfTimeValue === 'number') {
                const base = new Date(1970, 0, 1, 0, 0, 0, 0);
                dateObj = new Date(base.getTime() + sfTimeValue);
            } else if (typeof sfTimeValue === 'string') {
                const match = sfTimeValue.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d{3})?Z?$/);
                if (match) {
                    dateObj = new Date(1970, 0, 1, Number(match[1]), Number(match[2]), Number(match[3] || 0), 0);
                } else {
                    dateObj = new Date(sfTimeValue);
                }
            } else {
                dateObj = new Date(sfTimeValue);
            }

            if (Number.isNaN(dateObj.getTime())) {
                return String(sfTimeValue);
            }

            return dateObj.toLocaleTimeString('en-US', {
                hour: '2-digit',
                minute: '2-digit',
                hour12: true
            });
        } catch (error) {
            console.error('Error parsing time:', sfTimeValue, error);
            return sfTimeValue;
        }
    }

    @wire(getSlotMasterList)
    wiredSlots({ data, error }) {
        if (data) {
            this.data = data.map(slot => ({
                slotId: slot.Id,
                slotCode: slot.Name || '',
                slotDate: slot.SlotDate__c || '',
                startTime: this.formatSalesforceTime(slot.SlotStartTime__c),
                endTime: this.formatSalesforceTime(slot.SlotEndtime__c),
                location: slot.Location__c || '',
                status: slot.Status__c || '',
                mode: slot.Mode__c || ''
            }));
        } else if (error) {
            console.error('Error loading slot list:', error);
        }
    }

    handleSlotClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'SlotMaster__c',
                actionName: 'view'
            }
        });
    }
}