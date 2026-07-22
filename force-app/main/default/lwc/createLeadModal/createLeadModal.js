import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class CreateLeadModal extends NavigationMixin(LightningElement) {
    @track currentScreen = 'selection';
    @track selectedType = 'B2C';

    handleTypeChange(event) {
        this.selectedType = event.target.value;
    }  

    handleNext() {
        if (this.selectedType === 'B2C') {
            this.currentScreen = 'b2c';
        } else if (this.selectedType === 'B2B') {
            this.currentScreen = 'b2b';
        }
    }

    handleBack() {
        this.currentScreen = 'selection';
    }

    handleSuccess(event) {
        const detail = event.detail || {};
        const recordId = detail.recordId || detail.id || detail.leadId || null;
        const objectApiName = detail.objectApiName || 'Lead';
        if (recordId) {
            // Navigate here as a reliable fallback for contexts where parent handlers don't navigate.
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: objectApiName,
                    actionName: 'view'
                }
            });

            this.dispatchEvent(
                new CustomEvent('success', {
                    detail: { recordId: recordId, objectApiName: objectApiName },
                    bubbles: true,
                    composed: true
                })
            );
        }
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('cancel', {
                bubbles: true,
                composed: true
            })
        );
        window.history.back();
    }

    handleChildCancel() {
        this.currentScreen = 'selection';
        this.selectedType = 'B2C';
    }

    get isSelectionScreen() {
        return this.currentScreen === 'selection';
    }

    get isB2CScreen() {
        return this.currentScreen === 'b2c';
    }

    get isB2BScreen() {
        return this.currentScreen === 'b2b';
    }

    get isB2CSelected() {
        return this.selectedType === 'B2C';
    }

    get isB2BSelected() {
        return this.selectedType === 'B2B';
    }

    get showInlineB2CVerification() {
        return this.isSelectionScreen && this.isB2CSelected;
    }

    get showInlineB2BVerification() {
        return this.isSelectionScreen && this.isB2BSelected;
    }

    get modalTitle() {
        if (this.currentScreen === 'b2c') {
            return 'New B2C Lead';
        } else if (this.currentScreen === 'b2b') {
            return 'New B2B Lead';
        }
        return 'New Lead';
    }
}