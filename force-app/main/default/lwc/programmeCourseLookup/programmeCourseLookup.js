import { LightningElement, api, track, wire } from 'lwc';
import { getRecord, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import searchProgrammeCourses from '@salesforce/apex/LmsHostLinkAssignmentController.searchProgrammeCourses';
import PROGRAM_COURSE_OBJECT from '@salesforce/schema/Program_Courses__c';
import LMS_COURSE_FIELD from '@salesforce/schema/Program_Courses__c.LMS_Course__c';
import ID_FIELD from '@salesforce/schema/Program_Courses__c.Id';

const FIELDS = [LMS_COURSE_FIELD];

export default class ProgrammeCourseLookup extends LightningElement {
    @api recordId;
    @api label = 'LMS Course';
    @api placeholder = 'Search Programme Courses...';
    @api required = false;
    @api autoSave; // Auto-save to record when true
    
    @track searchTerm = '';
    @track searchResults = [];
    @track selectedRecord = null;
    @track isLoading = false;
    @track showDropdown = false;
    @track hasFocus = false;
    @track isSaving = false;
    
    _selectedId;
    wiredRecordResult;

    @api
    get selectedId() {
        return this._selectedId;
    }
    set selectedId(value) {
        this._selectedId = value;
        if (value && !this.selectedRecord) {
            this.loadSelectedRecord();
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord(result) {
        this.wiredRecordResult = result;
        if (result.data) {
            const currentValue = result.data.fields.LMS_Course__c?.value;
            if (currentValue && currentValue !== this._selectedId) {
                this._selectedId = currentValue;
                this.loadSelectedRecord();
            }
        } else if (result.error) {
            console.error('Error loading record:', result.error);
        }
    }

    connectedCallback() {
        // If recordId is not set, check for selectedId passed as API property
        if (!this.recordId && this._selectedId) {
            this.loadSelectedRecord();
        } else if (!this.recordId) {
            // Load all records on init
            this.performSearch();
        }
    }

    loadSelectedRecord() {
        this.isLoading = true;
        searchProgrammeCourses({ searchTerm: '', selectedIds: [this._selectedId] })
            .then(results => {
                if (results && results.length > 0) {
                    const selected = results.find(r => r.id === this._selectedId);
                    if (selected) {
                        this.selectedRecord = selected;
                    }
                }
                this.isLoading = false;
                this.performSearch();
            })
            .catch(error => {
                console.error('Error loading selected record:', error);
                this.isLoading = false;
                this.performSearch();
            });
    }

    performSearch() {
        this.isLoading = true;
        const term = this.searchTerm || '';
        searchProgrammeCourses({ searchTerm: term, selectedIds: [] })
            .then(results => {
                this.searchResults = results || [];
                this.isLoading = false;
                this.showDropdown = this.hasFocus && this.searchResults.length > 0;
            })
            .catch(error => {
                console.error('Error searching:', error);
                this.searchResults = [];
                this.isLoading = false;
                this.showDropdown = false;
            });
    }

    handleInputChange(event) {
        this.searchTerm = event.target.value;
        // Debounce search
        clearTimeout(this.searchTimeout);
        this.searchTimeout = setTimeout(() => {
            this.performSearch();
        }, 300);
    }

    handleInputFocus() {
        this.hasFocus = true;
        if (this.searchResults.length > 0) {
            this.showDropdown = true;
        } else {
            this.performSearch();
        }
    }

    handleInputBlur() {
        // Delay to allow click on dropdown items
        setTimeout(() => {
            this.hasFocus = false;
            this.showDropdown = false;
        }, 200);
    }

    handleResultClick(event) {
        const selectedId = event.currentTarget.dataset.id;
        const selected = this.searchResults.find(r => r.id === selectedId);
        
        if (selected) {
            this.selectedRecord = selected;
            this._selectedId = selected.id;
            this.searchTerm = '';
            this.showDropdown = false;
            
            // Dispatch event with selected value
            this.dispatchEvent(new CustomEvent('select', {
                detail: { 
                    value: selected.id,
                    record: selected
                }
            }));

            // Auto-save to record if enabled and recordId is present
            if (this.shouldAutoSave) {
                this.saveToRecord(selected.id);
            }
        }
    }

    handleClear() {
        this.selectedRecord = null;
        this._selectedId = null;
        this.searchTerm = '';
        this.searchResults = [];
        
        // Dispatch clear event
        this.dispatchEvent(new CustomEvent('select', {
            detail: { value: null }
        }));
        
        // Auto-save to record if enabled and recordId is present
        if (this.shouldAutoSave) {
            this.saveToRecord(null);
        }
        
        // Reload all results
        this.performSearch();
    }

    /**
     * Save the selected LMS Course to the Programme Course record
     */
    saveToRecord(lmsCourseId) {
        if (!this.recordId) {
            return;
        }

        this.isSaving = true;
        
        const fields = {};
        fields[ID_FIELD.fieldApiName] = this.recordId;
        fields[LMS_COURSE_FIELD.fieldApiName] = lmsCourseId;

        const recordInput = { fields };

        updateRecord(recordInput)
            .then(() => {
                this.isSaving = false;
                this.showToast('Success', 'LMS Course updated successfully', 'success');
                
                // Refresh the wired record
                return refreshApex(this.wiredRecordResult);
            })
            .catch(error => {
                this.isSaving = false;
                console.error('Error updating record:', error);
                const message = error.body?.message || error.message || 'Error updating LMS Course';
                this.showToast('Error', message, 'error');
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }

    get hasSelection() {
        return this.selectedRecord != null;
    }

    get inputValue() {
        return this.selectedRecord ? this.selectedRecord.title : this.searchTerm;
    }

    get dropdownClass() {
        return this.showDropdown ? 'slds-dropdown slds-dropdown_length-5 slds-dropdown_fluid' : 'slds-dropdown slds-dropdown_length-5 slds-dropdown_fluid slds-hide';
    }

    get dropdownContainerClass() {
        return 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click' + (this.showDropdown ? ' slds-is-open' : '');
    }

    get noResults() {
        return !this.isLoading && this.searchResults.length === 0 && this.hasFocus;
    }

    get isProcessing() {
        return this.isLoading || this.isSaving;
    }

    get inputDisabled() {
        return this.isSaving;
    }

    get shouldAutoSave() {
        // Default to true if not explicitly set to false
        return this.recordId && (this.autoSave !== false);
    }
}