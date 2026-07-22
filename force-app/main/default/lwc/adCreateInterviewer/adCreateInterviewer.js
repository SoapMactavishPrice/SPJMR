import { LightningElement, wire, track } from 'lwc';
import createInterviewer from '@salesforce/apex/AdmissionHelper.createInterviewer';
import getInterviewerUsers from '@salesforce/apex/AdmissionHelper.getInterviewerUsers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class AdCreateInterviewer extends LightningElement {

    firstName = '';
    lastName = '';
    email = '';

    @track userList = [];
    wiredUsersResult;

    columns = [
        { label: 'Name', fieldName: 'Name' },
        { label: 'Email', fieldName: 'Email' },
        { label: 'Username', fieldName: 'Username' },
    ];

    getSelectedName(event){
        const selectedRows = event.detail.selectedRows;
        console.log('Selected Rows ',JSON.stringify(selectedRows))
    }

    @wire(getInterviewerUsers)
    wiredUsers(result) {
        this.wiredUsersResult = result;
        if (result.data) {
            this.userList = result.data.map((user)=>{
                return {
                    ...user,
                    Name: user.FirstName + ' ' + user.LastName
                };
            });
        }
    }

    isValid() {
        return this.firstName && this.lastName && this.email;
    }

    handleChange(event) {
        this[event.target.name] = event.target.value;
    }

    async handleSubmit() {
        if (!this.isValid()) {
            this.showToast('Error', 'All fields are required', 'error');
            return;
        }

        const params = {
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email
        };

        try {
            await createInterviewer({ params: JSON.stringify(params) });
            this.showToast('Success', 'Interviewer Created Successfully', 'success');

            // Refresh table
            await refreshApex(this.wiredUsersResult);

            // Clear form
            this.firstName = '';
            this.lastName = '';
            this.email = '';

        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}