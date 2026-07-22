/**
 * @description LWC Component for enrolling students in Academic Term
 * Displays students in a modal with search and selection functionality
 * Supports two scenarios:
 * 1. Previous Term is blank: Shows all Active ProgramEnrollments for the Batch
 * 2. Previous Term is NOT blank: Shows students from Previous Term's AcademicTermEnrollments
 */
import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getStudentsForTerm from '@salesforce/apex/SPJIMREnrolledStudentInTermController.getStudentsForTerm';
import createTermEnrollments from '@salesforce/apex/SPJIMREnrolledStudentInTermController.createTermEnrollments';
import getFundamentalDivisions from '@salesforce/apex/SPJIMREnrolledStudentInTermController.getFundamentalDivisions';
import getDivisionGroups from '@salesforce/apex/SPJIMREnrolledStudentInTermController.getDivisionGroups';
import getDivisionColorPicklistOptions from '@salesforce/apex/SPJIMREnrolledStudentInTermController.getDivisionColorPicklistOptions';
import getBatchSpecialisations from '@salesforce/apex/SPJIMREnrolledStudentInTermController.getBatchSpecialisations';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ToastContainer from 'lightning/toastContainer';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference } from 'lightning/navigation';

export default class SpjimrEnrolledStudentInTermModal extends NavigationMixin(LightningElement) {
    @api recordId; // Primary: from record page context (AcademicTerm ID)
    
    // Student data
    @track allStudents = []; // Store all students for filtering
    @track filteredStudents = []; // Filtered students based on search
    @track searchKey = '';
    @track isLoading = false;
    @track isPreviousTermBlank = false;
    @track previousTermId;
    @track batchId;
    @track autoCreateFundamentalDivision = false;
    @track divisionCreationOption = 'previousTermDivision'; // 'previousTermDivision' or 'newDivision'
    @track fundamentalDivisions = []; // Store fundamental divisions for editing
    @track divisionGroupOptions = []; // Store Division Group options for combobox
    @track divisionColorOptions = []; // Division_Color__c picklist (from schema)
    @track specialisationOptions = []; // Specialisation_Name__c Options
    
    // Fallback recordId from page reference
    actualRecordId;
    @track isTermExpired = false;
    @track termEndDate;

