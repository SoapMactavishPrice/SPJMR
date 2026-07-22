import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPicklistValues from '@salesforce/apex/LeadIntakeController.getPicklistValues';
import submitLead from '@salesforce/apex/LeadIntakeController.submitLead';
import convertLead from '@salesforce/apex/LeadIntakeController.convertLead';

export default class LeadIntakeForm extends NavigationMixin(LightningElement) {
    activeTab = 'B2B';
    currentStep = 1; // 1=form, 2=processing, 3=result
    isSubmitting = false;
    isConverting = false;

    @track formData = {};
    @track result = {};

    // Picklist data
    picklistData = {};
    checkStates = [0, 0, 0, 0]; // 0=pending, 1=active, 2=done

    connectedCallback() {
        this.resetForm();
        this.loadPicklists();
    }

    async loadPicklists() {
        try {
            this.picklistData = await getPicklistValues();
        } catch (error) {
            this.showToast('Error', 'Failed to load picklist values', 'error');
        }
    }

    // --- Tab switching ---
    get isB2B() { return this.activeTab === 'B2B'; }
    get isB2C() { return this.activeTab === 'B2C'; }
    get activeTabLabel() { return this.activeTab; }

    get b2bTabClass() {
        return 'tab-btn' + (this.isB2B ? ' tab-active tab-b2b' : '');
    }
    get b2cTabClass() {
        return 'tab-btn' + (this.isB2C ? ' tab-active tab-b2c' : '');
    }

    switchToB2B() { this.activeTab = 'B2B'; this.resetForm(); }
    switchToB2C() { this.activeTab = 'B2C'; this.resetForm(); }

    // --- Step visibility ---
    get isFormStep() { return this.currentStep === 1; }
    get isProcessingStep() { return this.currentStep === 2; }
    get isResultStep() { return this.currentStep >= 3; }

    // --- Stepper classes ---
    get step1Active() { return this.currentStep === 1; }
    get step1Done() { return this.currentStep > 1; }
    get step2Active() { return this.currentStep === 2; }
    get step2Done() { return this.currentStep > 2; }
    get step3Active() { return this.currentStep === 3; }
    get step3Done() { return this.currentStep > 3; }
    get step4Active() { return this.currentStep === 4; }
    get step4Done() { return this.currentStep > 4; }

    get step1Class() { return 'step' + (this.step1Active ? ' step-active' : '') + (this.step1Done ? ' step-done' : ''); }
    get step2Class() { return 'step' + (this.step2Active ? ' step-active' : '') + (this.step2Done ? ' step-done' : ''); }
    get step3Class() { return 'step' + (this.step3Active ? ' step-active' : '') + (this.step3Done ? ' step-done' : ''); }
    get step4Class() { return 'step' + (this.step4Active ? ' step-active' : '') + (this.step4Done ? ' step-done' : ''); }

    get connector1Class() { return 'connector-line' + (this.currentStep > 1 ? ' connector-filled' : ''); }
    get connector2Class() { return 'connector-line' + (this.currentStep > 2 ? ' connector-filled' : ''); }
    get connector3Class() { return 'connector-line' + (this.currentStep > 3 ? ' connector-filled' : ''); }

    // --- Processing check states ---
    _checkClass(idx) {
        const s = this.checkStates[idx];
        if (s === 2) return 'check-item check-done';
        if (s === 1) return 'check-item check-active';
        return 'check-item';
    }
    _checkIcon(idx) {
        const s = this.checkStates[idx];
        if (s === 2) return 'utility:check';
        if (s === 1) return 'utility:spinner';
        return 'utility:clock';
    }

    get check1Class() { return this._checkClass(0); }
    get check2Class() { return this._checkClass(1); }
    get check3Class() { return this._checkClass(2); }
    get check4Class() { return this._checkClass(3); }
    get check1Icon() { return this._checkIcon(0); }
    get check2Icon() { return this._checkIcon(1); }
    get check3Icon() { return this._checkIcon(2); }
    get check4Icon() { return this._checkIcon(3); }

    // --- Result getters ---
    get isExistingMatch() {
        return this.result.action === 'OPP_CREATED_EXISTING' || this.result.action === 'OPP_CREATED_CONVERTED';
    }

    get resultBannerClass() {
        if (this.isExistingMatch) return 'result-banner banner-opp';
        return 'result-banner banner-lead';
    }

    get resultIcon() {
        return this.isExistingMatch ? 'standard:opportunity' : 'standard:lead';
    }

    get resultTitle() {
        if (this.result.action === 'OPP_CREATED_EXISTING') return 'Opportunity Created — Existing Record Found!';
        if (this.result.action === 'OPP_CREATED_CONVERTED') return 'Lead Converted to Opportunity!';
        return 'New Lead Created Successfully!';
    }

