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
        }else{
            this.showSuccess('Import completed successfully.');
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
        const downloadLink = this.template.querySelector('[data-id="sample-header-download"]');
        downloadLink.href = `data:text/csv;charset=utf-8,${encodeURIComponent(`${SAMPLE_HEADERS.join(',')}\n`)}`;
        downloadLink.download = 'Application_Import_Sample_Header.csv';
        downloadLink.click();
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
            this.showSuccess( 'Import initiated successfully. You will be notified when processing completes.' );
        }
        catch(error){
            console.log(error);
            this.showError(  error.body  ? error.body.message  : error.message);
        }
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

    // handleNotifyCheckbox(event) {
    //     this.notifyShortlistedApplicants = event.target.checked;
    // }

    handleEmailErrorReport(event) {
        this.emailErrorReport = event.target.checked;
    }
}