    /**
     * @description Wire to get recordId from page reference (fallback for ScreenAction)
     * This handles cases where @api recordId might not be available
     */
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference?.state?.recordId) {
            this.actualRecordId = currentPageReference.state.recordId;
            this.loadData();
        } else if (this.recordId && !this.actualRecordId) {
            this.actualRecordId = this.recordId;
            this.loadData();
        }
    }

    /**
     * @description Lifecycle hook - called when component is inserted into DOM
     * Loads data if recordId is available
     */
    connectedCallback() {
        const toastContainer = ToastContainer.instance();
        toastContainer.maxShown = 3;
        toastContainer.toastPosition = 'top-right';
        if (this.recordId && !this.actualRecordId) {
            this.actualRecordId = this.recordId;
            this.loadData();
        }
    }

    /**
     * @description Getter to return recordId from either @api or fallback source
     * @returns {String} The current record ID
     */
    get currentRecordId() {
        return this.recordId || this.actualRecordId;
    }

    get hideSaveButton() {
        return !this.showNoStudentsMessage && !this.isTermExpired;
    }

    /**
     * @description Getter to check if info boxes should be shown
     * Info boxes are hidden when Auto Create Fundamental Division is checked
     * @returns {Boolean} True if info boxes should be shown
     */
    get showInfoBoxes() {
        return !this.autoCreateFundamentalDivision;
    }

    /**
     * @description Getter to check if radio buttons should be shown
     * Shows when: Auto Create Fundamental Division is unchecked AND Previous Term has value AND at least one student is selected
     * @returns {Boolean} True if radio buttons should be visible
     */
    get showDivisionRadioButtons() {
        return !this.autoCreateFundamentalDivision && 
               !this.isPreviousTermBlank && 
               this.previousTermId && 
               this.hasSelectedStudents;
    }

    /**
     * @description Getter for radio button options
     * @returns {Array} Array of radio button options
     */
    get divisionOptions() {
    return [
        { 
            label: 'Create division and enroll students as per previous term', 
            value: 'previousTermDivision' 
        },
        { 
            label: 'Create new division', 
            value: 'newDivision' 
        },
        { 
            label: 'Enroll students in term only (without division creation)', 
            value: 'noDivision' 
        }
    ];
}

    /**
     * @description Handles radio button change for division creation option
     * @param {Event} event - The radio button change event
     */
    handleDivisionOptionChange(event) {
        this.divisionCreationOption = event.detail.value;
        // Load fundamental divisions when option changes
        if (this.shouldShowFundamentalDivisions) {
            this.loadFundamentalDivisions();
        }
    }

    /**
     * @description Getter to check if fundamental divisions table should be shown
     * Shows when: (Create new division is selected OR previous term is blank) AND students AND Auto Create Fundamental Division is unchecked are selected
     * @returns {Boolean} True if fundamental divisions table should be visible
     */
    get shouldShowFundamentalDivisions() {
        const isNewDivisionSelected = this.divisionCreationOption === 'newDivision';
        const shouldShow = !this.autoCreateFundamentalDivision &&(isNewDivisionSelected || this.isPreviousTermBlank) && this.hasSelectedStudents;
        return shouldShow;
    }

    /**
     * @description Getter to check if there are fundamental divisions
     * @returns {Boolean} True if fundamental divisions exist
     */
    get hasFundamentalDivisions() {
        return this.fundamentalDivisions && this.fundamentalDivisions.length > 0;
    }

    /**
     * @description Getter to check if there are no fundamental divisions
     * @returns {Boolean} True if no fundamental divisions exist
     */
    get hasNoFundamentalDivisions() {
        return !this.fundamentalDivisions || this.fundamentalDivisions.length === 0;
    }

    /**
     * @description Getter for fundamental divisions heading text
     * Returns custom message when "create new division" is selected OR previous term is blank
     * @returns {String} Heading text for fundamental divisions section
     */
    get fundamentalDivisionsHeading() {
        const isNewDivisionSelected = this.divisionCreationOption === 'newDivision';
        if (isNewDivisionSelected || this.isPreviousTermBlank) {
            return 'Retrieving Fundamental Divisions, you can add more division into it.';
        }
        return 'Fundamental Divisions';
    }


    /**
     * @description Loads division groups from Apex controller
     */
    loadDivisionGroups() {
        getDivisionGroups()
            .then(result => {
                this.divisionGroupOptions = (result || []).map(option => ({
                    label: option.label,
                    value: option.value
                }));
            })
            .catch(err => {
                const errorMessage = err.body?.message || err.message || 'Unknown error';
                this.showToast('Error', `Unable to load division groups: ${errorMessage}`, 'error');
                this.divisionGroupOptions = [];
            });
    }

    /**
     * Loads active picklist values for Division__c.Division_Color__c
     */
    loadDivisionColorOptions() {
        getDivisionColorPicklistOptions()
            .then(result => {
                this.divisionColorOptions = (result || []).map(option => ({
                    label: option.label,
                    value: option.value
                }));
            })
            .catch(err => {
                const errorMessage = err.body?.message || err.message || 'Unknown error';
                this.showToast('Error', `Unable to load division colors: ${errorMessage}`, 'error');
                this.divisionColorOptions = [];
            });
    }

    /**
     * @description Loads fundamental divisions from Apex controller
     */
    loadFundamentalDivisions() {
        const termId = this.currentRecordId;
        if (!termId) {
            return;
        }
        
        // Load division groups if not already loaded
        if (this.divisionGroupOptions.length === 0) {
            this.loadDivisionGroups();
        }
        if (this.divisionColorOptions.length === 0) {
            this.loadDivisionColorOptions();
        }

        getFundamentalDivisions({ termId: termId })
            .then(result => {
                // Mark existing divisions as not new and add uniqueKey and divisionKey
                this.fundamentalDivisions = (result || []).map(div => ({
                    ...div,
                    divisionColor:
                        div.divisionColor != null && String(div.divisionColor).trim() !== ''
                            ? String(div.divisionColor).trim()
                            : '',
                    isNew: false,
                    uniqueKey: div.divisionId,
                    showSpecialisation:div.divisionGroup && div.divisionGroup.includes('Specialisation'),  // Use divisionId as unique key for existing divisions
                    divisionKey: div.divisionId // Use divisionId for data attributes
                }));
            })
            .catch(err => {
                const errorMessage = err.body?.message || err.message || 'Unknown error';
                this.showToast('Error', `Unable to load divisions: ${errorMessage}`, 'error');
                this.fundamentalDivisions = [];
            });
    }
     /**
 * @description Filters Specialisation records to show only
 * active Specialisations related to the selected Batch
 */
    get specialisationFilter() {

    return {
        criteria: [
            {
                fieldPath: 'Is_Active__c',
                operator: 'eq',
                value: true
            },
            {
                fieldPath: 'Batch__c',
                operator: 'eq',
                value: this.batchId
            }
        ]
    };
}

    /**
     * @description Handles division field changes
     * @param {Event} event - The input change event
     */
    handleDivisionFieldChange(event) {
        const divisionId = event.currentTarget.dataset.divisionId;
        const fieldName = event.currentTarget.dataset.fieldName;
        let value;
      if (fieldName === 'specialisationId') {
       value = event.detail ? event.detail.recordId : null;
      }
       else if (fieldName === 'divisionColor') {
            value = event.detail ? event.detail.value : '';
        } else if (event.target.type === 'checkbox') {
            value = event.target.checked;
        } else if (event.target.type === 'number') {
            value = parseFloat(event.target.value) || 0;
        } else {
            value = event.target.value;
        }
        
        // Update the division in the array
        this.fundamentalDivisions = this.fundamentalDivisions.map(div => {
            if (div.divisionKey === divisionId) {
                const updatedDiv = { ...div, [fieldName]: value };
                
                // If Division Group changed, update both ID and Name
                if (fieldName === 'divisionGroupId') {
                    const selectedOption = this.divisionGroupOptions.find(opt => opt.value === value);
                    if (selectedOption) {
                        updatedDiv.divisionGroup = selectedOption.label;
                        updatedDiv.showSpecialisation = selectedOption.label && selectedOption.label.includes('Specialisation');
                    }
                }
                
                return updatedDiv;
            }
            return div;
        });
    }

    /**
     * @description Adds a new empty division row to the table
     */
    addNewDivision() {
        // Load division groups if not already loaded
        if (this.divisionGroupOptions.length === 0) {
            this.loadDivisionGroups();
        }
        if (this.divisionColorOptions.length === 0) {
            this.loadDivisionColorOptions();
        }

        // Get Division Group ID from existing divisions if available, or use first option
        const existingDivision = this.fundamentalDivisions.find(div => div.divisionGroupId);
        let divisionGroupId = existingDivision ? existingDivision.divisionGroupId : null;
        let divisionGroupName = existingDivision ? existingDivision.divisionGroup : '';
        
        // If no existing division group, use first option from the list (usually "Fundamental")
        if (!divisionGroupId && this.divisionGroupOptions.length > 0) {
            divisionGroupId = this.divisionGroupOptions[0].value;
            divisionGroupName = this.divisionGroupOptions[0].label;
        }
        
        // Create a new division object with a temporary ID
        const tempId = 'temp_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
        const newDivision = {
            tempId: tempId,
            divisionId: null, // null indicates it's a new division
            uniqueKey: tempId, // For template key
            divisionKey: tempId, // For data attributes
            divisionGroup: divisionGroupName,
            divisionGroupId: divisionGroupId,
            isActive: true,
            capacity: 0,
            divisionCode: '',
            divisionColor: '',
            isNew: true ,
            showSpecialisation: divisionGroupName && divisionGroupName.includes('Specialisation')// Flag to identify new divisions
        };
        
        // Add to the array
        this.fundamentalDivisions = [...this.fundamentalDivisions, newDivision];
    }
     /**
 * @description Loads active Batch Specialisations related to the selected Batch
 * and maps them as dropdown options for the Specialisation field
 */
    loadBatchSpecialisations() {

    if (!this.batchId) {
        return;
    }

    getBatchSpecialisations({
        batchId: this.batchId
    })
    .then(result => {

        this.specialisationOptions =
            (result || []).map(item => ({
                label: item.label,
                value: item.value
            }));
    })
    .catch(error => {
        console.error(error);
    });
}

    /**
     * @description Removes a division row (only for new divisions that haven't been saved)
     * @param {Event} event - The button click event
     */
    removeDivision(event) {
        const divisionId = event.currentTarget.dataset.divisionId;
        
        // Only allow removal of new divisions (those with tempId)
        this.fundamentalDivisions = this.fundamentalDivisions.filter(div => {
            return div.tempId !== divisionId && div.divisionId !== divisionId;
        });
    }

    /**
     * @description Getter to check if a division is new (not yet saved)
     * @param {Object} division - The division object
     * @returns {Boolean} True if division is new
     */
    isNewDivision(division) {
        return division.isNew || division.divisionId === null || division.tempId;
    }


    /**
     * @description Loads student data from Apex controller
     * Handles both scenarios: Previous Term blank vs NOT blank
     */
    loadData() {
        const termId = this.currentRecordId;
        
        if (!termId) {
            this.isLoading = false;
            return;
        }
        
        this.isLoading = true;
        getStudentsForTerm({ termId: termId })
            .then(result => {
                this.isPreviousTermBlank = result.isPreviousTermBlank || false;
                this.previousTermId = result.previousTermId;
                this.batchId = result.batchId;
                this.loadBatchSpecialisations();
                this.autoCreateFundamentalDivision = result.autoCreateFundamentalDivision || false;
                this.batchStudentCount = result.batchStudentCount || 0;
                this.termEndDate = result.termEndDate;

if (this.termEndDate) {

    const today = new Date();
    today.setHours(0,0,0,0);

    const endDate = new Date(this.termEndDate);

    this.isTermExpired = endDate < today;
}
                // Map students with row numbers for display
                // If autoCreateFundamentalDivision is checked, ensure all students are selected
                // Create a unique key for each student (use academicTermEnrollmentId if available, otherwise enrollmentId)
                this.allStudents = (result?.students && Array.isArray(result.students))
                    ? result.students.map((s, i) => ({
                        ...s,
                        rowNumber: i + 1,
                        selected: this.autoCreateFundamentalDivision ? true : (s.selected !== undefined ? s.selected : true),
                        uniqueKey: s.academicTermEnrollmentId || s.enrollmentId || `student_${i}`
                    }))
                    : [];
                
                // Initialize filtered students with all students
                this.filteredStudents = [...this.allStudents];
                this.isLoading = false;
                
                // Load fundamental divisions if conditions are met
                // 1. Auto Create Fundamental Division is checked
                // 2. OR (previous term blank or new division selected) and students are selected
                const isNewDivisionSelected = this.divisionCreationOption === 'newDivision';
                const hasSelectedStudents = this.allStudents && this.allStudents.some(s => s.selected);
                const shouldLoadDivisionsForManual = (isNewDivisionSelected || this.isPreviousTermBlank) && hasSelectedStudents;
                const shouldLoadDivisionsForAuto = this.autoCreateFundamentalDivision && hasSelectedStudents;
                
                if ((shouldLoadDivisionsForAuto || shouldLoadDivisionsForManual) && (!this.fundamentalDivisions || this.fundamentalDivisions.length === 0)) {
                    this.loadFundamentalDivisions();
                }
            })
            .catch(err => {
                const errorMessage = err.body?.message || err.message || 'Unknown error';
                this.showToast('Error', `Unable to load students: ${errorMessage}`, 'error');
                this.isLoading = false;
            });
    }

    /**
     * @description Getter to check if there are any students
     * @returns {Boolean} True if students exist
     */
    get hasStudents() {
        return this.allStudents?.length > 0;
    }

    /**
     * @description Getter to check if we should show "no students" message
     * Shows message when not loading and no students are available
     * @returns {Boolean} True if should show no students message
     */
    get showNoStudentsMessage() {
        return !this.isLoading && (!this.allStudents || this.allStudents.length === 0);
    }
