import { LightningElement, api, track } from 'lwc';
import getTermDetails from '@salesforce/apex/CourseAssignmentController.getTermDetails';
import saveEditableCourses from '@salesforce/apex/CourseAssignmentController.saveEditableCourses';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AssignCoursesToTerm extends LightningElement {
    @api recordId;   // termId
    @track courses = [];
    selectedRows = [];

    columns = [
        { label: 'Program', fieldName: 'programName', type: 'text', editable: false },
        { label: 'Course', fieldName: 'courseName', type: 'text', editable: false },
        { label: 'Start Date', fieldName: 'startDate', type: 'date', editable: true },
        { label: 'End Date', fieldName: 'endDate', type: 'date', editable: true },
        { label: 'Is Elective', fieldName: 'isElective', type: 'boolean', editable: true }
    ];

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        getTermDetails({ termId: this.recordId })
            .then(result => {
                this.courses = result.map((row, index) => ({
                    rowId: index,
                    courseId: row.courseId,
                    programName: row.programName,
                    courseName: row.courseName,
                    startDate: null,
                    endDate: null,
                    isElective: false
                }));
            })
            .catch(error => console.error(error));
    }

    // track row selections
    handleRowSelection(event) {
        this.selectedRows = event.detail.selectedRows;
    }

    // handle edited fields
    handleSave(event) {
        const draftValues = event.detail.draftValues;

        // merge edits into the main dataset
        draftValues.forEach(d => {
            let target = this.courses.find(r => r.rowId === d.rowId);
            Object.assign(target, d);
        });

        this.template.querySelector('lightning-datatable').draftValues = [];
    }

    handleFinalSave() {
        const payload = this.selectedRows.map(row => ({
            courseId: row.courseId,
            startDate: row.startDate,
            endDate: row.endDate,
            isElective: row.isElective
        }));

        saveEditableCourses({
            termId: this.recordId,
            assignments: payload
        })
        .then(() => {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Course offerings saved successfully!',
                    variant: 'success'
                })
            );
        })
        .catch(error => console.error(error));
    }
}