import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';
import getCountries from '@salesforce/apex/B2BLeadFormController.getCountries';
import getStatesByCountry from '@salesforce/apex/B2BLeadFormController.getStatesByCountry';
import getCitiesByState from '@salesforce/apex/B2BLeadFormController.getCitiesByState';
import searchPrograms from '@salesforce/apex/B2BLeadFormController.searchPrograms';
import checkAccountAndContact from '@salesforce/apex/B2BLeadProcessController.checkAccountAndContact';
import checkAccountAndContactForAccountId from '@salesforce/apex/B2BLeadProcessController.checkAccountAndContactForAccountId';
import getLeadMergePrefill from '@salesforce/apex/B2BLeadProcessController.getLeadMergePrefill';
import searchCompanyMatches from '@salesforce/apex/B2BLeadProcessController.searchCompanyMatches';
import getAccountContacts from '@salesforce/apex/B2BLeadProcessController.getAccountContacts';
import createLead from '@salesforce/apex/B2BLeadProcessController.createLead';
import getStdCodesByCountry from '@salesforce/apex/B2BLeadProcessController.getStdCodesByCountry';
import mergeB2BLeadWithPrograms from '@salesforce/apex/B2BLeadProcessController.mergeB2BLeadWithPrograms';
import createContactAndOpportunity from '@salesforce/apex/B2BLeadProcessController.createContactAndOpportunity';
import createOpportunityOnly from '@salesforce/apex/B2BLeadProcessController.createOpportunityOnly';
import DEPARTMENT_MASTER from '@salesforce/schema/Lead.Department_Master__c'
import CreateDepartmentModal from 'c/createDepartmentModal';
import checkLeadContacts from '@salesforce/apex/B2BLeadProcessController.checkLeadContacts'
/** B2B Lead Source picklist API values (must match Lead LeadSource / B2B record type). */
const B2B_LEAD_SOURCE_OPTIONS = [
    { label: 'Website', value: 'Website' },
    { label: 'Referrals', value: 'Referrals' },
    { label: 'Events', value: 'Events' },
    { label: 'Campaigns', value: 'Campaigns' },
    { label: 'LinkedIn', value: 'Linkedin' },
    { label: 'Calls Directly Via Desk Enquiry', value: 'Calls Directly Via Desk Enquiry' },
    { label: 'Email Enquiry', value: 'Email Enquiry' },
    { label: 'Referral', value: 'Referral' },
    { label: 'Alumni Referrals', value: 'Alumni Referrals' },
    { label: 'Marketing Outreach Campaign', value: 'Marketing Outreach Campaign' },
    { label: 'Occasional Inbound Calls', value: 'Occasional Inbound Calls' }
];

const SHOW_REMARK_VALUE = 'Events'

export default class CreateB2BLead extends NavigationMixin(LightningElement) {
    @track step = 'init';
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track mobilePhone = '';
    @track countryCode = '+91';
    @track company = '';
    @track title = '';
    @track department = '';
    @track linkedIn = '';
    @track website = '';
    @track street = '';
    @track selectedCountry = '';
    @track selectedState = '';
    @track selectedCity = '';
    @track postalCode = '';
    @track leadSource = '';
    @track description = '';
    /** Init-step values that must stay read-only on the details step (per field). */
    @track initStepLockedEmail = false;
    @track initStepLockedMobile = false;
    @track initStepLockedPhone = false;
    @track initStepLockedCountryCode = false;

    @track isSaving = false;
    @track errorMessage = '';
    /** MOU question: only for existing Account+Contact path (new Opportunity only). */
    @track isMouContractRequired = false;

    @track countryOptions = [];
    @track stateOptions = [];
    @track cityOptions = [];
    @track stdCodeOptions = [];
    @track stdCode = '';
    countryCodeOptions = [
        { label: 'IN +91', value: '+91' },
        { label: 'US +1', value: '+1' },
        { label: 'AE +971', value: '+971' },
        { label: 'SG +65', value: '+65' },
        { label: 'GB +44', value: '+44' }
    ];

    @track leadRemark = ''
    countryLengthMap = {};
    deptField = DEPARTMENT_MASTER
    departmentKey = 0;
    @track programSearchTerm = '';
    @track programSearchResults = [];
    @track selectedProgramsList = [];
    @track showProgramSearchResults = false;
    @track isSearching = false;
    @track checkResult = null;
    @track scenario = 'CREATE_LEAD';
    /** When user merges into an existing B2B Lead from company search. */
    @track existingLeadId = null;
    /** Optional: { type: 'Lead'|'Account', id, name } from fuzzy company match. */
    @track selectedMergeRecord = null;
    @track companyMatchLeads = [];
    @track companyMatchAccounts = [];
    @track showCompanyMatchDropdown = false;
    @track isCompanyMatchSearching = false;

    /** For Reporting To contact picklist (account + parent account contacts). */
    @track reportingToAccountId = null;
    @track reportingToExcludeContactId = null;
    @track reportsToId = '';
    @track reportingToContactRows = [];
    companyPhone = '';
    companyLinkedIn = ''
    companyEmail = ''
    searchTimeout;
    companyMatchDebounce;

    countryDialMap = {};      // countryId → +code
    dialToCountryMap = {};

