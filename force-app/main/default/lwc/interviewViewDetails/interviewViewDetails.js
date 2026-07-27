import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';

const STATUS_VARIANT = {
    'Complete'    : 'slds-badge slds-theme_success',
    'Pending'     : 'slds-badge slds-theme_warning',
    'Not Started' : 'slds-badge'
};

export default class InterviewViewDetails extends LightningElement {

    @track slotMasterId    = '';
    @track _bookings       = [];
    @track isLoading       = true;
    @track error           = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.slotMasterId = currentPageReference.attributes.recordId;
        }
    }

    @wire(getSlotBookingsBySlotMaster, { slotMasterId: '$slotMasterId' })
    wiredBookings({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._bookings = data;
            this.error = '';
        } else if (error) {
            this.error = error.body?.message || 'Error loading bookings.';
            this._bookings = [];
        }
    }

    get isEmpty() { return !this.isLoading && this._bookings.length === 0; }

    get headerInfo() {
        if (!this._bookings.length) return null;
        const b = this._bookings[0];
        return {
            programName     : b.programName     || '—',
            roundMasterName : b.roundMasterName || '—',
            panelMasterId   : b.panelMasterId   || '—'
        };
    }

    get firstBookingId() {
        return this._bookings.length ? this._bookings[0].id : null;
    }

    get tableRows() {
        return this._bookings.map((b, idx) => ({
            ...b,
            rowNum        : idx + 1,
            evalBadgeClass: STATUS_VARIANT[b.evalStatus] || 'slds-badge'
        }));
    }
}