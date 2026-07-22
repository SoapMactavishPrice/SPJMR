import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class LeadCreator extends NavigationMixin(LightningElement) {
    @track selectedRecordType = 'B2C';
    @track showB2BForm = false;
    @track showB2CForm = false;
    @track showSelection = true;

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
        this.showSelection = false;
        if (this.selectedRecordType === 'B2B') {
            this.showB2BForm = true;
        } else if (this.selectedRecordType === 'B2C') {
            this.showB2CForm = true;
        }
    }

    handleCancel() {
        this.navigateToLeadListView();
    }

    navigateToLeadListView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Lead',
                actionName: 'list'
            }
        });
    }

    handleB2BFormClose() {
        this.showB2BForm = false;
        this.showSelection = true;
    }

    handleB2CFormClose() {
        this.showB2CForm = false;
        this.showSelection = true;
    }

    handleB2BFormSuccess() {
        this.showB2BForm = false;
        this.showSelection = true;
    }

    handleB2CFormSuccess() {
        this.showB2CForm = false;
        this.showSelection = true;
    }
}