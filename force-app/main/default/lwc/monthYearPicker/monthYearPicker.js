import { LightningElement, api } from 'lwc';

export default class MonthYearPicker extends LightningElement {
    // Backing field with reactive getter/setter to keep comboboxes in sync with parent updates
    _value;

    /** Expected formats from parent: YYYY-MM or YYYY-MM-DD (we output YYYY-MM-01 00:00:00) */
    @api
    get value() {
        return this._value;
    }
    set value(v) {
        this._value = v;
        if (v) {
            const m = String(v).trim();
            // Match YYYY-MM or YYYY-MM-DD
            const match = m.match(/^(\d{4})-(\d{2})(?:-(\d{2}))?/);
            if (match) {
                const year = match[1];
                const monthPadded = match[2];
                // Normalize month to unpadded string to match combobox option values ('1'..'12')
                const monthUnpadded = String(parseInt(monthPadded, 10));
                this.yearValue = year;
                this.monthValue = monthUnpadded;
            } else {
                // Invalid incoming format → clear
                this.yearValue = undefined;
                this.monthValue = undefined;
            }
        } else {
            // Clear selection if parent clears value
            this.yearValue = undefined;
            this.monthValue = undefined;
        }
    }

    @api min;
    @api max;

    monthValue;
    yearValue;

    @api disabled;

    get isDisabled() {
        return this.disabled;
    }

    get isMonthDisabled() {
        return this.disabled || !this.yearValue;
    }

    monthDefault = [
        { label: 'January', value: '1' },
        { label: 'February', value: '2' },
        { label: 'March', value: '3' },
        { label: 'April', value: '4' },
        { label: 'May', value: '5' },
        { label: 'June', value: '6' },
        { label: 'July', value: '7' },
        { label: 'August', value: '8' },
        { label: 'September', value: '9' },
        { label: 'October', value: '10' },
        { label: 'November', value: '11' },
        { label: 'December', value: '12' }
    ];

    parseDateOnly(dateStr) {
        const [y, m, d] = dateStr.split('-').map(Number);
        return new Date(y, m - 1, d);
    }

    get monthOptions() {
        const minDate = this.min ? this.parseDateOnly(this.min) : null;
        const maxDate = this.max ? this.parseDateOnly(this.max) : null;
        const year = Number(this.yearValue);

        let start = 1;
        let end = 12;

        if (minDate && !isNaN(minDate) && year === minDate.getFullYear()) {
            start = minDate.getMonth() + 1;
        }

        if (maxDate && !isNaN(maxDate) && year === maxDate.getFullYear()) {
            end = maxDate.getMonth() + 1;
        }

        const months = this.monthDefault.slice(start - 1, end);
        return [
            { label: 'None', value: 'NONE' },  // 👈 special value
            ...months
        ];
    }

    get yearOptions() {
        const current = new Date().getFullYear();
        const minDate = this.min ? this.parseDateOnly(this.min) : null;
        const maxDate = this.max ? this.parseDateOnly(this.max) : null;
        const minYear = minDate && !isNaN(minDate) ? minDate.getFullYear() : current - 40;
        const maxYear = maxDate && !isNaN(maxDate) ? maxDate.getFullYear() : current + 10;
        const list = [];
        for (let y = minYear; y <= maxYear; y++) {
            list.push({ label: y.toString(), value: y.toString() });
        }
        return list;
    }

    handleMonthChange(event) {
        const val = event.detail.value;

        if (val === 'NONE') {
            this.monthValue = undefined;
            this._value = '';

            this.dispatchEvent(
                new CustomEvent('monthyearchange', {
                    detail: { value: '', isReset: true }
                })
            );
            return;
        }

        this.monthValue = val;
        this.fireChange();
    }

    handleYearChange(event) {
        this.yearValue = event.detail.value;

        // If selected month is now out of range, clear it silently
        const validMonths = this.monthOptions.map(m => m.value);

        if (!validMonths.includes(this.monthValue)) {
            this.monthValue = undefined;
        }

        this.fireChange();
    }

    fireChange() {
        // Only emit if BOTH selected
        if (!this.monthValue || !this.yearValue) {
            return; // 🔥 silent
        }

        const year = Number(this.yearValue);
        const month = Number(this.monthValue);

        const monthStr = String(month).padStart(2, '0');
        const newVal = `${year}-${monthStr}-01 00:00:00`;

        if (this._value === newVal) return; // avoid unnecessary events

        this._value = newVal;

        this.dispatchEvent(
            new CustomEvent('monthyearchange', {
                detail: { value: newVal }
            })
        );
    }
}