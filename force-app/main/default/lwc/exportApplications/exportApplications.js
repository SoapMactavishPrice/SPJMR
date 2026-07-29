import { LightningElement, wire } from 'lwc';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import exportApplicationsBatch from '@salesforce/apex/ExportApplicationsController.exportApplicationsBatch';
import getCohortsForProgram from '@salesforce/apex/ExportApplicationsController.getCohortsForProgram';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import USER_ID from '@salesforce/user/Id';
import sendExportEmail from '@salesforce/apex/ExportApplicationsController.sendExportEmail';
import getApplicationRecordTypeId from '@salesforce/apex/ExportApplicationsController.getApplicationRecordTypeId';
import getApplicationCount from '@salesforce/apex/ExportApplicationsController.getApplicationCount';

export default class ExportApplications extends LightningElement {
    programId;
    cohortId = '';
    applicationStage = '';
    applicationStatus = '';
    cohortOptions = [];
    applicationStageOptions = [];
    applicationStatusOptions = [];
    applicationRecordTypeId;
    applicantStateManagement = '';
    applicantStateOptions = [];

    channelName = '/event/AdmissionConsoleEvent__e';
    subscription = null;
    files = [];
    showFiles = false;
    sendEmail = false;
    userId = USER_ID;
    showConfirmation = false;
    recordCount = 0;

    get showFilters() {
        return !!this.programId;
    }

    @wire(getPicklistValuesByRecordType,{
        objectApiName: APPLICATION_OBJECT,
        recordTypeId:'$applicationRecordTypeId'
    })
    wiredPicklists({data,error}){
        if(data){
            this.applicationStageOptions =
                this.toOptions(
                    data.picklistFieldValues.Application_Stage__c.values
                );

            this.applicationStatusOptions =
                this.toOptions(
                    data.picklistFieldValues.Application_Status__c.values
                );

            this.applicantStateOptions =
                this.toOptions(
                    data.picklistFieldValues.Applicant_State_Management__c.values
                );
        }else if (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    connectedCallback() {
        this.registerErrorListener();
        this.subscribePlatformEvent();
    }

    disconnectedCallback() {
        if (this.subscription) {
            unsubscribe(this.subscription);
        }
    }

    subscribePlatformEvent() {
        subscribe(
            this.channelName,
            -1,
            (message)=>{
                this.handlePlatformEvent(message);
            }
        ).then(response=>{
            this.subscription = response;
        });
    }

    registerErrorListener(){
        onError(error=>{
            console.error(error);
        });
    }

    handlePlatformEvent(message){
        const payload = message.data.payload;
        if(payload.UserId__c !== this.userId){
            return;
        }

        if(payload.Intent__c !== 'ApplicationExport'){
            return;
        }

        const result = JSON.parse(payload.Message__c);

        if (result.status === 'NoRecords') {
            this.files = [];
            this.showFiles = true;
            this.showToast(
                'No Records Found',
                'No records were found for the selected filters.',
                'warning'
            );
            return;
        }

        this.files = result.files.map(file=>{
            return{
                name: file.name,
                documentId: file.documentId,
                downloadUrl: '/sfc/servlet.shepherd/document/download/' + file.documentId
            };

        });

        this.showFiles = true;

        this.showToast(
            'Export Completed',
            'Download links are ready.',
            'success'

        );

        if(this.sendEmail){
            sendExportEmail({
                filesJson:JSON.stringify(this.files)
            })
            .catch(error => {
                this.showToast(
                    'Email Failed',
                    this.getErrorMessage(error),
                    'error'
                );
            });
        }
    }

    handleEmailCheckbox(event){
        this.sendEmail = event.target.checked;
    }

    get isCohortDisabled() {
        return !this.programId;
    }

    get isExportDisabled() {
        return !this.programId;
    }

    toOptions(values) {
        return [{ label: 'All', value: '' }, ...values.map(value => ({ label: value.label, value: value.value }))];
    }

    handleProgramChange(event) {
        this.programId = event.detail.recordId;
        this.cohortId = '';

        this.applicationStage = '';
        this.applicationStatus = '';
        this.applicantStateManagement = '';

        this.applicationStageOptions = [];
        this.applicationStatusOptions = [];
        this.applicantStateOptions = [];

        this.files = [];
        this.showFiles = false;

        this.cohortOptions = [{ label: 'All', value: '' }];
        if (!this.programId) return;

        Promise.all([
            getCohortsForProgram({ programId: this.programId }),
            getApplicationRecordTypeId({ programId: this.programId })
        ])
        .then(([cohorts, recordTypeId]) => {

            this.cohortOptions = [
                { label: 'All', value: '' },
                ...cohorts.map(cohort => ({
                    label: cohort.Name,
                    value: cohort.Id
                }))
            ];

            this.applicationRecordTypeId = recordTypeId;

        })
        .catch(error => {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        });
    }

    handleFilterChange(event) {
        this[event.target.dataset.field] = event.detail.value;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    startExport() {
        this.files = [];
        this.showFiles = false;
        
        getApplicationCount({
            programId: this.programId,
            cohortId: this.cohortId || null,
            applicationStage: this.applicationStage || null,
            applicationStatus: this.applicationStatus || null,
            applicantStateManagement: this.applicantStateManagement || null
        }).then(count => {

            if (count === 0) {
                this.showToast(
                    'No Records Found',
                    'No records were found for the selected filters.',
                    'warning'
                );
                return;
            }

            this.recordCount = count;
            this.showConfirmation = true;
        }).catch(error => {
            this.showToast('Error', this.getErrorMessage(error),'error');
        });
    }

    cancelExport() {
        this.showConfirmation = false;
    }

    confirmExport() {
        this.showConfirmation = false;

        exportApplicationsBatch({
            programId: this.programId,
            cohortId: this.cohortId || null,
            applicationStage: this.applicationStage || null,
            applicationStatus: this.applicationStatus || null,
            applicantStateManagement: this.applicantStateManagement || null
        }).then(() => {
            this.showToast(
                'Export Started',
                'Please wait for the job to complete.',
                'info'
            );
        }).catch(error => {
            this.showToast(
                'Export Failed',
                this.getErrorMessage(error),
                'error'
            );
        });
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}