import { LightningElement } from 'lwc';
import { subscribe, unsubscribe } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';

import uploadChunk from '@salesforce/apex/AdmissionDecisionImportController.uploadChunk';
import startImport from '@salesforce/apex/AdmissionDecisionImportController.startImport';

const CHANNEL = '/event/AdmissionConsoleEvent__e';
const IMPORT_INTENT = 'AdmissionDecisionImport';
const CHUNK_SIZE = 5000;

const SAMPLE_HEADERS = [
    'Application Number',
    'Admission Decision',
    'Waitlist Number',
    'Offer Date',
    'Last Date of Acceptance',
    'Last Date of Uploading the Signed Letter of Acceptance',
    'Last Date for Completing the Payment of the Acceptance Fee',
    'Last Date for Completing the Payment of the First Installment'
];

const INSTRUCTIONS = [
    ['Column Name','Mandatory','Format / Value to Enter','Description / Validation'],
    ['Application Number','Yes','Existing Application Number','Enter an existing Application Number (Application__c.Name).'],
    ['Admission Decision','Yes','Eligible for Admission / Waitlisted / Not Eligible','Allowed values are Eligible for Admission, Waitlisted and Not Eligible.'],
    ['Waitlist Number','Conditional','Whole Number','Mandatory only when Admission Decision is Waitlisted.'],
    ['Offer Date','Conditional','dd-mm-yyyy','Mandatory when Admission Decision is Eligible for Admission.'],
    ['Last Date of Acceptance','Conditional','dd-mm-yyyy','Mandatory when Admission Decision is Eligible for Admission.'],
    ['Last Date of Uploading the Signed Letter of Acceptance','Conditional','dd-mm-yyyy','Mandatory when Admission Decision is Eligible for Admission.'],
    ['Last Date for Completing the Payment of the Acceptance Fee','Conditional','dd-mm-yyyy','Mandatory when Admission Decision is Eligible for Admission.'],
    ['Last Date for Completing the Payment of the First Installment','Conditional','dd-mm-yyyy','Mandatory when Admission Decision is Eligible for Admission.']
];

export default class AdmissionDecisionCsvImporter extends LightningElement {

    fileName = '';
    csvText = '';
    isLoading = false;
    emailReports = false;

    csvChunks = [];
    headerRow = '';
    chunkSize = CHUNK_SIZE;
    contentVersionIds = [];

    successFiles = [];
    errorFiles = [];

    subscription = null;

    get disableImportButton() {
        return !this.csvText || this.isLoading;
    }

    connectedCallback() {
        this.subscribePlatformEvent();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    subscribePlatformEvent() {

        subscribe(CHANNEL, -1, response => {

            const payload = response.data.payload;

            if (payload.UserId__c !== USER_ID) {
                return;
            }

            if (payload.Intent__c !== IMPORT_INTENT) {
                return;
            }

            if (!payload.Message__c) {
                return;
            }

            this.handleCompletion(JSON.parse(payload.Message__c));

        }).then(result => {

            this.subscription = result;

        }).catch(error => {

            console.error(error);

        });

    }

    handleFileUpload(event) {

        const file = event.target.files[0];

        if (!file) {
            return;
        }

        this.fileName = file.name;

        const reader = new FileReader();

        reader.onload = () => {

            this.csvText = reader.result
                .replace(/\r/g, '')
                .trim();

        };

        reader.readAsText(file, 'UTF-8');

    }

    handleEmailReports(event) {

        this.emailReports = event.target.checked;

    }

    downloadSampleHeader() {

        this.downloadCsv(
            'Admission_Decision_Import_Sample_Header.csv',
            [
                SAMPLE_HEADERS.join(',')
            ]
        );

    }

    downloadColumnInstructions() {

        const rows = [];

        INSTRUCTIONS.forEach(row => {

            rows.push(
                row
                    .map(value => `"${value.replace(/"/g, '""')}"`)
                    .join(',')
            );

        });

        this.downloadCsv(
            'Admission_Decision_Column_Instructions.csv',
            rows
        );

    }

    downloadCsv(fileName, rows) {

        const link = this.template.querySelector(
            '[data-id="sample-download"]'
        );

        link.href =
            'data:text/csv;charset=utf-8,' +
            encodeURIComponent(rows.join('\n'));

        link.download = fileName;

        link.click();

    }


        async startImport() {

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
            this.showError('CSV contains no data rows.');
            return;
        }

        this.headerRow = lines[0];

        const dataRows = lines.slice(1);

        for (
            let index = 0;
            index < dataRows.length;
            index += this.chunkSize
        ) {

            this.csvChunks.push(
                [
                    this.headerRow,
                    ...dataRows.slice(index, index + this.chunkSize)
                ].join('\n')
            );

        }

        this.uploadChunks();

    }

    async uploadChunks() {

        this.isLoading = true;

        this.successFiles = [];
        this.errorFiles = [];
        this.contentVersionIds = [];

        try {

            for (
                let index = 0;
                index < this.csvChunks.length;
                index++
            ) {

                const versionId = await uploadChunk({

                    fileName: this.fileName,
                    csvChunk: this.csvChunks[index],
                    chunkNumber: index + 1

                });

                this.contentVersionIds.push(versionId);

            }

            await this.callStartImport();

        }
        catch (error) {

            this.isLoading = false;

            this.showError(
                error?.body?.message ||
                error?.message ||
                'Unexpected Error.'
            );

        }

    }

    async callStartImport() {

        try {

            await startImport({

                contentVersionIds: this.contentVersionIds,
                emailReports: this.emailReports

            });

            this.showSuccess(
                'Import initiated successfully. You will be notified once processing completes.'
            );

        }
        catch (error) {

            this.isLoading = false;

            this.showError(
                error?.body?.message ||
                error?.message ||
                'Unexpected Error.'
            );

        }

    }

    handleCompletion(message) {

        this.isLoading = false;

        this.successFiles = [];

        this.errorFiles = [];

        if (message.successFiles) {

            this.successFiles = message.successFiles.map(file => ({

                name: file.name,
                documentId: file.documentId,
                contentVersionId: file.contentVersionId,
                url: `/sfc/servlet.shepherd/version/download/${file.contentVersionId}`

            }));

        }

        if (message.hasErrors) {

            this.errorFiles = [{

                name:
                    message.fileName ||
                    'Admission_Decision_Import_Error_Report.csv',

                documentId: message.contentDocumentId,

                contentVersionId: message.contentVersionId,

                url:
                    `/sfc/servlet.shepherd/version/download/${message.contentVersionId}`

            }];

            this.showToast(
                'Completed',
                'Import completed with errors.',
                'warning'
            );

        }
        else {

            this.showSuccess(
                'Admission Decision import completed successfully.'
            );

        }

    }

    showSuccess(message) {

        this.showToast(
            'Success',
            message,
            'success'
        );

    }

    showError(message) {

        this.showToast(
            'Error',
            message,
            'error'
        );

    }

    showToast(title, message, variant) {

        this.dispatchEvent(

            new ShowToastEvent({

                title,
                message,
                variant

            })

        );

    }

}