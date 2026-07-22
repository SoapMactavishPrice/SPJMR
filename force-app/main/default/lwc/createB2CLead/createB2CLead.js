import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getCountries from '@salesforce/apex/B2CLeadController.getCountries';
import getStatesByCountry from '@salesforce/apex/B2CLeadController.getStatesByCountry';
import getCitiesByState from '@salesforce/apex/B2CLeadController.getCitiesByState';
import searchPrograms from '@salesforce/apex/B2CLeadController.searchPrograms';
import getLeadSourceOptions from '@salesforce/apex/B2CLeadController.getLeadSourceOptions';
import getCampaignsByLeadSource from '@salesforce/apex/B2CLeadController.getCampaignsByLeadSource';
import getEntranceExamOptions from '@salesforce/apex/B2CLeadController.getEntranceExamOptions';
import createB2CLead from '@salesforce/apex/B2CLeadController.createB2CLead';
import checkExistingLead from '@salesforce/apex/B2CLeadController.checkExistingLead';
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import LEAD_OBJECT from "@salesforce/schema/Lead";
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import GENDER_FIELD from '@salesforce/schema/Lead.GenderIdentity';


export default class CreateB2CLead extends NavigationMixin(LightningElement) {
    @track step = 'init';
    @track firstName = '';
    @track lastName = '';
    @track email = '';
    @track phone = '';
    @track street = '';
    @track selectedCountry = '';
    @track selectedState = '';
    @track selectedCity = '';
    @track postalCode = '';
    @track dateOfBirth = null;
    @track age = '';
    @track hasWorkExperience = 'No';
    @track yearsOfWorkExperience = '';
    @track hasEntranceExam = 'No';
    @track entranceExamName = '';
    @track leadSource = '';
    /** Maps to Lead.Other__c when Lead Source is Others. */
    @track leadSourceOther = '';
    /** API value of Lead.LeadSource default from field metadata (org/profile aware). */
    leadSourceSchemaDefault = '';
    @track areYouNri = false;
    @track countryCode = '+91';

    @track isSaving = false;
    @track errorMessage = '';
    leadGender = ''
    @track countryOptions = [];
    @track stateOptions = [];
    @track cityOptions = [];
    @track leadSourceOptions = [];
    @track entranceExamOptions = [];

    /** Drives @wire for campaigns; kept in sync with Lead Source on the details step. */
    @track leadSourceForCampaignQuery = '';
    @track campaignOptions = [];
    @track selectedCampaignId = '';
    genderOptions = []
    @track programSearchTerm = '';
    @track programSearchResults = [];
    @track selectedProgramsList = [];
    @track showProgramSearchResults = false;
    @track isSearching = false;
    @track existingLeadId = null;
    @track existingApplicantAccountId = null;
    @track hasApplicantAccount = false;
    @track isCheckingLead = false;
    @track isPrefilled = false;
    @track acceptedNumberLength = null;
    searchTimeout;
    emailCheckTimeout;
    organizationName = '';
    graduation = 'Yes';
    studyingIn = '';
    partnerCompany = 'No';
    selectedEvent = '';
    partnerName = '';
    howDidYouKnow = '';
    eventCountry = '';
    eventState = '';
    eventCity = '';
    eventCountryId='';
    eventStateId='';
    eventCityId='';
    @track eventStateOptions = [];
    @track eventCityOptions = [];
    studyingInOptions = [
        { label: 'UG', value: 'UG' },
        { label: 'PG', value: 'PG' },
        { label: 'Diploma', value: 'Diploma' }
    ]
    yesNoOptions = [
        { label: 'Yes', value: 'Yes' },
        { label: 'No', value: 'No' }
    ];

    @track objectInfo;

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    objectInfo;

    get recordTypeId() {
        if (!this.objectInfo?.data) {
            return null;
        }
        const rtis = this.objectInfo.data.recordTypeInfos;
        return Object.keys(rtis).find((rti) => rtis[rti].name === "B2C");
    }