    @wire(getCountries)
    wiredCountries({ error, data }) {
        if (data) {
            this.countryOptions = data.map(c => ({
                label: c.label,
                value: c.value
            }));
            this.countryCodeOptions = data.map(c => {
                const dial = `+${c.code}`;

                this.countryDialMap[c.value] = dial;
                this.dialToCountryMap[dial] = c.value;
                this.countryLengthMap[c.value] = parseInt(c.acceptedLength, 10);
                return {
                    label: `${dial} ${c.label}`,
                    value: dial
                };
            });
            this.tryApplyIndiaAsDefaultCountry();
        } else if (error) {
            console.error('Error loading countries:', error);
        }
    }

    @wire(getAccountContacts, {
        accountId: '$reportingToAccountId',
        excludeContactId: '$reportingToExcludeContactId'
    })
    wiredReportingContacts({ error, data }) {
        if (data) {
            this.reportingToContactRows = data;
        } else if (error) {
            this.reportingToContactRows = [];
            console.error('Error loading reporting contacts:', error);
        }
    }

    get leadSourceOptions() {
        return B2B_LEAD_SOURCE_OPTIONS;
    }

    get isLeadSourceEvent() {
        return this.leadSource == SHOW_REMARK_VALUE
    }

    get isStateDisabled() {
        return !this.selectedCountry;
    }

    get isCityDisabled() {
        return !this.selectedState;
    }

    /** Country / State / City required when Lead or Contact is created/updated with address. */
    get isAddressRequired() {
        return this.scenario !== 'CREATE_OPPORTUNITY_ONLY';
    }

    get isEmailReadOnly() {
        if (!this.isDetailsStep) {
            return false;
        }
        if (this.scenario === 'MERGE_EXISTING_LEAD') {
            return false;
        }
        if (this.checkResult && this.checkResult.contactExists) {
            return true;
        }
        return this.initStepLockedEmail;
    }

    get isMobileReadOnly() {
        if (!this.isDetailsStep) {
            return false;
        }
        if (this.scenario === 'MERGE_EXISTING_LEAD') {
            return false;
        }
        if (this.checkResult && this.checkResult.contactExists) {
            return true;
        }
        return this.initStepLockedMobile;
    }

    get isPhoneReadOnly() {
        if (!this.isDetailsStep) {
            return false;
        }
        if (this.scenario === 'MERGE_EXISTING_LEAD') {
            return false;
        }
        if (this.checkResult && this.checkResult.contactExists) {
            return true;
        }
        return this.initStepLockedPhone;
    }

    get isCountryCodeReadOnly() {
        if (!this.isDetailsStep) {
            return false;
        }
        if (this.scenario === 'MERGE_EXISTING_LEAD') {
            return false;
        }
        if (this.checkResult && this.checkResult.contactExists) {
            return true;
        }
        return this.initStepLockedCountryCode;
    }

    get showReportingTo() {
        return !!(this.checkResult && this.checkResult.accountExists);
    }

    get reportingToOptions() {
        const rows = this.reportingToContactRows || [];
        return rows.map((c) => {
            const accName = c.Account && c.Account.Name;
            const label = accName ? `${c.Name} (${accName})` : c.Name;
            return { label, value: c.Id };
        });
    }

    get hasProgramSearchResults() {
        return this.programSearchResults && this.programSearchResults.length > 0;
    }

    get hasSelectedPrograms() {
        return this.selectedProgramsList && this.selectedProgramsList.length > 0;
    }

    get selectedProgramIds() {
        return this.selectedProgramsList.map(p => p.id);
    }

    get isInitStep() {
        return this.step === 'init';
    }

    get isDetailsStep() {
        return this.step === 'details';
    }

    get showScenarioBanner() {
        if (!this.isDetailsStep) {
            return false;
        }
        return !!(this.checkResult || this.scenario === 'MERGE_EXISTING_LEAD');
    }

    /**
     * Existing Account and Contact matched — user adds another Opportunity; MOU applies here only.
     */
    get showMouContractQuestion() {
        return this.scenario === 'CREATE_OPPORTUNITY_ONLY';
    }

    get scenarioMessage() {
        if (this.scenario === 'MERGE_EXISTING_LEAD') {
            return 'Existing Lead selected. Saving will update the lead and add new lead contacts.';
        }
        if (!this.checkResult) {
            return '';
        }
        if (this.scenario === 'CREATE_OPPORTUNITY_ONLY') {
            return 'Existing Account and Contact found. Saving will create Opportunity only.';
        }
        if (this.scenario === 'CREATE_CONTACT_AND_OPPORTUNITY') {
            return 'Existing Account found. Saving will create Contact and Opportunity.';
        }
        return 'No existing Account found. Saving will create Lead first.';
    }

    get hasCompanyMatchRows() {
        const leads = this.companyMatchLeads || [];
        const accounts = this.companyMatchAccounts || [];
        return leads.length > 0 || accounts.length > 0;
    }

    get mergeSelectionLabel() {
        const m = this.selectedMergeRecord;
        if (!m || !m.type) {
            return '';
        }
        return m.type === 'Lead' ? `Lead: ${m.name}` : `Account: ${m.name}`;
    }
    get mobileMaxLength() {
        return this.countryLengthMap[this.selectedCountry] || 20;
    }

