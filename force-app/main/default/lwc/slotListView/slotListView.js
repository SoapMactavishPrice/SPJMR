import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSlotMasterList from '@salesforce/apex/FacultyPortal.getSlotMasterList';

export default class SlotListView extends NavigationMixin(LightningElement) {

    data = [];

    formatSalesforceTime(sfTimeValue) {
        if (!sfTimeValue) return '';
        try {
            const dateObj = new Date(sfTimeValue);
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
