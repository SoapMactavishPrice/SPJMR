import { LightningElement, api, track } from 'lwc';
import getUnassignedProgramCourses from '@salesforce/apex/AssignCoursesForTerm.getUnassignedProgramCourses';
import getEvaluationTermsForBatchGroup from '@salesforce/apex/AssignCoursesForTerm.getEvaluationTermsForBatchGroup';
import createCourseOfferings from '@salesforce/apex/AssignCoursesForTerm.createCourseOfferings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class AssignCoursesForTerm extends LightningElement {
    @api recordId; // Term ID from action
    
    @track courses = [];
    @track filteredCourses = [];
    @track evaluationTerms = [];
    @track searchKey = '';
    @track isLoading = false;
    @track showModal = true;
    
    connectedCallback() {
        // Always reset modal state when component is connected (action is triggered)
        // This ensures the modal shows every time the action is opened
        this.showModal = true;
        this.courses = [];
        this.filteredCourses = [];
        this.evaluationTerms = [];
        this.searchKey = '';
        this.isLoading = false;
        this.loadData();
    }
    
    loadData() {
        this.isLoading = true;
        
        Promise.all([
            getUnassignedProgramCourses({ termId: this.recordId }),
            getEvaluationTermsForBatchGroup({ termId: this.recordId })
        ])
        .then(([coursesResult, termsResult]) => {
            // Add isDisabled property to each course
            this.courses = (coursesResult || []).map(course => ({
                ...course,
                isDisabled: !course.selected
            }));
            this.filteredCourses = [...this.courses];
            
            // Map evaluation terms to options format
            this.evaluationTerms = (termsResult || []).map(term => ({
                label: term.name,
                value: term.id
            }));
            
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error loading data:', error);
            this.showToast('Error', 'Failed to load courses: ' + (error.body?.message || error.message), 'error');
            this.isLoading = false;
        });
    }
    
    handleSearchChange(event) {
        this.searchKey = event.target.value.toLowerCase();
        this.applySearchFilter();
    }
    
    applySearchFilter() {
        if (!this.searchKey) {
            this.filteredCourses = [...this.courses];
            return;
        }
        
        this.filteredCourses = this.courses.filter(course => {
            const courseName = (course.courseName || '').toLowerCase();
            const courseNumber = (course.courseNumber || '').toLowerCase();
            return courseName.includes(this.searchKey) || courseNumber.includes(this.searchKey);
        });
    }
    
    handleSelectChange(event) {
        const courseId = event.target.dataset.courseId;
        const isSelected = event.target.checked;
        
        const course = this.courses.find(c => c.programCourseId === courseId);
        if (course) {
            course.selected = isSelected;
            course.isDisabled = !isSelected;
            if (!isSelected) {
                // Reset fields when deselected
                course.startDate = null;
                course.endDate = null;
                course.evaluationTermId = null;
            }
        }
        
        // Update filtered courses
        const filteredCourse = this.filteredCourses.find(c => c.programCourseId === courseId);
        if (filteredCourse) {
            filteredCourse.selected = isSelected;
            filteredCourse.isDisabled = !isSelected;
            if (!isSelected) {
                filteredCourse.startDate = null;
                filteredCourse.endDate = null;
                filteredCourse.evaluationTermId = null;
            }
        }
    }
    
    handleStartDateChange(event) {
        const courseId = event.target.dataset.courseId;
        const startDate = event.target.value;
        
        const course = this.courses.find(c => c.programCourseId === courseId);
        if (course) {
            course.startDate = startDate;
        }
        
        const filteredCourse = this.filteredCourses.find(c => c.programCourseId === courseId);
        if (filteredCourse) {
            filteredCourse.startDate = startDate;
        }
    }
    
    handleEndDateChange(event) {
        const courseId = event.target.dataset.courseId;
        const endDate = event.target.value;
        
        const course = this.courses.find(c => c.programCourseId === courseId);
        if (course) {
            course.endDate = endDate;
        }
        
        const filteredCourse = this.filteredCourses.find(c => c.programCourseId === courseId);
        if (filteredCourse) {
            filteredCourse.endDate = endDate;
        }
    }
    
    handleEvaluationTermChange(event) {
        const courseId = event.target.dataset.courseId;
        const evaluationTermId = event.detail.value;
        
        const course = this.courses.find(c => c.programCourseId === courseId);
        if (course) {
            course.evaluationTermId = evaluationTermId;
        }
        
        const filteredCourse = this.filteredCourses.find(c => c.programCourseId === courseId);
        if (filteredCourse) {
            filteredCourse.evaluationTermId = evaluationTermId;
        }
    }
    
    handleSave() {
        // Validate selected courses
        const selectedCourses = this.courses.filter(c => c.selected);
        
        if (selectedCourses.length === 0) {
            this.showToast('Error', 'Please select at least one course', 'error');
            return;
        }
        
        // Validate all selected courses have required fields
        const invalidCourses = [];
        for (const course of selectedCourses) {
            if (!course.startDate || !course.endDate) {
                invalidCourses.push(course.courseName || 'Unknown');
            }
        }
        
        if (invalidCourses.length > 0) {
            this.showToast('Error', 'Please fill Start Date and End Date for all selected courses: ' + invalidCourses.join(', '), 'error');
            return;
        }
        
        // Validate date ranges
        for (const course of selectedCourses) {
            const start = new Date(course.startDate);
            const end = new Date(course.endDate);
            if (end < start) {
                this.showToast('Error', `End date must be after start date for ${course.courseName}`, 'error');
                return;
            }
        }
        
        this.isLoading = true;
        
        // Prepare course offerings
        const courseOfferings = selectedCourses.map(course => ({
            programCourseId: course.programCourseId,
            startDate: course.startDate,
            endDate: course.endDate,
            evaluationTermId: course.evaluationTermId
        }));
        
        createCourseOfferings({ 
            termId: this.recordId, 
            courseOfferings: courseOfferings 
        })
        .then(() => {
            this.showToast('Success', 'Course offerings created successfully', 'success');
            this.handleClose();
        })
        .catch(error => {
            console.error('Error creating course offerings:', error);
            this.showToast('Error', 'Failed to create course offerings: ' + (error.body?.message || error.message), 'error');
            this.isLoading = false;
        });
    }
    
    handleClose(event) {
        // Prevent default behavior and stop propagation
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        
        // Close the action screen immediately
        const closeEvent = new CloseActionScreenEvent();
        this.dispatchEvent(closeEvent);
    }
    
    handleCancel(event) {
        // Prevent default behavior and stop propagation  
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        
        // Close the action screen immediately
        const closeEvent = new CloseActionScreenEvent();
        this.dispatchEvent(closeEvent);
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
    
    get hasSelectedCourses() {
        return this.courses.some(c => c.selected);
    }
}