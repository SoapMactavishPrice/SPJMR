import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFormConfiguration from '@salesforce/apex/ProgramRegistrationFormController.getFormConfiguration';
import getProgramDisplayLabels from '@salesforce/apex/ProgramRegistrationFormController.getProgramDisplayLabels';
import saveRegistrationLead from '@salesforce/apex/ProgramRegistrationFormController.saveRegistrationLead';
import getRegistrationThankYouRedirectUrl from '@salesforce/apex/ProgramRegistrationFormController.getRegistrationThankYouRedirectUrl';
import getCountries from '@salesforce/apex/ProgramRegistrationLocationService.getCountries';
import getStatesByCountry from '@salesforce/apex/ProgramRegistrationLocationService.getStatesByCountry';
import getCitiesByState from '@salesforce/apex/ProgramRegistrationLocationService.getCitiesByState';
import resolveCountryIdByName from '@salesforce/apex/ProgramRegistrationLocationService.resolveCountryIdByName';
import getPhoneCountryOptions from '@salesforce/apex/ProgramRegistrationLocationService.getPhoneCountryOptions';


/** Stable references so c-phone-input is not fed a new [] every render (breaks combobox / options sync). */
const EMPTY_PICKLIST_OPTS = [];
const EMPTY_PHONE_COUNTRY_OPTS = [];
const INDIA_NAME = 'india';
const INDIA_DIAL = '+91';

const SLDS_COL = {
    1: 'slds-size_1-of-12',
    2: 'slds-size_2-of-12',
    3: 'slds-size_3-of-12',
    4: 'slds-size_4-of-12',
    5: 'slds-size_5-of-12',
    6: 'slds-size_6-of-12',
    7: 'slds-size_7-of-12',
    8: 'slds-size_8-of-12',
    9: 'slds-size_9-of-12',
    10: 'slds-size_10-of-12',
    11: 'slds-size_11-of-12',
    12: 'slds-size_12-of-12'
};

export default class ProgramRegistrationForm extends LightningElement {
    /** When set (e.g. Experience Builder), URL query param is ignored. */
    @api programIdOverride;
    /**
     * When non-blank, forces brochure vs standard field set (true/false/1/yes). When blank, uses URL {@code isBrochure} / {@code c__isBrochure}.
     */
    @api brochureModeOverride;

    @track formPayload = {};
    @track captchaState = {};
    /** Stable option arrays per fieldKey — must not be recreated each render (fixes combobox/phone freeze). */
    optionCache = {};
    /** Bumps when dynamic picklist options change so displayRows recomputes. */
    @track picklistRefreshKey = 0;
    _countryNameResolveCache = new Map();
    @track loading = true;
    @track loadError = '';
    @track formModel = null;
    @track isSaving = false;
    /** When true, load only {@code Is_Brochure_Field__c} metadata rows and prefer {@code Brochure_URL__c} after submit. */
    isBrochureFlow = false;

    /** Ordered unique program ids from URL or override (comma- or pipe-separated). */
    parsedProgramIds = [];
    /** Programs shown in the multi-select: same ids as the URL (comma- or pipe-separated). */
    @track pickerProgramIds = [];
    /** When multiple programs: user-selected ids (multi-select). Defaults to all in picker. */
    @track selectedProgramIds = [];
    @track programPickerOptions = [];
    /** Multi-select program dropdown panel open state. */
    @track programPickerOpen = false;

    /** Google reCAPTCHA v2 response (set by widget callback). */
    @track recaptchaToken = '';
    _recaptchaWidgetId;
    _recaptchaRenderInProgress = false;

    constructor() {
        super();
        this._boundCloseProgramPicker = this.closeProgramPickerIfOutside.bind(this);
    }

    connectedCallback() {
         window.addEventListener("message", (event) => {

    switch(event.data?.name){

        case "recaptchaToken":
            this.recaptchaToken = event.data.payload;
            break;

        case "register":
            this.handleRegisterFromVF();
            break;
    }
});
        this.resolveProgramIds();
        this.resolveBrochureMode();
        this.loadConfiguration();
        document.addEventListener('click', this._boundCloseProgramPicker, true);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._boundCloseProgramPicker, true);
    }

    renderedCallback() {
        if (this.loading || !this.formModel || !this.showRecaptcha) {
            return;
        }
        if (this._recaptchaWidgetId !== undefined && this._recaptchaWidgetId !== null) {
            return;
        }
        if (this._recaptchaRenderInProgress) {
            return;
        }
        const host = this.template.querySelector('[data-recaptcha-host]');
        if (!host) {
            return;
        }
        this._recaptchaRenderInProgress = true;
        void this.initGoogleRecaptcha(host);
    }

    async handleRegisterFromVF(){
        if (this.isSaving) {
        return;
    }
    await this.submitRegistration();
}

