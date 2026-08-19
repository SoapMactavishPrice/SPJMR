import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSlotMastersForEvaluator from '@salesforce/apex/InterviewController.getSlotMastersForEvaluator';

export default class SlotListView extends NavigationMixin(LightningElement) {

    data = [];
    activeSlots = [];
    completedSlots = [];
    activeTab = 'active';

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

    @wire(getSlotMastersForEvaluator)
    wiredSlots({ data, error }) {
        if (data) {
            const mapped = data.map(slot => ({
                slotId: slot.id,
                slotCode: slot.name || '',
                slotDate: slot.slotDate || '',
                startTime: this.formatSalesforceTime(slot.slotStartTime),
                endTime: this.formatSalesforceTime(slot.slotEndTime),
                location: slot.locationName || '',
                status: slot.status || '',
                mode: slot.mode || '',
                isCompleted: slot.isCompleted === true,
                statusLabel: slot.isCompleted === true ? 'Completed' : 'Active'
            }));
            this.activeSlots = mapped.filter(s => !s.isCompleted);
            this.completedSlots = mapped.filter(s => s.isCompleted);
            this.data = this.activeSlots;
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

    handleTabClick(event) {
        const tab = event.currentTarget.dataset.tab;
        this.activeTab = tab;
        this.data = tab === 'active' ? this.activeSlots : this.completedSlots;
    }

    get activeTabActiveClass() {
        return this.activeTab === 'active' ? 'tab active' : 'tab';
    }

    get activeTabCompletedClass() {
        return this.activeTab === 'completed' ? 'tab active' : 'tab';
    }
}