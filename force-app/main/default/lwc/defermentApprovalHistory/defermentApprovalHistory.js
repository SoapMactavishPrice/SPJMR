import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getApprovalHistory
    from '@salesforce/apex/DefermentRequestController.getApprovalHistory';

export default class DefermentApprovalHistory extends LightningElement {

    @api recordId;

    approvalHistory = [];
    error;
    wiredResult; // NEW: keep reference to the whole wire response

    @wire(getApprovalHistory, {
        recordId: '$recordId'
    })
    wiredApprovalHistory(result) {

        this.wiredResult = result; // NEW: save it for refreshApex later

        const { data, error } = result;

        if (data) {

            this.approvalHistory = data.map(item => {

                let statusClass = '';

                if (item.status === 'Submitted') {
                    statusClass = 'status-submitted';

                } else if (item.status === 'Pending') {
                    statusClass = 'status-pending';

                } else if (item.status === 'Approved') {
                    statusClass = 'status-approved';

                } else if (item.status === 'Rejected') {
                    statusClass = 'status-rejected';
                }

                return {
                    ...item,
                    statusClass
                };
            });

            this.error = undefined;

        } else if (error) {
            this.approvalHistory = [];
            this.error = error;

            console.error(
                'Approval History Error:',
                JSON.stringify(error)
            );
        }
    }

    get hasApprovalHistory() {
        return this.approvalHistory &&
            this.approvalHistory.length > 0;
    }

    // NEW: public method the parent component can call to force a refetch
    @api
    refreshHistory() {
        return refreshApex(this.wiredResult);
    }
}