import { LightningElement, track, wire } from 'lwc';
import { createRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import LEARNING_OBJECT from '@salesforce/schema/Learning';
import LEARNING_NAME from '@salesforce/schema/Learning.Name';
import LEARNING_COURSE_OBJECT from '@salesforce/schema/LearningCourse';
import LEARNING_COURSE_NAME from '@salesforce/schema/LearningCourse.Name';
import LEARNING_COURSE_LEARNING_ID from '@salesforce/schema/LearningCourse.LearningId';
import LEARNING_COURSE_NUMBER from '@salesforce/schema/LearningCourse.CourseNumber';
import COURSE_DEPARTMENT from '@salesforce/schema/LearningCourse.Course_Department__c';
import LEARNING_COURSE_DESCRIPTION from '@salesforce/schema/LearningCourse.Description';
import LEARNING_ISACTIVE from '@salesforce/schema/Learning.IsActive';
import DEPARTMENT_OBJECT from '@salesforce/schema/Department_Master__c';
import searchDepartmentMasters from '@salesforce/apex/DepartmentMasterController.searchDepartmentMasters';

const SEARCH_DEBOUNCE_MS = 300;

export default class CreatelearningCourse extends LightningElement {
    @track name = '';
    @track courseNumber = '';
    @track courseGivenName = '';
    @track description = '';
    @track isSaving = false;
    @track errorMessage = '';

    // Department lookup state
    @track departmentSearchTerm = '';
    @track departmentOptions = [];
    @track selectedDepartmentId = '';
    @track selectedDepartmentLabel = '';
    @track showDepartmentDropdown = false;
    @track isLoadingDepartments = false;
    _searchTimeout = null;

    // Inline "New Department Master" overlay state
    @track showNewDeptOverlay = false;
    @track newDeptStep = 'recordType'; // 'recordType' | 'form'
    @track recordTypeOptions = [];
    @track selectedRecordTypeId = '';
    @track selectedRecordTypeLabel = '';
    @track newDeptName = '';
    @track newDeptCode = '';
    @track newDeptCurrency = 'INR';
    @track newDeptIsActive = true;
    @track newDeptError = '';
    @track isSavingDept = false;
    @track currencyOptions = [{ label: 'INR - Indian Rupee', value: 'INR' }];

    @wire(getObjectInfo, { objectApiName: DEPARTMENT_OBJECT })
    wiredDeptObjectInfo({ data }) {
        if (!data) return;
        const rtInfos = data.recordTypeInfos || {};
        const opts = [];
        Object.keys(rtInfos).forEach((rtId) => {
            const rt = rtInfos[rtId];
            if (rt.available && !rt.master) {
                opts.push({ label: rt.name, value: rt.recordTypeId });
            }
        });
        opts.sort((a, b) => a.label.localeCompare(b.label));
        this.recordTypeOptions = opts;
    }

    get hasSelectedDepartment() {
        return !!this.selectedDepartmentId;
    }

    get departmentDropdownTriggerClass() {
        const base = 'department-dropdown-trigger slds-dropdown-trigger slds-dropdown-trigger_click';
        return this.showDepartmentDropdown ? base + ' slds-is-open' : base;
    }

    get noDepartmentResults() {
        return this.departmentSearchTerm && this.departmentOptions.length === 0 && !this.isLoadingDepartments;
    }

    get newDeptOverlayTitle() {
        if (this.newDeptStep === 'recordType') return 'New Department Master';
        return `New Department Master: ${this.selectedRecordTypeLabel}`;
    }

    get isRecordTypeStep() {
        return this.newDeptStep === 'recordType';
    }

    get isFormStep() {
        return this.newDeptStep === 'form';
    }

    get nextDisabled() {
        return !this.selectedRecordTypeId || this.recordTypeOptions.length === 0;
    }

    get recordTypeOptionsWithChecked() {
        return this.recordTypeOptions.map((o) => ({
            ...o,
            checked: o.value === this.selectedRecordTypeId
        }));
    }

    handleNameChange(event) {
        this.name = event.target.value;
        this.clearError();
    }

    handleCourseNumberChange(event) {
        this.courseNumber = event.target.value;
        this.clearError();
    }

    handleCourseGivenNameChange(event) {
        this.courseGivenName = event.target.value;
        this.clearError();
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.clearError();
    }

    // ---------- Department lookup ----------

    handleDepartmentSearchInput(event) {
        const term = (event.target.value || '').trim();
        this.departmentSearchTerm = term;
        this.selectedDepartmentId = '';
        this.selectedDepartmentLabel = '';
        clearTimeout(this._searchTimeout);
        this.showDepartmentDropdown = true;
        if (term.length === 0) {

            this.showDepartmentDropdown = true;
        
            this.runDepartmentSearch('%');
        
            return;
        }
        this._searchTimeout = setTimeout(() => {
            this.runDepartmentSearch(term);
        }, SEARCH_DEBOUNCE_MS);
    }

    runDepartmentSearch(term) {
        this.isLoadingDepartments = true;
        searchDepartmentMasters({ searchTerm: term || '%' })
            .then((options) => {
                this.departmentOptions = options || [];
            })
            .catch((err) => {
                this.departmentOptions = [];
                this.showToast('Error', (err.body && err.body.message) || err.message || 'Search failed', 'error');
            })
            .finally(() => {
                this.isLoadingDepartments = false;
            });
    }

    handleDepartmentFocus() {

        this.showDepartmentDropdown = true;
    
        if (this.departmentOptions.length === 0) {
    
            this.runDepartmentSearch(
                this.departmentSearchTerm || '%'
            );
        }
    }
    handleDepartmentBlur() {
        // Delay so mousedown on dropdown can fire first
        setTimeout(() => {
            this.showDepartmentDropdown = false;
        }, 250);
    }

    handleDepartmentSelect(event) {
        event.preventDefault();
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;
        this.selectedDepartmentId = id;
        this.selectedDepartmentLabel = label;
        this.departmentSearchTerm = label;
        this.showDepartmentDropdown = false;
        this.departmentOptions = [];
    }

    handleClearDepartment() {
        this.selectedDepartmentId = '';
        this.selectedDepartmentLabel = '';
        this.departmentSearchTerm = '';
        this.departmentOptions = [];
        this.showDepartmentDropdown = false;
    }

    // ---------- New Department Master overlay ----------

    handleNewDepartmentClick(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showDepartmentDropdown = false;
        this.openNewDeptOverlay();
    }

    openNewDeptOverlay() {
        this.newDeptStep = 'recordType';
        this.selectedRecordTypeId = this.recordTypeOptions.length > 0 ? this.recordTypeOptions[0].value : '';
        this.selectedRecordTypeLabel = this.recordTypeOptions.length > 0 ? this.recordTypeOptions[0].label : '';
        this.newDeptName = '';
        this.newDeptCode = '';
        this.newDeptCurrency = 'INR';
        this.newDeptIsActive = true;
        this.newDeptError = '';
        this.showNewDeptOverlay = true;
    }

    handleRecordTypeChange(event) {
        const id = event.target.value;
        this.selectedRecordTypeId = id;
        const match = this.recordTypeOptions.find((o) => o.value === id);
        this.selectedRecordTypeLabel = match ? match.label : '';
    }

    handleOverlayNext() {
        if (!this.selectedRecordTypeId) return;
        this.newDeptStep = 'form';
    }

    handleOverlayCancel() {
        this.showNewDeptOverlay = false;
        this.newDeptError = '';
    }

    handleNewDeptNameChange(event) {
        this.newDeptName = event.target.value;
        this.newDeptError = '';
    }

    handleNewDeptCodeChange(event) {
        this.newDeptCode = event.target.value;
        this.newDeptError = '';
    }

    handleNewDeptCurrencyChange(event) {
        this.newDeptCurrency = event.detail.value;
    }

    handleNewDeptIsActiveChange(event) {
        this.newDeptIsActive = event.target.checked;
    }

    async handleNewDeptSave() {
        const nameVal = (this.newDeptName || '').trim();
        const codeVal = (this.newDeptCode || '').trim();
        if (!nameVal) {
            this.newDeptError = 'Department Name is required.';
            return;
        }
        if (!codeVal) {
            this.newDeptError = 'Department Code is required.';
            return;
        }
        this.isSavingDept = true;
        this.newDeptError = '';
        try {
            const fields = {
                Name: nameVal,
                Department_Code__c: codeVal,
                isActive__c: this.newDeptIsActive,
                RecordTypeId: this.selectedRecordTypeId
            };
            if (this.newDeptCurrency) {
                fields.CurrencyIsoCode = this.newDeptCurrency;
            }
            const created = await createRecord({
                apiName: DEPARTMENT_OBJECT.objectApiName,
                fields
            });
            // Auto-populate the lookup with the newly created record
            this.selectedDepartmentId = created.id;
            this.selectedDepartmentLabel = nameVal;
            this.departmentSearchTerm = nameVal;
            this.showNewDeptOverlay = false;
            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Department Master created.',
                variant: 'success'
            }));
        } catch (err) {
            this.newDeptError = this.extractError(err);
        } finally {
            this.isSavingDept = false;
        }
    }

    extractError(error) {
        if (error?.body?.output?.fieldErrors) {
            const fe = error.body.output.fieldErrors;
            for (const f in fe) {
                if (fe[f].length > 0) return fe[f][0].message;
            }
        }
        if (error?.body?.output?.errors && error.body.output.errors.length > 0) {
            return error.body.output.errors[0].message;
        }
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Unknown error';
    }

    // ---------- Course save ----------

    isValidId(value) {
        if (!value || typeof value !== 'string') return false;
        const trimmed = value.trim();
        return /^[a-zA-Z0-9]{15}$/.test(trimmed) || /^[a-zA-Z0-9]{18}$/.test(trimmed);
    }

    clearError() {
        this.errorMessage = '';
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('cancel', {
                bubbles: true,
                composed: true
            })
        );
        window.history.back();
    }

    async handleSave() {
        try {
            const nameVal = (this.name || '').trim();
            const courseNumberVal = (this.courseNumber || '').trim();


// =========================
// FIELD VALIDATIONS
// =========================

const errors = [];

// Individual validations
if (!nameVal) {
    errors.push('Name is required.');
}

if (!courseNumberVal) {
    errors.push('Course Code is required.');
}

if (!this.selectedDepartmentId) {
    errors.push('Course Department is required.');
}

// =====================================
// COMBINED MESSAGE CONDITIONS
// =====================================

// All blank
const allBlank =
    !nameVal &&
    !courseNumberVal &&
    !this.selectedDepartmentId;

// Only Name filled
const onlyNameFilled =
    nameVal &&
    !courseNumberVal &&
    !this.selectedDepartmentId;

// Only Course Code filled
const onlyCourseCodeFilled =
    !nameVal &&
    courseNumberVal &&
    !this.selectedDepartmentId;

// Only Department filled
const onlyDepartmentFilled =
    !nameVal &&
    !courseNumberVal &&
    this.selectedDepartmentId;

// =====================================
// SHOW COMMON MESSAGE
// =====================================

if (
    allBlank ||
    onlyNameFilled ||
    onlyCourseCodeFilled ||
    onlyDepartmentFilled
) {

    this.errorMessage =
        'Please fill all required fields.';

    return;
}

// =====================================
// SHOW INDIVIDUAL FIELD MESSAGE
// =====================================

if (errors.length > 0) {

    this.errorMessage = errors[0];

    return;
}

           
            this.isSaving = true;
            this.errorMessage = '';

            // 1. Create Learning
            const learningFields = {};
            learningFields[LEARNING_NAME.fieldApiName] = nameVal;
            learningFields[LEARNING_ISACTIVE.fieldApiName] = true;

            const learningInput = {
                apiName: LEARNING_OBJECT.objectApiName,
                fields: learningFields
            };

            const learningRecord = await createRecord(learningInput);

            // 2. Create Learning Course
            const lcFields = {};
            lcFields[LEARNING_COURSE_LEARNING_ID.fieldApiName] = learningRecord.id;
            lcFields[LEARNING_COURSE_NAME.fieldApiName] = nameVal;

            if (this.courseNumber) {
                lcFields[LEARNING_COURSE_NUMBER.fieldApiName] = this.courseNumber;
            }

            if (this.courseGivenName && this.courseGivenName.trim() !== '') {
                lcFields['Course_Given_Name__c'] = this.courseGivenName.trim();
            } else {
                lcFields['Course_Given_Name__c'] = nameVal;
            }

            if (this.description) {
                lcFields[LEARNING_COURSE_DESCRIPTION.fieldApiName] = this.description;
            }

            if (this.selectedDepartmentId && this.isValidId(this.selectedDepartmentId)) {
                lcFields[COURSE_DEPARTMENT.fieldApiName] = this.selectedDepartmentId;
            }

            const lcInput = {
                apiName: LEARNING_COURSE_OBJECT.objectApiName,
                fields: lcFields
            };
            const learningCourseRecord = await createRecord(lcInput);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Learning and Learning Course created successfully.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('success', {
                    bubbles: true,
                    composed: true,
                    detail: { recordId: learningCourseRecord.id }
                })
            );

            window.history.back();
        } catch (error) {
            console.error('Full Error:', JSON.stringify(error, null, 2));
            this.errorMessage = this.extractError(error);
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}