    @wire(getPicklistValues, {
        recordTypeId: '$recordTypeId',
        fieldApiName: GENDER_FIELD
    })
    wiredGender({ error, data }) {
        if (data) {
            this.genderOptions = data.values
        }
        else if (error) {
            console.log('Error Fetching Gender!')
        }
    }

    eventOptions = [{ label: "SPJIMR Open House", value: "SPJIMR Open House" },
    { label: "SEED Event", value: "SEED Event" }, { label: "GMAC Tour", value: "GMAC Tour" },
    { label: "Jamboree Event", value: "Jamboree Event" }, { label: "Partner Event", value: "Partner Event" },
    { label: "Education Fair / B-School Fair", value: "Education Fair / B-School Fair" },
    { label: "Partner Webinar", value: "Partner Webinar" }, { label: "Access MBA Event", value: "Access MBA Event" },
    { label: "IMS Webinar", value: "IMS Webinar" }, { label: "PGDM Exhibition", value: "PGDM Exhibition" }
    ]

    countryCodeOptions = [
        { label: 'IN +91', value: '+91' },
        { label: 'US +1', value: '+1' },
        { label: 'AE +971', value: '+971' },
        { label: 'SG +65', value: '+65' },
        { label: 'GB +44', value: '+44' }
    ];
    countryMetadataMap = {};
    @wire(getCountries)
    wiredCountries({ error, data }) {
        if (data) {
            this.countryOptions = data.map(c => ({
                label: c.label,
                value: c.value
            }));

            this.countryCodeOptions = data
                .filter(c => c.countryCode)
                .map(c => ({
                    label: `${c.countryCode} ${c.label}`,
                    value: c.countryCode
                }));
            data.forEach(c => {
                this.countryMetadataMap[c.value] = {
                    countryCode: c.countryCode,
                    acceptedLength: c.acceptedLength
                };
            });
            this.acceptedNumberLength =
    this.getAcceptedLengthByCode(this.countryCode);
        } else if (error) {
            console.error('Error loading countries:', error);
        }
    }

    @wire(getLeadSourceOptions)
    wiredLeadSource({ error, data }) {
        if (data) {
            const rawOptions = Array.isArray(data)
                ? data
                : Array.isArray(data.options)
                    ? data.options
                    : [];
            const def =
                data != null &&
                    !Array.isArray(data) &&
                    data.defaultValue != null &&
                    String(data.defaultValue).trim() !== ''
                    ? String(data.defaultValue).trim()
                    : '';
            this.leadSourceSchemaDefault = def;
            this.leadSourceOptions = rawOptions.map(opt => ({
                label: opt.label,
                value: opt.value
            }));
            this.applyLeadSourceDefaultIfBlank();
        } else if (error) {
            console.error('Error loading lead source options:', error);
        }
    }

    /** Apply org picklist default when value is still empty (handles wire vs. prefill order). */
    applyLeadSourceDefaultIfBlank() {
        const current = this.leadSource != null ? String(this.leadSource).trim() : '';
        if (current !== '') {
            return;
        }
        const d = this.leadSourceSchemaDefault;
        if (!d) {
            return;
        }
        for (let i = 0; i < this.leadSourceOptions.length; i++) {
            if (this.leadSourceOptions[i].value === d) {
                this.leadSource = d;
                return;
            }
        }
    }



    @wire(getCampaignsByLeadSource, { leadSource: '$leadSourceForCampaignQuery' })
    wiredCampaigns({ error, data }) {
        if (data) {
            console.log('Fetched Data ', JSON.stringify(data))
            this.campaignOptions = data.map((row) => ({
                label: row.label,
                value: row.value
            }));
            if (
                this.selectedCampaignId &&
                !this.campaignOptions.some((o) => o.value === this.selectedCampaignId)
            ) {
                this.selectedCampaignId = '';
            }
        } else if (error) {
            this.campaignOptions = [];
            console.error('Error loading campaigns:', error);
        }
    }

