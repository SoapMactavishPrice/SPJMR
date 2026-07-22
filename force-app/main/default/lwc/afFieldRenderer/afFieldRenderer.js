import SystemModstamp from '@salesforce/schema/Account.SystemModstamp';
import { LightningElement, api, track } from 'lwc';

export default class AfFieldRenderer extends LightningElement {
    @api field;      // metadata for field (object)
    @api value;      // current value
    @api context;    // full form state
    @api sectionName; // key of section that this field belongs to
    @track error = '';

    @track textareaValue = '';

    get showWordCounter() {
        return this.isTextarea &&
            this.field?.showCounter === true &&
            Number.isInteger(this.field?.maxWords);
    }

    get wordCount() {
        const text = (this.textareaValue || '').trim();

        const words = text.match(/\S+/g);
        return words ? words.length : 0;
    }

    get wordCounter() {
        return `${this.wordCount} / ${this.field.maxWords} words`;
    }

    get wordCounterClass() {
        if (!this.showWordCounter) {
            return 'textarea-counter';
        }

        const percentage = (this.wordCount / this.field.maxWords) * 100;

        if (percentage >= 95) {
            return 'textarea-counter textarea-counter--danger';
        }

        if (percentage >= 80) {
            return 'textarea-counter textarea-counter--warning';
        }

        return 'textarea-counter';
    }

    handleTextareaInput(event) {
        this.textareaValue = event.target.value || '';
    }

    get applicationId() {
        return this.context?.applicationId;
    }

    get isLabel() {
        return this.field.type === 'label';
    }

    get showNormalLabel() {
        return !this.isLabel && !this.isNote && !this.isFile;
    }

    get isNote() {
        return this.field.type === 'note';
    }

    get step() {
        return this.field?.step ?? 1;
    }

    get max() {
        if(this.field?.type === 'number')
            return this.field?.max ?? 99999;
        else
            return this.field?.max ?? null;
    }

    get isCheckboxGroup() {
        return this.field.type === 'multipicklist';
    }

    get valueList() {
        // Only used for checkbox-group
        if (!this.isCheckboxGroup) return this.value;

        // If value is already an array → pass it directly
        if (Array.isArray(this.value)) {
            return this.value;
        }

        // If empty/null → no selections
        if (!this.value) {
            return [];
        }

        // Convert semicolon string → array
        return this.value
            .split(';')
            .map(v => v.trim())
            .filter(Boolean);
    }

    get isFile() {
        return this.field?.type === "file";
    }

    get isRichText() {
        return this.field?.type === 'richtext';
    }

    _lastValue;

    renderedCallback() {
        if (this.isNote) {
            const el = this.template.querySelector('.note-box');

            if (el && this.value !== this._lastValue) {
                el.innerHTML = this.value || '';
                this._lastValue = this.value;
            }
        }

        if (this.isRichText) {
            const el = this.template.querySelector('.rich-text-block');

            const content = this.field?.value || this.value || '';

            if (el && el.innerHTML !== content) {
                el.innerHTML = content;
            }
        }

        if (this.isTextarea && this.value !== this.textareaValue) {
            this.textareaValue = this.value || '';
        }
        
        // visibility update to immediate parent
        const v = this.visible;

            this.dispatchEvent(
                new CustomEvent('visibilitychange', {
                    detail: {
                        api: this.field?.api,
                        sequence: this.field?.sequence,
                        sectionKey: this.sectionName,
                        visible: v
                    },
                    bubbles: true,
                    composed: true
                })
            );
        // }

    }

    _lastVisible = null;

    get visible() {
        if (this.field.visible === false) return false;
        if (!this.field.visibleWhen) return true;
        const conds = Array.isArray(this.field.visibleWhen) ? this.field.visibleWhen : [this.field.visibleWhen];
        return conds.every(c => {
            const key = Object.keys(c)[0];
            const expected = c[key];
            const parts = key.split('.');
            let cur = this.context;
            for (let p of parts) {
                if (cur === undefined || cur === null) { cur = undefined; break; }
                cur = cur[p];
            }

            // ⭐ Special rules
            if (expected === "__notEmpty" || expected === "__notNull") {
                return cur !== null && cur !== undefined && cur !== "";
            }
            return cur == expected;
        });
    }

    get isLookup() { 
        return this.field.type === 'lookup'; 
    }
    get isMonthYear() { return this.field.type === 'monthyear'; }
    get isInput() { return ['text','number','date','currency','email', 'checkbox'].includes(this.field.type); }
    get isPicklist() { return this.field.type === 'picklist'; }
    get isRadio() { return this.field.type === 'radio'; }
    get isTextarea() { return this.field.type === 'textarea'; }
    get isDisabled() { return this.field.readOnly; }
    get isPhone() { 
        return this.field.type === 'tel'; 
    }



    get countryOptions() {
        return this.field?.countryOptions || [];
    };
    
    get inputType() {
        if (this.field.type === 'number' || this.field.type === 'currency') return 'number';
        if (this.field.type === 'date') return 'date';
        if (this.field.type === 'email') return 'email';
        if (this.field.type === 'checkbox') return 'checkbox';
        return 'text';
    }

