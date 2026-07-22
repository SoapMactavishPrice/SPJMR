import { LightningElement, api, track, wire } from 'lwc';
import getTermDetails from '@salesforce/apex/CourseAssignmentController.getTermDetails';
import getEvaluationTermsForBatch from '@salesforce/apex/CourseAssignmentController.getEvaluationTermsForBatch';
import saveEditableCourses from '@salesforce/apex/CourseAssignmentController.saveEditableCourses';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';

export default class AssignCoursesToTermAction extends LightningElement {
  @track courses = [];
  @track filteredCourses = [];
  @track allCourses = []; // Store all courses for filtering
  @track searchKey = '';
  @track isLoading = false;
  @track evaluationTerms = []; // Terms for evaluation term selection
  recordId;

  // Read recordId from quick action context
  @wire(CurrentPageReference)
  getStateParameters(currentPageReference) {
    if (currentPageReference?.state?.recordId) {
      this.recordId = currentPageReference.state.recordId;
      this.loadData();
    }
  }

  connectedCallback() {
    // Increase modal width for ScreenAction
    this.increaseModalWidth();
  }

  increaseModalWidth() {
    // Use setTimeout to ensure modal is rendered
    setTimeout(() => {
      // Find the modal container created by Salesforce for ScreenAction
      const modalContainer = document.querySelector('.slds-modal__container');
      if (modalContainer) {
        modalContainer.style.width = '90vw';
        modalContainer.style.maxWidth = '1400px';
        modalContainer.style.minWidth = '1200px';
      }
      
      // Also try to find and update the modal itself
      const modal = document.querySelector('.slds-modal');
      if (modal) {
        const modalContent = modal.querySelector('.slds-modal__content');
        if (modalContent) {
          modalContent.style.width = '100%';
        }
      }
    }, 100);
  }

  loadData() {
    if (!this.recordId) return;
    
    this.isLoading = true;
    Promise.all([
      getTermDetails({ termId: this.recordId }),
      getEvaluationTermsForBatch({ termId: this.recordId })
    ])
      .then(([coursesResult, evaluationTermsResult]) => {
        // Map evaluation terms
        this.evaluationTerms = (evaluationTermsResult || []).map(term => ({
          label: term.name,
          value: term.id
        }));
        
        // Map courses with all necessary properties
        this.allCourses = coursesResult.map((r, i) => {
          const course = {
          courseId: r.courseId,
          learningCourse: r.learningCourse,
          programName: r.programName,
          courseName: r.courseName,
          courseCode: r.courseCode,
          courseType: r.courseType || '',
          specialisation: r.specialisation || '',
            isMultiTerm: r.isMultiTerm || false,
          selected: false,
          startDate: r.termStartDate || null,
          endDate: r.termEndDate || null,
          termStartDate: r.termStartDate || null, // Store term dates for restoration
          termEndDate: r.termEndDate || null,
            evaluationTermId: r.existingEvaluationTermId || null, // Pre-populate if exists
            existingEvaluationTermId: r.existingEvaluationTermId || null,
            isEvaluationTermReadOnly: r.isEvaluationTermReadOnly || false, // Set read-only flag
            existingCourseOfferingId: null, // For updating existing records
            isDisabled: true, // Disabled until selected
            rowNumber: i + 1
          };
          // Compute disabled and required states for evaluation term
          course.isEvalTermDisabled = true; // Disabled until selected
          course.isEvalTermRequired = !course.isEvaluationTermReadOnly;
          return course;
        });

        console.log('allCourses:::',JSON.stringify(this.allCourses));
        
        // Initialize filtered courses
        this.filteredCourses = [...this.allCourses];
        this.isLoading = false;
        // Increase modal width after data loads
        this.increaseModalWidth();
      })
      .catch(err => {
        this.showToast('Error', 'Unable to load courses', 'error');
        console.error(err);
        this.isLoading = false;
      });
  }

  get hasCourses() {
    return this.allCourses && this.allCourses.length > 0;
  }

  get hasSelectedCourses() {
    return this.allCourses.some(c => c.selected);
  }

  get selectedCount() {
    return this.allCourses.filter(c => c.selected).length;
  }

  get isSaveDisabled() {
    // Disable save if no courses are selected
    return !this.hasSelectedCourses;
  }

  get hasMultiTermCourses() {
    return this.allCourses.some(c => c.selected && c.isMultiTerm);
  }

  get hasSingleTermCourses() {
    return this.allCourses.some(c => c.selected && !c.isMultiTerm);
  }

  get showSaveButton() {
    // Show Save button if we have selected courses and all multi-term courses have evaluation terms
    if (!this.hasSelectedCourses) {
      return false;
    }
    
    // Check if all multi-term courses have evaluation terms
    const multiTermCoursesWithoutEval = this.allCourses.filter(
      c => c.selected && c.isMultiTerm && !c.evaluationTermId
    );
    
    return multiTermCoursesWithoutEval.length === 0;
  }

  get selectedEvaluationTermName() {
    if (!this.selectedEvaluationTermId || !this.evaluationTerms || this.evaluationTerms.length === 0) {
      return '';
    }
    const term = this.evaluationTerms.find(t => t.value === this.selectedEvaluationTermId);
    return term ? term.label : '';
  }
  

  handleSearchChange(event) {
    this.searchKey = event.target.value;
    this.applySearchFilter();
  }

