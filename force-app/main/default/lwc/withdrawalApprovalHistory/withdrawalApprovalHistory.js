import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getApprovalHistory from '@salesforce/apex/WithdrawalApprovalController.getApprovalHistory';

export default class WithdrawalApprovalHistory extends LightningElement {

    @api recordId;

    approvalHistory = [];
    error;
    wiredResult;

    @wire(getApprovalHistory, { recordId: '$recordId' })
    wiredApprovalHistory(result) {
        this.wiredResult = result;
        const { data, error } = result;

        if (data) {
            this.approvalHistory = data.map((item) => {
                let statusClass = '';
                if (item.status === 'Submitted') {
                    statusClass = 'status-submitted';
                } else if (item.status === 'Pending') {
                    statusClass = 'status-pending';
                } else if (item.status === 'Approved') {
                    statusClass = 'status-approved';
                } else if (item.status === 'Rejected') {
                    statusClass = 'status-rejected';
                } else if (item.status === 'Recalled') {
                    statusClass = 'status-recalled';
                }
                return { ...item, statusClass };
            });
            this.error = undefined;
        } else if (error) {
            this.approvalHistory = [];
            this.error = error;
            // eslint-disable-next-line no-console
            console.error('Withdrawal Approval History Error:', JSON.stringify(error));
        }
    }

    get hasApprovalHistory() {
        return this.approvalHistory && this.approvalHistory.length > 0;
    }

    @api
    refreshHistory() {
        return refreshApex(this.wiredResult);
    }
}