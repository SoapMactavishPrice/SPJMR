import { LightningElement, api, wire,track } from 'lwc';
import getShortlistedApplications from
    '@salesforce/apex/InterviewController.getShortlistedApplications';
import AdBulkInterviewScheduleModal  from 'c/adBulkInterviewScheduleModal'
const COLUMNS = [
    { label: 'Application Number', fieldName: 'applicationNumber' },
    { label: 'Applicant Name', fieldName: 'applicantName' },
    { label: 'Applicant State', fieldName: 'applicantStateManagement' },
    { label: 'Evaluation Score', fieldName: 'evaluationScore' }
];

export default class AdBulkInterviewSchedule extends LightningElement {

    // ---- CONFIG ----
    @api pageSize = 10;
    columns = COLUMNS;
    disableButton = true
    // ---- DATA ----
    allData = [];
    pagedData = [];
    @track selectedRows = [];

    // ---- PAGINATION ----
    page = 1;
    totalPages = 0;

    // ---- APEX ----
    @wire(getShortlistedApplications)
    wiredApps({ data, error }) {
        if (data) {
            this.allData = data;
            this.totalPages = Math.ceil(this.allData.length / this.pageSize);
            this.page = 1;
            this.setPageData();
        } else if (error) {
            console.error('Error fetching applications', error);
        }
    }

    // ---- PAGINATION LOGIC ----
    setPageData() {
        const start = (this.page - 1) * this.pageSize;
        const end = start + this.pageSize;
        this.pagedData = this.allData.slice(start, end);
    }

    nextPage() {
        if (this.page < this.totalPages) {
            this.page++;
            this.setPageData();
        }
    }

    previousPage() {
        if (this.page > 1) {
            this.page--;
            this.setPageData();
        }
    }

    get isFirstPage() {
        return this.page === 1;
    }

    get isLastPage() {
        return this.page === this.totalPages;
    }

    // ---- ROW SELECTION ----
    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows.map(row => row.Id);
        if(this.disableButton){
            this.disableButton = false
        }
        console.log('Selected ',JSON.stringify(this.selectedRows))
        // this.dispatchEvent(
        //     new CustomEvent('rowselection', {
        //         detail: event.detail.selectedRows
        //     })
        // );
    }

  async handleBookSlots() {
    const result = await AdBulkInterviewScheduleModal.open({
        size: 'small', // small | medium | large
        applicationIds: this.selectedRows // 👈 pass selected IDs
    });

    console.log('Modal closed with:', result);
}
}