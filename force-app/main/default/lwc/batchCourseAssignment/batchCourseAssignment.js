import { LightningElement, api, track, wire } from 'lwc';
import getAllCourses from '@salesforce/apex/BatchCourseAssignmentController.getAllCourses';
import getExistingProgramCourses from '@salesforce/apex/BatchCourseAssignmentController.getExistingProgramCourses';
import getBatchSpecialisations from '@salesforce/apex/BatchCourseAssignmentController.getBatchSpecialisations';
import getBatchIsSpecialisationProgram from '@salesforce/apex/BatchCourseAssignmentController.getBatchIsSpecialisationProgram';
import saveProgramCourses from '@salesforce/apex/BatchCourseAssignmentController.saveProgramCourses';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference } from 'lightning/navigation';

export default class BatchCourseAssignment extends LightningElement {
    @api recordId; // Batch ID from quick action context
    @track courses = [];
    @track allCourses = []; // Store all courses for filtering
    @track selectedCourses = [];
    @track searchKey = '';
    @track initialSelectedCourseIds = new Set(); // Track courses that were initially selected (have existing records)
    @track specialisationOptions = []; // Specializations assigned to the batch
    @track isBatchSpecialisationProgram = false; // Whether the batch is a specialisation program
    isLoading = false;
    batchId;
    

