import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getSlotBookingsBySlotMaster from '@salesforce/apex/InterviewController.getSlotBookingsBySlotMaster';
import getStaticPdfConfig from '@salesforce/apex/InterviewController.getStaticPdfConfig';
import getMerittoExtractFileUrl from '@salesforce/apex/InterviewController.getMerittoExtractFileUrl';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';



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

    // Static PDF column visibility
    @track showStaticPdfCol   = false;
    @track _pdfConfigLoaded   = false;

    // ── Page reference ──────────────────────────────────────────────────────
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.slotMasterId = currentPageReference.attributes.recordId;
        }
    }

    // ── Bookings wire ───────────────────────────────────────────────────────
    @wire(getSlotBookingsBySlotMaster, { slotMasterId: '$slotMasterId' })
    wiredBookings({ data, error }) {
        this.isLoading = false;
        if (data) {
            this._bookings = data;
            this.error = '';
            // Load static PDF config once using the program code from SlotMaster
            if (!this._pdfConfigLoaded && data.length > 0) {
                this._pdfConfigLoaded = true;
                this._loadStaticPdfConfig(data[0].programCode || '');
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

    // ── Derived getters ─────────────────────────────────────────────────────
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

    // ── Preview static PDF (MerittoExtract) ─────────────────────────────────
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
}
