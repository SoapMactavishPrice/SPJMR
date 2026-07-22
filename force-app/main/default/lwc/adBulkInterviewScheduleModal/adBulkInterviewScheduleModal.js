import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getSlots from '@salesforce/apex/SlotSchedulerController.getSlots';
import bookSlot from '@salesforce/apex/SlotSchedulerController.bookSlot';
import getLocations from '@salesforce/apex/SlotSchedulerController.getLocations';
import getAvailableRounds from '@salesforce/apex/SlotSchedulerController.getAvailableRounds';
import getPanels from '@salesforce/apex/SlotSchedulerController.getPanels';
import getBookedSlots from '@salesforce/apex/SlotSchedulerController.getBookedSlots';
import bookSlotsBulk from '@salesforce/apex/SlotSchedulerController.bookSlotsBulk';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

export default class AdBulkInterviewScheduleModal extends LightningModal {

    // ---- CONFIG ----
    programCode = 'GMP';

    selectedPanel = '';
selectedRound = '';
allRounds = [];
allPanels = [];
panelOptions = [];
roundOptions = [];

    // ---- API INPUT ----
    @api applicationIds = [];

    // ---- STATE ----
    selectedLocation = '';
    selectedSlot = '';
    locationOptions = [];
    slotOptions = [];
    slotMap = new Map();

    selectedSlotRecord = null;

    noSlots = false;
    isCreateBookingDisabled = true;
    showCapacityWarning = false;

    // ---- INIT ----
    connectedCallback() {
        console.log('Modal opened with applicationIds:', JSON.stringify(this.applicationIds));
        this.fetchLocations();
        this.fetchPanels()
        this.fetchRounds()
    }

    updateCreateBookingState() {
    this.isCreateBookingDisabled =
        !this.selectedSlot ||
        !this.selectedPanel ||
        !this.selectedRound ||
        this.showCapacityWarning;
}


    fetchRounds(){
        getAvailableRounds({pgmCode:'GMP'})
        .then((result)=>{
            this.allRounds = result
            this.roundOptions = result.map((item)=>{
                return{
                    label:item.Name,value:item.Id
                }
            })
        })
        .catch((error)=>{
            console.log('Error Fetching Rounds '+error)
        })
    }

    fetchPanels(){
        getPanels({pgmCode:'GMP'})
        .then((result)=>{
            console.log('Result is ',JSON.stringify(result))
            this.allPanels = result
            this.panelOptions = result.map((item)=>{
                return{
                    label:item.Name +' ('+item.ProgramTeam__r?.Name+') ', value:item.Id
                }
            })
        })
        .catch((error)=>{console.log('Error getting Panels '+error)})
    }

    // ---- DATA FETCH ----
    fetchLocations() {
        getLocations()
            .then(data => {
                this.locationOptions = data.map(loc => ({
                    label: loc.LocationName__c,
                    value: loc.Id
                }));
            })
            .catch(() => {
                this.showToast('Error', 'Failed to load locations', 'error');
            });
    }

    fetchSlots() {
        if (!this.programCode || !this.selectedLocation) return;

        getSlots({
            programCode: this.programCode,
            locationId: this.selectedLocation
        })
            .then(data => {
                this.noSlots = data.length === 0;

                this.slotMap.clear();
                data.forEach(slot => {
                    this.slotMap.set(slot.Id, slot);
                });

                this.slotOptions = data.map(slot => ({
                    label: `${this.concatSlot(slot)} (${slot.BookedCapacity__c}/${slot.Capacity__c})`,
                    value: slot.Id
                }));

                // Reset slot-related state
                this.selectedSlot = '';
                this.selectedSlotRecord = null;
                this.isCreateBookingDisabled = true;
                this.showCapacityWarning = false;
            })
            .catch(() => {
                this.showToast('Error', 'Failed to load slots', 'error');
            });
    }

    // ---- UI HANDLERS ----
    handleLocationChange(event) {
        this.selectedLocation = event.detail.value;
        this.fetchSlots();
    }
    handlePanelChange(event) {
    this.selectedPanel = event.detail.value;
    this.updateCreateBookingState();
}


handleRoundChange(event) {
    this.selectedRound = event.detail.value;
    this.updateCreateBookingState();
}



   handleSlotChange(event) {
    this.selectedSlot = event.detail.value;
    this.selectedSlotRecord = this.slotMap.get(this.selectedSlot);

    if (!this.selectedSlotRecord) {
        this.showCapacityWarning = false;
        this.updateCreateBookingState();
        return;
    }

    const { Capacity__c, BookedCapacity__c } = this.selectedSlotRecord;
    this.showCapacityWarning = BookedCapacity__c >= Capacity__c;

    this.updateCreateBookingState();
}


    // ---- HELPERS ----
    concatSlot(slot) {
        const [y, m, d] = slot.SlotDate__c.split('-').map(Number);
        const date = new Date(y, m - 1, d);

        const base = new Date(1970, 0, 1);
        const time = new Date(base.getTime() + slot.SlotStartTime__c);

        return `${date.toLocaleDateString('en-GB', {
            day: '2-digit',
            month: 'long',
            year: 'numeric'
        })} ${time.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: true
        })}`;
    }

    // // ---- VALIDATION ----
    // async checkExistingBookings() {
    //     try {
    //         return await getBookedSlots({
    //             pgmCode: this.programCode,
    //             slotId: this.selectedSlot
    //         });
    //     } catch {
    //         return false;
    //     }
    // }

    // ---- BOOKING ----
    async handleBookSlot() {
    // 1️⃣ Confirm
    const confirmed = await LightningConfirm.open({
        message: 'Are you sure you want to create bookings for these applications?',
        variant: 'headerless'
    });

    if (!confirmed) {
        return; // ✅ actually stops execution
    }

    try {
        const params = JSON.stringify({
            programCode: this.programCode,
            slotId: this.selectedSlot,
            panelId: this.selectedPanel,
            roundId: this.selectedRound
        });

        console.log('Params are', params);

        const result = await bookSlotsBulk({
            params: params,
            applicationIds: this.applicationIds
        });

        // 2️⃣ Success
        if (result === 'Booking successful') {
            this.showToast('Success', result, 'success');
            this.close({
                slotId: this.selectedSlot,
                applicationIds: this.applicationIds
            });
        }

    } catch (e) {
        // 3️⃣ Proper error extraction
        let message = 'Booking failed';

        if (e?.body?.message) {
            message = e.body.message;
        } else if (e?.message) {
            message = e.message;
        }

        this.showToast('Error', message, 'error');
    }
}


    // ---- TOAST ----
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}