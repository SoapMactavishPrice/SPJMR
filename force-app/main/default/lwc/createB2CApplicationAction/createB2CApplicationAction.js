import { api, LightningElement } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import createApplicationForOpportunity from '@salesforce/apex/ConvertB2CLeadController.createApplicationForOpportunity';

export default class CreateB2CApplicationAction extends LightningElement {
    @api recordId;
    isLoading = false;

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleCreate() {
        this.isLoading = true;
        try {
            const result = await createApplicationForOpportunity({ opportunityId: this.recordId });
            if (result?.isSuccess) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result.message,
                        variant: 'success'
                    })
                );
                this.dispatchEvent(new RefreshEvent());
                this.dispatchEvent(new CloseActionScreenEvent());
                return;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: result?.message || 'Unable to create application.',
                    variant: 'error'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error?.body?.message || error?.message || 'Unable to create application.',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }
}