    // --- Picklist options ---
    _opts(key) {
        const vals = this.picklistData[key];
        if (!vals) return [];
        return vals.map(v => ({ label: v.label, value: v.value }));
    }
    get salutationOptions() { return this._opts('Salutation'); }
    get industryOptions() { return this._opts('Industry'); }
    get leadSourceOptions() { return this._opts('LeadSource'); }
    get ratingOptions() { return this._opts('Rating'); }
    get countryOptions() { return this._opts('Country__c'); }
    get programOptions() { return this._opts('Program_Picklist__c'); }
    get programTypeOptions() { return this._opts('Program_Type__c'); }
    get genderOptions() { return this._opts('GenderIdentity'); }

    // --- Form handlers ---
    handleFieldChange(event) {
        const field = event.target.dataset.field;
        this.formData = { ...this.formData, [field]: event.target.value };
    }

    handleCheckboxChange(event) {
        const field = event.target.dataset.field;
        this.formData = { ...this.formData, [field]: event.target.checked };
    }

    validateForm() {
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea');
        let valid = true;
        inputs.forEach(input => {
            if (!input.reportValidity()) {
                valid = false;
            }
        });

        if (this.isB2B && !this.formData.company) {
            this.showToast('Validation Error', 'Company Name is required for B2B leads', 'error');
            return false;
        }
        if (!this.formData.lastName) {
            this.showToast('Validation Error', 'Last Name is required', 'error');
            return false;
        }
        return valid;
    }

    async handleSubmit() {
        if (!this.validateForm()) return;

        this.isSubmitting = true;
        this.currentStep = 2;
        this.checkStates = [0, 0, 0, 0];

        await this.animateChecks();

        try {
            const input = {
                recordType: this.activeTab,
                salutation: this.formData.salutation || null,
                firstName: this.formData.firstName || null,
                lastName: this.formData.lastName,
                email: this.formData.email || null,
                phone: this.formData.phone || null,
                company: this.formData.company || null,
                title: this.formData.title || null,
                industry: this.formData.industry || null,
                numberOfEmployees: this.formData.numberOfEmployees ? parseInt(this.formData.numberOfEmployees, 10) : null,
                annualRevenue: this.formData.annualRevenue ? parseFloat(this.formData.annualRevenue) : null,
                website: this.formData.website || null,
                leadSource: this.formData.leadSource || null,
                street: this.formData.street || null,
                city: this.formData.city || null,
                state: this.formData.state || null,
                postalCode: this.formData.postalCode || null,
                country: this.formData.country || null,
                description: this.formData.description || null,
                rating: this.formData.rating || null,
                programInterest: this.formData.programInterest || null,
                programType: this.formData.programType || null,
                dateOfBirth: this.formData.dateOfBirth || null,
                gender: this.formData.gender || null,
                linkedin: this.formData.linkedin || null,
                panNumber: this.formData.panNumber || null,
                emailOptOut: this.formData.emailOptOut || false,
                revenueEstimate: this.formData.revenueEstimate ? parseFloat(this.formData.revenueEstimate) : null,
                department: this.formData.department || null
            };

            this.result = await submitLead({ input });
            this.checkStates = [2, 2, 2, 2];
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await this.delay(600);
            this.currentStep = 4;
            this.showToast('Success', this.result.message, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.currentStep = 1;
        } finally {
            this.isSubmitting = false;
        }
    }

    async animateChecks() {
        for (let i = 0; i < 4; i++) {
            this.checkStates = this.checkStates.map((s, idx) =>
                idx === i ? 1 : idx < i ? 2 : 0
            );
            this.checkStates = [...this.checkStates];
            await this.delay(500 + Math.random() * 400);
        }
    }

    async handleConvertLead() {
        this.isConverting = true;
        try {
            this.result = await convertLead({ leadId: this.result.leadId });
            this.showToast('Success', this.result.message, 'success');
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isConverting = false;
        }
    }

    navigateToRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    handleReset() {
        this.currentStep = 1;
        this.result = {};
        this.checkStates = [0, 0, 0, 0];
        this.resetForm();
    }

    resetForm() {
        this.formData = {
            salutation: '', firstName: '', lastName: '', email: '', phone: '',
            company: '', title: '', industry: '', numberOfEmployees: null,
            annualRevenue: null, website: '', leadSource: '', street: '',
            city: '', state: '', postalCode: '', country: '', description: '',
            rating: '', programInterest: '', programType: '', dateOfBirth: null,
            gender: '', linkedin: '', panNumber: '', emailOptOut: false,
            revenueEstimate: null, department: ''
        };
    }

    delay(ms) {
        return new Promise(resolve => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, ms);
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'An unexpected error occurred';
    }
}