    /**
     * Flattened rows for the init-step match table (Type, Name, Details, selection state).
     */
    get companyMatchTableRows() {
        console.log('Record Selected ', JSON.stringify(this.selectedMergeRecord))
        const selId = this.selectedMergeRecord?.id;
        const base = 'company-match-row';
        const leads = (this.companyMatchLeads || []).map((r) => ({
            recordId: r.recordId,
            recordType: r.recordType,
            name: r.name,
            subtitle: r.subtitle || '',
            typeLabel: 'Lead',
            trClass: selId === r.recordId ? `${base} is-selected` : base
        }));
        console.log('Found these leads: ', JSON.stringify(leads))
        const accounts = (this.companyMatchAccounts || []).map((r) => ({
            recordId: r.recordId,
            recordType: r.recordType,
            name: r.name,
            subtitle: r.subtitle || '',
            typeLabel: 'Account',
            trClass: selId === r.recordId ? `${base} is-selected` : base
        }));
        return [...leads, ...accounts];
    }

    validateMobileLength() {
        if (!this.mobilePhone || !this.selectedCountry) {
            return true;
        }

        const expectedLength = this.countryLengthMap[this.selectedCountry];

        if (
            expectedLength &&
            this.mobilePhone.replace(/\D/g, '').length !== expectedLength
        ) {
            this.errorMessage =
                `Mobile number must be ${expectedLength} digits for the selected country.`;
            return false;
        }

        return true;
    }

    async handleNewDepartment() {
        try {
            const result = await CreateDepartmentModal.open({
                size: 'small'
            });

            if (result) {
                console.log('Created Department Id:', result);

                this.department = result;
            }

        } catch (error) {
            console.error('Modal error:', error);
        }
    }




    handleStdCodeChange(event) {
        this.stdCode = event.detail.value;
        const selectedOption = this.stdCodeOptions.find(
            opt => opt.value === this.stdCode
        );

        if (selectedOption) {
            const stateName = selectedOption.label.split(' - ')[1];

            const matchingState = this.stateOptions.find(
                state => state.label === stateName
            );

            if (matchingState) {
                this.selectedState = matchingState.value;

                this.handleStateChange({
                    detail: {
                        value: matchingState.value
                    }
                });
            }
        }

    }

    handleDepartmentChange(event) {
        const value = event.detail.value;

        this.department = Array.isArray(value) ? value[0] : value;

        console.log('Department Id is ', this.department);
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        if (field) {
            const target = event.target;
            if (target.type === 'checkbox') {
                this[field] = !!target.checked;
            } else {
                this[field] = target.value;
            }
        }
        console.log('Event Remarks: ', this.leadRemark)
        this.clearError();
        if (field === 'company' && this.isInitStep) {
            this.scheduleCompanyMatchSearch();
        }
    }

    scheduleCompanyMatchSearch() {
        if (this.companyMatchDebounce) {
            clearTimeout(this.companyMatchDebounce);
        }
        const term = (this.company || '').trim();
        if (term.length < 2) {
            this.companyMatchLeads = [];
            this.companyMatchAccounts = [];
            this.showCompanyMatchDropdown = false;
            this.isCompanyMatchSearching = false;
            return;
        }
        this.showCompanyMatchDropdown = true;
        this.isCompanyMatchSearching = true;
        this.companyMatchDebounce = setTimeout(() => {
            this.fetchCompanyMatches(term);
        }, 300);
    }

    async fetchCompanyMatches(term) {
        try {
            const res = await searchCompanyMatches({ searchTerm: term });
            this.companyMatchLeads = res?.leads || [];
            this.companyMatchAccounts = res?.accounts || [];
        } catch (error) {
            console.error('Company match search failed:', error);
            this.companyMatchLeads = [];
            this.companyMatchAccounts = [];
        } finally {
            this.isCompanyMatchSearching = false;
        }
    }

    handleSelectCompanyMatch(event) {
        const { mergeId, mergeType, mergeName } = event.currentTarget.dataset;
        if (!mergeId || !mergeType) {
            return;
        }
        if (mergeType === 'Account') {
            this.clearNewContactPersonFieldsForAccountPath();
        }
        this.selectedMergeRecord = {
            type: mergeType,
            id: mergeId,
            name: mergeName || ''
        };
        if (mergeName) {
            this.company = mergeName;
        }
        this.clearError();
    }

    handleClearMergeSelection() {
        this.selectedMergeRecord = null;
        this.clearError();
    }

    async handleCountryCodeChange(event) {
        this.selectedState = '';
        this.selectedCity = '';
        this.stateOptions = [];
        this.cityOptions = [];
        this.countryCode = event.detail.value;
        const countryId = this.dialToCountryMap[this.countryCode];
        if (countryId) {
            this.selectedCountry = countryId;
            this.stdCodeOptions = []
            this.stdCode = ''
            this.loadStatesForCountryId(countryId);
            this.loadStdCodes(countryId);
        }
        this.clearError();



    }

    handleReportsToChange(event) {
        this.reportsToId = event.detail.value || '';
        this.clearError();
    }

