import { LightningElement } from 'lwc';
import Toast from 'lightning/toast';
import getSessions from '@salesforce/apex/LeaveRequestController.getSessions';
import saveLeaveRequest from '@salesforce/apex/LeaveRequestController.saveLeaveRequest';

export default class LeaveRequest extends LightningElement {

    startDate;
    endDate;
    leaveType;
    remark;
    sessions = [];

    showModal = false;
    isLoading = false;

    leaveTypeOptions = [
        { label: 'Sick Leave', value: 'Sick Leave' },
        { label: 'Casuall Leave', value: 'Casual Leave' },
        { label: 'Emergency Leave', value: 'Emergency Leave' }
    ];

    columns = [
        { label: 'Session Name', fieldName: 'sessionName' },
        { label: 'Start Time', fieldName: 'startTime', type: 'date' },
        { label: 'End Time', fieldName: 'endTime', type: 'date' }
    ];

    handleChange(event) {
        const field = event.target.name;
        this[field] = event.target.value;
    }

    showToast(message, variant) {
        Toast.show({
            label: variant === 'success' ? 'Success' :
                   variant === 'warning' ? 'Warning' : 'Error',
            message: message,
            variant: variant
        });
    }

    async handlePreview() {

        if (!this.startDate || !this.endDate) {
            this.showToast('Please select Start and End Date', 'error');
            return;
        }

        this.isLoading = true;

        try {
            const result = await getSessions({
                startDate: this.startDate,
                endDate: this.endDate
            });

            if (!result || result.length === 0) {
                this.showToast('No sessions found for selected dates', 'warning');
                return;
            }

            this.sessions = result;
            this.showModal = true;

        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleSubmit() {

        if (!this.startDate || !this.endDate || !this.leaveType) {
            this.showToast('Please fill all required fields', 'error');
            return;
        }

        this.isLoading = true;

        try {
            await saveLeaveRequest({
                startDate: this.startDate,
                endDate: this.endDate,
                leaveType: this.leaveType,
                remark: this.remark
            });

            this.showModal = false;
            this.showToast('Leave request submitted successfully!', 'success');
            this.resetForm();

        } catch (error) {
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.showModal = false;
        this.sessions = [];
    }

    resetForm() {
        this.startDate = null;
        this.endDate = null;
        this.leaveType = null;
        this.remark = null;
        this.sessions = [];
    }

    handleError(error) {
        console.error(error);

        let message = 'Something went wrong';
        if (error?.body?.message) {
            message = error.body.message;
        }

        this.showToast(message, 'error');
    }
}