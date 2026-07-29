import { LightningElement, track, wire ,api } from 'lwc';
import getUserInfo from '@salesforce/apex/StudentProfileDashboardController.getUserInfo';
import isStudentPortalLeaveModuleEnabled from '@salesforce/apex/StudentProfileDashboardController.isStudentPortalLeaveModuleEnabled';

export default class StudentDashboard extends LightningElement {
    /** Used by mainContentClass when a sidebar layout is added; default full-width. */
    isSidebarOpen = false;

    /** Defaults true until wire resolves (matches Apex default when CMDT record is absent). */
    @track leaveModuleEnabled = true;

    @track currentTermId = '';
    @track currentTerm = '';
    @track termOptions = [];
    @track selectedTermValue = '';
    @api pageType = 'leave';
    @wire(isStudentPortalLeaveModuleEnabled)
    wiredLeaveModuleEnabled({ data }) {
        if (data !== undefined && data !== null) {
            this.leaveModuleEnabled = data === true;
        }
    }

    connectedCallback() {
        this.loadUserName();
        const path = window.location.pathname.toLowerCase();

    if (path.includes('attendance-report')) {
        this.pageType = 'Attendance Report';
    } else if (path.includes('leave-and-attendance')){
        this.pageType = 'leave';
     }
    }
    loadUserName() {
        getUserInfo()
            .then((result) => {
                if (result) {

                    const rawOptions = result.termOptions || [];
                    this.termOptions = [...rawOptions].sort((a, b) =>
                        (a.label || '').localeCompare(b.label || '', undefined, { numeric: true })
                    );
                    this.currentTerm = result.term || '';
                    this.currentTermId = result.currentTermId || '';
                    this.selectedTermValue = this.currentTermId || '';
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
    get mainContentClass() {
        return this.isSidebarOpen ? 'main-content main-content-with-sidebar' : 'main-content main-content-full';
    }

    get pageTitle() {
        if (this.pageType === 'Attendance Report') {
        return 'Attendance Report';
    }
        return this.leaveModuleEnabled ? 'Leave Application' : 'Attendance Report';
    } 

   /* get pageTitle() {
    return this.isAttendancePage ? 'Attendance Report' : 'Leave';
    }*/

    get showLeaveApplication() {
        return this.leaveModuleEnabled === true;
    }

    get showAttendance() {
        return true;
    }

    get dashboardGridClass() {
        const base = 'slds-grid slds-gutters dashboard-grid';
        return this.showLeaveApplication ? base : `${base} dashboard-grid--attendance-only`;
    }

    get leftPanelClass() {
        return 'slds-col slds-size_1-of-3 left-panel';
    }

    get rightPanelClass() {
        return this.showLeaveApplication
            ? 'slds-col slds-size_2-of-3 right-panel'
            : 'slds-col slds-size_1-of-1 right-panel right-panel--full';
    }
    get isAttendancePage() {
    return this.pageType === 'Attendance Report';
    }

    get isLeavePage() {
    return this.pageType === 'leave';
    }

    get selectedTermStartDate() {
    const match = this.termOptions.find(o => o.value === this.selectedTermValue);
    return match?.startDate || '';
}

get selectedTermEndDate() {
    const match = this.termOptions.find(o => o.value === this.selectedTermValue);
    return match?.endDate || '';
}
}