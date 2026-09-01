import { LightningElement, track } from 'lwc';
import uploadChunk from '@salesforce/apex/ImportApplications.uploadChunk';
import startImport from '@salesforce/apex/ImportApplications.startImport';
import { subscribe, unsubscribe } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const SAMPLE_HEADERS = [
    'Application Number',
    'Applicant State Management',
    'Application Stage',
    'Application Status'
];

export default class CsvUploader extends LightningElement {
    @track fileName = '';
    @track isLoading = false;
    notifyShortlistedApplicants = false;
    emailErrorReport = false;
    generatedFiles = [];
    subscription = null;

    csvChunks = [];
    headerRow = '';
    chunkSize = 5000;
    contentVersionIds = [];
    csvText = '';
    
    warningMessage = 'Please make sure to upload files < 9MBs in size';

    get disableImportButton() {
        return !this.csvText || this.isLoading;
    }

    connectedCallback(){
        this.subscribePlatformEvent();
    }

    disconnectedCallback(){
        if(this.subscription){
            unsubscribe(this.subscription);
        }
    }

    subscribePlatformEvent() {
        const channel = '/event/AdmissionConsoleEvent__e';

        subscribe( channel, -1,(response) => {
                const payload = response.data.payload;
                if(payload.UserId__c !== USER_ID){
                    return;
                }

                if(payload.Intent__c !== 'ApplicationImport'){
                    return;
                }
                const message = JSON.parse(payload.Message__c);
                this.handleImportCompleted( message);
            }
        ).then(result => {
            this.subscription = result;
        }).catch(error => {
            console.error(error);
        });
    }


    handleImportCompleted(message){
        this.isLoading = false;
        this.generatedFiles = [];
        if(message.hasErrors){
            // this.generatedFiles = [
            //     {
            //         fileName: message.fileName,
            //         contentDocumentId: message.contentDocumentId,
            //         url: '/lightning/r/ContentDocument/' + message.contentDocumentId + '/view'
            //     }
            // ];
            this.generatedFiles = [
                {
                    fileName: message.fileName,
                    contentDocumentId: message.contentDocumentId,
                    contentVersionId: message.contentVersionId,
                    url: '/sfc/servlet.shepherd/version/download/' + message.contentVersionId
                }
            ];
        }
        this.showCompletionToast(message);
    }

    showCompletionToast(message) {
        const successCount = Number(message.successCount || 0);
        const failedCount = Number(message.failedCount || 0);

        if (failedCount > 0 && successCount === 0) {
            this.showToast('Import failed', `Application import failed. Successful: 0, Failed: ${failedCount}.`, 'error');
        } else if (failedCount > 0) {
            this.showToast('Import partially completed', `Application import partially completed. Successful: ${successCount}, Failed: ${failedCount}.`, 'warning');
        } else {
            this.showToast('Import successful', `Application import completed successfully. Successful: ${successCount}, Failed: 0.`, 'success');
        }
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
        const csvContent = `${SAMPLE_HEADERS.join(',')}\n`;
        const blob = new Blob([csvContent], { type: 'text/plain' });
        const blobUrl = URL.createObjectURL(blob);
        const anchorTag = document.createElement('a');

        anchorTag.setAttribute('href', blobUrl);
        anchorTag.setAttribute('download', 'Application_Import_Sample_Header.csv');
        anchorTag.click();
        URL.revokeObjectURL(blobUrl);
    }

    async handleStartImport() {
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
            this.showError( 'CSV contains no data.' );
            return;
        }

        this.headerRow = lines[0];
        const dataRows = lines.slice(1);

        for ( let i = 0; i < dataRows.length; i += this.chunkSize) {
            const chunkRows = dataRows.slice(i, i + this.chunkSize);
            const chunk =[ this.headerRow, ...chunkRows].join('\n');
            this.csvChunks.push(chunk);
        }

        console.log('Total Chunks:', this.csvChunks.length);

        console.log(this.csvChunks);

        this.uploadChunks();
    }


    async uploadChunks() {

        this.isLoading = true;
        this.contentVersionIds = [];
        try {
            for ( let i = 0; i < this.csvChunks.length; i++) {

                const id = await uploadChunk({ fileName: this.fileName, csvChunk: this.csvChunks[i], chunkNumber: i + 1});
                this.contentVersionIds.push(id);
                console.log('Uploaded chunk', i + 1, id);
            }
            await this.startImport();
        }

        catch(error){
            this.isLoading = false;
            console.log(error);
            this.showError( error.body ? error.body.message : error.message);
        }
    }


    async startImport() {
        try {
            await startImport({ contentVersionIds: this.contentVersionIds, notifyShortlistedApplicants: this.notifyShortlistedApplicants, emailErrorReport: this.emailErrorReport});
            this.showToast('Import started', 'Import initiated successfully. You will be notified when processing completes.', 'info');
        }
        catch(error){
            console.log(error);
            this.showError(  error.body  ? error.body.message  : error.message);
        }
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

    // handleNotifyCheckbox(event) {
    //     this.notifyShortlistedApplicants = event.target.checked;
    // }

    handleEmailErrorReport(event) {
        this.emailErrorReport = event.target.checked;
    }
}