import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class ConfirmationModal extends LightningModal {
    @api headerLabel; // Header label received from parent
    @api message; // Message received from parent

    handleConfirm() {
        this.close('confirm');
    }

    handleCancel() {
        this.close('cancel');
    }
}