    renderedCallback() {
        if (this.step === 'details' && this.leadSourceOptions.length > 0) {
            this.applyLeadSourceDefaultIfBlank();
        }
        if (this.step === 'details') {
            const q = this.leadSource ? String(this.leadSource).trim() : '';
            if (q !== this.leadSourceForCampaignQuery) {

                console.log('Lead Source is ', this.leadSource, ' q is ', q)
                this.leadSourceForCampaignQuery = q;
                console.log('Setting Campaign Source as ', this.leadSourceForCampaignQuery)
            }
        }
    }

    @wire(getEntranceExamOptions)
    wiredEntranceExam({ error, data }) {
        if (data) {
            this.entranceExamOptions = data.map(opt => ({
                label: opt.label,
                value: opt.value
            }));
        } else if (error) {
            console.error('Error loading entrance exam options:', error);
        }
    }

    getAcceptedLengthByCode(code) {
        const entry = Object.values(this.countryMetadataMap).find(
            item => item.countryCode === code
        );

        return Number(entry?.acceptedLength) || 10;
    }

    get showEventPicklist() {
        return this.leadSource == 'Events';
    }
    get isEventStateDisabled() {
        return !this.eventCountry;
    }

    get isEventCityDisabled() {
        return !this.eventState;
    }
    get showStudyingIn() {
        return this.graduation == 'No'
    }
    get showOrganizationField() {
        return this.partnerCompany == 'Yes'
    }
    get isStateDisabled() {
        return !this.selectedCountry;
    }

    get isCityDisabled() {
        return !this.selectedState;
    }

    get showWorkExperienceYears() {
        return this.hasWorkExperience === 'Yes';
    }

    get showEntranceExamName() {
        return this.hasEntranceExam === 'Yes';
    }

    get showPartnerEventInput() {
        return this.selectedEvent === 'Partner Webinar' ||
            this.selectedEvent === 'Partner Event';
    }

    get showLeadSourceOther() {
        const v = this.leadSource != null ? String(this.leadSource).trim() : '';
        return v === 'Others' || v === 'Other';
    }

    get showCampaignPicker() {
        return this.isDetailsStep && (this.leadSource || '').trim() !== '';
    }