    // Normalize initial value for rendering, especially for checkbox
    get normalizedValue() {
        // Only special-case checkbox; pass-through others
        if (this.field?.type === 'checkbox') {
            const v = this.value;
            if (typeof v === 'boolean') return v;
            if (typeof v === 'string') {
                const s = v.trim().toLowerCase();
                return s === 'true' || s === '1' || s === 'yes' || s === 'y';
            }
            if (typeof v === 'number') return v === 1;
            return false;
        }
        return this.value;
    }

    handleFileChange(e) {
        this.clearError();
    }

    get isButton() { return this.field.type === 'button'; }

    buttonEventHandlers = {
        click : this.handleClick
    }

    handleClick(e) {
        const api = e.target.dataset.api;

        this.dispatchEvent(new CustomEvent('actionclick', {
            detail: { 
                api,
                action: this.field.action,
                fieldMeta: this.field, 
                sectionKey: this.sectionName, 
                sequence: this.field.sequence ,
                browserEventType: e.type
            },
            bubbles: true, 
            composed: true
        }));
    }

    handleChange(e) {
        this.clearError();

        const api = e.target.dataset.api;
        let val;

        // Correctly handle checkbox vs other inputs
        if (this.field.type === 'checkbox') {
            val = e.target.checked;
        } else {
            val = e.detail ? e.detail.value : e.target.value;
        }

        if (this.field.type === 'tel') {
            val = e.detail?.full || null;
        }
        
        // 🔥 Checkbox-group = array → convert to joined string
        if (this.field.type === 'multipicklist' && Array.isArray(val)) {
            val = val.join(';');
        }

        // Validate using existing validator
        if(!this.field.skipOnChangeValidation) {
            const v = this._validate(val);
            if (v) this.error = v;
        }

        this.dispatchEvent(new CustomEvent('fieldchange', {
            detail: { 
                api, 
                value: val,
                fieldMeta: this.field, 
                sectionKey: this.sectionName, 
                sequence: this.field.sequence ,
                browserEventType: e.type
            },
            bubbles: true, 
            composed: true
        }));
    }



    handleLookupChange(e) {
        const api = e.target.dataset.api;
        // lightning-record-picker fires { detail: { value: recordId } }
        // Backward-compat: also accept { recordId }
        const recordId = e?.detail?.value ?? e?.detail?.recordId ?? null;
        const primaryLabel = e?.detail?.primaryLabel ?? null;
        const additionalFields = e?.detail?.additionalFields ?? null;
        this.clearError();
        this.dispatchEvent(new CustomEvent('fieldchange', {
            detail: { api, value: recordId, displayValue : primaryLabel, additionalFields, fieldMeta: this.field, sectionKey: this.sectionName, sequence: this.field.sequence },
            bubbles: true, composed: true
        }));
    }

    handleLookupSet(e) {
        const api = e.target.dataset.api;
        // lightning-record-picker fires { detail: { value: recordId } }
        // Backward-compat: also accept { recordId }
        const recordId = e?.detail?.value ?? e?.detail?.recordId ?? null;
        const primaryLabel = e?.detail?.primaryLabel ?? null;
        const additionalFields = e?.detail?.additionalFields ?? null;
        this.clearError();
        this.dispatchEvent(new CustomEvent('customlookupset', {
            detail: { api, value: recordId, displayValue : primaryLabel, additionalFields, fieldMeta: this.field, sectionKey: this.sectionName, sequence: this.field.sequence },
            bubbles: true, composed: true
        }));
        
    }

    _validate(val) {
        // Special case: required checkbox must be true
        if (this.field.type === 'checkbox' && this.field.required) {
            if (val !== true) {
                return this.field.errorMessage || 'This field is required';
            }
        }

        if (this.field.required && (val === undefined || val === null || val === '')) {
            return this.field.errorMessage || 'This field is required';
        }
        if (val !== undefined && val !== null && val !== '') {
            if (this.field.type === 'number') {
                const n = Number(val);
                if (isNaN(n)) return 'Invalid number';
                if (this.field.min !== undefined && n < this.field.min) return this.field.errorMessage || `Minimum ${this.field.min}`;
                if (this.field.max !== undefined && n > this.field.max) return this.field.errorMessage || `Maximum ${this.field.max}`;
            }
            if (this.field.regex) {
                try {
                    const re = new RegExp(this.field.regex);
                    if (!re.test(String(val))) return this.field.errorMessage || 'Invalid format';
                } catch(e) {}
            }
        }
        return null;
    }

    // Public API for parent components to set/clear errors
    @api setError(message) {
        this.error = message || '';
    }

    @api clearError() {
        this.error = '';
    }

    @api get apiName() {
        return this.field ? this.field.api : null;
    }

    @api
    validatePhoneField() {

        // Handle PHONE specially
        if (this.field.type === 'tel') {
            const phone = this.template.querySelector('c-phone-input');
            if (!phone) return null;
            const err = phone.validateAndGetError();
            if (!err) return null;

            return {
                section: this.sectionName,
                api: this.field.api,
                message: err.message
            };
        }

    }

    @api reportValidity() {
        this.template.querySelectorAll('.fine-inputs').forEach((el) => {
            el.reportValidity();
        });
    }

}