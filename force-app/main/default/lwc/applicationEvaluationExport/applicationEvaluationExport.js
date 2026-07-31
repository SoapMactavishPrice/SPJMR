import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';
import getEvaluationCount from '@salesforce/apex/ApplicationEvaluationExportController.getEvaluationCount';
import startEvaluationExport from '@salesforce/apex/ApplicationEvaluationExportController.startExport';
import sendExportEmail from '@salesforce/apex/ApplicationEvaluationExportController.sendExportEmail';

const CHANNEL_NAME = '/event/AdmissionConsoleEvent__e';
const EVENT_INTENT = 'ApplicationEvaluationExport';

export default class ApplicationEvaluationExport extends LightningElement {
    programId;
    roundId;
    slotStartDate = '';
    slotEndDate = '';
    today = new Date().toISOString().slice(0, 10);
    subscription = null;
    files = [];
    showFiles = false;
    showConfirmation = false;
    recordCount = 0;
    isStarting = false;
    sendEmail = false;
    userId = USER_ID;

    connectedCallback() {
        this.registerErrorListener();
        this.subscribePlatformEvent();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    get roundFilter() {
        if (!this.programId) {
            return null;
        }

        return {
            criteria: [
                {
                    fieldPath: 'Program__c',
                    operator: 'eq',
                    value: this.programId
                }
            ]
        };
    }

    get isRoundDisabled() {
        return !this.programId;
    }

    get isEndDateDisabled() {
        return !this.slotStartDate;
    }

    get isExportDisabled() {
        return this.isStarting || !this.programId || !this.roundId;
    }

    handleProgramChange(event) {
        this.programId = event.detail.recordId;
        this.roundId = null;
        this.files = [];
        this.showFiles = false;
    }

    handleRoundChange(event) {
        this.roundId = event.detail.recordId;
        this.files = [];
        this.showFiles = false;
    }

    handleStartDateChange(event) {
        const selectedDate = event.detail.value;
        if (selectedDate && selectedDate > this.today) {
            this.slotStartDate = '';
            this.slotEndDate = '';
            this.showToast('Invalid Date', 'Slot Start Date cannot be a future date.', 'error');
            return;
        }

        this.slotStartDate = selectedDate;
        if (!this.slotStartDate) {
            this.slotEndDate = '';
        } else if (this.slotEndDate && this.slotEndDate < this.slotStartDate) {
            this.slotEndDate = '';
        }
        this.files = [];
        this.showFiles = false;
    }

    handleEndDateChange(event) {
        const selectedDate = event.detail.value;
        if (selectedDate && this.slotStartDate && selectedDate < this.slotStartDate) {
            this.slotEndDate = '';
            this.showToast('Invalid Date', 'Slot End Date cannot be before Slot Start Date.', 'error');
            return;
        }

        this.slotEndDate = selectedDate;
        this.files = [];
        this.showFiles = false;
    }

    handleEmailCheckbox(event) {
        this.sendEmail = event.target.checked;
    }

    startExport() {
        if (!this.validateInputs()) {
            return;
        }

        this.files = [];
        this.showFiles = false;

        getEvaluationCount({
            programId: this.programId,
            roundId: this.roundId,
            slotStartDate: this.slotStartDate || null,
            slotEndDate: this.slotEndDate || null
        }).then(count => {
            if (count === 0) {
                this.showToast('No Records Found', 'No evaluations were found for the selected filters.', 'warning');
                return;
            }

            this.recordCount = count;
            this.showConfirmation = true;
        }).catch(error => {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
    }

    cancelExport() {
        this.showConfirmation = false;
    }

    confirmExport() {
        this.showConfirmation = false;
        this.isStarting = true;

        startEvaluationExport({
            programId: this.programId,
            roundId: this.roundId,
            slotStartDate: this.slotStartDate || null,
            slotEndDate: this.slotEndDate || null
        }).then(() => {
            this.showToast('Export Started', 'Please wait for the job to complete.', 'info');
        }).catch(error => {
            this.showToast('Export Failed', this.getErrorMessage(error), 'error');
            this.isStarting = false;
        });
    }

    subscribePlatformEvent() {
        subscribe(CHANNEL_NAME, -1, message => {
            this.handlePlatformEvent(message);
        }).then(response => {
            this.subscription = response;
        });
    }

    registerErrorListener() {
        onError(error => {
            // Keep EMP API errors visible for browser diagnostics.
            // eslint-disable-next-line no-console
            console.error(error);
        });
    }

    handlePlatformEvent(message) {
        const payload = message.data.payload;
        if (payload.UserId__c !== this.userId || payload.Intent__c !== EVENT_INTENT) {
            return;
        }

        this.isStarting = false;
        const result = JSON.parse(payload.Message__c);

        if (result.status === 'NoRecords') {
            this.files = [];
            this.showFiles = true;
            this.showToast('No Records Found', 'No evaluations were found for the selected filters.', 'warning');
            return;
        }

        this.files = result.files.map(file => ({
            name: file.name,
            documentId: file.documentId,
            downloadUrl: `/sfc/servlet.shepherd/document/download/${file.documentId}`
        }));
        this.showFiles = true;
        this.showToast('Export Completed', 'Download links are ready.', 'success');

        if (this.sendEmail) {
            sendExportEmail({
                filesJson: JSON.stringify(this.files)
            }).then(() => {
                this.showToast('Email Sent', 'Download links were sent to your email.', 'success');
            }).catch(error => {
                this.showToast('Email Failed', this.getErrorMessage(error), 'error');
            });
        }
    }

    validateInputs() {
        if (!this.programId || !this.roundId) {
            this.showToast('Missing Required Fields', 'Program and Round are required.', 'error');
            return false;
        }
        if (this.slotStartDate && this.slotStartDate > this.today) {
            this.showToast('Invalid Date', 'Slot Start Date cannot be a future date.', 'error');
            return false;
        }
        if (!this.slotStartDate && this.slotEndDate) {
            this.showToast('Invalid Date', 'Enter Slot Start Date before selecting Slot End Date.', 'error');
            return false;
        }
        if (this.slotStartDate && this.slotEndDate && this.slotEndDate < this.slotStartDate) {
            this.showToast('Invalid Date', 'Slot End Date cannot be before Slot Start Date.', 'error');
            return false;
        }
        return true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}
