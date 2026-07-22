import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getSequenceOptions from '@salesforce/apex/BatchGroupSequenceController.getSequenceOptions';

export default class BatchGroupCreator extends NavigationMixin(LightningElement) {

    @api recordId; // Batch__c Id
    @track radioOptions = [];
    selectedValue;
    optionsLoaded = false;

    connectedCallback() {
        this.loadOptions();
    }

    loadOptions() {
        getSequenceOptions({ batchId: this.recordId })
            .then(result => {
                let options = [];

                result.missingNumbers.forEach(num => {
                    options.push({
                        label: `Use missing number ${num}`,
                        value: num.toString()
                    });
                });

                options.push({
                    label: `Create new sequence (${result.nextNumber})`,
                    value: result.nextNumber.toString()
                });

                this.radioOptions = options;
                this.selectedValue = options[0]?.value;
                this.optionsLoaded = true;
            })
            .catch(error => {
                console.error(error);
            });
    }

    handleChange(event) {
        this.selectedValue = event.detail.value;
    }

    handleCreate() {
        if (!this.selectedValue) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'AcademicYear',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: {
                    Batch__c: this.recordId,
                    Batch_Group_Number__c: parseInt(this.selectedValue, 10)
                }
            }
        });
    }
}