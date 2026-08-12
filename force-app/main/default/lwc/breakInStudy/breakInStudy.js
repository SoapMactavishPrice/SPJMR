import { LightningElement, api } from 'lwc';

import createDefermentRequest
    from '@salesforce/apex/BreakInStudyController.createDefermentRequest';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { CloseActionScreenEvent }
    from 'lightning/actions';

export default class BreakInStudy extends LightningElement {

    @api recordId;

    startDate;
    endDate;
    fee;

    isLoading = false;

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }

    handleFeeChange(event) {
        this.fee = event.target.value;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSave() {

        if (!this.startDate || !this.endDate || !this.fee) {

            this.showToast(
                'Error',
                'Please fill all required fields.',
                'error'
            );
            return;
        }

        if (new Date(this.endDate) <= new Date(this.startDate)) {

            this.showToast(
                'Error',
                'Break End Date & Time must be greater than Break Start Date & Time.',
                'error'
            );
            return;
        }

        this.isLoading = true;

        try {

            await createDefermentRequest({

                programCohortMemberId: this.recordId,

                startDate: this.startDate,

                endDate: this.endDate,

                fee: Number(this.fee)

            });

            this.showToast(
                'Success',
                'Deferment Request created successfully.',
                'success'
            );

            this.dispatchEvent(new CloseActionScreenEvent());

        }
        catch(error) {

            let message = 'Unknown Error';

            if(error.body && error.body.message){
                message = error.body.message;
            }

            this.showToast(
                'Error',
                message,
                'error'
            );
        }
        finally{

            this.isLoading = false;
        }

    }

    showToast(title,message,variant){

        this.dispatchEvent(

            new ShowToastEvent({

                title,
                message,
                variant

            })

        );

    }

}