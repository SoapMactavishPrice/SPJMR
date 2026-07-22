import { LightningElement, track } from 'lwc';
import importApplications from '@salesforce/apex/ImportApplications.importApplications';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CsvUploader extends LightningElement {
    @track fileName = '';
    @track isLoading = false;

    csvString = '';
    warningMessage = 'Please make sure to upload files < 9MBs in size';
    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        this.fileName = file.name;
        
        const reader = new FileReader();

        reader.onload = () => {
            let text = reader.result;

            // Trim trailing/leading blank lines
            text = text.trim();

            // Validate required columns exist
            if (!text.includes('Application Number') || !text.includes('Applicant State Management')) {
                this.showError('CSV missing required columns: "Application Number" or "Applicant State Management".');
                return;
            }

            this.csvString = text;

            this.processCSV();
        };

        reader.readAsText(file, 'UTF-8');
    }

    async processCSV() {
        this.isLoading = true;

        await importApplications({ csvString: this.csvString })
            .then(() => {
                this.showSuccess('Application statuses updated successfully.');
                this.fileName = '';
            })
            .catch(error => {
                console.log('Error processing ',JSON.stringify(error))
                this.showError(error.body ? error.body.message : error.message);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showSuccess(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: message,
                variant: 'success'
            })
        );
    }

    showError(message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: message,
                variant: 'error'
            })
        );
    }
}