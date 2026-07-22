import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class LookupWithOptions extends NavigationMixin(LightningElement) {
    @api label = '';
    @api placeholder = 'Search...';
    @api value = null;
    @api options = [];
    @api newRecordLabel = 'New Record';
    @api newRecordObjectApiName = '';
    @api required = false;
    @api showNewRecord = false; //1001

    @track isOpen = false;
    @track searchTerm = '';

    get showLabel() {
        return !!this.label;
    }

    get displayValue() {
        if (!this.value) return '';
        const opt = this.normalizedOptions.find(o => o.value === this.value);
        return opt ? opt.label : '';
    }

    /** Single search bar: when open show search term, when closed with selection show primary label. */
    get inputDisplayValue() {
        if (this.isOpen) return this.searchTerm;
        if (this.value) return this.displayValue;
        return this.searchTerm;
    }

    get inputReadonly() {
        return !this.isOpen && !!this.value;
    }

    get hasValue() {
        return !!this.value;
    }

    get normalizedOptions() {
        return Array.isArray(this.options) ? this.options : [];
    }

    get filteredOptions() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) return this.normalizedOptions;
        return this.normalizedOptions.filter(o => {
            const labelMatch = (o.label || '').toLowerCase().includes(term);
            const subMatch = (o.subLabel || '').toLowerCase().includes(term);
            return labelMatch || subMatch;
        });
    }

    get hasNoOptions() {
        return this.normalizedOptions.length === 0;
    }

    get hasNoFilteredOptions() {
        return this.filteredOptions.length === 0;
    }

    stopPropagation(e) {
        e.stopPropagation();
    }


    connectedCallback() {
        this._onDocumentClick = this._handleDocumentClick.bind(this);
        document.addEventListener('click', this._onDocumentClick);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._onDocumentClick);
    }

    _handleDocumentClick() {
        this.isOpen = false;
    }

    handleInputClick() {
        if (this.isOpen) return;
        this.isOpen = true;
        this.searchTerm = '';
    }

    handleMainInput(event) {
        this.searchTerm = event.target.value || '';
    }

    handleSelectOption(e) {
        const id = e.currentTarget.dataset.id;
        const label = e.currentTarget.dataset.label;
        this.isOpen = false;
        this.searchTerm = '';
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: id, recordId: id, primaryLabel: label },
            bubbles: true,
            composed: true
        }));
    }

    handleClear(e) {
        e.stopPropagation();
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: null, recordId: null, primaryLabel: null },
            bubbles: true,
            composed: true
        }));
    }

    handleNewRecord(e) {
        e.preventDefault();
        e.stopPropagation();
        this.isOpen = false;
        if (this.newRecordObjectApiName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: {
                    objectApiName: this.newRecordObjectApiName,
                    actionName: 'new'
                }
            });
        }
        this.dispatchEvent(new CustomEvent('newrecord', { bubbles: true, composed: true }));
    }
}