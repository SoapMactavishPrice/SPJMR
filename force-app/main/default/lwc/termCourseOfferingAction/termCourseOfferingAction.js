import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getProgramCoursesForTerm from '@salesforce/apex/TermCourseOfferingController.getProgramCoursesForTerm';
import getAcademicTerms from '@salesforce/apex/TermCourseOfferingController.getAcademicTerms';
import createCourseOfferings from '@salesforce/apex/TermCourseOfferingController.createCourseOfferings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import BATCH_FIELD from '@salesforce/schema/Term__c.Batch__c';

const TERM_FIELDS = [BATCH_FIELD];

export default class TermCourseOfferingAction extends LightningElement {
    @api recordId; // Term ID from record action
    
    @track courses = [];
    @track academicTerms = [];
    @track selectedCourse = null;
    @track showModal = false;
    @track startDate;
    @track endDate;
    @track evaluationTermId;
    @track isLoading = false;
    @track searchKey = '';
    
    termBatchId;

    @wire(getRecord, { recordId: '$recordId', fields: TERM_FIELDS })
    wiredTerm({ error, data }) {
        if (data) {
            this.termBatchId = data.fields.Batch__c.value;
            this.loadCourses();
        } else if (error) {
            console.error('Error loading term:', error);
            this.showToast('Error', 'Failed to load term information', 'error');
        }
    }

    connectedCallback() {
        this.loadAcademicTerms();
    }

    loadCourses() {
        if (!this.recordId) {
            return;
        }
        
        this.isLoading = true;
        getProgramCoursesForTerm({ termId: this.recordId })
            .then(result => {
                this.courses = result.map((course, index) => ({
                    ...course,
                    rowNumber: index + 1
                }));
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading courses:', error);
                this.showToast('Error', 'Failed to load courses: ' + (error.body?.message || error.message), 'error');
                this.isLoading = false;
            });
    }

    loadAcademicTerms() {
        getAcademicTerms()
            .then(result => {
                this.academicTerms = result.map(term => ({
                    label: term.name + (term.termCode ? ' (' + term.termCode + ')' : ''),
                    value: term.id
                }));
            })
            .catch(error => {
                console.error('Error loading academic terms:', error);
            });
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
    }

    get filteredCourses() {
        if (!this.searchKey || this.searchKey.trim() === '') {
            return this.courses;
        }
        const searchLower = this.searchKey.toLowerCase().trim();
        return this.courses.filter(course => {
            return (
                (course.courseName && course.courseName.toLowerCase().includes(searchLower)) ||
                (course.courseNumber && course.courseNumber.toLowerCase().includes(searchLower)) ||
                (course.programCourseCode && course.programCourseCode.toLowerCase().includes(searchLower))
            );
        });
    }

    handleSelectCourse(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const course = this.courses.find(c => c.programCourseId === courseId);
        
        if (course && !course.isAlreadyOffered) {
            this.selectedCourse = course;
            this.startDate = null;
            this.endDate = null;
            this.evaluationTermId = null;
            this.showModal = true;
        } else if (course && course.isAlreadyOffered) {
            this.showToast('Info', 'This course is already offered for this term', 'info');
        }
    }

    handleStartDateChange(event) {
        this.startDate = event.target.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.target.value;
    }

    handleEvaluationTermChange(event) {
        this.evaluationTermId = event.detail.value;
    }

    handleCloseModal() {
        this.showModal = false;
        this.selectedCourse = null;
        this.startDate = null;
        this.endDate = null;
        this.evaluationTermId = null;
    }

    handleSaveOffering() {
        // Validate dates
        if (!this.startDate || !this.endDate) {
            this.showToast('Error', 'Please select both start date and end date', 'error');
            return;
        }

        // Validate date range
        const start = new Date(this.startDate);
        const end = new Date(this.endDate);
        if (end < start) {
            this.showToast('Error', 'End date must be after start date', 'error');
            return;
        }

        // Validate evaluation term for multi-term courses
        if (this.selectedCourse.isMultiTerm && !this.evaluationTermId) {
            this.showToast('Error', 'Please select an evaluation term for multi-term courses', 'error');
            return;
        }

        this.isLoading = true;

        const offeringWrapper = {
            programCourseId: this.selectedCourse.programCourseId,
            startDate: this.startDate,
            endDate: this.endDate,
            isMultiTerm: this.selectedCourse.isMultiTerm,
            evaluationTermId: this.evaluationTermId
        };

        createCourseOfferings({ 
            termId: this.recordId, 
            courseOfferings: [offeringWrapper] 
        })
            .then(() => {
                this.showToast('Success', 'Course offering created successfully', 'success');
                this.handleCloseModal();
                this.loadCourses(); // Reload to refresh the list
                // Close the action screen after a short delay
                setTimeout(() => {
                    this.dispatchEvent(new CloseActionScreenEvent());
                }, 1500);
            })
            .catch(error => {
                console.error('Error creating course offering:', error);
                this.showToast('Error', 'Failed to create course offering: ' + (error.body?.message || error.message), 'error');
                this.isLoading = false;
            });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    get showEvaluationTerm() {
        return this.selectedCourse && this.selectedCourse.isMultiTerm;
    }

    get isSaveDisabled() {
        return !this.startDate || !this.endDate || (this.showEvaluationTerm && !this.evaluationTermId);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}