    handleInitialNext() {
        const emailVal = (this.email || '').trim();
        const companyVal = (this.company || '').trim();
        const mobileVal = (this.mobilePhone || '').trim();
        const hasPhoneDigits = (this.phone || '').trim().length > 0;
        const validationErrors = [];

        if (!companyVal) {
            validationErrors.push('Company is required.');
        }
        if (!emailVal && !mobileVal && !hasPhoneDigits) {
            validationErrors.push('Provide at least one of Email, Mobile, or Phone.');
        }
        if (emailVal && !this.isValidEmail(emailVal)) {
            validationErrors.push('Please enter a valid email address.');
        }

        if (validationErrors.length > 0) {
            this.errorMessage = validationErrors.join(' ');
            return;
        }

        this.errorMessage = '';
        this.runInitialCheck(companyVal, emailVal);
    }

    clearNewContactPersonFieldsForAccountPath() {
        this.firstName = '';
        this.lastName = '';
        this.title = '';
        this.department = '';
        this.linkedIn = '';
        this.phone = '';
        this.mobilePhone = '';
        this.reportsToId = '';
    }

    async runInitialCheck(companyVal, emailVal) {
        try {
            this.isSaving = true;
            this.existingLeadId = null;
            this.initStepLockedEmail = !!(this.email || '').trim();
            this.initStepLockedMobile = !!(this.mobilePhone || '').trim();
            this.initStepLockedPhone = !!(this.phone || '').trim();
            this.initStepLockedCountryCode =
                this.initStepLockedMobile || this.initStepLockedPhone;

            const matchPhone =
                (this.phone || '').trim().length > 0 ? this.getCombinedPhone() : null;
            const matchMobile =
                (this.mobilePhone || '').trim().length > 0
                    ? this.getCombinedMobile()
                    : null;

            if (this.selectedMergeRecord?.type === 'Lead') {
                this.checkResult = null;
                this.scenario = 'MERGE_EXISTING_LEAD';
                this.existingLeadId = this.selectedMergeRecord.id;
                this.reportingToAccountId = null;
                this.reportingToExcludeContactId = null;
                this.reportsToId = '';
                this.reportingToContactRows = [];
                const prefill = await getLeadMergePrefill({ leadId: this.existingLeadId });
                this.applyLeadMergePrefill(prefill);
                this.isMouContractRequired = false;
                this.step = 'details';
                this.tryApplyIndiaAsDefaultCountry();
                return;
            }

            let result;
            if (this.selectedMergeRecord?.type === 'Account') {
                result = await checkAccountAndContactForAccountId({
                    accountId: this.selectedMergeRecord.id,
                    email: emailVal || null,
                    matchPhone,
                    matchMobile
                });
                if (result?.accountName) {
                    this.company = result.accountName;
                }
            } else {
                result = await checkAccountAndContact({
                    companyName: companyVal,
                    email: emailVal || null,
                    matchPhone,
                    matchMobile
                });
            }

            this.checkResult = result;
            this.scenario = result?.scenario || 'CREATE_LEAD';
            if (result.accountExists && result.accountId) {
                this.reportingToAccountId = result.accountId;
                this.reportingToExcludeContactId =

                    result.contactExists && result.contactId ? result.contactId : null;
            } else {
                this.reportingToAccountId = null;
                this.reportingToExcludeContactId = null;
                this.reportsToId = '';
                this.reportingToContactRows = [];
            }
            this.applyCheckResultPrefill();
            this.isMouContractRequired = false;
            this.step = 'details';
            this.tryApplyIndiaAsDefaultCountry();
        } catch (error) {
            this.errorMessage = 'Error checking existing account/contact.';
        } finally {
            this.isSaving = false;
        }
    }

    async applyLeadMergePrefill(prefill) {
        if (!prefill) {
            return;
        }
        // this.firstName = prefill.firstName || '';
        // this.lastName = prefill.lastName || '';
        // if (prefill.email) {
        //     this.email = prefill.email;
        // }
        // this.title = prefill.title || '';
        // this.department = prefill.department || '';
        // this.linkedIn = prefill.linkedIn || '';
        //this.phone = prefill.Phone || ''
        this.selectedCountry = prefill.countryId
        const states = await getStatesByCountry({
            countryId: prefill.countryId
        });

        this.stateOptions = states.map(s => ({
            label: s.label,
            value: s.value
        }));

        this.selectedState = prefill.stateId;
        const cities = await getCitiesByState({
            stateId: prefill.stateId
        });

        this.cityOptions = cities.map(c => ({
            label: c.label,
            value: c.value,
            stdCode: c.stdCode
        }));

        this.selectedCity = prefill.cityId;
        this.selectedCity = prefill.cityId
        console.log(JSON.stringify(prefill.cityId))
        this.company = prefill.company || this.company;
        this.website = prefill.website || '';
        this.street = prefill.street || '';
        this.postalCode = prefill.postalCode || '';
        this.description = prefill.description || '';
        this.leadSource = prefill.leadSource || '';
        this.reportsToId = prefill.reportingToContactId || '';
        // this.setPhoneFromStoredValue(prefill.phone || '');
        // this.setMobileFromStoredValue(prefill.mobilePhone || '');
    }

