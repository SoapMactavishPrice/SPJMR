import { LightningElement, api, track } from 'lwc';
import getBatchGroupNumbers from '@salesforce/apex/BatchGroupSequenceController.getBatchGroupNumbers';
import createBatchGroup from '@salesforce/apex/BatchGroupSequenceController.createBatchGroup';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class BatchGroupCreator extends LightningElement {
    @api batchId; // Parent Batch record
    @track missingNumbers = [];
    @track nextNumber;
    @track selectedNumber;
    @track sequenceMode = 'Next Batch Group'; // default

    // Sequence Mode Options
    @track sequenceOptions = [
        { label: 'Next Batch Group', value: 'Next Batch Group' },
        { label: 'Create Missed Batch Group', value: 'Create Missed Batch Group' }
    ];

    // Computed getter for missing number radio options
    get missingNumberOptions() {
        return this.missingNumbers.map(num => ({ label: String(num), value: String(num) }));
    }

    // Getters for template conditions
    get isCreateMissed() {
        return this.sequenceMode === 'Create Missed Batch Group';
    }

    get isNextBatch() {
        return this.sequenceMode === 'Next Batch Group';
    }

    get hasMissingNumbers() {
        return this.missingNumbers.length > 0;
    }

    connectedCallback() {
        this.loadNumbers();
    }

    // Load missing numbers and next number from Apex
    loadNumbers() {
        getBatchGroupNumbers({ batchId: this.batchId })
            .then(result => {
                this.missingNumbers = result.missingNumbers;
                this.nextNumber = result.nextNumber;

                // Default selected number depends on mode
                if (this.isNextBatch) {
                    this.selectedNumber = this.nextNumber;
                } else if (this.isCreateMissed && this.missingNumbers.length > 0) {
                    this.selectedNumber = this.missingNumbers[0];
                } else {
                    this.selectedNumber = this.nextNumber;
                }
            })
            .catch(error => {
                console.error(error);
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error'
                }));
            });
    }

    handleSequenceChange(event) {
        this.sequenceMode = event.target.value;

        if (this.isNextBatch) {
            this.selectedNumber = this.nextNumber;
        } else if (this.isCreateMissed && this.missingNumbers.length > 0) {
            this.selectedNumber = this.missingNumbers[0];
        }
    }

    handleNumberChange(event) {
        this.selectedNumber = parseInt(event.target.value);
    }

    handleCreate() {
        createBatchGroup({ batchId: this.batchId, groupNumber: this.selectedNumber })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: `Batch Group ${this.selectedNumber} created`,
                    variant: 'success'
                }));
                this.loadNumbers(); // reload missing numbers
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error'
                }));
            });
    }
}