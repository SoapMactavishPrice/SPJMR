import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';
import getStaticPdfConfig from '@salesforce/apex/InterviewController.getStaticPdfConfig';
import getShowSpecialisationConfig from '@salesforce/apex/InterviewController.getShowSpecialisationConfig';
import getMerittoExtractFileUrl from '@salesforce/apex/InterviewController.getMerittoExtractFileUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, MessageContext } from 'lightning/messageService';
import INTERVIEW_MESSAGE_CHANNEL from '@salesforce/messageChannel/InterviewMessageChannel__c';


const STATUS_VARIANT = {
    'Complete'    : 'slds-badge slds-theme_success',
    'Pending'     : 'slds-badge slds-theme_warning',
    'Not Started' : 'slds-badge'
};

export default class InterviewViewDetails extends NavigationMixin(LightningElement) {

    @track slotMasterId       = '';
    @track _bookings          = [];
    @track isLoading          = true;
    @track error              = '';

    @track showStaticPdfCol   = false;
    @track showSpecialisation = false;
    @track _pdfConfigLoaded   = false;
    _specialConfigLoaded     = false;
    _wiredBookingsResult      = null;

    @wire(MessageContext)
    messageContext;

    subscription = null;

    connectedCallback() {
        this.subscribeToInterviewMessageChannel();
    }

    subscribeToInterviewMessageChannel() {
        if (!this.subscription) {
            this.subscription = subscribe(this.messageContext, INTERVIEW_MESSAGE_CHANNEL, (message) => {this.handleSubscriptionMessage(message);});
        }
    }

    handleSubscriptionMessage(message) {
        if (message && message.action === 'refresh') {
            if (this._wiredBookingsResult) {
                refreshApex(this._wiredBookingsResult)
                    .catch(err => {
                        console.error('Failed to refresh bookings after message', err);
                    });
            }
        }
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.slotMasterId = currentPageReference.attributes.recordId;
        }
    }

    @wire(getSlotBookingsBySlotMaster, { slotMasterId: '$slotMasterId' })
    wiredBookings(result) {
        this._wiredBookingsResult = result;
        const { data, error } = result;
        this.isLoading = false;
        if (data) {
            this._bookings = data;
            this.error = '';
            if (!this._pdfConfigLoaded && data.length > 0) {
                this._pdfConfigLoaded = true;
                this._loadStaticPdfConfig(data[0].programCode || '');
            }
                if (!this._specialConfigLoaded && data.length > 0) {
                    this._specialConfigLoaded = true;
                    this._loadSpecialisationConfig(data[0].programCode || '');
                }
        } else if (error) {
            this.error = error.body?.message || 'Error loading bookings.';
            this._bookings = [];
        }
    }

    async _loadStaticPdfConfig(programCode) {
        try {
            const result = await getStaticPdfConfig({ programCode });
            this.showStaticPdfCol = result === true;
        } catch (err) {
            console.error('Error loading static PDF config', err);
            this.showStaticPdfCol = false;
        }
    }

    async _loadSpecialisationConfig(programCode) {
        try {
            const result = await getShowSpecialisationConfig({ programCode });
            this.showSpecialisation = result === true;
        } catch (err) {
            console.error('Error loading specialisation config', err);
            this.showSpecialisation = false;
        }
    }

    get isEmpty() { return !this.isLoading && this._bookings.length === 0; }

    get headerInfo() {
        if (!this._bookings.length) return null;
        const b = this._bookings[0];
        return {
            programName     : b.programName     || '—',
            roundMasterName : b.roundMasterName || '—',
            locationId      : b.locationId      || null,
            locationName    : b.locationName    || '—'
        };
    }

    get locationUrl() {
        if (this._bookings.length && this._bookings[0].locationId) {
            return '/' + this._bookings[0].locationId;
        }
        return '#';
    }

    get firstBookingId() {
        return this._bookings.length ? this._bookings[0].id : null;
    }

    get tableRows() {
        return this._bookings.map((b, idx) => ({
            ...b,
            rowNum        : idx + 1,
            evalBadgeClass: STATUS_VARIANT[b.evalStatus] || 'slds-badge',
            formattedSlotStartTime: this.formatTime(b.slotStartTime),
            formattedSlotEndTime: this.formatTime(b.slotEndTime)
        }));
    }

    redirectToContentVersion(contentVersionId) {
        console.log('ContentVersionId:', contentVersionId);

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: contentVersionId,
                objectApiName: 'ContentVersion',
                actionName: 'view'
            }
        });
    }

    async handlePreviewStaticPdf(event) {
        const applicationId = event.currentTarget.dataset.appid;
        if (!applicationId) return;

        try {
            const url = await getMerittoExtractFileUrl({ applicationId });
            console.log('MerittoExtract url:', url);
            if (url) {
                window.open(url, '_blank');
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'No Document Found',
                    message: 'No MerittoExtract document is attached to this application.',
                    variant: 'warning'
                }));
            }
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Error',
                message: err.body?.message || 'Could not fetch document.',
                variant: 'error'
            }));
        }
    }

    formatTime(timeInMilliseconds) {
        if (timeInMilliseconds === null || timeInMilliseconds === undefined || timeInMilliseconds === '') {
            return '—';
        }

        const milliseconds = Number(timeInMilliseconds);

        if (isNaN(milliseconds)) {
            return timeInMilliseconds;
        }

        const totalMinutes = Math.floor(milliseconds / 60000);

        let hours = Math.floor(totalMinutes / 60);
        const minutes = totalMinutes % 60;

        const period = hours >= 12 ? 'PM' : 'AM';

        hours = hours % 12;
        hours = hours === 0 ? 12 : hours;

        return `${hours}:${String(minutes).padStart(2, '0')} ${period}`;
    }
}