import { LightningElement, track } from 'lwc';
import { subscribe, unsubscribe } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import uploadChunk from '@salesforce/apex/ImportSlotMaster.uploadChunk';
import startImport from '@salesforce/apex/ImportSlotMaster.startImport';

const PLATFORM_EVENT_CHANNEL = '/event/AdmissionConsoleEvent__e';
const IMPORT_INTENT = 'SlotMasterImport';
const SAMPLE_HEADERS = [
    'Program Code',
    'Location Code',
    'Slot Code',
    'Capacity',
    'Slot Date',
    'Slot Start Time',
    'Slot End Time'
];

const INSTRUCTIONS = [
    ['Program Code', 'Yes', 'Existing Program.Program_Code__c', 'Enter an existing Program Code. Example: PGPM.'],
    ['Location Code', 'Yes', 'Existing LocationMaster__c.Name', 'Enter an existing Location Code. Example: L-001.'],
    ['Slot Code', 'Yes', 'Text', 'Enter a unique Slot Code. Example: S-001. This is stored in SlotMaster__c.Name.'],
    ['Capacity', 'Yes', 'Whole Number', 'Enter the maximum number of applicants that can be booked for the slot. Example: 25. Decimal values are not allowed.'],
    ['Slot Date', 'Yes', 'dd-MM-yyyy', 'Enter the slot date in dd-MM-yyyy format. Example: 15-08-2026.'],
    ['Slot Start Time', 'Yes', 'HH:mm (24-hour format)', 'Enter the slot start time in 24-hour format. Example: 09:30 or 14:00.'],
    ['Slot End Time', 'No', 'HH:mm (24-hour format)', 'Optional. If provided, enter the slot end time. Example: 10:30.']
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
            // this.generatedFiles = [{
            //     fileName: message.fileName,
            //     contentDocumentId: message.contentDocumentId,
            //     url: `/lightning/r/ContentDocument/${message.contentDocumentId}/view`
            // }];
            this.generatedFiles = [{
                fileName: message.fileName,
                contentDocumentId: message.contentDocumentId,
                contentVersionId: message.contentVersionId,
                url: `/sfc/servlet.shepherd/version/download/${message.contentVersionId}`
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

    // downloadSampleHeader() {
    //     const downloadLink = this.template.querySelector('[data-id="sample-header-download"]');
    //     downloadLink.href = `data:text/csv;charset=utf-8,${encodeURIComponent(`${SAMPLE_HEADERS.join(',')}\n`)}`;
    //     downloadLink.download = 'SlotMaster_Import_Sample_Header.csv';
    //     downloadLink.click();
    // }
    downloadSampleHeader() {
        this.downloadCsv(
            'SlotMaster_Import_Sample_Header.csv',
            [SAMPLE_HEADERS.join(',')]
        );
    }

    downloadColumnInstructions() {
        const rows = [ 'Column Name,Mandatory,Format / Value to Enter,Description / Validation' ];
        INSTRUCTIONS.forEach(row => { rows.push( row.map(value => `"${value.replace(/"/g, '""')}"`).join(',')); });
        this.downloadCsv('SlotMaster_Import_Column_Instructions.csv', rows);
    }

    downloadCsv(fileName, rows) {
        const downloadLink = this.template.querySelector('[data-id="sample-header-download"]');
        downloadLink.href = `data:text/csv;charset=utf-8,${encodeURIComponent(rows.join('\n') + '\n')}`;
        downloadLink.download = fileName;
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