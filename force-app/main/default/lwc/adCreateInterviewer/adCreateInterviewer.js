import { LightningElement, wire, track } from 'lwc';
import createInterviewer from '@salesforce/apex/AdmissionHelper.createInterviewer';
import getInterviewerUsers from '@salesforce/apex/AdmissionHelper.getInterviewerUsers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

export default class AdCreateInterviewer extends LightningElement {

    firstName = '';
    lastName = '';
    email = '';
    selectedProgramId;

    @track userList = [];
    wiredUsersResult;

    columns = [
        { label: 'Name', fieldName: 'Name', initialWidth: 220 },
        { label: 'Email', fieldName: 'Email', initialWidth: 360 },
        { label: 'Username', fieldName: 'Username', initialWidth: 400 },
    ];

    getSelectedName(event){
        const selectedRows = event.detail.selectedRows;
        console.log('Selected Rows ',JSON.stringify(selectedRows))
    }

    @wire(getInterviewerUsers, { programId: '$selectedProgramId' })
    wiredUsers(result) {
        this.wiredUsersResult = result;
        if (result.data) {
            this.userList = result.data.map((user)=>{
                return {
                    ...user,
                    Name: user.FirstName + ' ' + user.LastName
                };
            });
        } else if (result.error) {
            this.userList = [];
            this.showToast(
                'Error',
                result.error?.body?.message || 'Unable to load interviewers.',
                'error'
            );
        }
    }

    isValid() {
        return this.selectedProgramId &&
            this.firstName &&
            this.lastName &&
            this.email;
    }

    handleProgramChange(event) {
        this.selectedProgramId = event.detail.recordId;
        if (!this.selectedProgramId) {
            this.userList = [];
        }
    }

    handleChange(event) {
        this[event.target.name] = event.target.value;
    }

    async handleSubmit() {
        if (!this.isValid()) {
            this.showToast('Error', 'Program and all fields are required', 'error');
            return;
        }

        const params = {
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email
        };

        try {
            await createInterviewer({
                params: JSON.stringify(params),
                programId: this.selectedProgramId
            });
            this.showToast('Success', 'Interviewer Created Successfully', 'success');

            // Refresh table
            await refreshApex(this.wiredUsersResult);

            // Clear form
            this.firstName = '';
            this.lastName = '';
            this.email = '';

        } catch (error) {
            this.showToast(
                'Error',
                error?.body?.message || error?.message || 'Unable to create interviewer.',
                'error'
            );
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}