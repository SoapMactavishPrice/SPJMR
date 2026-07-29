import { LightningElement, api, wire } from 'lwc';
import getApprovalHistory from '@salesforce/apex/LeaveApprovalHistoryController.getApprovalHistory';

export default class ApprovalHistory extends LightningElement {

    @api recordId;
    rows = [];
    error;
    isLoading = true;

    @wire(getApprovalHistory, { leaveId: '$recordId' })
    wiredHistory({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.rows = data.map((r, idx) => ({
                key: idx,
                stepName: r.stepName,
                stepDate: r.stepDate,
                status: r.status,
                statusClass: this.getStatusClass(r.status),
            
                assignedTo: r.assignedTo
                    ? r.assignedTo.split(',')
                        .map(name => name.trim())
                        .reduce((acc, name, index) => {
                            if (index > 0 && index % 3 === 0) {
                                acc += '\n';
                            } else if (index > 0) {
                                acc += ', ';
                            }
                            acc += name;
                            return acc;
                        }, '')
                    : '',
            
                approvedBy: r.approvedBy,
                remark: r.remark
            }));
            this.error = undefined;
        } else if (error) {
            this.error = error.body ? error.body.message : error.message;
            this.rows = [];
        }
    }

    getStatusClass(status) {
        if (!status) return 'status-badge';
        const s = status.toLowerCase();
        if (s.includes('approved')) return 'status-badge status-approved';
        if (s.includes('rejected')) return 'status-badge status-rejected';
        if (s.includes('pending')) return 'status-badge status-pending';
        if (s.includes('incomplete')) return 'status-badge status-incomplete';
        if (s.includes('submitted')) return 'status-badge status-submitted';
        return 'status-badge';
    }

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    get rowCount() {
        return this.rows ? this.rows.length : 0;
    }

    get cardTitle() {
        return `Approval History (${this.rowCount})`;
    }
}