async submitRegistration(){
    if (this.isSaving) {
    return;
}
        const errors = this.validate();
        if (errors.length) {
            this.showToast('Check your entries', errors[0], 'error');
            return;
        }
        const programsToSave = this.programsToSaveOnSubmit();
        if (programsToSave.length === 0) {
            this.showToast('Select a program', 'Choose at least one program you want to register for.', 'error');
            return;
        }
        const recaptchaResponse = '';
        const formValuesJson = this.buildPayloadForSave();

        this.isSaving = true;
        try {
            let leadIdOut = '';
             let lastMessage = '';
            for (let i = 0; i < programsToSave.length; i++) {
                const programId = programsToSave[i];
                const res = await saveRegistrationLead({
                    programId,
                    formValuesJson,
                    recaptchaToken: this.recaptchaToken ||  '',
                    registrationConfigProgramId: this.configProgramId,
                    brochureMode: this.isBrochureFlow
                });
                if (res.alreadyRegistered) {
                    this.showToast(
                        'Already Registered',
                        res.message,
                        'warning',
                        'sticky'
                    );
                    return;
                }
                if (!res.success) {
                    this.showToast(
                        'Could not save',
                        res.message ||
                            (programsToSave.length > 1
                                ? `Registration failed for program ${programId}.`
                                : 'Registration failed.'),
                        'error',
                                ''
                    );
                    return;
                }
                
                if (res.leadId) {
                    leadIdOut = res.leadId;
                }
                if (res.message) {
                lastMessage = res.message;
            }
            }
            this.showToast('Registration Successful', lastMessage  || 'Registration Successful .Please check your email inbox.', 'success','sticky');
            const detail = {
                programId: programsToSave.join(','),
                programIds: [...programsToSave],
                values: { ...this.formPayload },
                leadId: leadIdOut,
                ...(this.showRecaptcha && recaptchaResponse ? { recaptchaResponse } : {})
            };
            this.dispatchEvent(new CustomEvent('registered', { detail, bubbles: true, composed: true }));
            if (this.isBrochureFlow) {
                const brochureUrl = (this.formModel?.config?.brochureUrl || '').trim();
                if (brochureUrl) {
                    this.navigateToUrlOrPath(brochureUrl);
                    return;
                }
            }
            let thankYouUrl = '';
            try {
                thankYouUrl = (await getRegistrationThankYouRedirectUrl({ programIds: programsToSave })) || '';
            } catch (redirectErr) {
                // Non-blocking: stay on form if lookup fails
            }
            if (thankYouUrl) {
                this.navigateToUrlOrPath(thankYouUrl);
                return;
            }
            if (this.showRecaptcha) {
                this.resetGoogleRecaptcha();
            }
        } catch (e) {
            this.showToast('Error', e?.body?.message || e?.message || 'Registration failed.', 'error');
        } finally {
            this.isSaving = false;
        }
    
}
    parseProgramIdsFromRaw(raw) {
        if (!raw || typeof raw !== 'string') {
            return [];
        }
        const parts = raw
            .split(/[,|]/)
            .map((s) => s.trim())
            .filter(Boolean);
        const seen = new Set();
        const out = [];
        for (const p of parts) {
            if (!seen.has(p)) {
                seen.add(p);
                out.push(p);
            }
        }
        return out;
    }

    resolveProgramIds() {
        let raw = '';
        if (this.programIdOverride) {
            raw = this.programIdOverride.trim();
        } else {
            const params = new URLSearchParams(window.location.search);
            raw =
                params.get('programId') ||
                params.get('c__programId') ||
                params.get('program_id') ||
                '';
        }
        this.parsedProgramIds = this.parseProgramIdsFromRaw(raw);
    }

    isTruthyQueryFlag(raw) {
        if (raw == null) {
            return false;
        }
        const v = String(raw).trim().toLowerCase();
        return v === 'true' || v === '1' || v === 'yes';
    }

    resolveBrochureMode() {
        const o = this.brochureModeOverride;
        if (o !== undefined && o !== null && String(o).trim() !== '') {
            this.isBrochureFlow = this.isTruthyQueryFlag(o);
            return;
        }
        const params = new URLSearchParams(window.location.search);
        const raw = params.get('isBrochure') || params.get('c__isBrochure');
        this.isBrochureFlow = this.isTruthyQueryFlag(raw);
    }

    /** Program id used for form layout / metadata (first in URL list when multiple). */
    get configProgramId() {
        return this.parsedProgramIds[0] || '';
    }

    get showProgramSelector() {
    return this.pickerProgramIds.length > 1;
    }

    get selectedProgramId() {
    return this.selectedProgramIds.length
        ? this.selectedProgramIds[0]
        : null;
    }
   get isMultiProgramSelection() {
    return this.formModel?.config?.allowMultipleProgramSelection === true;
    }

    get isSingleProgramSelection() {
    return !this.formModel?.config?.allowMultipleProgramSelection;
    }

    get programPickerHelpText() {
        return 'Choose one or more programs from the list. Form fields follow the configuration for the first program id in the link (same field layout for all programs on this page).';
    }

    get programPickerLabel() {
        return 'Program(s) you are registering for';
    }

    get programPickerFieldHelp() {
        return 'Each checked program creates a separate program registration (Lead Program) when you submit.';
    }

    // Short trigger text; full names show as wrapping chips above (readable when open or closed).
    get programPickerSummaryText() {
        const n = (this.selectedProgramIds || []).length;
        if (n === 0) {
            return '';
        }
        return n === 1 ? '1 program selected' : `${n} programs selected`;
    }

    get hasProgramPickerSelections() {
        return (this.selectedProgramIds || []).length > 0;
    }

    get selectedProgramLabelRows() {
        const opts = this.programPickerOptions || [];
        const byValue = new Map(opts.map((o) => [o.value, o.label]));
        return (this.selectedProgramIds || []).map((id) => ({
            value: id,
            label: byValue.get(id) || id
        }));
    }

    get displayRowsWithoutConsent() {
    const rows = this.displayRows;

    return rows.map(row => ({
        ...row,
        fields: row.fields.filter(field => !field.isCheckbox)
    })).filter(row => row.fields.length > 0);
}

