import { LightningElement, track } from 'lwc';

import getPendingApprovals from '@salesforce/apex/SpecializationApprovalController.getPendingApprovals';
import approveRequests from '@salesforce/apex/SpecializationApprovalController.approveRequests';
import rejectRequests from '@salesforce/apex/SpecializationApprovalController.rejectRequests';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    {
        label: 'Request',
        fieldName: 'requestName'
    },
    {
        label: 'Student',
        fieldName: 'studentName'
    },
    {
        label: 'Current Specialization',
        fieldName: 'currentSpecialization'
    },
    {
        label: 'Requested Specialization',
        fieldName: 'requestedSpecialization'
    },
    {
        label: 'Submitted',
        fieldName: 'createdDate',
        type: 'date'
    }
];

export default class SpecializationBulkApproval extends LightningElement {

    columns = COLUMNS;

    @track records = [];

    selectedRows = [];

    isLoading = false;

    showRejectModal = false;

    rejectComments = '';

    connectedCallback() {
        this.loadData();
    }

    get selectedCount() {
        return this.selectedRows.length;
    }

    loadData() {

        this.isLoading = true;

        getPendingApprovals()
            .then(result => {
                this.records = result;
            })
            .catch(error => {
                this.showError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

    handleApprove() {

        if(this.selectedRows.length === 0){
            this.showToast(
                'Warning',
                'Select records first',
                'warning'
            );
            return;
        }

        this.isLoading = true;

        approveRequests({
            workItemIds:
                this.selectedRows.map(
                    row => row.workItemId
                )
        })
        .then(() => {

            this.showToast(
                'Success',
                'Requests approved successfully',
                'success'
            );

            this.loadData();
        })
        .catch(error => {
            this.showError(error);
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    openRejectModal() {

        if(this.selectedRows.length === 0){

            this.showToast(
                'Warning',
                'Select records first',
                'warning'
            );

            return;
        }

        this.showRejectModal = true;
    }

    closeRejectModal() {
        this.showRejectModal = false;
    }

    handleCommentChange(event) {
        this.rejectComments = event.target.value;
    }

    handleReject() {

        this.isLoading = true;

        rejectRequests({
            workItemIds:
                this.selectedRows.map(
                    row => row.workItemId
                ),
            comments: this.rejectComments
        })
        .then(() => {

            this.showToast(
                'Success',
                'Requests rejected successfully',
                'success'
            );

            this.showRejectModal = false;

            this.loadData();
        })
        .catch(error => {
            this.showError(error);
        })
        .finally(() => {
            this.isLoading = false;
        });
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

    showError(error) {

        this.showToast(
            'Error',
            error.body?.message || 'Unknown Error',
            'error'
        );
    }
}