import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import checkAccountAndContact from '@salesforce/apex/B2BLeadProcessController.checkAccountAndContact';
import createLead from '@salesforce/apex/B2BLeadProcessController.createLead';
import createContactAndOpportunity from '@salesforce/apex/B2BLeadProcessController.createContactAndOpportunity';
import createOpportunityOnly from '@salesforce/apex/B2BLeadProcessController.createOpportunityOnly';
import getOpportunityStages from '@salesforce/apex/B2BLeadProcessController.getOpportunityStages';
import getProgramName from '@salesforce/apex/B2BLeadProcessController.getProgramName';
import convertLeadToAccountContactOpportunity from '@salesforce/apex/B2BLeadProcessController.convertLeadToAccountContactOpportunity';
import getAccountContacts from '@salesforce/apex/B2BLeadProcessController.getAccountContacts';

export default class B2bLeadForm extends NavigationMixin(LightningElement) {
    // Step tracking
    @track currentStep = 'company-check';
    
    // Company check fields
    @track company = '';
    @track email = '';
    @track isChecking = false;
    
    // Check result
    @track checkResult = null;
    @track scenario = '';
    
    // Contact Information fields
    @track firstName = '';
    @track lastName = '';
    @track phone = '';
    @track title = '';
    @track department = '';
    @track mobilePhone = '';
    @track linkedIn = '';
    @track contactCountry = '';
    @track contactState = '';
    @track contactCity = '';
    @track reportsToId = null;
    @track accountContacts = [];
    
    // Company Information fields
    @track industry = '';
    @track website = '';
    @track numberOfEmployees = null;
    @track annualRevenue = null;
    @track street = '';
    @track city = '';
    @track state = '';
    @track postalCode = '';
    @track country = '';
    @track description = '';
    @track leadSource = '';
    @track isMouContractRequired = false;
    
    // Opportunity fields
    @track opportunityName = '';
    @track opportunityAmount = null;
    @track closeDate = '';
    @track stage = 'Prospecting';
    @track stageOptions = [];
    @track minNumberOfStudents = null;
    @track maxNumberOfStudents = null;
    
    // Program fields
    @track selectedProgramId = null;
    @track selectedProgramName = '';
    @track selectedPrograms = [];
    
    // Program picker configuration
    programDisplayInfo = {
        additionalFields: ['Programme_Type__c']
    };
    
    programMatchingInfo = {
        primaryField: { fieldPath: 'Name' },
        additionalFields: [{ fieldPath: 'Programme_Type__c' }]
    };
    
    // UI State
    @track isSaving = false;
    @track errorMessage = '';
    @track showConvertOption = false;
    @track createdLeadId = null;

    connectedCallback() {
        this.loadOpportunityStages();
        const today = new Date();
        today.setDate(today.getDate() + 30);
        this.closeDate = today.toISOString().split('T')[0];
    }

    async loadOpportunityStages() {
        try {
            const stages = await getOpportunityStages();
            this.stageOptions = stages.map(s => ({
                label: s.label,
                value: s.value
            }));
        } catch (error) {
            console.error('Error loading stages:', error);
            this.stageOptions = [
                { label: 'Prospecting', value: 'Prospecting' },
                { label: 'Qualification', value: 'Qualification' },
                { label: 'Needs Analysis', value: 'Needs Analysis' },
                { label: 'Proposal/Price Quote', value: 'Proposal/Price Quote' },
                { label: 'Negotiation/Review', value: 'Negotiation/Review' }
            ];
        }
    }