    get hasCampaignPickerEmptyMessage() {
        return this.showCampaignPicker && this.campaignOptions.length === 0;
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

    handleFieldChange(event) {
        const host = event.currentTarget || event.target;
        const field = host && host.dataset ? host.dataset.field : null;
        if (field) {
            const fromDetail = event.detail && Object.prototype.hasOwnProperty.call(event.detail, 'value');
            const newVal = fromDetail ? event.detail.value : event.target.value;
            this[field] = newVal;
            if (field === 'leadSource') {
                 const v = newVal ? String(newVal).trim() : '';
                if (v !== 'Others' && v !== 'Other') {
                    this.leadSourceOther = '';
                }
                this.selectedCampaignId = '';
               

                if (v === 'Events' && !this.eventCountryId) {
                    const india = this.countryOptions.find(
                        c => c.label === 'India'
                    );

                    if (india) {
                        this.handleEventCountryChange({
                            detail: { value: india.value }
                        });
                    }
                }

                if (v !== 'Events') {
                    this.eventCountry = '';
                    this.eventState = '';
                    this.eventCity = '';
                    this.eventStateOptions = [];
                    this.eventCityOptions = [];
                }
            }


        }
        this.clearError();
    }

    handleHowDidYouKnow(event) {
        this.howDidYouKnow = event.target.value
    }

    handleEventChange(event) {
        this.selectedEvent = event.detail.value;

        // Optional: Clear the value when switching away
        if (!this.showPartnerEventInput) {
            this.partnerName = '';
        }
    }

    handlePartnerNameChange(event) {
        this.partnerName = event.target.value;
    }

    handleCampaignChange(event) {
        this.selectedCampaignId = event.detail.value || '';
        this.clearError();
    }

    handleAreYouNriChange(event) {
        this.areYouNri = event.target.checked === true;
        this.clearError();
    }

    async handleEventCountryChange(event) {
       
        const countryId = event.detail.value
        this.eventState = '';
        this.eventCity = '';
        this.eventCountryId = countryId;
        this.eventStateId = ''
        this.eventCityId = ''
        this.eventStateOptions = [];
        this.eventCityOptions = [];
        const selectedCountry = this.countryOptions.find(
        option => option.value === countryId
    );

    this.eventCountry = selectedCountry ? selectedCountry.label : '';

        if (countryId) {
            const states = await getStatesByCountry({
                countryId: countryId
            });

            this.eventStateOptions = states.map(s => ({
                label: s.label,
                value: s.value
            }));
        }
    }

    async handleEventStateChange(event) {
        
        const stateId = event.detail.value
        this.eventCity = '';
        this.eventStateId = stateId;
        this.eventCityOptions = [];
        const selectedState = this.eventStateOptions.find(
        option => option.value === stateId
    );

    this.eventState = selectedState ? selectedState.label : '';
        if (stateId) {
            const cities = await getCitiesByState({
                stateId: stateId
            });

            this.eventCityOptions = cities.map(c => ({
                label: c.label,
                value: c.value
            }));
        }
    }
    handleEventCityChange(event) {
         const cityId = event.detail.value;

    const selectedCity = this.eventCityOptions.find(
        option => option.value === cityId
    );
    this.eventCityId = cityId;

    this.eventCity = selectedCity ? selectedCity.label : '';
    }

    async handleInitialNext() {
        const emailVal = (this.email || '').trim();
        const phoneVal = (this.phone || '').trim();
        if (!phoneVal) {
            this.errorMessage = 'Phone is required.';
            return;
        }
        if (!emailVal) {
            this.errorMessage = 'Email is required.'
            return;
        }

        if (phoneVal && !this.isValidPhone(phoneVal)) {
            this.errorMessage = 'Please enter a valid phone number.'
            return;
        }
        if (emailVal && !this.isValidEmail(emailVal)) {
            this.errorMessage = 'Please enter a valid email address.';
            return;
        }
        const acceptedLength = this.getAcceptedLengthByCode(this.countryCode);

        if (
            phoneVal &&
            acceptedLength &&
            phoneVal.length !== acceptedLength
        ) {
            this.errorMessage = `Phone number must be ${acceptedLength} digits.`;
            return;
        }

        const matchedCountry = Object.keys(this.countryMetadataMap).find(
            countryId =>
                this.countryMetadataMap[countryId].countryCode === this.countryCode
        );

        if (matchedCountry) {
            this.selectedCountry = matchedCountry;
            await this.loadStates();
        }
        this.errorMessage = '';
        await this.checkForExistingLead(emailVal, this.getCombinedPhone());
        this.step = 'details';
    }

    async checkForExistingLead(email, phone) {
        const emailVal = (email || '').trim();
        const phoneVal = (phone || '').trim();
        if (!emailVal && !phoneVal) {
            return;
        }
        if (emailVal && !this.isValidEmail(emailVal)) {
            return;
        }

        if (this.emailCheckTimeout) {
            clearTimeout(this.emailCheckTimeout);
        }

        this.emailCheckTimeout = setTimeout(async () => {
            try {
                this.isCheckingLead = true;
                console.log('Checking existing lead for email:', emailVal, 'phone:', phoneVal);
                const result = await checkExistingLead({ email: emailVal, phone: phoneVal });
                console.log('checkExistingLead result:', JSON.stringify(result));

                this.existingLeadId = null;
                this.existingApplicantAccountId = null;
                this.hasApplicantAccount = false;
                this.isPrefilled = false;

                if (result.hasUnconvertedLead && result.lead) {
                    console.log('Found unconverted lead:', result.lead);
                    this.existingLeadId = result.leadId;
                    this.prefillForm(result.lead, result.existingPrograms || []);
                }

                if (result.hasApplicantAccount && result.account) {
                    console.log('Found existing account:', result.account);
                    this.hasApplicantAccount = true;
                    this.existingApplicantAccountId = result.accountId;
                    if (!result.hasUnconvertedLead) {
                        this.prefillFromAccount(result.account);
                    }
                }
            } catch (error) {
                console.error('Error checking existing lead:', error);
            } finally {
                this.isCheckingLead = false;
            }
        }, 250);
    }

    prefillForm(lead, existingPrograms) {
        // Don't overwrite email as it's what triggered the check
        this.firstName = lead.FirstName || '';
        this.lastName = lead.LastName || '';
        this.phone = lead.Phone || '';
        this.street = lead.Street || '';
        this.postalCode = lead.PostalCode || '';
        this.dateOfBirth = lead.Date_Of_Birth__c || null;
        this.age = lead.XS_Age__c || '';
        this.yearsOfWorkExperience = lead.XS_YearsOfWorkExperience__c || '';
        this.leadSource =
            (lead.LeadSource && String(lead.LeadSource).trim()) ? lead.LeadSource : (this.leadSourceSchemaDefault || '');
        this.leadSourceOther = lead.Other__c || '';
        this.selectedCampaignId = '';
        this.areYouNri = lead.Are_you_NRI__c === true;
        this.leadGender = lead.GenderIdentity;
        this.hasWorkExperience =
            lead.XS_YearsOfWorkExperience__c ? 'Yes' : 'No';

        this.yearsOfWorkExperience =
            lead.XS_YearsOfWorkExperience__c;

        this.hasEntranceExam =
            lead.XS_DoYouHaveEntranceExamScore__c ? 'Yes' : 'No';

        this.entranceExamName =
            lead.entranceExam;

        this.partnerCompany = lead.XS_SPJIMR_PartnerCompany__c ? 'Yes' : 'No';
        this.organizationName = lead.XS_SPJIMR_PartnerCompany__c;

        this.graduation = lead.XS_HaveYouCompletedYourGraduation__c;
        this.studyingIn = lead.XS_CurrentlyStudingIn__c;
        this.setPhoneFromStoredValue(lead.Phone);

        // Set work experience
        if (lead.XS_YearsOfWorkExperience__c && String(lead.XS_YearsOfWorkExperience__c).trim() !== '') {
            this.hasWorkExperience = 'Yes';
        } else {
            this.hasWorkExperience = 'No';
        }

        // Set entrance exam
        if (lead.XS_DoYouHaveEntranceExamScore__c === 'Yes') {
            this.hasEntranceExam = 'Yes';
            this.entranceExamName = lead.XS_EntranceExamName__c || '';
        } else {
            this.hasEntranceExam = 'No';
            this.entranceExamName = '';
        }

        // Set address fields
        if (lead.Country_Master_backend__c) {
            this.selectedCountry = lead.Country_Master_backend__c;
            this.loadStates().then(() => {
                if (lead.State_Master__c) {
                    this.selectedState = lead.State_Master__c;
                    this.loadCities().then(() => {
                        if (lead.District_City__c) {
                            this.selectedCity = lead.District_City__c;
                        }
                    });
                }
            });
        }

        // Prefill selected programs
        if (existingPrograms && existingPrograms.length > 0) {
            this.selectedProgramsList = existingPrograms.map(prog => ({
                id: prog.id,
                name: prog.name
            }));
        }

        this.isPrefilled = true;
    }

    prefillFromAccount(account) {
        console.log('prefillFromAccount called with:', JSON.stringify(account));

        this.firstName = account.FirstName || '';
        this.lastName = account.LastName || '';

        // Phone - try PersonMobilePhone first, then Phone
        const phoneValue = account.PersonMobilePhone || account.Phone || '';
        console.log('Phone value from account:', phoneValue);
        if (phoneValue) {
            this.setPhoneFromStoredValue(phoneValue);
        }

        // Street - try PersonMailingStreet first, then BillingStreet
        this.street = account.PersonMailingStreet || account.BillingStreet || '';
        this.postalCode = account.PersonMailingPostalCode || account.BillingPostalCode || '';
        this.leadGender = account.PersonGenderIdentity;
        // Use custom fields from Account for address lookups
        console.log('Country_Master__c:', account.Country_Master__c);
        if (account.Country_Master__c) {
            this.selectedCountry = account.Country_Master__c;
            this.loadStates().then(() => {
                if (account.State_Master__c) {
                    this.selectedState = account.State_Master__c;
                    this.loadCities().then(() => {
                        if (account.District_City__c) {
                            this.selectedCity = account.District_City__c;
                        }
                    });
                }
            });
        }

        // Date of Birth - prefer custom field, fallback to PersonBirthdate
        console.log('Date_Of_Birth__c:', account.Date_Of_Birth__c);
        console.log('PersonBirthdate:', account.PersonBirthdate);
        const dobValue = account.Date_Of_Birth__c || account.PersonBirthdate;
        if (dobValue) {
            this.dateOfBirth = dobValue;
            this.calculateAge();
        }

        // Years of Work Experience
        if (account.Years_Of_Work_Experience__c != null && account.Years_Of_Work_Experience__c > 0) {
            this.hasWorkExperience = 'Yes';
            this.yearsOfWorkExperience = String(account.Years_Of_Work_Experience__c);
        } else {
            this.hasWorkExperience = 'No';
            this.yearsOfWorkExperience = '';
        }

        // Entrance Exam
        if (account.Has_Entrance_Exam_Score__c === 'Yes') {
            this.hasEntranceExam = 'Yes';
            this.entranceExamName = account.Entrance_Exam_Name__c || '';
        } else {
            this.hasEntranceExam = 'No';
            this.entranceExamName = '';
        }

        this.isPrefilled = true;
    }

    async loadStates() {
        if (this.selectedCountry) {
            try {
                const states = await getStatesByCountry({ countryId: this.selectedCountry });
                this.stateOptions = states.map(s => ({
                    label: s.label,
                    value: s.value
                }));
            } catch (error) {
                console.error('Error loading states:', error);
            }
        }
    }

    async loadCities() {
        if (this.selectedState) {
            try {
                const cities = await getCitiesByState({ stateId: this.selectedState });
                this.cityOptions = cities.map(c => ({
                    label: c.label,
                    value: c.value
                }));
            } catch (error) {
                console.error('Error loading cities:', error);
            }
        }
    }

    handleDateOfBirthChange(event) {
        this.dateOfBirth = event.target.value;
        this.calculateAge();
        this.clearError();
    }

    handleCountryCodeChange(event) {
        this.countryCode = event.detail.value;
        this.phone = ''
         this.acceptedNumberLength =this.getAcceptedLengthByCode(this.countryCode) || 10;
        this.clearError();
    }

    calculateAge() {
        if (this.dateOfBirth) {
            const today = new Date();
            const birthDate = new Date(this.dateOfBirth);
            let calculatedAge = today.getFullYear() - birthDate.getFullYear();
            const monthDiff = today.getMonth() - birthDate.getMonth();

            if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
                calculatedAge--;
            }

            this.age = calculatedAge >= 0 ? calculatedAge.toString() : '';
        }
    }

