import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import courseEnrolled from '@salesforce/apex/StudentProfileDashboardController.courseEnrolled';
import getDivisionEnrollmentTable from '@salesforce/apex/StudentProfileDashboardController.getDivisionEnrollmentTable';
import getDivisionCourseTable from '@salesforce/apex/StudentProfileDashboardController.getDivisionCourseTable';
import profileDummy from '@salesforce/resourceUrl/Profile_Dummy';

export default class Spjimr_termDetail extends LightningElement {
    profileDummyIcon = profileDummy;
    @track studentName = '';
    @track rollNumber = '';
    @track programName = '';
    @track programCode = '';
    subjects = [];
    divisionRows = [];
    combinedDivisionCourseRows = [];
    @track currentTermId = '';
    @track currentTerm = '';
    @track termOptions = []; // sorted options for term combobox
    @track selectedTermValue = ''; // combobox value (term Id)
    urlTermId = null; // term Id passed via navigation state (from program details dropdown)

    get mainContentClass() {
        return this.isSidebarOpen ? 'main-content main-content-with-sidebar' : 'main-content main-content-full';
    }

    @wire(CurrentPageReference)
    setPageRef(pageRef) {
        if (pageRef && pageRef.state && pageRef.state.termId) {
            this.urlTermId = pageRef.state.termId;
            if (this.termOptions && this.termOptions.length > 0) {
                this.applyTermFromUrl();
            }
        }
    }

    connectedCallback() {
        this.loadUserName();
    }

    applyTermFromUrl() {
        if (!this.urlTermId || !this.termOptions.length) return;
        const option = this.termOptions.find((o) => o.value === this.urlTermId);
        this.currentTermId = this.urlTermId;
        this.currentTerm = option ? option.label : '';
        this.selectedTermValue = this.urlTermId;
    }

    loadUserName() {
        getUserInfo()
            .then((result) => {
                if (result) {
                    this.studentName = result.fullName || this.studentName;
                    this.rollNumber = result.rollNumber || '';
                    this.programName = result.programName || '';
                    this.programCode = result.programCode || '';
                    // Sort term options like programDetails (label order)
                    const rawOptions = result.termOptions || [];
                    this.termOptions = [...rawOptions].sort((a, b) =>
                        (a.label || '').localeCompare(b.label || '', undefined, { numeric: true })
                    );
                    if (this.urlTermId) {
                        this.applyTermFromUrl();
                    } else {
                        this.currentTerm = result.term || '';
                        this.currentTermId = result.currentTermId || '';
                        this.selectedTermValue = this.currentTermId || '';
                        // Default to current term: if no currentTermId, match by term label (like programDetails)
                        if (!this.selectedTermValue && this.currentTerm && this.termOptions.length) {
                            const normalized = (this.currentTerm || '').replace(/\s+/g, '').toLowerCase();
                            const opt = this.termOptions.find(
                                (o) => (o.label || '').replace(/\s+/g, '').toLowerCase() === normalized
                            );
                            if (opt) {
                                this.selectedTermValue = opt.value;
                                this.currentTermId = opt.value;
                            }
                        }
                    }
                }
            })
            .catch((error) => {
                console.error('getUserInfo error:', error);
            });
    }

    handleTermChange(event) {
        const value = event.detail.value;
        if (value === this.selectedTermValue) return;
        this.selectedTermValue = value;
        this.currentTermId = value || '';
        const option = this.termOptions.find((o) => o.value === value);
        this.currentTerm = option ? option.label : '';
    }
    @wire(courseEnrolled,{currentTermId:'$currentTermId'})
    fetchCourseEnrolled({ data, error }) {
        if (data) {
            console.log('data::',JSON.stringify(data));
            this.subjects = data;
        } else if (error) {
            this.subjects = [];
            console.error(error);
        }
    }

    @wire(getDivisionEnrollmentTable, { currentTermId: '$currentTermId' })
    wiredDivisionTable({ data, error }) {
        if (data) {
            console.log('data::',data);
            this.divisionRows = [...data].sort((a, b) =>
    a.divisionName.toLowerCase().localeCompare(b.divisionName.toLowerCase())
);
        } else if (error) {
            this.divisionRows = [];
            console.error('Division table error:', error);
        }
    }

    @wire(getDivisionCourseTable, { currentTermId: '$currentTermId' })
    wiredDivisionCourseTable({ data, error }) {
        if (data) {
            console.log('table data::',data);
            this.combinedDivisionCourseRows = data;
        } else if (error) {
            this.combinedDivisionCourseRows = [];
            console.error('Combined division course table error:', error);
        }
    }
}