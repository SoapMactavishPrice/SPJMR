import LightningModal from 'lightning/modal';

export default class OfferBulkModal extends LightningModal {

    offerDate;
    result;

    resultOptions = [
        { label: 'Eligible for Admission', value: 'Eligible for Admission' },
        { label: 'Not Eligible', value: 'Not Eligible' },
        { label: 'Waitlisted', value: 'Waitlisted' }
    ];

    handleDateChange(event) {
        this.offerDate = event.target.value;
    }

    handleResultChange(event) {
        this.result = event.target.value;
    }

    get isConfirmDisabled() {
        return !(this.offerDate && this.result);
    }

    handleCancel() {
        this.close();
    }

    handleConfirm() {
        this.close({
            offerDate: this.offerDate,
            result: this.result
        });
    }
}