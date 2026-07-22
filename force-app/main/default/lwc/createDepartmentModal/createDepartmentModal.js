import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CreateDepartmentModal extends LightningModal {

    handleCancel() {
        this.close(null);
    }

    handleSuccess(event) {
        const recordId = event.detail.id;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Department created successfully',
                variant: 'success'
            })
        );

        // Return created Id to parent
        this.close(recordId);
    }

    handleError(event) {
        console.error('Error creating department:', event.detail);
    }
}