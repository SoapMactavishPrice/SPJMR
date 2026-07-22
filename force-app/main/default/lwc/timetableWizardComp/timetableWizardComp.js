import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPrograms from '@salesforce/apex/TimetableWizardController.getPrograms';
import getTermsForPrograms from '@salesforce/apex/TimetableWizardController.getTermsForPrograms';
import getDivisionsForTerms from '@salesforce/apex/TimetableWizardController.getDivisionsForTerms';
import createTimetable from '@salesforce/apex/TimetableWizardController.createTimetable';

export default class TimetableWizardComp extends LightningElement {

    @track timetableType;
    @track programOptions = [];
    @track divisionOptions = [];
    @track termOptions = [];
    
    // Dedicated timetable selections
    @track selectedProgram;
    @track selectedDivision;
    @track selectedTerm;
    
    // Common timetable selections
    @track selectedPrograms = [];
    @track selectedDivisions = [];
    @track selectedTerms = [];
    
    // Form fields
    @track description = '';
    @track startDate = '';
    @track endDate = '';

    get timetableTypeOptions() {
        return [
            { label: 'Dedicated Timetable', value: 'Dedicated' },
            { label: 'Common Timetable', value: 'Common' },
        ];
    }

    get isDedicated() {
        return this.timetableType === 'Dedicated';
    }

    get isCommon() {
        return this.timetableType === 'Common';
    }

    get isProgramNotSelected() {
        return !this.selectedProgram;
    }

    get isTermNotSelected() {
        return !this.selectedTerm;
    }

    get programOptionsLength() {
        return this.programOptions.length;
    }

    get divisionOptionsLength() {
        return this.divisionOptions.length;
    }

    get termOptionsLength() {
        return this.termOptions.length;
    }

    get showDetailsSection() {
        if (this.isDedicated) {
            return this.selectedProgram && this.selectedTerm && this.selectedDivision;
        } else if (this.isCommon) {
            return this.selectedPrograms && this.selectedPrograms.length > 0 &&
                   this.selectedTerms && this.selectedTerms.length > 0 &&
                   this.selectedDivisions && this.selectedDivisions.length > 0;
        }
        return false;
    }

    get isCreateDisabled() {
        return !this.startDate || !this.endDate;
    }

    connectedCallback() {
        this.loadPrograms();
    }

    loadPrograms() {
        getPrograms()
            .then(result => {
                this.programOptions = result.map(option => ({
                    label: option.label,
                    value: option.value
                }));
            })
            .catch(error => {
                console.error('Error loading programs:', error);
            });
    }

    handleTimetableTypeChange(event) {
        this.timetableType = event.detail.value;
        
        // Reset selections when type changes
        this.selectedProgram = null;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.selectedPrograms = [];
        this.selectedTerms = [];
        this.selectedDivisions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        this.description = '';
        this.startDate = '';
        this.endDate = '';
    }

    // Dedicated timetable handlers
    handleProgramChange(event) {
        this.selectedProgram = event.detail.value;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.termOptions = [];
        this.divisionOptions = [];
        
        if (this.selectedProgram) {
            // Use the same method as Common timeline, passing single program as array
            getTermsForPrograms({ programIds: [this.selectedProgram] })
                .then(result => {
                    this.termOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                })
                .catch(error => {
                    console.error('Error loading terms:', error);
                });
        }
    }

    handleTermChange(event) {
        this.selectedTerm = event.detail.value;
        this.selectedDivision = null;
        this.divisionOptions = [];
        
        if (this.selectedTerm) {
            // Use the same method as Common timeline, passing single term as array
            getDivisionsForTerms({ termIds: [this.selectedTerm] })
                .then(result => {
                    this.divisionOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                })
                .catch(error => {
                    console.error('Error loading divisions:', error);
                });
        }
    }

    handleDivisionChange(event) {
        this.selectedDivision = event.detail.value;
    }

    // Common timetable handlers
    handleProgramsChange(event) {
        this.selectedPrograms = event.detail.value;
        
        // Reset terms and divisions when programs change
        this.selectedTerms = [];
        this.selectedDivisions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        
        // Filter terms based on selected programs
        if (this.selectedPrograms && this.selectedPrograms.length > 0) {
            getTermsForPrograms({ programIds: this.selectedPrograms })
                .then(result => {
                    this.termOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                })
                .catch(error => {
                    console.error('Error loading terms for programs:', error);
                });
        }
    }

    handleDivisionsChange(event) {
        this.selectedDivisions = event.detail.value;
    }

    handleTermsChange(event) {
        this.selectedTerms = event.detail.value;
        
        // Reset divisions when terms change
        this.selectedDivisions = [];
        this.divisionOptions = [];
        
        // Filter divisions based on selected terms
        if (this.selectedTerms && this.selectedTerms.length > 0) {
            getDivisionsForTerms({ termIds: this.selectedTerms })
                .then(result => {
                    this.divisionOptions = result.map(option => ({
                        label: option.label,
                        value: option.value
                    }));
                })
                .catch(error => {
                    console.error('Error loading divisions for terms:', error);
                });
        }
    }

    // Form field handlers
    handleDescriptionChange(event) {
        this.description = event.detail.value;
    }

    handleStartDateChange(event) {
        this.startDate = event.detail.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.detail.value;
    }

    // Create Timetable
    handleCreateTimetable() {
        // Validate form
        if (!this.startDate || !this.endDate) {
            this.showToast('Error', 'Please fill in all required fields (Start Date and End Date)', 'error');
            return;
        }

        if (new Date(this.startDate) > new Date(this.endDate)) {
            this.showToast('Error', 'End Date must be after Start Date', 'error');
            return;
        }

        // Prepare data based on timetable type
        let timetableData = {
            description: this.description || '',
            startDate: this.startDate,
            endDate: this.endDate,
            timetableType: this.timetableType
        };

        if (this.isDedicated) {
            timetableData.programId = this.selectedProgram;
            timetableData.termId = this.selectedTerm;
            timetableData.divisionName = this.selectedDivision;
        } else if (this.isCommon) {
            timetableData.programIds = this.selectedPrograms;
            timetableData.termIds = this.selectedTerms;
            timetableData.divisionNames = this.selectedDivisions;
        }

        // Call Apex method
        createTimetable({ timetableData: JSON.stringify(timetableData) })
            .then(result => {
                this.showToast('Success', 'Timetable created successfully', 'success');
                // Reset form
                this.resetForm();
            })
            .catch(error => {
                console.error('Error creating timetable:', error);
                this.showToast('Error', error.body?.message || 'Error creating timetable', 'error');
            });
    }

    resetForm() {
        this.selectedProgram = null;
        this.selectedTerm = null;
        this.selectedDivision = null;
        this.selectedPrograms = [];
        this.selectedTerms = [];
        this.selectedDivisions = [];
        this.termOptions = [];
        this.divisionOptions = [];
        this.description = '';
        this.startDate = '';
        this.endDate = '';
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }
}