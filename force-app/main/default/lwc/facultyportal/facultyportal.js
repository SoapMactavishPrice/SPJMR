import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAssignedSlotBookings from '@salesforce/apex/FacultyPortal.getAssignedSlotBookings';

export default class Facultyportal extends NavigationMixin(LightningElement) {

    data = [];

   formatSalesforceTime(sfTimeValue) {
    if (!sfTimeValue) return '';

    try {
        // Create JS Date object directly from Salesforce datetime string
        const dateObj = new Date(sfTimeValue);

        // Format to local readable time
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

    @wire(getAssignedSlotBookings)
wiredBookings({ data, error }) {
    if (data) {
        this.data = data.map((wrapper, index) => {
            const res = wrapper.booking; // the ApplicationSlotBooking__c record
            console.log('start time'+res.SlotMaster__r?.SlotStartTime__c);
            return {
                    slotId: res.Id,
                    applicantId: res.Application__r?.Applicant__c,
                    applicationId: res.Application__c,
                    panelId: res.Panel_Master__c,
                    roundId: res.RoundMaster__c,

                    
                    bookingSlot: res.Name || '',
                    applicantName: res.Application__r?.Applicant__r?.Name || '',
                    applicationName: res.Application__r?.Name || '',
                    panelName: res.Panel_Master__r?.Name || '',
                    roundName: res.RoundMaster__r?.Name || '',
                    slotDate: res.SlotMaster__r?.SlotDate__c || '',
                    startTime: this.formatSalesforceTime(res.SlotMaster__r?.SlotStartTime__c) || '',
                    endTime: this.formatSalesforceTime(res.SlotMaster__r?.SlotEndtime__c) || '',

                    // Evaluation Status (from wrapper in Apex)
                    evaluationStatus: wrapper.evaluationStatus || 'Pending'
            };
        });
    } else if (error) {
        console.error(error);
    }
}


    navigate(recordId, objectApi) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: objectApi,
                actionName: 'view'
            }
        });
    }
   
    handleSlotClick(event) { this.navigate(event.target.dataset.id, 'ApplicationSlotBooking__c'); }  
    handleApplicantClick(event) { this.navigate(event.target.dataset.id, 'Contact'); }
    handleApplicationClick(event) { this.navigate(event.target.dataset.id, 'Application__c'); }
    handlePanelClick(event) { this.navigate(event.target.dataset.id, 'Panel_Master__c'); }
    handleRoundClick(event) { this.navigate(event.target.dataset.id, 'Round_Master__c'); }
}