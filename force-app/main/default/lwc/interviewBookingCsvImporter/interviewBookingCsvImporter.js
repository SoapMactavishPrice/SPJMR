import { LightningElement } from 'lwc';
import { subscribe, unsubscribe } from 'lightning/empApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import uploadChunk from '@salesforce/apex/InterviewBookingImportController.uploadChunk';
import startImport from '@salesforce/apex/InterviewBookingImportController.startImport';

const CHANNEL = '/event/AdmissionConsoleEvent__e';
const IMPORT_INTENT = 'InterviewBookingImport';
const CHUNK_SIZE = 5000;
const HEADERS = {
    WITHOUT_PANEL: ['Application Number', 'Slot Code', 'Round Name'],
    WITH_PANEL: ['Application Number', 'Slot Code', 'Round Name', 'Interviewer Emails'],
    ASSIGN_PANEL: ['ApplicationSlotBookingCode', 'Interviewer Emails']
};
const INSTRUCTIONS = {
    WITHOUT_PANEL: [
        ['Application Number', 'Yes', 'Existing Application__c.Name value.'],
        ['Slot Code', 'Yes', 'Existing SlotMaster__c.Name value.'],
        ['Round Name', 'Yes', 'Existing RoundMaster__c.Name value.']
    ],
    WITH_PANEL: [
        ['Application Number', 'Yes', 'Existing Application__c.Name value.'],
        ['Slot Code', 'Yes', 'Existing SlotMaster__c.Name value.'],
        ['Round Name', 'Yes', 'Existing RoundMaster__c.Name value.'],
        ['Interviewer Emails', 'Yes', 'Semicolon-separated Account.PersonEmail values, for example: one@example.com;two@example.com.']
    ],
    ASSIGN_PANEL: [
        ['ApplicationSlotBookingCode', 'Yes', 'Existing ApplicationSlotBooking__c.Name value.'],
        ['Interviewer Emails', 'Yes', 'Semicolon-separated Account.PersonEmail values, for example: one@example.com;two@example.com.']
    ]
};

export default class InterviewBookingCsvImporter extends LightningElement {
    importType = '';
    programId;
    fileName = '';
    csvText = '';
    isLoading = false;
    notifyApplicants = false;
    notifyInterviewers = false;
    emailReports = false;
    successFiles = [];
    errorFiles = [];
    subscription;

    importOptions = [
        { label: 'Book Interview Without Panel', value: 'WITHOUT_PANEL' },
        { label: 'Book Interview With Panel', value: 'WITH_PANEL' },
        { label: 'Assign Panel', value: 'ASSIGN_PANEL' }
    ];

    connectedCallback() {
        this.subscription = subscribe(CHANNEL, -1, response => {
            const payload = response.data.payload;
            if (payload.UserId__c === USER_ID && payload.Intent__c === IMPORT_INTENT && payload.Message__c) {
                this.handleCompletion(JSON.parse(payload.Message__c));
            }
        });
    }

    disconnectedCallback() {
        if (this.subscription) unsubscribe(this.subscription);
    }

    get showImportForm() { return Boolean(this.importType); }
    get isImportTypeUnselected() { return !this.importType; }
    get requiresProgram() { return this.importType === 'WITH_PANEL'; }
    get showNotifyApplicants() { return this.importType !== 'ASSIGN_PANEL'; }
    get showNotifyInterviewers() { return this.importType !== 'WITHOUT_PANEL'; }
    get requiredHeaders() { return (HEADERS[this.importType] || []).join(', '); }
    get isStartDisabled() { return !this.csvText || this.isLoading || (this.requiresProgram && !this.programId); }

    handleImportTypeChange(event) {
        this.importType = event.detail.value;
        this.programId = null;
        this.fileName = '';
        this.csvText = '';
        this.successFiles = [];
        this.errorFiles = [];
    }

    handleProgramChange(event) { this.programId = event.detail.recordId; }
    handleCheckboxChange(event) { this[event.target.dataset.field] = event.target.checked; }

    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;
        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => { this.csvText = reader.result.replace(/\r/g, '').trim(); };
        reader.readAsText(file, 'UTF-8');
    }

    downloadSampleHeader() {
        this.downloadCsv(
            `${this.importType.toLowerCase()}_interview_import_sample.csv`,
            [(HEADERS[this.importType] || []).join(',')]
        );
    }

    downloadColumnInstructions() {
        const rows = ['Column Name,Required,What to enter'];
        (INSTRUCTIONS[this.importType] || []).forEach(instruction => {
            rows.push(instruction.map(value => `"${value.replace(/"/g, '""')}"`).join(','));
        });
        this.downloadCsv(`${this.importType.toLowerCase()}_interview_import_instructions.csv`, rows);
    }

    downloadCsv(fileName, rows) {
        const link = this.template.querySelector('[data-id="sample-download"]');
        link.href = `data:text/csv;charset=utf-8,${encodeURIComponent(`${rows.join('\n')}\n`)}`;
        link.download = fileName;
        link.click();
    }

    async startImport() {
        const lines = this.csvText.split('\n');
        if (lines.length <= 1) {
            this.toast('Error', 'CSV contains no data rows.', 'error');
            return;
        }
        this.isLoading = true;
        this.successFiles = [];
        this.errorFiles = [];
        try {
            const contentVersionIds = [];
            for (let index = 1; index < lines.length; index += CHUNK_SIZE) {
                contentVersionIds.push(await uploadChunk({
                    fileName: this.fileName,
                    csvChunk: [lines[0], ...lines.slice(index, index + CHUNK_SIZE)].join('\n'),
                    chunkNumber: contentVersionIds.length + 1
                }));
            }
            await startImport({
                contentVersionIds,
                importType: this.importType,
                programId: this.programId || null,
                notifyApplicants: this.notifyApplicants,
                notifyInterviewers: this.notifyInterviewers,
                emailErrorCsv: this.emailReports
            });
            this.toast('Success', 'Import started. You will be notified when it completes.', 'success');
        } catch (error) {
            this.isLoading = false;
            this.toast('Error', error?.body?.message || error?.message || 'Unable to start the import.', 'error');
        }
    }

    handleCompletion(message) {
        this.isLoading = false;
        // this.successFiles = (message.successFiles || []).map(file => ({
        //     name: file.name,
        //     documentId: file.documentId,
        //     url: `/lightning/r/ContentDocument/${file.documentId}/view`
        // }));
        this.successFiles = (message.successFiles || []).map(file => ({
            name: file.name,
            documentId: file.documentId,
            contentVersionId: file.contentVersionId,
            url: `/sfc/servlet.shepherd/version/download/${file.contentVersionId}`
        }));
        if (message.hasErrors) {
            // this.errorFiles = [{
            //     name: message.fileName || 'Interview_Booking_Import_Error_Report.csv',
            //     documentId: message.contentDocumentId,
            //     url: `/lightning/r/ContentDocument/${message.contentDocumentId}/view`
            // }];
            this.errorFiles = [{
                name: message.fileName || 'Interview_Booking_Import_Error_Report.csv',
                documentId: message.contentDocumentId,
                contentVersionId: message.contentVersionId,
                url: `/sfc/servlet.shepherd/version/download/${message.contentVersionId}`
            }];
            this.toast('Import completed', 'An error CSV was generated.', 'warning');
        } else {
            this.toast('Success', 'Import completed successfully.', 'success');
        }
    }

    toast(title, message, variant) { this.dispatchEvent(new ShowToastEvent({ title, message, variant })); }
}