    tryApplyIndiaAsDefaultCountry() {
        if (this.selectedCountry) {
            return;
        }
        const opts = this.countryOptions || [];
        const india = opts.find(
            (o) => (o.label || '').trim().toLowerCase() === 'india'
        );
        if (!india) {
            return;
        }
        this.selectedCountry = india.value;
        this.loadStatesForCountryId(india.value);
        this.loadStdCodes(india.value);
    }

    async loadStdCodes(countryId) {
        try {
            const stdCodes = await getStdCodesByCountry({ countryId });

            this.stdCodeOptions = stdCodes.map(code => ({
                label: code,
                value: code.split(' - ')[0]
            }));

            if (this.stdCodeOptions.length > 0) {
                this.stdCode = this.stdCodeOptions[0].value;
            }

        } catch (error) {
            console.error('STD load error:', error);
        }
    }

    loadStatesForCountryId(countryId) {
        if (!countryId) {
            return;
        }
        getStatesByCountry({ countryId })
            .then((states) => {
                this.stateOptions = states.map((s) => ({
                    label: s.label,
                    value: s.value
                }));
            })
            .catch((error) => {
                console.error('Error loading states:', error);
                this.stateOptions = [];
            });
    }

    applyDialCodeFromCountryLabel(countryLabel) {
        if (!countryLabel) {
            return;
        }
        const k = countryLabel.toLowerCase().trim();
        const dialByCountry = {
            india: '+91',
            'united states': '+1',
            usa: '+1',
            'united arab emirates': '+971',
            uae: '+971',
            singapore: '+65',
            'united kingdom': '+44',
            uk: '+44',
            australia: '+61',
            canada: '+1',
            china: '+86',
            japan: '+81',
            germany: '+49',
            france: '+33',
            'saudi arabia': '+966',
            qatar: '+974',
            kuwait: '+965',
            oman: '+968',
            bahrain: '+973',
            nepal: '+977',
            bangladesh: '+880',
            'sri lanka': '+94',
            malaysia: '+60',
            thailand: '+66',
            'new zealand': '+64',
            ireland: '+353',
            'south africa': '+27'
        };
        const dial = dialByCountry[k];
        if (dial) {
            this.countryCode = dial;
        }
    }

    async handleCountryChange(event) {
        this.selectedCountry = event.detail.value;
        this.selectedState = '';
        this.selectedCity = '';
        this.stateOptions = [];
        this.cityOptions = [];
        this.stdCodeOptions = [];
        this.stdCode = '';
        this.clearError();

        if (this.selectedCountry) {
            const dial = this.countryDialMap[this.selectedCountry];
            if (dial) {
                this.countryCode = dial;
            }
            this.loadStatesForCountryId(this.selectedCountry);
            this.loadStdCodes(this.selectedCountry);
        }
    }

    async handleStateChange(event) {
        this.selectedState = event.detail.value;
        this.selectedCity = '';
        this.cityOptions = [];
        // this.stdCodeOptions = [];
        // this.stdCode = '';

        this.clearError();

        if (this.selectedState) {
            try {
                const cities = await getCitiesByState({ stateId: this.selectedState });

                this.cityOptions = cities.map(c => ({
                    label: c.label,
                    value: c.value,
                    stdCode: c.stdCode
                }));
            } catch (error) {
                console.error('Error loading cities:', error);
            }
        }
    }

    handleCityChange(event) {
        this.selectedCity = event.detail.value;
        this.clearError();

        const selected = this.cityOptions.find(c => c.value === this.selectedCity);

        if (selected?.stdCode) {
            const codes = selected.stdCode.split(';');

            this.stdCodeOptions = codes.map(code => ({
                label: code.trim(),
                value: code.trim()
            }));

            this.stdCode = codes[0].trim();
        }
    }

    handleProgramSearch(event) {
        const searchTerm = event.target.value;
        this.programSearchTerm = searchTerm;

        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }

        if (searchTerm && searchTerm.length >= 2) {
            this.showProgramSearchResults = true;
            this.isSearching = true;

            this.searchTimeout = setTimeout(() => {
                this.performProgramSearch(searchTerm);
            }, 300);
        } else {
            this.showProgramSearchResults = false;
            this.programSearchResults = [];
        }
    }

    async performProgramSearch(searchTerm) {
        try {
            const results = await searchPrograms({ searchTerm: searchTerm });
            const selectedIds = this.selectedProgramIds;
            this.programSearchResults = results.filter(p => !selectedIds.includes(p.value));
            this.isSearching = false;
        } catch (error) {
            console.error('Error searching programs:', error);
            this.programSearchResults = [];
            this.isSearching = false;
        }
    }

    handleAddProgram(event) {
        const programId = event.currentTarget.dataset.id;
        const programName = event.currentTarget.dataset.name;

        if (!this.selectedProgramIds.includes(programId)) {
            this.selectedProgramsList = [
                ...this.selectedProgramsList,
                { id: programId, name: programName }
            ];
        }

        this.programSearchTerm = '';
        this.programSearchResults = [];
        this.showProgramSearchResults = false;
        this.clearError();
    }

    handleRemoveProgram(event) {
        const programId = event.currentTarget.dataset.id;
        this.selectedProgramsList = this.selectedProgramsList.filter(p => p.id !== programId);
        this.clearError();
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
    }

    handleBack() {
    if (this.isDetailsStep) {
        this.resetComponentState();
        this.step = 'init';
        return;
    }
    this.handleCancel();
}