get consentRows() {
    const rows = this.displayRows;

    return rows.map(row => ({
        ...row,
        fields: row.fields.filter(field => field.isCheckbox)
    })).filter(row => row.fields.length > 0);
}

    get programPickerPlaceholder() {
        return 'Select program(s)';
    }

    get programPickerCheckboxRows() {
        const sel = new Set(this.selectedProgramIds || []);
       // const firstId = this.pickerProgramIds && this.pickerProgramIds[0];
        return (this.programPickerOptions || []).map((o) => ({
        value: o.value,
        label: o.label,
        checked: sel.has(o.value),
    }));
    }

    async loadConfiguration() {
        this.loading = true;
        this.loadError = '';
        this.programPickerOpen = false;
        this.programPickerOptions = [];
        this.selectedProgramIds = [];
        this.pickerProgramIds = [];
        if (!this.configProgramId) {
            this.loading = false;
            this.loadError =
                'Missing program id. Pass programId in the URL (Salesforce Program Id), comma- or pipe-separated for multiple programs, or set the component property.';
            return;
        }
        try {
            const data = await getFormConfiguration({
                programId: this.configProgramId,
                brochureMode: this.isBrochureFlow
            });
            this.formModel = data;
            this.initializeState(data);

            this.pickerProgramIds = [...this.parsedProgramIds];
            if (
                this.pickerProgramIds.length > 1 &&
                this.formModel?.config?.showParentProgramInSelection === false
            ) {
                this.pickerProgramIds.shift(); // Remove the first program
            }

            if (this.pickerProgramIds.length > 1) {
                const labelMap = await getProgramDisplayLabels({ programIds: [...this.pickerProgramIds] });
                this.programPickerOptions = this.pickerProgramIds.map((id) => ({
                    label: labelMap[id] || id,
                    value: id
                }));
                this.selectedProgramIds = this.pickerProgramIds.length ? [this.pickerProgramIds[0]] : [];
            }
            await this.bootstrapPhoneCountryOptionsFromMaster();
            await this.bootstrapLocationPicklists();
        } catch (e) {
            this.loadError = e?.body?.message || e?.message || 'Unable to load registration form.';
            this.showToast('Error', this.loadError, 'error');
        } finally {
            this.loading = false;
        }
    }

    initializeState(data) {
        const next = {};
        const captcha = { ...this.captchaState };
        const options = {};
        const rows = data.fieldRows || [];
        rows.forEach((row) => {
            (row.fields || []).forEach((field) => {
                const key = field.fieldKey;
                if (field.fieldType === 'checkbox') {
                    next[key] = data.config?.consentCheckedByDefault === true;
                } else {
                    next[key] = '';
                }
                if (field.fieldType === 'captcha') {
                    captcha[key] = this.generateCaptchaChallenge();
                }
                options[key] = {
                    picklistOptions: this.parsePicklistOptions(field),
                    phoneCountryOptions: this.parsePhoneOptions(field)
                };
            });
        });
        this.optionCache = options;
        this.formPayload = next;
        this.captchaState = captcha;
    }

    collectFields() {
        const rows = this.formModel?.fieldRows || [];
        const out = [];
        rows.forEach((row) => {
            (row.fields || []).forEach((f) => out.push(f));
        });
        return out;
    }

    getFieldByKey(fieldKey) {
        return this.collectFields().find((f) => f.fieldKey === fieldKey);
    }

    picklistSourceIs(field, token) {
        return (field?.picklistSource || '').toLowerCase() === String(token).toLowerCase();
    }

    phoneOptionsFromCountryMaster(field) {
        return (field?.phoneOptionsSource || '').toLowerCase() === 'country_master';
    }

    getLocationFieldKey(sourceToken) {
        const f = this.collectFields().find(
            (x) => x.fieldType === 'picklist' && this.picklistSourceIs(x, sourceToken)
        );
        return f?.fieldKey;
    }

    mergePicklistOptions(fieldKey, picklistOptions) {
        if (!fieldKey) {
            return;
        }
        const prev = this.optionCache[fieldKey] || {
            picklistOptions: EMPTY_PICKLIST_OPTS,
            phoneCountryOptions: EMPTY_PHONE_COUNTRY_OPTS
        };
        this.optionCache = {
            ...this.optionCache,
            [fieldKey]: { ...prev, picklistOptions: picklistOptions || EMPTY_PICKLIST_OPTS }
        };
        this.picklistRefreshKey += 1;
    }

    mergePhoneCountryOptions(fieldKey, phoneCountryOptions) {
        if (!fieldKey) {
            return;
        }
        const prev = this.optionCache[fieldKey] || {
            picklistOptions: EMPTY_PICKLIST_OPTS,
            phoneCountryOptions: EMPTY_PHONE_COUNTRY_OPTS
        };
        this.optionCache = {
            ...this.optionCache,
            [fieldKey]: { ...prev, phoneCountryOptions: phoneCountryOptions || EMPTY_PHONE_COUNTRY_OPTS }
        };
        this.picklistRefreshKey += 1;
    }

    parseCountryNameFromPhoneLabel(label) {
        if (!label || typeof label !== 'string') {
            return '';
        }
        const m = label.match(/^\([^)]*\)\s*(.+)$/);
        return (m ? m[1] : label).trim();
    }

    getIndiaCountryOption(options) {
        const list = Array.isArray(options) ? options : [];
        return (
            list.find((opt) => String(opt?.label || '').trim().toLowerCase() === INDIA_NAME) ||
            null
        );
    }

    getIndiaPhoneOption(options) {
        const list = Array.isArray(options) ? options : [];
        return (
            list.find((opt) => this.normalizeDialCode(opt?.value) === INDIA_DIAL) ||
            list.find((opt) => this.parseCountryNameFromPhoneLabel(opt?.label).toLowerCase() === INDIA_NAME) ||
            null
        );
    }

    moveOptionToTop(options, preferredOption) {
        if (!Array.isArray(options) || !options.length || !preferredOption) {
            return options || [];
        }
        const idx = options.findIndex((opt) => opt?.value === preferredOption?.value);
        if (idx <= 0) {
            return options;
        }
        return [options[idx], ...options.slice(0, idx), ...options.slice(idx + 1)];
    }

    async resolveCountryIdForPhoneOption(opt) {
        if (!opt) {
            return '';
        }
        if (opt.countryMasterId) {
            return String(opt.countryMasterId);
        }
        const name = this.parseCountryNameFromPhoneLabel(opt.label);
        if (!name) {
            return '';
        }
        const countryFk = this.getLocationFieldKey('Country_Master');
        if (countryFk) {
            const countries = this.optionCache[countryFk]?.picklistOptions || [];
            const hit = countries.find(
                (c) => c.label && c.label.toLowerCase() === name.toLowerCase()
            );
            if (hit?.value) {
                return hit.value;
            }
        }
        if (this._countryNameResolveCache.has(name)) {
            return this._countryNameResolveCache.get(name);
        }
        let id = '';
        try {
            const resolved = await resolveCountryIdByName({ countryName: name });
            id = resolved || '';
        } catch (e) {
            id = '';
        }
        this._countryNameResolveCache.set(name, id);
        return id;
    }

    normalizeDialCode(code) {
        if (!code) {
            return '';
        }
        return '+' + String(code).replace(/\D/g, '');
    }

    async loadStatesForCountryId(countryId) {
        const stateFk = this.getLocationFieldKey('State_By_Country');
        const cityFk = this.getLocationFieldKey('City_By_State');
        if (!stateFk) {
            return;
        }
        if (!countryId) {
            this.mergePicklistOptions(stateFk, []);
            this.mergePicklistOptions(cityFk, []);
            return;
        }
        try {
            const rows = await getStatesByCountry({ countryId });
            this.mergePicklistOptions(stateFk, rows || []);
        } catch (e) {
            this.mergePicklistOptions(stateFk, []);
        }
    }

    async loadCitiesForStateId(stateId) {
        const cityFk = this.getLocationFieldKey('City_By_State');
        if (!cityFk || !stateId) {
            this.mergePicklistOptions(cityFk, []);
            return;
        }
        try {
            const rows = await getCitiesByState({ stateId });
            this.mergePicklistOptions(cityFk, rows || []);
        } catch (e) {
            this.mergePicklistOptions(cityFk, []);
        }
    }

    async bootstrapPhoneCountryOptionsFromMaster() {
        console.log('bootstrapPhoneCountryOptionsFromMaster');
        const telFields = this.collectFields().filter(
            (f) => f.fieldType === 'tel' && this.phoneOptionsFromCountryMaster(f)
        );
        if (!telFields.length) {
            return;
        }
        let rows = [];
        try {
            rows = await getPhoneCountryOptions();
            console.log('rows', JSON.parse(JSON.stringify(rows)));
        } catch (e) {
            rows = [];
        }
        console.log('rows', rows);
        const list = rows || [];
        const indiaPhone = this.getIndiaPhoneOption(list);
        const prioritizedList = this.moveOptionToTop(list, indiaPhone);
        telFields.forEach((f) => {
            this.mergePhoneCountryOptions(f.fieldKey, prioritizedList);
        });
    }

    async bootstrapLocationPicklists() {
        const countryFk = this.getLocationFieldKey('Country_Master');
        if (!countryFk) {
            return;
        }
        try {
            const rows = await getCountries();
            this.mergePicklistOptions(countryFk, rows || []);
        } catch (e) {
            this.mergePicklistOptions(countryFk, []);
        }
        await this.applyDefaultCountryFromPhone();
    }

    async applyDefaultCountryFromPhone() {
        const countryFk = this.getLocationFieldKey('Country_Master');
        if (!countryFk) {
            return;
        }
        const countryOptions = this.optionCache[countryFk]?.picklistOptions || [];
        const indiaCountry = this.getIndiaCountryOption(countryOptions);
        if (indiaCountry?.value && !this.formPayload[countryFk]) {
            const stateFk = this.getLocationFieldKey('State_By_Country');
            const cityFk = this.getLocationFieldKey('City_By_State');
            const next = { ...this.formPayload, [countryFk]: indiaCountry.value };
            if (stateFk) {
                next[stateFk] = '';
            }
            if (cityFk) {
                next[cityFk] = '';
            }
            this.formPayload = next;
            await this.loadStatesForCountryId(indiaCountry.value);
            this.mergePicklistOptions(cityFk, []);
            return;
        }
        const telField = this.collectFields().find((f) => f.fieldType === 'tel');
        if (!telField) {
            return;
        }
        const phoneOpts = this.optionCache[telField.fieldKey]?.phoneCountryOptions || [];
        if (!phoneOpts.length) {
            return;
        }
        const def = this.getIndiaPhoneOption(phoneOpts) || phoneOpts[0];
        const countryId = await this.resolveCountryIdForPhoneOption(def);
        if (!countryId || this.formPayload[countryFk]) {
            return;
        }
        const stateFk = this.getLocationFieldKey('State_By_Country');
        const cityFk = this.getLocationFieldKey('City_By_State');
        const next = { ...this.formPayload, [countryFk]: countryId };
        if (stateFk) {
            next[stateFk] = '';
        }
        if (cityFk) {
            next[cityFk] = '';
        }
        this.formPayload = next;
        await this.loadStatesForCountryId(countryId);
        this.mergePicklistOptions(cityFk, []);
    }

    async syncCountryFromPhoneDial(phoneFieldKey, dialValue) {
        const countryFk = this.getLocationFieldKey('Country_Master');
        if (!countryFk || !phoneFieldKey) {
            return;
        }
        const phoneOpts = this.optionCache[phoneFieldKey]?.phoneCountryOptions || [];
        const d = this.normalizeDialCode(dialValue);
        const opt = phoneOpts.find((o) => this.normalizeDialCode(o.value) === d);
        if (!opt) {
            return;
        }
        const countryId = await this.resolveCountryIdForPhoneOption(opt);
        if (!countryId) {
            return;
        }
        const stateFk = this.getLocationFieldKey('State_By_Country');
        const cityFk = this.getLocationFieldKey('City_By_State');
        const next = { ...this.formPayload, [countryFk]: countryId };
        if (stateFk) {
            next[stateFk] = '';
        }
        if (cityFk) {
            next[cityFk] = '';
        }
        this.formPayload = next;
        await this.loadStatesForCountryId(countryId);
        this.mergePicklistOptions(cityFk, []);
    }

    async afterPicklistChange(fieldKey, value) {
        const field = this.getFieldByKey(fieldKey);
        if (!field || field.fieldType !== 'picklist') {
            return;
        }
        if (this.picklistSourceIs(field, 'Country_Master')) {
            const stateFk = this.getLocationFieldKey('State_By_Country');
            const cityFk = this.getLocationFieldKey('City_By_State');
            const next = { ...this.formPayload };
            if (stateFk) {
                next[stateFk] = '';
            }
            if (cityFk) {
                next[cityFk] = '';
            }
            this.formPayload = next;
            await this.loadStatesForCountryId(value);
            this.mergePicklistOptions(cityFk, []);
            return;
        }
        if (this.picklistSourceIs(field, 'State_By_Country')) {
            const cityFk = this.getLocationFieldKey('City_By_State');
            this.formPayload = { ...this.formPayload, ...(cityFk ? { [cityFk]: '' } : {}) };
            await this.loadCitiesForStateId(value);
        }
    }

    generateCaptchaChallenge() {
        const chars = 'abcdef0123456789';
        let out = '';
        for (let i = 0; i < 6; i++) {
            out += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return { display: out, answer: out };
    }

    refreshCaptcha(fieldKey) {
        this.captchaState = {
            ...this.captchaState,
            [fieldKey]: this.generateCaptchaChallenge()
        };
    }

    isFieldVisible(field) {
        if (!field.visibleWhenFieldKey) {
            return true;
        }
        const current = this.formPayload[field.visibleWhenFieldKey];
        return current === field.visibleWhenValue;
    }

    parsePicklistOptions(field) {
        if (!field.optionsJson) {
            return [];
        }
        const trimmed = field.optionsJson.trim();
        if (!trimmed.startsWith('[')) {
            return [];
        }
        try {
            return JSON.parse(trimmed);
        } catch (e) {
            return [];
        }
    }

    parsePhoneOptions(field) {
        if (this.phoneOptionsFromCountryMaster(field)) {
            return EMPTY_PHONE_COUNTRY_OPTS;
        }
        if (!field.optionsJson) {
            return EMPTY_PHONE_COUNTRY_OPTS;
        }
        const trimmed = field.optionsJson.trim();
        if (!trimmed.startsWith('{')) {
            return EMPTY_PHONE_COUNTRY_OPTS;
        }
        try {
            const obj = JSON.parse(trimmed);
            const co = obj.countryOptions;
            return Array.isArray(co) && co.length ? co : EMPTY_PHONE_COUNTRY_OPTS;
        } catch (e) {
            return EMPTY_PHONE_COUNTRY_OPTS;
        }
    }

    get displayRows() {
        void this.picklistRefreshKey;
        if (!this.formModel || !this.formModel.fieldRows) {
            return [];
        }
        const t = (field) => field.fieldType;
        return this.formModel.fieldRows.map((row, rowIndex) => ({
            rowKey: `row-${rowIndex}`,
            fields: (row.fields || []).map((field) => {
                const width = Math.min(12, Math.max(1, field.columnWidth || 12));
                const fk = field.fieldKey;
                const col = SLDS_COL[width];
                const cached = this.optionCache[fk];
                return {
                    ...field,
                    isVisible: this.isFieldVisible(field),
                    columnClass: `slds-col ${col}`,
                    picklistOptions: cached?.picklistOptions ?? EMPTY_PICKLIST_OPTS,
                    phoneCountryOptions: cached?.phoneCountryOptions ?? EMPTY_PHONE_COUNTRY_OPTS,
                    inputValue: this.formPayload[fk],
                    checkboxChecked: field.fieldType === 'checkbox' ? !!this.formPayload[fk] : false,
                    consentLabel:
                        field.fieldType === 'checkbox' && this.formModel.config?.consentText
                            ? this.formModel.config.consentText
                            : field.label,
                    captchaDisplay: this.captchaState[fk]?.display || '',
                    isText: t(field) === 'text',
                    isEmail: t(field) === 'email',
                    isPassword: t(field) === 'password',
                    isOtp: t(field) === 'otp',
                    isTel: t(field) === 'tel',
                    isPicklist: t(field) === 'picklist',
                    isCheckbox: t(field) === 'checkbox',
                    isCaptcha: t(field) === 'captcha'
                };
            })
        }));
    }

    get pageTitle() {
        return this.formModel?.config?.formTitle || '';
    }

    get pageSubtitle() {
        return this.formModel?.config?.formSubtitle || '';
    }

    get submitLabel() {
        return this.formModel?.config?.submitButtonLabel || 'Register';
    }

    get primaryButtonColor() {
        return this.formModel?.config?.primaryButtonColor || '#D4A017';
    }

    get loginPath() {
        return this.formModel?.config?.loginRelativePath || '/login';
    }

    get primaryButtonStyle() {
        return `background-color:${this.primaryButtonColor};border-color:${this.primaryButtonColor};color:#1a1a1a;`;
    }

    get showRecaptcha() {
        const k = this.formModel?.config?.recaptchaSiteKey;
        return typeof k === 'string' && k.trim().length > 0;
    }

    buildPayloadForSave() {
        const payload = { ...this.formPayload };
        const rows = this.formModel?.fieldRows || [];
        rows.forEach((row) => {
            (row.fields || []).forEach((field) => {
                if (field.fieldType === 'password') {
                    delete payload[field.fieldKey];
                }
            });
        });
        return JSON.stringify(payload);
    }

    async initGoogleRecaptcha(host) {
        try {
            const siteKey = this.formModel.config.recaptchaSiteKey.trim();
            await this.ensureRecaptchaScript();
            await this.ensureGrecaptchaReady();
            if (this._recaptchaWidgetId !== undefined && this._recaptchaWidgetId !== null) {
                return;
            }
            const g = window.grecaptcha;
            if (!g || typeof g.render !== 'function') {
                throw new Error('grecaptcha.render not available');
            }
            // reCAPTCHA v2 — "I'm not a robot" checkbox (not v3 invisible).
            this._recaptchaWidgetId = g.render(host, {
                sitekey: siteKey,
                theme: 'light',
                size: 'normal',
                tabindex: 0,
                callback: (token) => {
                    this.recaptchaToken = token;
                },
                'expired-callback': () => {
                    this.recaptchaToken = '';
                },
                'error-callback': () => {
                    this.recaptchaToken = '';
                }
            });
        } catch (e) {
            console.error('reCAPTCHA init failed', e);
            this.showToast(
                'reCAPTCHA',
                'Could not load Google reCAPTCHA. Add CSP Trusted Sites for https://www.google.com and https://www.gstatic.com (Experience Builder: Settings > Security > Trusted URLs).',
                'error'
            );
        } finally {
            this._recaptchaRenderInProgress = false;
        }
    }

    ensureRecaptchaScript() {
        return new Promise((resolve, reject) => {
            if (window.grecaptcha && window.grecaptcha.render) {
                resolve();
                return;
            }
            const existing = document.querySelector('script[src*="google.com/recaptcha/api.js"]');
            if (existing) {
                if (window.grecaptcha && window.grecaptcha.render) {
                    resolve();
                } else {
                    existing.addEventListener('load', () => resolve());
                    existing.addEventListener('error', () => reject(new Error('reCAPTCHA script error')));
                }
                return;
            }
            const s = document.createElement('script');
            // hl= en shows the standard “I'm not a robot” label in English; change if needed.
            s.src = 'https://www.google.com/recaptcha/api.js?hl=en';
            s.async = true;
            s.defer = true;
            s.onload = () => resolve();
            s.onerror = () => reject(new Error('reCAPTCHA script load failed'));
            document.head.appendChild(s);
        });
    }

    ensureGrecaptchaReady() {
        return new Promise((resolve) => {
            const g = window.grecaptcha;
            if (g && typeof g.render === 'function') {
                resolve();
                return;
            }
            if (g && typeof g.ready === 'function') {
                g.ready(() => resolve());
                return;
            }
            const start = Date.now();
            const t = setInterval(() => {
                if (window.grecaptcha && window.grecaptcha.render) {
                    clearInterval(t);
                    resolve();
                } else if (Date.now() - start > 15000) {
                    clearInterval(t);
                    resolve();
                }
            }, 50);
        });
    }

    getRecaptchaResponse() {
        if (!this.showRecaptcha) {
            return '';
        }
        const id = this._recaptchaWidgetId;
        if (typeof id === 'number' && window.grecaptcha && typeof window.grecaptcha.getResponse === 'function') {
            const fromApi = window.grecaptcha.getResponse(id);
            if (fromApi) {
                return fromApi;
            }
        }
        return this.recaptchaToken || '';
    }

    resetGoogleRecaptcha() {
        const id = this._recaptchaWidgetId;
        if (typeof id === 'number' && window.grecaptcha && typeof window.grecaptcha.reset === 'function') {
            window.grecaptcha.reset(id);
        }
        this.recaptchaToken = '';
    }
    handleProgramRadioChange(event) {
    this.selectedProgramIds = [event.detail.value];
}

    handleTextChange(event) {
        const fieldKey = event.currentTarget.dataset.fieldKey;
        let value;
        if (event.target.type === 'checkbox') {
            value = event.target.checked;
        } else {
            value = event.detail?.value ?? event.target.value ?? '';
        }
        if (this.formPayload[fieldKey] === value) {
            return;
        }
        this.formPayload = { ...this.formPayload, [fieldKey]: value };
        void this.afterPicklistChange(fieldKey, value);
    }

    handlePhoneChange(event) {
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        const shell =
            path.find((el) => el?.classList?.contains?.('input-shell')) ||
            (event.target?.closest ? event.target.closest('.input-shell') : null);
        const fieldKey = shell?.dataset?.fk;
        if (!fieldKey) {
            return;
        }
        const full = event.detail?.full ?? '';
        if (this.formPayload[fieldKey] === full) {
            return;
        }
        this.formPayload = { ...this.formPayload, [fieldKey]: full };
        void this.syncCountryFromPhoneDial(fieldKey, event.detail?.country);
    }

    handleCaptchaRefresh(event) {
        const fieldKey = event.currentTarget.dataset.fieldKey;
        this.refreshCaptcha(fieldKey);
        this.formPayload = { ...this.formPayload, [fieldKey]: '' };
    }

    closeProgramPickerIfOutside(event) {
        if (!this.programPickerOpen) {
            return;
        }
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        if (path.indexOf(this.template.host) !== -1) {
            return;
        }
        this.programPickerOpen = false;
    }

    handleProgramPickerTriggerClick(event) {
        event.stopPropagation();
        this.programPickerOpen = !this.programPickerOpen;
    }

    handleProgramMultiselectDropdownClick(event) {
        event.stopPropagation();
    }

    handleProgramCheckboxChange(event) {
        const id = event.currentTarget.dataset.value;
        if (!id) {
            return;
        }
        const checked = event.target.checked;
        const set = new Set(this.selectedProgramIds || []);
        if (checked) {
            set.add(id);
        } else {
            set.delete(id);
        }
        this.selectedProgramIds = this.pickerProgramIds.filter((pid) => set.has(pid));
    }

    programsToSaveOnSubmit() {
        if (this.showProgramSelector) {
            return (this.selectedProgramIds || []).filter((id) => this.pickerProgramIds.includes(id));
        }
        return this.configProgramId ? [this.configProgramId] : [];
    }

    async handleRegister(event) {
        event.preventDefault();
        await this.submitRegistration();
    }

    validate() {
        const msgs = [];
        const rows = this.formModel?.fieldRows || [];
        rows.forEach((row) => {
            (row.fields || []).forEach((field) => {
                if (!this.isFieldVisible(field)) {
                    return;
                }
                const val = this.formPayload[field.fieldKey];
                const consentLabel =
                    field.fieldType === 'checkbox' && this.formModel.config?.consentText
                        ? this.formModel.config.consentText
                        : field.label;
                if (field.required) {
                    if (field.fieldType === 'checkbox' && val !== true) {
                        msgs.push(`${consentLabel || field.fieldKey} is required`);
                    } else if (field.fieldType !== 'checkbox' && (val === undefined || val === null || val === '')) {
                        msgs.push(`${field.placeholder || field.label || field.fieldKey} is required`);
                    }
                }
                /*if (field.fieldType === 'captcha') {
                    const challenge = this.captchaState[field.fieldKey];
                    const entered = (val || '').trim().toLowerCase();
                    const expected = challenge?.answer?.toLowerCase() || '';
                    if (entered !== expected) {
                        msgs.push('Captcha does not match');
                    }
                }*/
                if (field.fieldType === 'email' && val) {
                    const ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(val));
                    if (!ok) {
                        msgs.push('Enter a valid email address');
                    }
                }
            });
        });
        if (!this.recaptchaToken) {
            msgs.push('Please complete the I\'m not a robot verification');
        }
        return msgs;
    }

    handleLoginClick(event) {
        event.preventDefault();
        this.navigateToUrlOrPath(this.loginPath);
    }

    /** Relative site path or absolute http(s) URL. */
    navigateToUrlOrPath(raw) {
        const s = (raw || '').trim();
        if (!s) {
            return;
        }
        if (/^https?:\/\//i.test(s)) {
            window.location.assign(s);
            return;
        }
        const path = s.startsWith('/') ? s : `/${s}`;
        window.location.assign(path);
    }

    showToast(title, message, variant,mode) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode
            })
        );
    }
}