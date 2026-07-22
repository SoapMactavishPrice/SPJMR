import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class NewLeadModal extends NavigationMixin(LightningElement) {
    @track selectedRecordType = 'B2C'; // Default selection
    @track showB2BForm = false;
    @track showB2CForm = false;

    get recordTypeOptions() {
        return [
            { label: 'B2C', value: 'B2C' },
            { label: 'B2B', value: 'B2B' }
        ];
    }

    handleRecordTypeChange(event) {
        this.selectedRecordType = event.detail.value;
    }

    handleNext() {
        if (this.selectedRecordType === 'B2B') {
            this.showB2BForm = true;
        } else if (this.selectedRecordType === 'B2C') {
            this.showB2CForm = true;
        }
    }

    handleCancel() {
        this.navigateToLeadListView();
    }

    handleClose() {
        this.navigateToLeadListView();
    }

    navigateToLeadListView() {
        // Close action screen if it's a quick action
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            // Not a quick action, continue
        }
        
        // Navigate to Lead list view
        setTimeout(() => {
            window.location.href = '/lightning/o/Lead/list';
        }, 100);
    }

    handleB2BFormClose() {
        this.showB2BForm = false;
    }

    handleB2CFormClose() {
        this.showB2CForm = false;
    }

    handleB2BFormSuccess() {
        this.showB2BForm = false;
        this.dispatchEvent(
            new CustomEvent('close', {
                bubbles: true,
                composed: true
            })
        );
    }

    handleB2CFormSuccess() {
        this.showB2CForm = false;
        this.dispatchEvent(
            new CustomEvent('close', {
                bubbles: true,
                composed: true
            })
        );
    }
}