import { LightningElement, track } from 'lwc';
import getGMPApplications from '@salesforce/apex/ConvertApplicantController.getGMPApplications';
import convertToStudent from '@salesforce/apex/ConvertApplicantController.convertToStudent';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTotalGMPApplications from '@salesforce/apex/ConvertApplicantController.getTotalGMPApplications';

export default class AdmissionConvertToStudentTable_GMP extends LightningElement {

    columns = [
        { label: 'Application Number', fieldName: 'applicationNumber' },
        { label: 'Applicant Name', fieldName: 'applicantName' },
        { label: 'Applicant State', fieldName: 'applicantStateManagement' }
    ];

    @track pagedData = [];
    @track selectedRows = [];

    pageSize = 10;

    totalRecords = 0;
    totalPages = 0;

    page = 1;
    pageHistory = [null]; // first page

    connectedCallback() {
        this.loadData();
         this.loadTotalRecords();
    }

    loadData() {

        let lastId = this.pageHistory[this.page - 1];

        getGMPApplications({
            pageSize: this.pageSize,
            lastRecordId: lastId
        })
        .then(result => {

            this.pagedData = result;

            if(result.length > 0){
                let newLastId = result[result.length - 1].Id;

                if(this.pageHistory.length === this.page){
                    this.pageHistory.push(newLastId);
                }
            }

        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

    nextPage() {
        this.page++;
        this.loadData();
    }

    previousPage() {
        if(this.page > 1){
            this.page--;
            this.loadData();
        }
    }

    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows.map(r => r.Id);
    }

    get disableConvert() {
        return this.selectedRows.length === 0;
    }

    get isFirstPage() {
        return this.page === 1;
    }

    get isLastPage() {
        return this.pagedData.length < this.pageSize;
    }

    loadTotalRecords() {

    getTotalGMPApplications()
    .then(result => {

        this.totalRecords = result;
        this.totalPages = Math.ceil(result / this.pageSize);

    })
    .catch(error => {
        this.showToast('Error', error.body.message, 'error');
    });

}

    handleConvert() {

        convertToStudent({ applicationIds: this.selectedRows })
        .then(() => {
            this.showToast('Success', 'Student created successfully', 'success');

            this.selectedRows = [];
            this.loadData();
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}