    async handleCountryChange(event) {
        this.selectedCountry = event.detail.value;
        this.selectedState = '';
        this.selectedCity = '';
        this.stateOptions = [];
        this.cityOptions = [];
        this.clearError();

        const metadata = this.countryMetadataMap[this.selectedCountry];

        if (metadata) {
            this.countryCode = metadata.countryCode || '';
            this.acceptedNumberLength = Number(metadata.acceptedLength) || 10;;
        }

        if (this.selectedCountry) {
            try {
                const states = await getStatesByCountry({ countryId: this.selectedCountry });
                this.stateOptions = states.map(s => ({
                    label: s.label,
                    value: s.value
                }));
            } catch (error) {
                console.error('Error loading states:', error);
            }
        }
    }

    async handleStateChange(event) {
        this.selectedState = event.detail.value;
        this.selectedCity = '';
        this.cityOptions = [];
        this.clearError();

        if (this.selectedState) {
            try {
                const cities = await getCitiesByState({ stateId: this.selectedState });
                this.cityOptions = cities.map(c => ({
                    label: c.label,
                    value: c.value
                }));
            } catch (error) {
                console.error('Error loading cities:', error);
            }
        }
    }

    handleCompletedGraduation(event) {
        this.graduation = event.detail.value
        if (this.graduation == 'Yes') {
            this.studyingIn = ''
        }
        this.clearError()
    }

