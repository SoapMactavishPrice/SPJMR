import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { NavigationMixin } from 'lightning/navigation';  
export default class SlotSchedulerModal extends LightningModal {
    @api programCode;
    @api bookingInfo;
    confirmSlotSelection() {
        console.log('confirmSlotSelection event');
        this.close('booked');
    }

    handleCancel() {
        this.close('cancel');
    }
}