    // Industry options
    get industryOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Agriculture', value: 'Agriculture' },
            { label: 'Banking', value: 'Banking' },
            { label: 'Biotechnology', value: 'Biotechnology' },
            { label: 'Chemicals', value: 'Chemicals' },
            { label: 'Communications', value: 'Communications' },
            { label: 'Construction', value: 'Construction' },
            { label: 'Consulting', value: 'Consulting' },
            { label: 'Education', value: 'Education' },
            { label: 'Electronics', value: 'Electronics' },
            { label: 'Energy', value: 'Energy' },
            { label: 'Engineering', value: 'Engineering' },
            { label: 'Entertainment', value: 'Entertainment' },
            { label: 'Environmental', value: 'Environmental' },
            { label: 'Finance', value: 'Finance' },
            { label: 'Food & Beverage', value: 'Food & Beverage' },
            { label: 'Government', value: 'Government' },
            { label: 'Healthcare', value: 'Healthcare' },
            { label: 'Hospitality', value: 'Hospitality' },
            { label: 'Insurance', value: 'Insurance' },
            { label: 'Manufacturing', value: 'Manufacturing' },
            { label: 'Media', value: 'Media' },
            { label: 'Not For Profit', value: 'Not For Profit' },
            { label: 'Real Estate', value: 'Real Estate' },
            { label: 'Retail', value: 'Retail' },
            { label: 'Technology', value: 'Technology' },
            { label: 'Telecommunications', value: 'Telecommunications' },
            { label: 'Transportation', value: 'Transportation' },
            { label: 'Utilities', value: 'Utilities' },
            { label: 'Other', value: 'Other' }
        ];
    }

    // Lead Source options
    get leadSourceOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'Web', value: 'Web' },
            { label: 'Phone Inquiry', value: 'Phone Inquiry' },
            { label: 'Partner Referral', value: 'Partner Referral' },
            { label: 'Purchased List', value: 'Purchased List' },
            { label: 'Other', value: 'Other' }
        ];
    }

    // Country options
    get countryOptions() {
        return [
            { label: '--None--', value: '' },
            { label: 'India', value: 'India' },
            { label: 'United States', value: 'United States' },
            { label: 'United Kingdom', value: 'United Kingdom' },
            { label: 'Canada', value: 'Canada' },
            { label: 'Australia', value: 'Australia' },
            { label: 'Germany', value: 'Germany' },
            { label: 'France', value: 'France' },
            { label: 'Japan', value: 'Japan' },
            { label: 'China', value: 'China' },
            { label: 'Singapore', value: 'Singapore' },
            { label: 'UAE', value: 'UAE' },
            { label: 'Other', value: 'Other' }
        ];
    }

    // State options (will be filtered based on country)
    get stateOptions() {
        if (this.contactCountry === 'India') {
            return [
                { label: '--None--', value: '' },
                { label: 'Andhra Pradesh', value: 'Andhra Pradesh' },
                { label: 'Delhi', value: 'Delhi' },
                { label: 'Gujarat', value: 'Gujarat' },
                { label: 'Karnataka', value: 'Karnataka' },
                { label: 'Kerala', value: 'Kerala' },
                { label: 'Maharashtra', value: 'Maharashtra' },
                { label: 'Punjab', value: 'Punjab' },
                { label: 'Rajasthan', value: 'Rajasthan' },
                { label: 'Tamil Nadu', value: 'Tamil Nadu' },
                { label: 'Telangana', value: 'Telangana' },
                { label: 'Uttar Pradesh', value: 'Uttar Pradesh' },
                { label: 'West Bengal', value: 'West Bengal' },
                { label: 'Other', value: 'Other' }
            ];
        } else if (this.contactCountry === 'United States') {
            return [
                { label: '--None--', value: '' },
                { label: 'California', value: 'California' },
                { label: 'Florida', value: 'Florida' },
                { label: 'Illinois', value: 'Illinois' },
                { label: 'New York', value: 'New York' },
                { label: 'Texas', value: 'Texas' },
                { label: 'Washington', value: 'Washington' },
                { label: 'Other', value: 'Other' }
            ];
        } else if (this.contactCountry === 'United Kingdom') {
            return [
                { label: '--None--', value: '' },
                { label: 'England', value: 'England' },
                { label: 'Scotland', value: 'Scotland' },
                { label: 'Wales', value: 'Wales' },
                { label: 'Northern Ireland', value: 'Northern Ireland' }
            ];
        }
        return [{ label: '--None--', value: '' }];
    }

    // City options (will be filtered based on state)
    get cityOptions() {
        const cityMap = {
            'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Tirupati', 'Nellore'],
            'Delhi': ['New Delhi'],
            'Gujarat': ['Ahmedabad', 'Surat', 'Vadodara', 'Rajkot', 'Gandhinagar'],
            'Karnataka': ['Bangalore', 'Mysore', 'Mangalore', 'Hubli', 'Belgaum'],
            'Kerala': ['Thiruvananthapuram', 'Kochi', 'Kozhikode', 'Thrissur', 'Kannur'],
            'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Nashik', 'Thane'],
            'Punjab': ['Ludhiana', 'Amritsar', 'Jalandhar', 'Patiala', 'Chandigarh'],
            'Rajasthan': ['Jaipur', 'Jodhpur', 'Udaipur', 'Kota', 'Ajmer'],
            'Tamil Nadu': ['Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem'],
            'Telangana': ['Hyderabad', 'Warangal', 'Nizamabad', 'Karimnagar', 'Khammam'],
            'Uttar Pradesh': ['Lucknow', 'Kanpur', 'Agra', 'Varanasi', 'Noida'],
            'West Bengal': ['Kolkata', 'Howrah', 'Durgapur', 'Asansol', 'Siliguri'],
            'California': ['Los Angeles', 'San Francisco', 'San Diego', 'San Jose', 'Sacramento'],
            'Florida': ['Miami', 'Orlando', 'Tampa', 'Jacksonville', 'Fort Lauderdale'],
            'Illinois': ['Chicago', 'Aurora', 'Naperville', 'Rockford', 'Springfield'],
            'New York': ['New York City', 'Buffalo', 'Albany', 'Rochester', 'Syracuse'],
            'Texas': ['Houston', 'Dallas', 'Austin', 'San Antonio', 'Fort Worth'],
            'Washington': ['Seattle', 'Spokane', 'Tacoma', 'Vancouver', 'Bellevue'],
            'England': ['London', 'Manchester', 'Birmingham', 'Liverpool', 'Leeds'],
            'Scotland': ['Edinburgh', 'Glasgow', 'Aberdeen', 'Dundee', 'Inverness'],
            'Wales': ['Cardiff', 'Swansea', 'Newport', 'Wrexham', 'Barry'],
            'Northern Ireland': ['Belfast', 'Derry', 'Lisburn', 'Newry', 'Bangor']
        };

        const cities = cityMap[this.contactState];
        if (cities && cities.length > 0) {
            const options = [{ label: '--None--', value: '' }];
            cities.forEach(city => {
                options.push({ label: city, value: city });
            });
            options.push({ label: 'Other', value: 'Other' });
            return options;
        }
        return [{ label: '--None--', value: '' }];
    }

    // Getter for Reporting To options (contacts from the account and parent/ancestor accounts)
    get reportsToOptions() {
        const options = [{ label: '--None--', value: '' }];
        if (this.accountContacts && this.accountContacts.length > 0) {
            this.accountContacts.forEach((contact) => {
                const accName = contact.Account && contact.Account.Name;
                const label = accName ? `${contact.Name} (${accName})` : contact.Name;
                options.push({
                    label,
                    value: contact.Id
                });
            });
        }
        return options;
    }

    // Check if account exists (for showing Reporting To field)
    get showReportsToField() {
        return this.checkResult && this.checkResult.accountExists;
    }

    // Getters for disabled state of cascading picklists
    get isStateDisabled() {
        return !this.contactCountry;
    }

    get isCityDisabled() {
        return !this.contactState;
    }

    // Computed properties for step visibility
    get isCompanyCheckStep() {
        return this.currentStep === 'company-check';
    }

    get isLeadFormStep() {
        return this.currentStep === 'lead-form';
    }

    get isContactOpportunityStep() {
        return this.currentStep === 'contact-opportunity';
    }

    get isOpportunityOnlyStep() {
        return this.currentStep === 'opportunity-only';
    }

    get isSuccessStep() {
        return this.currentStep === 'success';
    }

    get modalTitle() {
        switch (this.currentStep) {
            case 'company-check':
                return 'B2B Lead - Company Check';
            case 'lead-form':
                return 'Create New Lead';
            case 'contact-opportunity':
                return 'Create Contact & Opportunity';
            case 'opportunity-only':
                return 'Create Opportunity';
            case 'success':
                return 'Success';
            default:
                return 'B2B Lead Process';
        }
    }

    get scenarioMessage() {
        if (!this.checkResult) return '';
        
        switch (this.checkResult.scenario) {
            case 'CREATE_LEAD':
                return 'No existing Account found. A new Lead will be created. After conversion, it will create Account, Contact, and Opportunity.';
            case 'CREATE_CONTACT_AND_OPPORTUNITY':
                return `Account "${this.checkResult.accountName}" already exists. A new Contact and Opportunity will be created under this Account.`;
            case 'CREATE_OPPORTUNITY_ONLY':
                return `Account "${this.checkResult.accountName}" and Contact "${this.checkResult.contactName}" already exist. Only a new Opportunity will be created.`;
            default:
                return '';
        }
    }

    get scenarioClass() {
        if (!this.checkResult) return '';
        
        switch (this.checkResult.scenario) {
            case 'CREATE_LEAD':
                return 'slds-theme_info slds-p-around_small slds-m-bottom_medium scenario-info';
            case 'CREATE_CONTACT_AND_OPPORTUNITY':
                return 'slds-theme_warning slds-p-around_small slds-m-bottom_medium scenario-warning';
            case 'CREATE_OPPORTUNITY_ONLY':
                return 'slds-theme_success slds-p-around_small slds-m-bottom_medium scenario-success';
            default:
                return '';
        }
    }

    get formattedAccountRevenue() {
        if (this.checkResult && this.checkResult.accountAnnualRevenue) {
            return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD',
                minimumFractionDigits: 0,
                maximumFractionDigits: 0
            }).format(this.checkResult.accountAnnualRevenue);
        }
        return '-';
    }

    // Event Handlers - Company Check
    handleCompanyChange(event) {
        this.company = event.target.value;
        this.clearError();
    }

    handleEmailChange(event) {
        this.email = event.target.value;
        this.clearError();
    }

    // Event Handlers - Contact/Lead Fields
    handleFirstNameChange(event) {
        this.firstName = event.target.value;
        this.clearError();
    }

    handleLastNameChange(event) {
        this.lastName = event.target.value;
        this.clearError();
    }

    handlePhoneChange(event) {
        this.phone = event.target.value;
        this.clearError();
    }

    handleTitleChange(event) {
        this.title = event.target.value;
        this.clearError();
    }

    handleDepartmentChange(event) {
        this.department = event.target.value;
        this.clearError();
    }

    handleMobilePhoneChange(event) {
        this.mobilePhone = event.target.value;
        this.clearError();
    }

    handleLinkedInChange(event) {
        this.linkedIn = event.target.value;
        this.clearError();
    }

    handleContactCountryChange(event) {
        this.contactCountry = event.detail.value;
        this.contactState = '';
        this.contactCity = '';
        this.clearError();
    }

    handleContactStateChange(event) {
        this.contactState = event.detail.value;
        this.contactCity = '';
        this.clearError();
    }

    handleContactCityChange(event) {
        this.contactCity = event.detail.value;
        this.clearError();
    }

    handleReportsToChange(event) {
        this.reportsToId = event.detail.value || null;
        this.clearError();
    }

    // Event Handlers - Company Information
    handleIndustryChange(event) {
        this.industry = event.detail.value;
        this.clearError();
    }

    handleWebsiteChange(event) {
        this.website = event.target.value;
        this.clearError();
    }

    handleNumberOfEmployeesChange(event) {
        this.numberOfEmployees = event.target.value ? parseInt(event.target.value) : null;
        this.clearError();
    }

    handleAnnualRevenueChange(event) {
        this.annualRevenue = event.target.value ? parseFloat(event.target.value) : null;
        this.clearError();
    }

    handleStreetChange(event) {
        this.street = event.target.value;
        this.clearError();
    }

    handleCityChange(event) {
        this.city = event.target.value;
        this.clearError();
    }

    handleStateChange(event) {
        this.state = event.target.value;
        this.clearError();
    }

    handlePostalCodeChange(event) {
        this.postalCode = event.target.value;
        this.clearError();
    }

    handleCountryChange(event) {
        this.country = event.target.value;
        this.clearError();
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
        this.clearError();
    }

    handleLeadSourceChange(event) {
        this.leadSource = event.detail.value;
        this.clearError();
    }

    handleMouContractChange(event) {
        this.isMouContractRequired = event.target.checked;
        this.clearError();
    }

    // Event Handlers - Opportunity Fields
    handleOpportunityNameChange(event) {
        this.opportunityName = event.target.value;
        this.clearError();
    }

    handleOpportunityAmountChange(event) {
        this.opportunityAmount = event.target.value ? parseFloat(event.target.value) : null;
        this.clearError();
    }

    handleCloseDateChange(event) {
        this.closeDate = event.target.value;
        this.clearError();
    }

    handleStageChange(event) {
        this.stage = event.detail.value;
        this.clearError();
    }

    handleMinStudentsChange(event) {
        this.minNumberOfStudents = event.target.value ? parseInt(event.target.value) : null;
        this.clearError();
    }

    handleMaxStudentsChange(event) {
        this.maxNumberOfStudents = event.target.value ? parseInt(event.target.value) : null;
        this.clearError();
    }

    // Event Handlers - Program Selection
    handleProgramRecordChange(event) {
        const recordId = event.detail.recordId;
        if (recordId) {
            this.selectedProgramId = recordId;
            this.selectedProgramName = '';
            
            // Fetch program name from Apex
            getProgramName({ programId: recordId })
                .then(result => {
                    this.selectedProgramName = result || '';
                })
                .catch(error => {
                    console.error('Error fetching program name:', error);
                    this.selectedProgramName = '';
                });
        } else {
            this.selectedProgramId = null;
            this.selectedProgramName = '';
        }
        this.clearError();
    }

    async handleAddProgram() {
        if (!this.selectedProgramId) {
            this.showToast('Info', 'Please search and select a program to add.', 'info');
            return;
        }

        const alreadyAdded = this.selectedPrograms.some(p => p.id === this.selectedProgramId);
        if (alreadyAdded) {
            this.showToast('Info', 'This program is already added.', 'info');
            this.clearProgramPicker();
            return;
        }

        // If name not yet fetched, fetch it now
        let programName = this.selectedProgramName;
        if (!programName) {
            try {
                programName = await getProgramName({ programId: this.selectedProgramId });
            } catch (error) {
                console.error('Error fetching program name:', error);
                programName = 'Program';
            }
        }

        this.selectedPrograms = [
            ...this.selectedPrograms,
            {
                id: this.selectedProgramId,
                name: programName || 'Program'
            }
        ];
        
        this.clearProgramPicker();
    }

    clearProgramPicker() {
        this.selectedProgramId = null;
        this.selectedProgramName = '';
        // Reset the record picker
        const recordPickers = this.template.querySelectorAll('lightning-record-picker');
        recordPickers.forEach(picker => {
            picker.clearSelection();
        });
    }

    handleRemoveProgram(event) {
        const programId = event.currentTarget.dataset.id;
        this.selectedPrograms = this.selectedPrograms.filter(p => p.id !== programId);
    }

    get hasSelectedPrograms() {
        return this.selectedPrograms && this.selectedPrograms.length > 0;
    }

    get selectedProgramIds() {
        return this.selectedPrograms.map(p => p.id);
    }

    clearError() {
        this.errorMessage = '';
    }

    // Check Company and Email
    async handleCheckCompany() {
        const companyVal = (this.company || '').trim();
        const emailVal = (this.email || '').trim();

        if (!companyVal) {
            this.errorMessage = 'Company Name is required.';
            this.showToast('Validation Error', 'Company Name is required.', 'error');
            return;
        }

        if (!emailVal) {
            this.errorMessage = 'Email is required to check for existing contacts.';
            this.showToast('Validation Error', 'Email is required.', 'error');
            return;
        }

        try {
            this.isChecking = true;
            this.errorMessage = '';

            const result = await checkAccountAndContact({
                companyName: companyVal,
                email: emailVal,
                matchPhone: null,
                matchMobile: null
            });
            
            this.checkResult = result;
            this.scenario = result.scenario;

            // Set default opportunity name
            this.opportunityName = companyVal + ' - Opportunity';

            // Load contacts for the account if account exists (for Reporting To field)
            if (result.accountExists && result.accountId) {
                try {
                    this.accountContacts = await getAccountContacts({
                        accountId: result.accountId,
                        excludeContactId:
                            result.contactExists && result.contactId ? result.contactId : null
                    });
                } catch (err) {
                    console.error('Error loading account contacts:', err);
                    this.accountContacts = [];
                }
            }
            this.reportsToId =
                result.contactExists && result.contactReportsToId ? result.contactReportsToId : null;
            this.department = result.contactExists ? result.contactDepartment || '' : '';

            // Navigate to appropriate step based on scenario
            switch (result.scenario) {
                case 'CREATE_LEAD':
                    this.currentStep = 'lead-form';
                    break;
                case 'CREATE_CONTACT_AND_OPPORTUNITY':
                    this.currentStep = 'contact-opportunity';
                    break;
                case 'CREATE_OPPORTUNITY_ONLY':
                    this.currentStep = 'opportunity-only';
                    break;
            }

        } catch (error) {
            console.error('Error checking account:', error);
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isChecking = false;
        }
    }

    // Handle Lead Creation
    async handleCreateLead() {
        if (!this.validateLeadFields()) return;

        try {
            this.isSaving = true;
            this.errorMessage = '';

            const result = await createLead({
                lastName: this.lastName.trim(),
                firstName: this.firstName ? this.firstName.trim() : null,
                company: this.company.trim(),
                email: this.email.trim(),
                phone: this.phone ? this.phone.trim() : null,
                mobilePhone: this.mobilePhone ? this.mobilePhone.trim() : null,
                title: this.title ? this.title.trim() : null,
                department: this.department ? this.department.trim() : null,
                linkedIn: this.linkedIn ? this.linkedIn.trim() : null,
                contactCountry: this.contactCountry || null,
                contactState: this.contactState || null,
                contactCity: this.contactCity || null,
                industry: this.industry || null,
                website: this.website ? this.website.trim() : null,
                numberOfEmployees: this.numberOfEmployees,
                annualRevenue: this.annualRevenue,
                street: this.street ? this.street.trim() : null,
                city: this.city ? this.city.trim() : null,
                state: this.state ? this.state.trim() : null,
                postalCode: this.postalCode ? this.postalCode.trim() : null,
                country: this.country ? this.country.trim() : null,
                description: this.description ? this.description.trim() : null,
                leadSource: this.leadSource || null,
                isMouContractRequired: this.isMouContractRequired,
                opportunityName: this.opportunityName ? this.opportunityName.trim() : null,
                opportunityAmount: this.opportunityAmount,
                closeDate: this.closeDate || null,
                stage: this.stage,
                minNumberOfStudents: this.minNumberOfStudents,
                maxNumberOfStudents: this.maxNumberOfStudents,
                reportingToContactId: this.reportsToId || null,
                programIds: this.selectedProgramIds
            });

            if (result.success) {
                this.createdLeadId = result.leadId;
                this.showConvertOption = true;
                this.showToast('Success', result.message, 'success');
                this.currentStep = 'success';
            } else {
                this.errorMessage = result.message;
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('Error creating lead:', error);
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // Handle Lead Conversion
    async handleConvertLead() {
        if (!this.createdLeadId) return;

        try {
            this.isSaving = true;
            this.errorMessage = '';

            const result = await convertLeadToAccountContactOpportunity({
                leadId: this.createdLeadId
            });

            if (result.success) {
                this.showToast('Success', result.message, 'success');
                if (result.opportunityId) {
                    this.navigateToRecord(result.opportunityId, 'Opportunity');
                } else {
                    this.navigateToRecord(result.accountId, 'Account');
                }
            } else {
                this.errorMessage = result.message;
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('Error converting lead:', error);
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // Handle Contact and Opportunity Creation
    async handleCreateContactAndOpportunity() {
        if (!this.validateContactOpportunityFields()) return;

        try {
            this.isSaving = true;
            this.errorMessage = '';

            const result = await createContactAndOpportunity({
                accountId: this.checkResult.accountId,
                lastName: this.lastName.trim(),
                firstName: this.firstName ? this.firstName.trim() : null,
                email: this.email.trim(),
                phone: this.phone ? this.phone.trim() : null,
                mobilePhone: this.mobilePhone ? this.mobilePhone.trim() : null,
                title: this.title ? this.title.trim() : null,
                department: this.department ? this.department.trim() : null,
                linkedIn: this.linkedIn ? this.linkedIn.trim() : null,
                contactCountry: this.contactCountry || null,
                contactState: this.contactState || null,
                contactCity: this.contactCity || null,
                reportsToId: this.reportsToId,
                leadSource: this.leadSource || null,
                isMouContractRequired: this.isMouContractRequired,
                opportunityName: this.opportunityName ? this.opportunityName.trim() : this.company + ' - Opportunity',
                opportunityAmount: this.opportunityAmount,
                closeDate: this.closeDate || null,
                stage: this.stage,
                minNumberOfStudents: this.minNumberOfStudents,
                maxNumberOfStudents: this.maxNumberOfStudents,
                programIds: this.selectedProgramIds
            });

            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.navigateToRecord(result.opportunityId, 'Opportunity');
            } else {
                this.errorMessage = result.message;
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('Error creating contact and opportunity:', error);
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // Handle Opportunity Only Creation
    async handleCreateOpportunityOnly() {
        if (!this.validateOpportunityFields()) return;

        try {
            this.isSaving = true;
            this.errorMessage = '';

            const result = await createOpportunityOnly({
                accountId: this.checkResult.accountId,
                contactId: this.checkResult.contactId,
                leadSource: this.leadSource || null,
                isMouContractRequired: this.isMouContractRequired,
                opportunityName: this.opportunityName ? this.opportunityName.trim() : this.company + ' - Opportunity',
                opportunityAmount: this.opportunityAmount,
                closeDate: this.closeDate || null,
                stage: this.stage,
                minNumberOfStudents: this.minNumberOfStudents,
                maxNumberOfStudents: this.maxNumberOfStudents,
                programIds: this.selectedProgramIds,
                reportsToId: this.reportsToId || null,
                department: this.department ? this.department.trim() : null
            });

            if (result.success) {
                this.showToast('Success', result.message, 'success');
                this.navigateToRecord(result.opportunityId, 'Opportunity');
            } else {
                this.errorMessage = result.message;
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('Error creating opportunity:', error);
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // Validation Methods
    validateLeadFields() {
        const errors = [];
        
        if (!this.lastName || !this.lastName.trim()) {
            errors.push('Last Name is required.');
        }
        if (!this.company || !this.company.trim()) {
            errors.push('Company is required.');
        }
        if (!this.department || !this.department.trim()) {
            errors.push('Department is required.');
        }

        if (errors.length > 0) {
            this.errorMessage = errors.join(' ');
            this.showToast('Validation Error', this.errorMessage, 'error');
            return false;
        }
        return true;
    }

    validateContactOpportunityFields() {
        const errors = [];
        
        if (!this.lastName || !this.lastName.trim()) {
            errors.push('Last Name is required.');
        }
        if (!this.department || !this.department.trim()) {
            errors.push('Department is required.');
        }
        if (!this.closeDate) {
            errors.push('Close Date is required.');
        }
        if (!this.stage) {
            errors.push('Stage is required.');
        }
        if (!this.selectedPrograms || this.selectedPrograms.length === 0) {
            errors.push('At least one Program must be selected.');
        }

        if (errors.length > 0) {
            this.errorMessage = errors.join(' ');
            this.showToast('Validation Error', this.errorMessage, 'error');
            return false;
        }
        return true;
    }

    validateOpportunityFields() {
        const errors = [];
        
        if (!this.department || !this.department.trim()) {
            errors.push('Department is required.');
        }
        if (!this.closeDate) {
            errors.push('Close Date is required.');
        }
        if (!this.stage) {
            errors.push('Stage is required.');
        }
        if (!this.selectedPrograms || this.selectedPrograms.length === 0) {
            errors.push('At least one Program must be selected.');
        }

        if (errors.length > 0) {
            this.errorMessage = errors.join(' ');
            this.showToast('Validation Error', this.errorMessage, 'error');
            return false;
        }
        return true;
    }

    // Navigation
    handleCancel() {
        this.dispatchCloseEvent();
        this.navigateToLeadListView();
    }

    handleBack() {
        this.currentStep = 'company-check';
        this.checkResult = null;
        this.scenario = '';
        this.errorMessage = '';
        this.selectedPrograms = [];
        this.selectedProgramId = null;
        this.selectedProgramName = '';
        this.department = '';
    }

    handleViewLead() {
        if (this.createdLeadId) {
            this.navigateToRecord(this.createdLeadId, 'Lead');
        }
    }

    dispatchCloseEvent() {
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            // Not a quick action
        }
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));
    }

    navigateToLeadListView() {
        setTimeout(() => {
            window.location.href = '/lightning/o/Lead/list';
        }, 100);
    }

    navigateToRecord(recordId, objectApiName) {
        this.dispatchCloseEvent();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: objectApiName,
                actionName: 'view'
            }
        });
    }

    // Utility Methods
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    extractErrorMessage(error) {
        let errorMsg = 'Unknown error occurred.';
        
        if (error.body) {
            if (error.body.message) {
                errorMsg = error.body.message;
            } else if (Array.isArray(error.body.pageErrors)) {
                errorMsg = error.body.pageErrors.map(e => e.message).join(' ');
            }
        } else if (error.message) {
            errorMsg = error.message;
        }
        
        return errorMsg;
    }
}