    handlePartnerCompanyChange(event) {
        this.partnerCompany = event.detail.value;
        if (this.partnerCompany == 'No') {
            this.organizationName = ''
        }
        this.clearError();
    }
    handleCityChange(event) {
        this.selectedCity = event.detail.value;
        this.clearError();
    }

    handleWorkExperienceChange(event) {
        this.hasWorkExperience = event.detail.value;
        if (this.hasWorkExperience === 'No') {
            this.yearsOfWorkExperience = '';
        }
        this.clearError();
    }

    handleEntranceExamChange(event) {
        this.hasEntranceExam = event.detail.value;
        if (this.hasEntranceExam === 'No') {
            this.entranceExamName = '';
        }
        this.clearError();
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
    clearDetailsForm() {
        this.firstName = '';
        this.lastName = '';

        this.street = '';
        this.selectedCountry = '';
        this.selectedState = '';
        this.selectedCity = '';
        this.postalCode = '';

        this.dateOfBirth = null;
        this.age = '';

        this.hasWorkExperience = 'No';
        this.yearsOfWorkExperience = '';

        this.hasEntranceExam = 'No';
        this.entranceExamName = '';

        this.leadSource = '';
        this.leadSourceOther = '';

        this.selectedCampaignId = '';
        this.campaignOptions = [];
        this.leadSourceForCampaignQuery = '';

        this.areYouNri = false;
        this.leadGender = '';

        this.partnerCompany = 'No';
        this.organizationName = '';

        this.graduation = 'Yes';
        this.studyingIn = '';

        this.selectedProgramsList = [];
        this.programSearchResults = [];
        this.programSearchTerm = '';
        this.showProgramSearchResults = false;

        this.stateOptions = [];
        this.cityOptions = [];

        this.existingLeadId = null;
        this.existingApplicantAccountId = null;
        this.hasApplicantAccount = false;
        this.isPrefilled = false;
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
            this.step = 'init';
            this.clearDetailsForm();
            this.selectedCampaignId = '';
            this.leadSourceForCampaignQuery = '';
            this.campaignOptions = [];
            this.clearError();
            return;
        }
        this.handleCancel();
    }

