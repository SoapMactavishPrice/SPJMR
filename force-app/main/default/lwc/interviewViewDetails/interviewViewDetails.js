import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';

const STATUS_VARIANT = {
    'Complete'    : 'slds-badge_success',
    'Pending'     : 'slds-badge_warning',
    'Not Started' : 'slds-badge_neutral'
};

export default class InterviewViewDetails extends LightningElement {

    @track slotMasterId   = '';
    @track _bookings      = [];
    @track activeBookingId = '';
    @track isLoading      = true;
    @track error          = '';

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
            if (data.length > 0) {
                this.activeBookingId = data[0].id;
            }
            this.error = '';
        } else if (error) {
            this.error = error.body?.message || 'Error loading bookings.';
            this._bookings = [];
        }
    }

    get isSingle()   { return this._bookings.length === 1; }
    get isMultiple() { return this._bookings.length > 1; }
    get isEmpty()    { return !this.isLoading && this._bookings.length === 0; }

    get singleBookingId()     { return this.isSingle ? this._bookings[0].id : null; }
    get singleEvalStatus()    { return this.isSingle ? this._bookings[0].evalStatus : ''; }
    get singleEvalBadgeClass(){ return `slds-badge eval-badge ${STATUS_VARIANT[this.singleEvalStatus] || 'slds-badge_neutral'}`; }

    get bookings() {
        return this._bookings.map((b, idx) => ({
            ...b,
            rowNum        : idx + 1,
            evalBadgeClass: `slds-badge eval-badge ${STATUS_VARIANT[b.evalStatus] || 'slds-badge_neutral'}`
        }));
    }

    get tabItems() {
        return this._bookings.map((b, idx) => ({
            id      : b.id,
            label   : b.applicantName || `Applicant ${idx + 1}`,
            liClass : `slds-tabs_default__item${b.id === this.activeBookingId ? ' slds-is-active' : ''}`
        }));
    }

    get activeBooking() {
        return this._bookings.find(b => b.id === this.activeBookingId) || null;
    }

    get activeEvalBadgeClass() {
        const status = this.activeBooking?.evalStatus || 'Not Started';
        return `slds-badge eval-badge ${STATUS_VARIANT[status] || 'slds-badge_neutral'}`;
    }

    handleTabClick(event) {
        this.activeBookingId = event.currentTarget.dataset.id;
    }
}