// ✅ NEW GETTER (IMPORTANT)
   get isNoBatchStudents() {
    return !this.isLoading && this.batchStudentCount === 0;
   }
    /**
     * @description Getter to check if there are filtered students
     * @returns {Boolean} True if filtered students exist
     */
    get hasFilteredStudents() {
        return this.filteredStudents?.length > 0;
    }

    /**
     * @description Getter to check if any students are selected
     * @returns {Boolean} True if at least one student is selected
     */
    get hasSelectedStudents() {
        return this.allStudents.some(s => s.selected);
    }

    /**
     * @description Getter for selected students count
     * @returns {Number} Count of selected students
     */
    get selectedCount() {
        return this.allStudents.filter(s => s.selected).length;
    }

    /**
     * @description Getter to determine if save button should be disabled
     * Always enabled - shows "Nothing to Save" message if nothing selected
     * @returns {Boolean} Always returns false (button always enabled)
     */
    get isSaveDisabled() {
        return false;
    }

    /**
     * @description Handles search input change event
     * @param {Event} event - The input change event
     */
    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.applySearchFilter();
    }

    /**
     * @description Applies search filter to student list
     * Filters by student name or roll number (case-insensitive)
     */
    applySearchFilter() {
        const searchTerm = this.searchKey?.trim();
        
        if (!searchTerm) {
            // No search term - show all students
            this.filteredStudents = [...this.allStudents];
        } else {
            // Filter students by name or roll number
            const searchLower = searchTerm.toLowerCase();
            this.filteredStudents = this.allStudents
                .filter(student => {
                    const nameMatch = student.studentName?.toLowerCase().includes(searchLower);
                    const rollMatch = student.rollNumber?.toLowerCase().includes(searchLower);
                    return nameMatch || rollMatch;
                })
                .map((student, index) => ({
                    ...student,
                    rowNumber: index + 1 // Recalculate row numbers for filtered results
                }));
        }
    }

    /**
     * @description Handles checkbox selection change
     * Updates both allStudents and filteredStudents to keep them in sync
     * @param {Event} event - The checkbox change event
     */
    handleSelectChange(event) {
        const uniqueKey = event.currentTarget.dataset.uniqueKey;
        const isSelected = event.target.checked;
        
        // Update student selection in both arrays using unique key
        const updateStudent = (student) => {
            return student.uniqueKey === uniqueKey
                ? { ...student, selected: isSelected }
                : student;
        };
        
        this.allStudents = this.allStudents.map(updateStudent);
        this.filteredStudents = this.filteredStudents.map(updateStudent);
        
        // Load fundamental divisions when students are selected and conditions are met
        if (this.shouldShowFundamentalDivisions && this.fundamentalDivisions.length === 0) {
            this.loadFundamentalDivisions();
        }
    }

    /**
     * @description Saves selected students by creating AcademicTermEnrollment records
     * Validates selection and shows appropriate messages
     */
    saveSelected() {
        const selectedStudents = this.allStudents.filter(s => s.selected);
        
        // Validation: Check if nothing to save
        if (selectedStudents.length === 0) {
            this.showToast('Info', 'Nothing to Save', 'info');
            return;
        }

        const termId = this.currentRecordId;
        if (!termId) {
            this.showToast('Error', 'Term ID is missing', 'error');
            return;
        }

        // Extract IDs based on scenario - only one type will be used at a time
        const enrollmentIds = this.isPreviousTermBlank
            ? selectedStudents
                .filter(s => s.enrollmentId != null)
                .map(s => s.enrollmentId)
            : selectedStudents
                .filter(s => s.academicTermEnrollmentId != null)
                .map(s => s.academicTermEnrollmentId);
        
        if (enrollmentIds.length === 0) {
            const errorMsg = this.isPreviousTermBlank 
                ? 'No valid Program Cohort Members to save'
                : 'No valid AcademicTermEnrollments to save';
            this.showToast('Error', errorMsg, 'error');
            return;
        }

        // Validation: Check if division is required (when "create new division" is selected OR previous term is blank)
        // Skip validation if autoCreateFundamentalDivision is checked (divisions will be auto-created or use existing)
        const requiresDivision =
    this.divisionCreationOption === 'newDivision' &&
    !this.autoCreateFundamentalDivision;        
        if (requiresDivision) {

            // When autoCreateFundamentalDivision is checked, validate that fundamental divisions exist
            if (this.autoCreateFundamentalDivision) {
                if (!this.fundamentalDivisions || this.fundamentalDivisions.length === 0) {
                    this.showToast('Error', 'At least one fundamental division is required. Please add a fundamental division before saving.', 'error');
                    return;
                }
                
                // Check if at least one fundamental division is active
                const activeFundamentalDivisions = this.fundamentalDivisions.filter(div => div.isActive === true);
                if (activeFundamentalDivisions.length === 0) {
                    this.showToast('Error', 'At least one active fundamental division is required. Please activate at least one fundamental division before saving.', 'error');
                    return;
                }
            }

            // Check if there are any fundamental divisions
            if (!this.fundamentalDivisions || this.fundamentalDivisions.length === 0) {
                this.showToast('Error', 'At least one division is required. Please add a division before saving.', 'error');
                return;
            }
            
            // Filter out divisions without divisionGroupId to get valid divisions
            const validDivisions = this.fundamentalDivisions.filter(div => div.divisionGroupId != null && div.divisionGroupId !== '');
            
            if (validDivisions.length === 0) {
                this.showToast('Error', 'At least one valid division with Division Group is required. Please add a division with Division Group selected.', 'error');
                return;
            }
            
            // Check if at least one division is active
            const activeDivisions = validDivisions.filter(div => div.isActive === true);
            if (activeDivisions.length === 0) {
                this.showToast('Error', 'At least one active division is required. Please activate at least one division before saving.', 'error');
                return;
            }

            const missingDivisionColor = validDivisions.some(
                div => div.divisionColor == null || String(div.divisionColor).trim() === ''
            );
            if (missingDivisionColor) {
                this.showToast('Error', 'Division Color is required for each division. Please select a color.', 'error');
                return;
            }
        }

        // Prepare divisions data if "Create new division" is selected OR previous term is blank
        // Do not save divisions when autoCreateFundamentalDivision is checked (we use existing divisions)
        let divisionsToSave = null;
        if (requiresDivision && this.fundamentalDivisions && this.fundamentalDivisions.length > 0) {
            // Filter out divisions without divisionGroupId, then map to the format expected by Apex
            divisionsToSave = this.fundamentalDivisions
                .filter(div => div.divisionGroupId != null && div.divisionGroupId !== '')
                .map(div => ({
                    divisionId: div.divisionId || null,
                    divisionGroupId: div.divisionGroupId,
                    specialisationId: div.specialisationId || null,
                    isActive: div.isActive !== undefined ? div.isActive : true,
                    capacity: div.capacity !== undefined ? div.capacity : 0,
                    divisionCode: div.divisionCode || null,
                    divisionColor: div.divisionColor != null && String(div.divisionColor).trim() !== ''
                        ? String(div.divisionColor).trim()
                        : null
                }));
            
            // This should not happen due to validation above, but keeping as safety check
            if (divisionsToSave.length === 0) {
                this.showToast('Error', 'At least one valid division is required. Please add a division with Division Group selected.', 'error');
                return;
            }
        }

        // Call Apex to create AcademicTermEnrollment records
        this.isLoading = true;
        createTermEnrollments({ 
            termId: termId, 
            enrollmentIds: enrollmentIds,
            batchId: this.batchId,
            isPreviousTermBlank: this.isPreviousTermBlank,
            divisionCreationOption: this.divisionCreationOption,
            divisions: divisionsToSave,
            autoCreateFundamentalDivision: this.autoCreateFundamentalDivision
        })
        .then((insertedCount) => {
            const count = insertedCount || 0;
        
            this.showToast(
                'Success',
                `${count} student(s) enrolled successfully`,
                'success'
            );
        
            // Close Quick Action modal
            this.dispatchEvent(new CloseActionScreenEvent());
        
            // Hard refresh record page (only reliable way in Screen Action)
            setTimeout(() => {
                window.location.href = '/' + this.currentRecordId;
            }, 500);
        })
        .catch(err => {
            const errorMessage = err.body?.message || err.message || 'Unknown error';
            this.showToast('Error', `Unable to save enrollments: ${errorMessage}`, 'error');
            this.isLoading = false;
        });
    }

    /**
     * @description Helper method to show toast notifications
     * @param {String} title - Toast title
     * @param {String} message - Toast message
     * @param {String} variant - Toast variant (success, error, warning, info)
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * @description Closes the modal by dispatching CloseActionScreenEvent
     */
    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}