    get backButtonLabel() {
        return this.isDetailsStep ? 'Back' : 'Cancel';
    }

    get showEventPicklist() {
        return this.leadSource == 'Events'
    }

    async handleSave() {
        this.applyLeadSourceDefaultIfBlank();

        const firstNameVal = (this.firstName || '').trim();
        const lastNameVal = (this.lastName || '').trim();
        const emailVal = (this.email || '').trim();
        const phoneVal = (this.phone || '').trim();
        const leadSourceVal =
            this.leadSource != null && String(this.leadSource).trim() !== ''
                ? String(this.leadSource).trim()
                : null;

        const q = leadSourceVal || '';
        if (q !== this.leadSourceForCampaignQuery) {
            this.leadSourceForCampaignQuery = q;
        }

        const validationErrors = [];

        if (!firstNameVal) {
            validationErrors.push('First Name is required.');
        }

        if (!emailVal) {
            validationErrors.push('Email is required.');
        } else if (!this.isValidEmail(emailVal)) {
            validationErrors.push('Please enter a valid email address.');
        }
        if (!phoneVal) {
            validationErrors.push('Phone is required.');
        }

        if (this.selectedProgramsList.length === 0) {
            validationErrors.push('Please select at least one program.');
        }
        if(this.dateOfBirth){
             const today = new Date();
                today.setHours(0, 0, 0, 0);

                const dob = new Date(this.dateOfBirth);
                dob.setHours(0, 0, 0, 0);

                if (dob >= today) {
                    validationErrors.push('Date of Birth must be in the past.');
                }
        }
        if (
            phoneVal &&
            this.acceptedNumberLength &&
            phoneVal.length !== Number(this.acceptedNumberLength)
        ) {
            validationErrors.push(
                `Phone number must be ${this.acceptedNumberLength} digits.`
            );
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
            console.log('Gender is ', this.leadGender)
            const saveResult = await createB2CLead({
                firstName: firstNameVal,
                lastName: lastNameVal,
                email: emailVal,
                phone: this.getCombinedPhone(),
                street: this.street ? this.street.trim() : null,
                countryId: this.selectedCountry || null,
                stateId: this.selectedState || null,
                cityId: this.selectedCity || null,
                postalCode: this.postalCode ? this.postalCode.trim() : null,
                dateOfBirth: this.dateOfBirth || null,
                age: this.age || null,
                hasWorkExperience: this.hasWorkExperience === 'Yes',
                yearsOfWorkExperience: this.yearsOfWorkExperience || null,
                hasEntranceExam: this.hasEntranceExam === 'Yes',
                entranceExamName: this.entranceExamName || null,
                studyingIn: this.studyingIn || null,
                organizationName: this.organizationName || null,
                selectedProgramIds: this.selectedProgramIds,
                leadSource: leadSourceVal,
                xs_source: this.selectedEvent && leadSourceVal ? leadSourceVal + ':' + this.selectedEvent
                    + (this.partnerName ? ' - ' + this.partnerName : '') : '',
                howDidYouKnow: this.howDidYouKnow,
                areYouNri: this.areYouNri === true,
                leadSourceOther: this.showLeadSourceOther
                    ? (this.leadSourceOther || '').trim() || null
                    : null,
                selectedCampaignId: this.selectedCampaignId || null,
                existingLeadId: this.existingLeadId || null,
                existingApplicantAccountId: this.existingApplicantAccountId || null,
                gender: this.leadGender,
                eventCountry: this.eventCountry || null,
                eventState: this.eventState || null,
                eventCity: this.eventCity || null,
            });

            const successMessage = saveResult?.message || 'Saved successfully.';

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: successMessage,
                    variant: 'success'
                })
            );

            this.dispatchEvent(
                new CustomEvent('success', {
                    detail: { recordId: saveResult.recordId },
                    bubbles: true,
                    composed: true
                })
            );

            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: saveResult.recordId,
                    objectApiName: saveResult.objectApiName || 'Lead',
                    actionName: 'view'
                }
            });

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

    isValidPhone(phone) {
        const phoneRegex = /^\d+$/;
        return phoneRegex.test(phone);
    }

    getCombinedPhone() {
        const num = (this.phone || '').trim();
        if (!num) return null;
        const code = (this.countryCode || '').trim();
        return code ? `${code} ${num}` : num;
    }

    setPhoneFromStoredValue(stored) {
        const value = (stored || '').trim();
        if (!value) {
            this.phone = '';
            return;
        }
        const match = this.countryCodeOptions.find(opt => value.startsWith(opt.value + ' ') || value === opt.value);
        if (match) {
            this.countryCode = match.value;
            this.phone = value.replace(match.value, '').trim();
        } else {
            this.phone = value;
        }
    }
}