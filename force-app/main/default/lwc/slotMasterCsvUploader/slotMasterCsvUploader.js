import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import uploadChunk from '@salesforce/apex/ImportSlotMaster.uploadChunk';
import startImport from '@salesforce/apex/ImportSlotMaster.startImport';

const PLATFORM_EVENT_CHANNEL = '/event/AdmissionConsoleEvent__e';
const IMPORT_INTENT = 'SlotMasterImport';
const SAMPLE_HEADERS = [
    'SlotCode',
    'Program Master',
    'SlotDate',
    'Slot Start Time',
    'Capacity',
    'Slot End Time',
    'Location Master'
];

export default class SlotMasterCsvUploader extends LightningElement {
    @track fileName = '';
    @track isLoading = false;
    @track generatedFiles = [];

    warningMessage = 'Please make sure to upload files < 9 MB in size';
    emailErrorReport = false;
    csvChunks = [];
    headerRow = '';
    chunkSize = 5000;
    contentVersionIds = [];
    csvText = '';
    subscription = null;

    get disableImportButton() {
        return !this.csvText || this.isLoading;
    }

    connectedCallback() {
        this.subscribePlatformEvent();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                // Subscription is no longer needed after the component is removed.
            });
        }
    }

    subscribePlatformEvent() {
        subscribe(PLATFORM_EVENT_CHANNEL, -1, response => {
            const payload = response.data.payload;
            if (payload.UserId__c !== USER_ID || payload.Intent__c !== IMPORT_INTENT || !payload.Message__c) {
                return;
            }

            this.handleImportCompleted(JSON.parse(payload.Message__c));
        })
            .then(result => {
                this.subscription = result;
            })
            .catch(error => {
                // Keep the upload UI available even if completion notifications cannot be subscribed to.
                // eslint-disable-next-line no-console
                console.error('Platform Event Subscription Error', error);
            });
    }

    handleImportCompleted(message) {
        this.isLoading = false;
        this.generatedFiles = [];

        if (message.hasErrors) {
            this.generatedFiles = [{
                fileName: message.fileName,
                contentDocumentId: message.contentDocumentId,
                url: `/lightning/r/ContentDocument/${message.contentDocumentId}/view`
            }];
            this.showSuccess('Import completed. Error CSV has been generated.');
            return;
        }

        this.showSuccess('Slot Master import completed successfully.');
    }

    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }

        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => {
            this.csvText = reader.result.replace(/\r/g, '').trim();
        };
        reader.readAsText(file, 'UTF-8');
    }

    downloadSampleHeader() {
        const downloadLink = this.template.querySelector('[data-id="sample-header-download"]');
        downloadLink.href = `data:text/csv;charset=utf-8,${encodeURIComponent(`${SAMPLE_HEADERS.join(',')}\n`)}`;
        downloadLink.download = 'SlotMaster_Import_Sample_Header.csv';
        downloadLink.click();
    }

    handleStartImport() {
        if (!this.csvText) {
            this.showError('Please select a CSV file.');
            return;
        }

        this.prepareChunks(this.csvText);
    }

    prepareChunks(csvText) {
        this.csvChunks = [];
        const lines = csvText.split('\n');
        if (lines.length <= 1) {
            this.showError('CSV contains no data.');
            return;
        }

        this.headerRow = lines[0];
        const dataRows = lines.slice(1);
        for (let index = 0; index < dataRows.length; index += this.chunkSize) {
            this.csvChunks.push([this.headerRow, ...dataRows.slice(index, index + this.chunkSize)].join('\n'));
        }

        this.uploadChunks();
    }

    async uploadChunks() {
        this.isLoading = true;
        this.contentVersionIds = [];

        try {
            for (let index = 0; index < this.csvChunks.length; index += 1) {
                const contentVersionId = await uploadChunk({
                    fileName: this.fileName,
                    csvChunk: this.csvChunks[index],
                    chunkNumber: index + 1
                });
                this.contentVersionIds.push(contentVersionId);
            }

            await this.startImport();
        } catch (error) {
            this.isLoading = false;
            this.showError(this.getErrorMessage(error));
        }
    }

    async startImport() {
        try {
            await startImport({
                contentVersionIds: this.contentVersionIds,
                emailErrorReport: this.emailErrorReport
            });
            this.showSuccess('Import initiated successfully. You will be notified when processing completes.');
        } catch (error) {
            this.isLoading = false;
            this.showError(this.getErrorMessage(error));
        }
    }

    handleEmailErrorReport(event) {
        this.emailErrorReport = event.target.checked;
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }

    showSuccess(message) {
        this.showToast('Success', message, 'success');
    }

    showError(message) {
        this.showToast('Error', message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}