resetComponentState() {
    // Navigation / Scenario
    this.initStepLockedEmail = false;
    this.initStepLockedMobile = false;
    this.initStepLockedPhone = false;
    this.initStepLockedCountryCode = false;

    this.existingLeadId = null;
    this.selectedMergeRecord = null;
    this.scenario = 'CREATE_LEAD';
    this.checkResult = null;

    // Reporting
    this.reportingToAccountId = null;
    this.reportingToExcludeContactId = null;
    this.reportsToId = '';
    this.reportingToContactRows = [];

    // Contact
    this.firstName = '';
    this.lastName = '';
    this.email = '';
    this.phone = '';
    this.mobilePhone = '';
    this.countryCode = '+91';
    this.title = '';
    this.department = '';
    this.linkedIn = '';

    // Company
    this.company = '';
    this.companyEmail = '';
    this.companyPhone = '';
    this.companyLinkedIn = '';

    // Address
    this.website = '';
    this.street = '';
    this.selectedCountry = '';
    this.selectedState = '';
    this.selectedCity = '';
    this.postalCode = '';

    this.countryOptions = this.countryOptions; // keep loaded options
    this.stateOptions = [];
    this.cityOptions = [];
    this.stdCodeOptions = [];
    this.stdCode = '';

    // Lead
    this.leadSource = '';
    this.leadRemark = '';
    this.description = '';
    this.isMouContractRequired = false;

    // Programs
    this.programSearchTerm = '';
    this.programSearchResults = [];
    this.selectedProgramsList = [];
    this.showProgramSearchResults = false;
    this.isSearching = false;

    // Company search
    this.companyMatchLeads = [];
    this.companyMatchAccounts = [];
    this.showCompanyMatchDropdown = false;
    this.isCompanyMatchSearching = false;
    this.tryApplyIndiaAsDefaultCountry();
    // Misc
    this.errorMessage = '';
    this.clearError();
}
    async applyCheckResultPrefill() {
        const r = this.checkResult;
        if (!r) {
            return;
        }
        if (r.accountExists) {
            console.log('Acc is ' + JSON.stringify(r))
            this.companyEmail = r.accountEmail ? r.accountEmail : ''
            this.companyLinkedIn = r.accountLinkedIn ? r.accountLinkedIn : ''
            this.companyPhone = r.accountPhone ? r.accountPhone : ''
            if (r.accountWebsite) {
                this.website = r.accountWebsite;
            }
           
            if(this.countryOptions?.length){
              const country = this.countryOptions.find(
                c => c.label === r.accountBillingCountry
                );
            this.selectedCountry = country ? country.value : '';
              
            }
            

            // Load states
            const states = await getStatesByCountry({
                countryId: this.selectedCountry
            });

            this.stateOptions = states.map(s => ({
                label: s.label,
                value: s.value
            }));

            const state = this.stateOptions.find(
                s => s.label === r.accountBillingState
            );

            this.selectedState = state ? state.value : '';

            // Load cities
            const cities = await getCitiesByState({
                stateId: this.selectedState
            });

            this.cityOptions = cities.map(c => ({
                label: c.label,
                value: c.value,
                stdCode: c.stdCode
            }));

            const city = this.cityOptions.find(
                c => c.label === r.accountBillingCity
            );

            this.selectedCity = city ? city.value : '';

            this.street = r.accountBillingStreet || ''




            if (r.accountBillingPostalCode) {
                this.postalCode = r.accountBillingPostalCode;
            }
        }
        if (r.contactExists) {
            this.firstName = r.contactFirstName || '';
            this.lastName = r.contactLastName || '';
            this.title = r.contactTitle || '';
            this.department = r.contactDepartment || '';
            this.reportsToId = r.contactReportsToId || '';
            const storedPhone = r.contactPhone || '';
            this.setPhoneFromStoredValue(storedPhone);
            const storedMobile = r.contactMobilePhone || '';
            this.setMobileFromStoredValue(storedMobile);
        } else {
            this.firstName = '';
            this.lastName = '';
            this.title = '';
            this.department = '';
            this.linkedIn = '';
            this.reportsToId = '';
        }
    }

    getCombinedPhone() {
        const num = (this.phone || '').trim();
        if (!num) return null;

        const code = (this.stdCode || '').trim();

        return code ? `${code} ${num}` : num;
    }

    getCombinedMobile() {
        const num = (this.mobilePhone || '').trim();
        if (!num) {
            return null;
        }
        const code = (this.countryCode || '').trim();
        const parts = [];
        if (code) {
            parts.push(code);
        }
        parts.push(num);
        return parts.join(' ').trim();
    }

    /** Resolve master picklist Id to display name for Lead / Contact address text fields. */
    getOptionLabel(options, value) {
        if (!value) {
            return '';
        }
        const row = (options || []).find((o) => o.value === value);
        return row && row.label ? row.label : '';
    }

    setPhoneFromStoredValue(stored) {
        const value = (stored || '').trim();
        if (!value) {
            this.phone = '';
            return;
        }
        const parts = value.split(' ');

        if (parts.length > 1) {
            this.stdCode = parts[0];
            this.phone = parts.slice(1).join(' ');
        } else {
            this.phone = value;
        }
    }

    setMobileFromStoredValue(stored) {
        const value = (stored || '').trim();
        if (!value) {
            this.mobilePhone = '';
            return;
        }
        const current = (this.countryCode || '').trim();
        if (current && (value.startsWith(`${current} `) || value === current)) {
            this.mobilePhone = value.replace(current, '').trim();
            return;
        }
        const match = this.countryCodeOptions.find(
            (opt) => value.startsWith(`${opt.value} `) || value === opt.value
        );
        if (match) {
            this.countryCode = match.value;
            this.mobilePhone = value.replace(match.value, '').trim();
        } else {
            this.mobilePhone = value;
        }
    }

    get backButtonLabel() {
        return this.isDetailsStep ? 'Back' : 'Cancel';
    }

    async handleSave() {
        const firstNameVal = (this.firstName || '').trim();
        const lastNameVal = (this.lastName || '').trim();
        const lastNameForSave = lastNameVal;
        const emailVal = (this.email || '').trim();
        const companyVal = (this.company || '').trim();
        const designationVal = (this.title || '').trim();
        const contactCountryLabel = this.getOptionLabel(this.countryOptions, this.selectedCountry);
        const contactStateLabel = this.getOptionLabel(this.stateOptions, this.selectedState);
        const contactCityLabel = this.getOptionLabel(this.cityOptions, this.selectedCity);
        const eventRemarks = (this.leadRemark || '').trim()
        const validationErrors = [];
        const companyEmail = (this.companyEmail || '').trim()
        const companyPhoneInput = this.template.querySelector('lightning-input[data-field="companyPhone"]');
        const companyLinkedIn = (this.companyLinkedIn || '').trim()
        const isValidCompanyPhone = companyPhoneInput.reportValidity()
        if (!isValidCompanyPhone) {
            validationErrors.push('Phone number can only contain digits. No letters, spaces, or special characters allowed.');
        }
        const companyPhone = (this.companyPhone || '').trim()
        if (!firstNameVal) {
            validationErrors.push('First Name is required.');
        }

        if (!lastNameVal) {
            validationErrors.push('Last Name is required.');
        }

        if (!designationVal) {
            validationErrors.push('Designation is required.');
        }

        const deptCmp = this.template.querySelector('.deptLookupField');

        if (!this.department && deptCmp) {
            const val = deptCmp.value;
            this.department = Array.isArray(val) ? val[0] : val;
        }

        const departmentVal = this.department || null;



        console.log('Dept Val is ', departmentVal)
        if (this.scenario !== 'CREATE_OPPORTUNITY_ONLY') {
            if (!this.selectedCountry || !contactCountryLabel) {
                validationErrors.push('Country is required.');
            }

            if (!this.selectedState || !contactStateLabel) {
                validationErrors.push('State is required.');
            }

            if (!this.selectedCity || !contactCityLabel) {
                validationErrors.push('City is required.');
            }
        }

        const mobileCombined = this.getCombinedMobile();
        const phoneForSave = this.getCombinedPhone();
        const hasAnyContact = !!emailVal || !!mobileCombined || !!phoneForSave;
        if (!hasAnyContact) {
            validationErrors.push('Provide at least one of Email, Mobile, or Phone.');
        }
        if (emailVal && !this.isValidEmail(emailVal)) {
            validationErrors.push('Please enter a valid email address.');
        }

        if (!companyVal) {
            validationErrors.push('Company is required.');
        }

        if (!(this.leadSource || '').trim()) {
            validationErrors.push('Lead Source is required.');
        }

        if (this.selectedProgramsList.length === 0) {
            validationErrors.push('Please select at least one program.');
        }
        if (!this.validateMobileLength()) {
            validationErrors.push(this.errorMessage)
        }

        if (validationErrors.length > 0) {
            this.errorMessage = validationErrors.join(' ');
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: validationErrors.join(' '),
                    variant: 'error'
                })
            );
            return;
        }

        try {
            this.isSaving = true;
            this.errorMessage = '';

            const phoneCombined = this.getCombinedPhone();
            const reportsToIdForSave = this.reportsToId ? this.reportsToId : null;
            const mobileForSave = mobileCombined || null;

            let saveResult;
            if (this.scenario === 'MERGE_EXISTING_LEAD' && this.existingLeadId) {
                const leadContacts = await checkLeadContacts({
                    leadId: this.existingLeadId, email: emailVal,
                    fname: firstNameVal, lname: lastNameForSave
                });
                if (leadContacts) {


                    if (leadContacts?.length) {

                        const contactDetails = leadContacts
                            .map(c =>
                                `${c.Name || ''} ${c.Last_Name__c || ''}`.trim() +
                                (c.Email__c ? ` (${c.Email__c})` : '')
                            )
                            .join('\n');

                        const proceed = await LightningConfirm.open({
                            message:
                                `The following contact(s) already exist under this lead:\n\n${contactDetails}\n\nDo you want to continue?`,
                            variant: 'header',
                            label: 'Existing Contact Found'
                        });

                        if (!proceed) {
                            return;
                        }
                    }
                }
                console.log('Scenario is ', this.scenario, ' Id is ', this.existingLeadId.trim())
                saveResult = await mergeB2BLeadWithPrograms({
                    request: {
                        leadId: this.existingLeadId.trim(),
                        lastName: lastNameForSave,
                        firstName: firstNameVal || null,
                        company: companyVal,
                        companyLinkedIn: companyLinkedIn,
                        companyPhone: companyPhone,
                        companyEmail: companyEmail,
                        email: emailVal,
                        phone: phoneCombined,
                        mobilePhone: mobileForSave,
                        designation: designationVal || null,
                        department: departmentVal,
                        linkedIn: this.linkedIn ? this.linkedIn.trim() : null,
                        contactCountry: contactCountryLabel || null,
                        contactState: contactStateLabel || null,
                        contactCity: contactCityLabel || null,
                        industry: null,
                        website: this.website ? this.website.trim() : null,
                        numberOfEmployees: null,
                        annualRevenue: null,
                        street: this.street ? this.street.trim() : null,
                        city: null,
                        state: null,
                        postalCode: this.postalCode ? this.postalCode.trim() : null,
                        country: null,
                        description: this.description || null,
                        leadSource: this.leadSource || null,
                        programIds: this.selectedProgramIds,
                        eventRemarks: eventRemarks
                    }
                });
            } else if (this.scenario === 'CREATE_CONTACT_AND_OPPORTUNITY') {
                saveResult = await createContactAndOpportunity({
                    accountId: this.checkResult?.accountId,
                    lastName: lastNameForSave,
                    firstName: firstNameVal || null,
                    email: emailVal,
                    phone: phoneCombined,
                    mobilePhone: mobileForSave,
                    title: designationVal || null,
                    department: departmentVal,
                    linkedIn: this.linkedIn ? this.linkedIn.trim() : null,
                    contactCountry: contactCountryLabel || null,
                    contactState: contactStateLabel || null,
                    contactCity: contactCityLabel || null,
                    reportsToId: reportsToIdForSave,
                    leadSource: this.leadSource || null,
                    isMouContractRequired: false,
                    opportunityName: this.company ? `${this.company} - Opportunity` : null,
                    opportunityAmount: null,
                    closeDate: null,
                    stage: 'Prospecting',
                    minNumberOfStudents: null,
                    maxNumberOfStudents: null,
                    programIds: this.selectedProgramIds
                });
            } else if (this.scenario === 'CREATE_OPPORTUNITY_ONLY') {
                saveResult = await createOpportunityOnly({
                    accountId: this.checkResult?.accountId,
                    contactId: this.checkResult?.contactId,
                    leadSource: this.leadSource || null,
                    isMouContractRequired: this.isMouContractRequired === true,
                    opportunityName: this.company ? `${this.company} - Opportunity` : null,
                    opportunityAmount: null,
                    closeDate: null,
                    stage: 'Prospecting',
                    minNumberOfStudents: null,
                    maxNumberOfStudents: null,
                    programIds: this.selectedProgramIds,
                    reportsToId: reportsToIdForSave,
                    department: departmentVal
                });
            } else {

                saveResult = await createLead({
                    req: {
                        lastName: lastNameForSave,
                        firstName: firstNameVal || null,
                        company: companyVal,
                        companyLinkedIn: companyLinkedIn,
                        companyPhone: companyPhone,
                        companyEmail: companyEmail,
                        email: emailVal,
                        phone: phoneCombined,
                        mobilePhone: mobileForSave,
                        title: designationVal || null,
                        department: departmentVal,
                        linkedIn: this.linkedIn ? this.linkedIn.trim() : null,
                        contactCountry: contactCountryLabel || null,
                        contactState: contactStateLabel || null,
                        contactCity: contactCityLabel || null,
                        industry: null,
                        website: this.website ? this.website.trim() : null,
                        numberOfEmployees: null,
                        annualRevenue: null,
                        street: this.street ? this.street.trim() : null,
                        city: null,
                        state: null,
                        postalCode: this.postalCode ? this.postalCode.trim() : null,
                        country: null,
                        description: this.description || null,
                        leadSource: this.leadSource || null,
                        isPrimary: 'true',
                        programIds: this.selectedProgramIds,
                        eventRemarks: eventRemarks
                    }
                });
            }

            if (!saveResult || saveResult.success === false) {
                const failMsg = saveResult?.message || 'Save did not complete.';
                this.errorMessage = failMsg;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: failMsg,
                        variant: 'error'
                    })
                );
                return;
            }

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: saveResult?.message || 'B2B process completed successfully.',
                    variant: 'success'
                })
            );

            this.dispatchEvent(
                new CustomEvent('success', {
                    detail: { recordId: saveResult?.recordId },
                    bubbles: true,
                    composed: true
                })
            );

        } catch (error) {
            console.error('Error:', error);

            let errorMsg = 'Unknown error occurred.';

            if (error.body && error.body.message) {
                errorMsg = error.body.message;
            } else if (error.message) {
                errorMsg = error.message;
            }

            this.errorMessage = errorMsg;

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: errorMsg,
                    variant: 'error'
                })
            );

        } finally {
            this.isSaving = false;
        }
    }

    isValidEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }
}