  applySearchFilter() {
    if (!this.searchKey || this.searchKey.trim() === '') {
      this.filteredCourses = [...this.allCourses];
    } else {
      const searchLower = this.searchKey.toLowerCase().trim();
      this.filteredCourses = this.allCourses.filter(course => {
        return (
          (course.courseName && course.courseName.toLowerCase().includes(searchLower)) ||
          (course.courseCode && course.courseCode.toLowerCase().includes(searchLower)) ||
          (course.specialisation && course.specialisation.toLowerCase().includes(searchLower))
        );
      });
      
      // Update row numbers for filtered results
      this.filteredCourses = this.filteredCourses.map((course, index) => ({
        ...course,
        rowNumber: index + 1
      }));
    }
  }

  handleSelectChange(event) {
    const courseId = event.currentTarget.dataset.courseId;
    const isSelected = event.target.checked;
    
    // Update both filtered courses and all courses
    const updateCourse = (course) => {
      if (course.courseId === courseId) {
        const updatedCourse = {
          ...course,
          selected: isSelected,
          isDisabled: !isSelected,
          // Reset fields when deselected, restore term dates when selected
          startDate: isSelected ? (course.startDate || course.termStartDate) : null,
          endDate: isSelected ? (course.endDate || course.termEndDate) : null,
          evaluationTermId: isSelected ? (course.evaluationTermId || course.existingEvaluationTermId) : null
        };
        // Compute disabled and required states for evaluation term
        updatedCourse.isEvalTermDisabled = !isSelected || updatedCourse.isEvaluationTermReadOnly;
        updatedCourse.isEvalTermRequired = !updatedCourse.isEvaluationTermReadOnly;
        return updatedCourse;
      }
      return course;
    };
    
    this.allCourses = this.allCourses.map(updateCourse);
    this.filteredCourses = this.filteredCourses.map(updateCourse);
  }

  handleStartDateChange(event) {
    const courseId = event.currentTarget.dataset.courseId;
    const startDate = event.target.value;
    
    // Update both filtered courses and all courses
    const updateCourse = (course) => {
      if (course.courseId === courseId) {
        return {
          ...course,
          startDate: startDate
        };
      }
      return course;
    };
    
    this.allCourses = this.allCourses.map(updateCourse);
    this.filteredCourses = this.filteredCourses.map(updateCourse);
    
  }

  handleEndDateChange(event) {
    const courseId = event.currentTarget.dataset.courseId;
    const endDate = event.target.value;
    
    // Update both filtered courses and all courses
    const updateCourse = (course) => {
      if (course.courseId === courseId) {
        return {
          ...course,
          endDate: endDate
        };
      }
      return course;
    };
    
    this.allCourses = this.allCourses.map(updateCourse);
    this.filteredCourses = this.filteredCourses.map(updateCourse);
    
  }

  handleEvaluationTermChange(event) {
    const courseId = event.currentTarget.dataset.courseId;
    // lightning-combobox uses event.detail.value
    const evaluationTermId = event.detail ? event.detail.value : (event.target ? event.target.value : null);
    
    // Update the course data
    const updateCourse = (course) => {
      if (course.courseId === courseId) {
        return {
          ...course,
          evaluationTermId: evaluationTermId
        };
      }
      return course;
    };
    
    this.allCourses = this.allCourses.map(updateCourse);
    this.filteredCourses = this.filteredCourses.map(updateCourse);
  }



  saveAll() {
    // Get all selected courses (both single-term and multi-term)
    let selectedCourses = this.allCourses.filter(c => c.selected);
    
    // Validate multi-term courses have evaluation terms
    const missingEvaluationTerms = [];
    for (const course of selectedCourses) {
      if (course.isMultiTerm && !course.evaluationTermId) {
        missingEvaluationTerms.push(course.courseName || 'Unknown');
      }
    }
    
    if (missingEvaluationTerms.length > 0) {
      this.showToast('Error', 'Please select Evaluation Term for all multi-term courses: ' + missingEvaluationTerms.join(', '), 'error');
      return;
    }
    
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

    // Get ALL inputs from this LWC DOM for validation
    const inputs = this.template.querySelectorAll('lightning-input[type="date"]');
    let isValid = true;

    inputs.forEach(input => {
        if (input.type === "date") {
        const courseId = input.dataset.courseId;
        const course = selectedCourses.find(c => c.courseId === courseId);
        if (course && !input.value) {
                input.setCustomValidity("This field is required");
                input.reportValidity();
                isValid = false;
            } else {
                input.setCustomValidity("");
                input.reportValidity();
            }
        }
    });

    if (!isValid) {
        return; // Stop Save
    }

    // Combine selected courses into assignments
    const allAssignments = selectedCourses.map(r => ({
      courseName: r.courseName,
      courseId: r.courseId,
      startDate: r.startDate,
      endDate: r.endDate,
      learningCourse: r.learningCourse,
      isMultiTerm: r.isMultiTerm || false,
      evaluationTermId: r.evaluationTermId || null,
      existingCourseOfferingId: r.existingCourseOfferingId || null,
      isEvaluationTermReadOnly: r.isEvaluationTermReadOnly || false
    }));
    
    // No need to delete old records when evaluation term is read-only
    const idsToDelete = [];

    this.isLoading = true;
    saveEditableCourses({ 
      termId: this.recordId, 
      assignments: allAssignments,
      courseIdsToDelete: idsToDelete
    })
      .then(() => {
        this.showToast('Success', 'Course offerings created', 'success');
        // Close modal first
        this.dispatchEvent(new CloseActionScreenEvent());
        // Wait longer to ensure modal closes completely before reload
        // Using 1000ms delay like batchCourseAssignment
        setTimeout(() => {
        window.location.reload();
        }, 1000);
      })
      .catch(err => {
        console.error(err);
        this.showToast('Error', err.body ? err.body.message : 'Unknown', 'error');
        this.isLoading = false;
      });
}

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  closeAction() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }
}