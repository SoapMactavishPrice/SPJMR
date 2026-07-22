/**
 * @description LWC Component for enrolling students in Division
 * Displays Academic Term Enrollments in a modal with search and selection functionality
 * Shows only enrollments that are not already part of any Division Enrollment
 */
import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { CurrentPageReference } from 'lightning/navigation';
import getAvailableEnrollments from '@salesforce/apex/DivisionEnrollmentController.getAvailableEnrollments';
import createDivisionEnrollments from '@salesforce/apex/DivisionEnrollmentController.createDivisionEnrollments';

export default class DivisionEnrollmentModal extends LightningElement {
    @api recordId; // Division recordId from record page context
    
    // Enrollment data
    @track allEnrollments = []; // Store all enrollments for filtering
    @track filteredEnrollments = []; // Filtered enrollments based on search
    @track searchKey = '';
    @track isLoading = false;
    
    // Fallback recordId from page reference
    actualRecordId;

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

    /**
     * @description Loads enrollment data from Apex controller
     */
    loadData() {
        const divisionId = this.currentRecordId;
        if (!divisionId) {
            this.isLoading = false;
            return;
        }
        
        this.isLoading = true;
        getAvailableEnrollments({ divisionId: divisionId })
            .then(result => {
                // Map enrollments with row numbers for display
                this.allEnrollments = (result && Array.isArray(result))
                    ? result.map((e, i) => ({
                        ...e,
                        rowNumber: i + 1,
                        selected: e.selected !== undefined ? e.selected : false
                    }))
                    : [];
                
                // Initialize filtered enrollments with all enrollments
                this.filteredEnrollments = [...this.allEnrollments];
                this.isLoading = false;
            })
            .catch(err => {
                const errorMessage = err.body?.message || err.message || 'Unknown error';
                this.showToast('Error', `Unable to load enrollments: ${errorMessage}`, 'error');
                this.isLoading = false;
            });
    }

    /**
     * @description Getter to check if there are any enrollments
     * @returns {Boolean} True if enrollments exist
     */
    get hasEnrollments() {
        return this.allEnrollments?.length > 0;
    }

    /**
     * @description Getter to check if we should show "no enrollments" message
     * Shows message when not loading and no enrollments are available
     * @returns {Boolean} True if should show no enrollments message
     */
    get showNoEnrollmentsMessage() {
        return !this.isLoading && (!this.allEnrollments || this.allEnrollments.length === 0);
    }

    /**
     * @description Getter to check if there are filtered enrollments
     * @returns {Boolean} True if filtered enrollments exist
     */
    get hasFilteredEnrollments() {
        return this.filteredEnrollments?.length > 0;
    }

    /**
     * @description Getter to check if any enrollments are selected
     * @returns {Boolean} True if at least one enrollment is selected
     */
    get hasSelectedEnrollments() {
        return this.allEnrollments.some(e => e.selected);
    }

    /**
     * @description Getter for selected enrollments count
     * @returns {Number} Count of selected enrollments
     */
    get selectedCount() {
        return this.allEnrollments.filter(e => e.selected).length;
    }

    /**
     * @description Getter to determine if save button should be disabled
     * @returns {Boolean} True if no enrollments are selected
     */
    get isSaveDisabled() {
        return !this.hasSelectedEnrollments;
    }

    /**
    * @description Checks whether all filtered enrollments are selected
    * Used to control the state of the Select All checkbox.
    * @returns {Boolean} True if all filtered enrollments are selected
    */
    get isAllSelected() {
        return this.filteredEnrollments.length > 0 &&
        this.filteredEnrollments.every(e => e.selected);
    }

    /**
    * @description Handles Select All / Deselect All functionality
    * Updates the selected status of all currently filtered enrollments
    * and keeps allEnrollments and filteredEnrollments in sync.
    * @param {Event} event - Header checkbox change event
    */ 
    handleSelectAll(event) {
    const checked = event.target.checked;

    const filteredKeys = new Set(
        this.filteredEnrollments.map(e => e.uniqueKey)
    );

    this.allEnrollments = this.allEnrollments.map(e => {
        if (filteredKeys.has(e.uniqueKey)) {
            return { ...e, selected: checked };
        }
        return e;
    });

    this.filteredEnrollments = this.filteredEnrollments.map(e => ({
        ...e,
        selected: checked}));
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
     * @description Applies search filter to enrollment list
     * Filters by student name or roll number (case-insensitive)
     */
    applySearchFilter() {
        const searchTerm = this.searchKey?.trim();
        
        if (!searchTerm) {
            // No search term - show all enrollments
            this.filteredEnrollments = [...this.allEnrollments];
        } else {
            // Filter enrollments by name or roll number
            const searchLower = searchTerm.toLowerCase();
            this.filteredEnrollments = this.allEnrollments
                .filter(enrollment => {
                    const nameMatch = enrollment.studentName?.toLowerCase().includes(searchLower);
                    const rollMatch = enrollment.rollNumber?.toLowerCase().includes(searchLower);
                    return nameMatch || rollMatch;
                })
                .map((enrollment, index) => ({
                    ...enrollment,
                    rowNumber: index + 1 // Recalculate row numbers for filtered results
                }));
        }
    }

    /**
     * @description Handles checkbox selection change
     * Updates both allEnrollments and filteredEnrollments to keep them in sync
     * @param {Event} event - The checkbox change event
     */
    handleSelectChange(event) {
        const uniqueKey = event.currentTarget.dataset.uniqueKey;
        const isSelected = event.target.checked;
        
        // Update enrollment selection in both arrays using unique key
        const updateEnrollment = (enrollment) => {
            return enrollment.uniqueKey === uniqueKey
                ? { ...enrollment, selected: isSelected }
                : enrollment;
        };
        
        this.allEnrollments = this.allEnrollments.map(updateEnrollment);
        this.filteredEnrollments = this.filteredEnrollments.map(updateEnrollment);
    }

    /**
     * @description Saves selected enrollments by creating Division Enrollment records
     * Validates selection and shows appropriate messages
     */
    saveSelected() {
        const selectedEnrollments = this.allEnrollments.filter(e => e.selected);
        
        // Validation: Check if nothing to save
        if (selectedEnrollments.length === 0) {
            this.showToast('Info', 'Please select at least one enrollment to save', 'info');
            return;
        }

        const divisionId = this.currentRecordId;
        if (!divisionId) {
            this.showToast('Error', 'Division ID is missing', 'error');
            return;
        }

        // Extract enrollment IDs
        const enrollmentIds = selectedEnrollments
            .filter(e => e.enrollmentId != null)
            .map(e => e.enrollmentId);
        
        if (enrollmentIds.length === 0) {
            this.showToast('Error', 'No valid enrollments to save', 'error');
            return;
        }

        // Call Apex to create Division Enrollment records
        this.isLoading = true;
        createDivisionEnrollments({ 
            divisionId: divisionId, 
            enrollmentIds: enrollmentIds
        })
        .then((insertedCount) => {
            // Use actual inserted count from Apex
            const count = insertedCount || 0;
            this.showToast('Success', `${count} enrollment(s) saved successfully`, 'success');
            
            // Close modal first
            this.dispatchEvent(new CloseActionScreenEvent());
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