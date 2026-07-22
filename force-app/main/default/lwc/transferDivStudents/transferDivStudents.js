import { LightningElement, api, wire } from 'lwc';
import getDivisionStudents from '@salesforce/apex/DivisionTransferController.getDivisionStudents';
import getDivisions from '@salesforce/apex/DivisionTransferController.getDivisions';
import transferStudents from '@salesforce/apex/DivisionTransferController.transferStudents';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class TransferDivStudents extends LightningElement {

    @api recordId;

    students = [];
    filteredStudents = [];
    selectedStudents = [];
    targetDivision;

    divisionOptions = [];

    // Fetch students
    @wire(getDivisionStudents, { divisionId: '$recordId' })
    wiredStudents({ error, data }) {

        if (data) {

            this.students = data.map(student => ({
                Id: student.Id,
                Student_Name__c: student.Student_Name__c,
                Roll_Number__c: student.Roll_Number__c,
                DivisionName: student.Division__r ? student.Division__r.Name : '',
                TermEnrollmentName: student.Academic_Term_Enrollment__r 
                    ? student.Academic_Term_Enrollment__r.Name 
                    : ''
            }));

            this.filteredStudents = [...this.students];

        } else if (error) {
            console.error(error);
        }
    }

    // Fetch divisions
    @wire(getDivisions, { currentDivisionId: '$recordId' })
    wiredDivisions({ error, data }) {

        if (data) {
            this.divisionOptions = data.map(div => ({
                label: div.Name,
                value: div.Id
            }));
        } else if (error) {
            console.error(error);
        }
    }

    // Search
    handleSearch(event){

        const key = event.target.value.toLowerCase();

      this.filteredStudents = [...this.students].filter(student =>
            student.Student_Name__c.toLowerCase().includes(key) ||
            (student.Roll_Number__c && student.Roll_Number__c.toString().includes(key))
        );
    }

    // Select Student
    handleStudentSelect(event){

        const studentId = event.target.value;

        if(event.target.checked){
            this.selectedStudents = [...this.selectedStudents, studentId];
        }
        else{
            this.selectedStudents = this.selectedStudents.filter(id => id !== studentId);
        }
    }

    // Select All
    handleSelectAll(event){

        const checkboxes = this.template.querySelectorAll('lightning-input[data-id="studentCheckbox"]');

        if(event.target.checked){

            this.selectedStudents = this.filteredStudents.map(stu => stu.Id);

            checkboxes.forEach(cb => {
                cb.checked = true;
            });

        } else {

            this.selectedStudents = [];

            checkboxes.forEach(cb => {
                cb.checked = false;
            });
        }
    }

    handleDivisionChange(event){
        this.targetDivision = event.detail.value;
    }

    transferStudents(){

        if(!this.targetDivision){

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please select Target Division',
                    variant: 'error'
                })
            );
            return;
        }

        if(this.selectedStudents.length === 0){

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please select students to transfer',
                    variant: 'error'
                })
            );
            return;
        }

        transferStudents({
            enrollmentIds: this.selectedStudents,
            newDivisionId: this.targetDivision
        })
        .then(() => {

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Students transferred successfully',
                    variant: 'success'
                })
            );

            // Close quick action
            this.dispatchEvent(new CloseActionScreenEvent());

            // Refresh page
            setTimeout(() => {
                window.location.reload();
            }, 1000);

        })
        .catch(error => {
            console.error(error);
        });

    }

}