    // Wire to get recordId from page reference
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference?.state?.recordId) {
            this.batchId = currentPageReference.state.recordId;
            this.loadCourses();
        } else if (this.recordId) {
            this.batchId = this.recordId;
            this.loadCourses();
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.batchId = this.recordId;
            this.loadCourses();
        }
    }

    loadCourses() {
        this.isLoading = true;
        
        // Load all courses, existing program courses, specializations, and batch specialisation program flag in parallel
        Promise.all([
            getAllCourses(),
            this.batchId ? getExistingProgramCourses({ batchId: this.batchId }) : Promise.resolve([]),
            this.batchId ? getBatchSpecialisations({ batchId: this.batchId }) : Promise.resolve([]),
            this.batchId ? getBatchIsSpecialisationProgram({ batchId: this.batchId }) : Promise.resolve(false)
        ])
        .then(([coursesResult, existingCoursesResult, specialisationsResult, isSpecialisationProgram]) => {
            // Store the batch specialisation program flag
            this.isBatchSpecialisationProgram = isSpecialisationProgram === true;
            // Map specializations to options format
            if (specialisationsResult && Array.isArray(specialisationsResult)) {
                this.specialisationOptions = specialisationsResult
                    .filter(spec => spec && spec.specialisationId && spec.specialisationName)
                    .map(spec => ({
                        label: spec.specialisationName,
                        value: spec.specialisationId
                    }));
                console.log('Specialisation options:', this.specialisationOptions);
            } else {
                this.specialisationOptions = [];
                console.log('No specialisations found or invalid result:', specialisationsResult);
            }
            
            // Create a map of existing program courses by learning course ID
            const existingCoursesMap = new Map();
            if (existingCoursesResult) {
                existingCoursesResult.forEach(existing => {
                    existingCoursesMap.set(existing.learningCourseId, existing);
                });
            }
            
            // Map courses and merge with existing data
            this.initialSelectedCourseIds = new Set(); // Reset the set
            this.allCourses = coursesResult.map((course, index) => {
                const courseId = course.courseId || course.Id;
                const existingCourse = existingCoursesMap.get(courseId);
                
                // Track courses that have existing records
                if (existingCourse && existingCourse.programCourseId) {
                    this.initialSelectedCourseIds.add(courseId);
                }
                
                const courseType = existingCourse && existingCourse.courseType ? existingCourse.courseType : 'Core';
                const isHostCourse =
                    existingCourse == null ||
                    existingCourse.isHostCourse === true ||
                    existingCourse.isHostCourse == null;
                return {
                    ...course,
                    selected: existingCourse ? true : false,
                    isMultiTerm: existingCourse ? existingCourse.isMultiTerm : false,
                    courseType: courseType,
                    specialisationId: existingCourse && existingCourse.specialisationId ? existingCourse.specialisationId : null,
                    isHostCourse: isHostCourse,
                    isLocked: existingCourse ? existingCourse.isLocked : false,
                    courseTypeDisabled: existingCourse?.isLocked || false,
                    showSpecialisationDropdown:
    courseType === 'Specialisation' &&
    this.specialisationOptions.length > 0 &&
    !!existingCourse,
                    rowId: courseId,
                    rowNumber: index + 1,
                    isDisabled: existingCourse ? false : true,
                    programCourseId: existingCourse ? existingCourse.programCourseId : null
                };
            });
            
            // Apply search filter
            this.applySearchFilter();
            
            // Update selected courses
            this.updateSelectedCourses();
            
            this.isLoading = false;
        })
        .catch(error => {
            console.error('Error loading courses:', error);
            this.showToast('Error', 'Failed to load courses: ' + (error.body?.message || error.message), 'error');
            this.isLoading = false;
        });
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.applySearchFilter();
    }

    applySearchFilter() {
        if (!this.searchKey || this.searchKey.trim() === '') {
            this.courses = [...this.allCourses];
        } else {
            const searchLower = this.searchKey.toLowerCase().trim();
            this.courses = this.allCourses.filter(course => {
                return (
                    (course.courseName && course.courseName.toLowerCase().includes(searchLower)) ||
                    (course.courseNumber && course.courseNumber.toLowerCase().includes(searchLower))
                );
            });
            
            // Update row numbers for filtered results
            this.courses = this.courses.map((course, index) => ({
                ...course,
                rowNumber: index + 1,
                showSpecialisationDropdown:
    course.courseType === 'Specialisation' &&
    course.selected &&
    this.specialisationOptions.length > 0

            }));
        }
    }

    get courseTypeOptions() {
        const options = [
            { label: 'Core', value: 'Core' },
            { label: 'Elective', value: 'Elective' }
        ];
    
        // ✅ Add Specialization ONLY if batch has active specializations AND batch is a specialisation program
        if (this.specialisationOptions && this.specialisationOptions.length > 0 && this.isBatchSpecialisationProgram) {
            options.push({ label: 'Specialisation', value: 'Specialisation' });
        }
    
        return options;
    }
    
    get specialisationOptionsList() {
        // Return the tracked property as a getter to ensure reactivity
        return this.specialisationOptions || [];
    }

    handleCheckboxChange(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const selected = event.target.checked;
        
        // Update both filtered courses and all courses
        const updateCourse = (course) => {
            if (course.rowId === courseId) {
                const courseType = selected ? course.courseType : 'Core';
                return {
                    ...course,
                    selected: selected,
                    isDisabled: !selected,
                    // Reset multi-term, course type, and specialization if deselected
                    isMultiTerm: selected ? course.isMultiTerm : false,
                    courseType: courseType,
                    specialisationId: selected ? course.specialisationId : null,
                    isHostCourse: selected ? (course.isHostCourse !== false) : true,
                    showSpecialisationDropdown: courseType === 'Specialisation' && selected
                };
            }
            return course;
        };
        
        this.courses = this.courses.map(updateCourse);
        this.allCourses = this.allCourses.map(updateCourse);
        
        this.updateSelectedCourses();
    }


    handleIsHostChange(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const isHostCourse = event.target.checked;

        const updateCourse = (course) => {
            if (course.rowId === courseId) {
                return {
                    ...course,
                    isHostCourse: isHostCourse
                };
            }
            return course;
        };

        this.courses = this.courses.map(updateCourse);
        this.allCourses = this.allCourses.map(updateCourse);
        this.updateSelectedCourses();
    }

    handleMultiTermChange(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const isMultiTerm = event.target.checked;
        
        // Update both filtered courses and all courses
        const updateCourse = (course) => {
            if (course.rowId === courseId) {
                return {
                    ...course,
                    isMultiTerm: isMultiTerm
                };
            }
            return course;
        };
        
        this.courses = this.courses.map(updateCourse);
        this.allCourses = this.allCourses.map(updateCourse);
        
        this.updateSelectedCourses();
    }

    handleCourseTypeChange(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const courseType = event.detail.value;
        
        // Update both filtered courses and all courses
        const updateCourse = (course) => {
            if (course.rowId === courseId) {
                return {
                    ...course,
                    courseType: courseType,
                    // Clear specialization if course type is not Specialization
                    specialisationId: courseType === 'Specialisation' ? course.specialisationId : null,
                    showSpecialisationDropdown: courseType === 'Specialisation' && course.selected
                };
            }
            return course;
        };
        
        this.courses = this.courses.map(updateCourse);
        this.allCourses = this.allCourses.map(updateCourse);
        
        this.updateSelectedCourses();
    }


    handleSpecialisationChange(event) {
        const courseId = event.currentTarget.dataset.courseId;
        const specialisationId = event.detail.value;
        
        // Update both filtered courses and all courses
        const updateCourse = (course) => {
            if (course.rowId === courseId) {
                return {
                    ...course,
                    specialisationId: specialisationId
                };
            }
            return course;
        };
        
        this.courses = this.courses.map(updateCourse);
        this.allCourses = this.allCourses.map(updateCourse);
        
        this.updateSelectedCourses();
    }


    updateSelectedCourses() {
        // Get selected courses from allCourses (not filtered courses)
        this.selectedCourses = this.allCourses.filter(course => course.selected);
    }

    get hasSelectedCourses() {
        return this.selectedCourses.length > 0;
    }

    get selectedCount() {
        return this.selectedCourses.length;
    }

    get isSaveDisabled() {
        // Allow save if there are selected courses OR if there are courses that were initially selected (to handle deletions)
        return this.allCourses.length === 0;
    }

    handleSave() {
        
        if (!this.batchId) {
            this.showToast('Error', 'Batch ID is missing', 'error');
            return;
        }


        // ✅ Validate specialization ONLY if batch specializations exist
        if (this.specialisationOptions && this.specialisationOptions.length > 0) {
            const invalidCourses = this.selectedCourses.filter(course =>
                course.courseType === 'Specialisation' && !course.specialisationId
            );

            if (invalidCourses.length > 0) {
                const courseNames = invalidCourses.map(c => c.courseName || c.courseNumber).join(', ');
                this.showToast(
                    'Validation Error', 
                    `Please select a Specialisation for the following Specialisation-type course(s): ${courseNames}`,
                    'error'
                );
                return;
            }
        }


        this.isLoading = true;

        // Get currently selected course IDs
        const currentlySelectedIds = new Set(
            this.allCourses
                .filter(course => course.selected)
                .map(course => course.courseId)
        );

        // Find courses that were initially selected but are now unselected (need to be deleted)
        const coursesToDelete = [];
        this.allCourses.forEach(course => {
            if (this.initialSelectedCourseIds.has(course.courseId) && !currentlySelectedIds.has(course.courseId)) {
                // This course had an existing record but is now unselected
                if (course.programCourseId) {
                    coursesToDelete.push(course.programCourseId);
                }
            }
        });

        // Prepare course selections for insert/update
        const courseSelections = this.selectedCourses.map(course => ({
            learningCourseId: course.courseId,
            selected: true,
            isMultiTerm: course.isMultiTerm || false,
            courseType: course.courseType || 'Core',
            courseName: course.courseName,
            programCourseId: course.programCourseId || null,
            specialisationId: course.specialisationId || null,
            isHostCourse: course.isHostCourse !== false
        }));

        // Check if there's anything to save or delete
        if (courseSelections.length === 0 && coursesToDelete.length === 0) {
            this.showToast('Info', 'No changes to save', 'info');
            this.isLoading = false;
            return;
        }

        saveProgramCourses({ 
            batchId: this.batchId, 
            courseSelections: courseSelections,
            programCourseIdsToDelete: coursesToDelete
        })
        .then(() => {
            const message = coursesToDelete.length > 0 
                ? `Program courses updated successfully. ${coursesToDelete.length} record(s) deleted.`
                : 'Program courses saved successfully';
            this.showToast('Success', message, 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
            // Refresh the page to show new records
            setTimeout(() => {
                window.location.reload();
            }, 1000);
        })
        .catch(error => {
            console.error('Error saving courses:', error);
            this.showToast('Error', 'Failed to save courses: ' + (error.body?.message || error.message), 'error');
            this.isLoading = false;
        });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
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