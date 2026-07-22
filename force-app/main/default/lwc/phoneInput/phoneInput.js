import { LightningElement, api } from 'lwc';

const DEFAULT_OPTIONS = [
    { label: '(+91) India', value: '+91', acceptedLengths: '10' },
    { label: '(+1-784) Saint Vincent', value: '+1-784', acceptedLengths: '7;10' },
    { label: '(+971) UAE', value: '+971', acceptedLengths: '8;9' },
    { label: '(+65) Singapore', value: '+65', acceptedLengths: '8' }
];

export default class PhoneInput extends LightningElement {

    /* =======================
       PUBLIC API
    ======================= */

    _value;

    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v;
        this._syncFromValue(v);
    }

    @api options;          // optional override
    @api disabled = false;
    @api required = false;

    /* =======================
       INTERNAL STATE
    ======================= */

    country;               // display value (may contain '-')
    phone = '';
    acceptedLengthsSet = new Set();
    maxLength = 10;
    _initialized = false;
    _userSelectedCountry = false;

    get isDisabled() {
        return !!this.disabled;
    }

    get titleVal() {
        return this.resolvedOptions.find(o => o.value === this.country)?.label;
    }

    get resolvedOptions() {
        return (this.options && this.options.length)
            ? this.options
            : DEFAULT_OPTIONS;
    }

    /* =======================
       LIFECYCLE
    ======================= */

    connectedCallback() {
        this._syncFromValue(this._value);
    }

    _isFirstRender = true;

    renderedCallback() {
        if (!this._initialized && this.resolvedOptions.length) {
            this._initialized = true;
            this._syncFromValue(this._value);
        }

        if (this._isFirstRender) {
            this._isFirstRender = false;
            if (!this.phone) return;
        }

        this._dispatch();
    }


    /* =======================
       NORMALIZATION
    ======================= */

    _normalizeCountryCode(code) {
        if (!code) return '';
        return '+' + code.replace(/\D/g, '');
    }

    _isFocused = false;

    handleFocus() {
        this._isFocused = true;
    }

    handleBlur() {
        this._isFocused = false;

        // After blur, if still empty → show India in UI
        if (!this.phone && !this._userSelectedCountry) {
            const def =
                this.resolvedOptions.find(o => o.value === '+91') ||
                this.resolvedOptions[0];

            this.country = def.value;
            this._applyRules(def);
        }
    }


    /* =======================
       VALUE → UI SYNC
    ======================= */
    _syncFromValue(v) {
        if (!this.resolvedOptions.length) return;

        // no value → default country (ONLY if not focused)
        if (!v) {
            if (this._isFocused) return; // ⭐ critical fix

            if (this._userSelectedCountry && this.country) {
                return;
            }

            const def =
                this.resolvedOptions.find(o => o.value === '+91') ||
                this.resolvedOptions[0];

            this.country = def.value;
            this.phone = '';
            this._userSelectedCountry = false;
            this._applyRules(def);
            return;
        }

        const match = [...this.resolvedOptions]
            .sort((a, b) => b.value.length - a.value.length)
            .find(opt =>
                v.startsWith(this._normalizeCountryCode(opt.value))
            );

        if (!match) {
            const def =
                this.resolvedOptions.find(o => o.value === '+91') ||
                this.resolvedOptions[0];

            this.country = def.value;
            this.phone = '';
            this._userSelectedCountry = false;
            this._applyRules(def);
            return;
        }

        const norm = this._normalizeCountryCode(match.value);
        this.country = match.value;
        this.phone = v.slice(norm.length).replace(/\D/g, '');
        this._userSelectedCountry = true;
        this._applyRules(match);
    }


    /* =======================
       EVENT HANDLERS
    ======================= */

    handleCountryChange(event) {
        const selected = event.detail?.value ?? event.target?.value;
        if (!selected) return;

        this.country = selected;
        this._userSelectedCountry = true;

        // IMPORTANT: compare normalized values
        const cfg = this.resolvedOptions.find(o =>
            this._normalizeCountryCode(o.value) ===
            this._normalizeCountryCode(this.country)
        );

        this._applyRules(cfg);

        // reset phone if invalid for new country
        if (this.phone.length > this.maxLength) {
            this.phone = '';
        }

        this._dispatch();
    }

    handlePhoneChange(event) {
        const incoming = event.detail?.value ?? event.target?.value ?? '';
        let raw = incoming.replace(/\D/g, '');

        if (raw.length > this.maxLength) {
            raw = raw.slice(0, this.maxLength);
        }

        this.phone = raw;

        const inputEl = this.template.querySelector('lightning-input');
        this._validate(inputEl);

        this._dispatch();
    }

    /* =======================
       RULES & VALIDATION
    ======================= */

    _applyRules(cfg) {
        if (!cfg) {
            this.acceptedLengthsSet = new Set();
            this.maxLength = 10;
            return;
        }

        if (cfg.acceptedLengths) {
            this.acceptedLengthsSet = new Set(
                cfg.acceptedLengths
                    .split(';')
                    .map(s => s.trim())
                    .filter(s => s && !isNaN(s))
                    .map(Number)
            );
        } else {
            this.acceptedLengthsSet = new Set();
        }
        const arr = Array.from(this.acceptedLengthsSet);
        this.maxLength = arr.length ? Math.max(...arr) : 10;
    }

    _validate(inputEl, setError=true) {
        if (!inputEl) return;

        if (this.required && !this.phone) {
            this.errorMessage = 'Phone number is required';
            inputEl.setCustomValidity('Phone number is required');
            inputEl.reportValidity();
            return;
        }

        if (
            this.phone.length > 0 &&
            this.acceptedLengthsSet.size &&
            !this.acceptedLengthsSet.has(this.phone.length)
        )
        {
            this.errorMessage = `Phone number must be ${[...this.acceptedLengthsSet].join(', ')} digits`;
            if (setError) {
                inputEl.setCustomValidity(
                    `Phone number must be ${[...this.acceptedLengthsSet].join(', ')} digits`
                );
            } else {
                inputEl.setCustomValidity('');
            }
        } else {
            this.errorMessage = '';
            inputEl.setCustomValidity('');
        }

        inputEl.reportValidity();
    }

    errorMessage = '';

    /* =======================
       PUBLIC SAVE-TIME API
    ======================= */
    @api
    validateAndGetError() {
        const input = this.template.querySelector('lightning-input');
        if (!input) return null;

        this._validate(input, false);

        return {
            message: this.errorMessage
        };
    }


    /* =======================
       DISPATCH
    ======================= */

    _dispatch() {

        const hasPhone = this.phone && this.phone.length > 0;

        const valid =
            !hasPhone ||
            !this.acceptedLengthsSet.size ||
            this.acceptedLengthsSet.has(this.phone.length);

        this.dispatchEvent(
            new CustomEvent('phonechange', {
                detail: {
                    country: this.country, // display value
                    phone: this.phone,
                    full: hasPhone ? `${this._normalizeCountryCode(this.country)}${this.phone}` : null,
                    valid
                },
                bubbles: true,
                composed: true
            })
        );
    }
}