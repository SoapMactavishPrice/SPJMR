import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import DIVISION_OBJECT from '@salesforce/schema/Division__c';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi'; // ✅ ADD
import BATCH_GROUP_NAME from '@salesforce/schema/AcademicYear.Name'; // ✅ ADD
import ACADEMIC_TERM_YEAR from '@salesforce/schema/AcademicTerm.AcademicYearId'; // ✅ ADD
import DIVISION_COLOR_FIELD from '@salesforce/schema/Division__c.Division_Color__c';
import getDivisionGroups from '@salesforce/apex/DivisionFormController.getDivisionGroups';
import getTermOptions from '@salesforce/apex/DivisionFormController.getTermOptions';
import getSpecialisationsForTerm from '@salesforce/apex/DivisionFormController.getSpecialisationsForTerm';
import getDivision from '@salesforce/apex/DivisionFormController.getDivision';
import getSObjectTypeName from '@salesforce/apex/DivisionFormController.getSObjectTypeName';
import saveDivision from '@salesforce/apex/DivisionFormController.saveDivision';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DivisionForm extends NavigationMixin(LightningElement) {
    @api recordId;
    /** Parent record ID from Aura (decoded from inContextOfRef when New is clicked from related list). */
    @api parentContextRecordId;
    @track divisionNumber = '';
    @track divisionName = '';
    @track divisionCode = '';
    @track termId = null;
    @track divisionGroupId = null;
    @track divisionGroupName = null;
    /** Mirrors Division_Group__c.Is_Specialiation__c for the selected group. */
    @track divisionGroupIsSpecialisation = false;
    @track specialisationId = null;
    @track capacity = null;
    @track divisionColor = null;
    @track isActive = false;
    @track divisionGroupOptions = [];
    @track termOptions = [];
    @track specialisationOptions = [];
    @track isSaving = false;
    @track errorMessage = '';
    @track createdByName = '';
    @track lastModifiedByName = '';
    @track ownerName = '';
    @track batchGroupId = null;
    @track batchGroupName = null;
    @track termRecordId = null; // ✅ ADD
    /** Set only when editing an existing Division; null when creating (including from Term context). */
    editRecordId = null;
    /** Record ID from current page or inContextOfRef (e.g. Term when New is clicked from Term's related list). */
    pageRecordId = null;

    /** Default record type for Division__c — required by getPicklistValues for Division_Color__c */
    divisionRecordTypeId;

    @track divisionColorOptions = [];

   //showNewDivisionGroup = false;//1001

    /**
     * Decode parent record ID from inContextOfRef (base64) when New is opened from a related list.
     * @param {string} base64Context - state.inContextOfRef or URL param inContextOfRef
     * @returns {string|null} recordId or null
     */
    _decodeInContextOfRef(base64Context) {
        if (!base64Context || typeof base64Context !== 'string') return null;
        try {
            let str = base64Context;
            if (str.startsWith('1.')) str = str.substring(2);
            const decoded = JSON.parse(window.atob(str));
            return (decoded && decoded.attributes && decoded.attributes.recordId) || null;
        } catch (e) {
            return null;
        }
    }

    _applyContextRecordId(id) {
        if (!id) return;
        this.pageRecordId = id;
        if (!this.editRecordId && !this.termId) {
            getSObjectTypeName({ recordId: this.pageRecordId })
                .then(typeName => {
                    if (typeName === 'AcademicTerm') {
                        this.termId = this.pageRecordId;
                        this.termRecordId = this.pageRecordId; // ✅ ADD — triggers wiredTermRecord
                    } else if (typeName === 'AcademicYear') {
                        this.batchGroupId = this.pageRecordId;
                    }
                })
                .catch(() => {});
        }
    }

    @wire(getObjectInfo, { objectApiName: DIVISION_OBJECT })
    wiredDivisionObjectInfo({ data, error }) {
        if (data && data.defaultRecordTypeId) {
            this.divisionRecordTypeId = data.defaultRecordTypeId;
        }
    }
    @wire(getRecord, { recordId: '$batchGroupId', fields: [BATCH_GROUP_NAME] })
    wiredBatchGroup({ data, error }) {
        if (data) {
            this.batchGroupName = getFieldValue(data, BATCH_GROUP_NAME);
        }
    }
    
    // ✅ ADD — when context is a Term, get its AcademicYearId (Batch Group)
    @wire(getRecord, { recordId: '$termRecordId', fields: [ACADEMIC_TERM_YEAR] })
    wiredTermRecord({ data, error }) {
        if (data) {
            const yearId = getFieldValue(data, ACADEMIC_TERM_YEAR);
            if (yearId) {
                this.batchGroupId = yearId; // ✅ this triggers wiredBatchGroup to get the name
            }
        }
    }
    @wire(getPicklistValues, {
        recordTypeId: '$divisionRecordTypeId',
        fieldApiName: DIVISION_COLOR_FIELD
    })
    wiredDivisionColorPicklist({ data, error }) {
        if (data && data.values) {
            this.divisionColorOptions = data.values.map(entry => ({
                label: entry.label,
                value: entry.value
            }));
        } else if (error) {
            this.divisionColorOptions = [];
        }
    }

    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef) return;
        const fromAttrs = pageRef.attributes?.recordId;
        const fromState = pageRef.state?.recordId;
        const fromContext = this._decodeInContextOfRef(pageRef.state?.inContextOfRef);
        const id = fromAttrs || fromState || fromContext;
        if (id) this._applyContextRecordId(id);
    }

    connectedCallback() {
        console.log('FOUND IT');
        this._tryApplyParentContext();
    }

    renderedCallback() {
        this._tryApplyParentContext();
    }

    _tryApplyParentContext() {
        if (this.editRecordId || this.termId) return;
        const id = this.parentContextRecordId || this.pageRecordId;
        if (id && id !== this._lastAppliedContextId) {
            this._lastAppliedContextId = id;
            this.pageRecordId = id;
            getSObjectTypeName({ recordId: id })
    .then(typeName => {
        if (typeName === 'AcademicTerm') {
            this.termId = id;
            this.termRecordId = id; // ✅ ADD
        } else if (typeName === 'AcademicYear') {
            this.batchGroupId = id;
        }
    })
    .catch(() => {});
            return;
        }
        if (this.pageRecordId) return;
        const urlParams = new URLSearchParams(window.location.search || '');
        const fromUrl = this._decodeInContextOfRef(urlParams.get('inContextOfRef'));
        if (fromUrl && fromUrl !== this._lastAppliedContextId) {
            this._lastAppliedContextId = fromUrl;
            this._applyContextRecordId(fromUrl);
        }
    }

    get formTitle() {
        return this.editRecordId ? 'Edit Division' : 'New Division';
    }
    get filteredTermOptions() {
        if (!this.termOptions || this.termOptions.length === 0) {
            return [];
        }
        // ✅ If batchGroupName not yet resolved, return empty to avoid showing all terms prematurely
        if (!this.batchGroupName) {
            return [];
        }
        return this.termOptions.filter(o => o.subLabel === this.batchGroupName);
    }
    /** Show Specialisation when Division Group has Is_Specialiation__c = true. */
    get showSpecialisationField() {
        return this.divisionGroupIsSpecialisation === true;
    }

    /** Used for validation and for copying name from the specialisation lookup. */
    get isSpecialisationOnly() {
        return this.divisionGroupIsSpecialisation === true;
    }

    @wire(getDivisionGroups)
    wiredDivisionGroups({ data, error }) {
        if (data) {
            this.divisionGroupOptions = data.map(o => ({
                value: o.value,
                label: o.label,
                isSpecialisation: o.isSpecialisation === true
            }));
        }
    }

    @wire(getTermOptions, { batchGroupId: '$batchGroupId' })
wiredTermOptions({ data }) {
    if (data) {
        this.termOptions = data.map(o => ({
            value: o.value,
            label: o.label,
            subLabel: o.subLabel || null
        }));
    }
}

    @wire(getSpecialisationsForTerm, { termId: '$termId' })
    wiredSpecialisations({ data }) {
        if (data) {
            this.specialisationOptions = data.map(o => ({ value: o.value, label: o.label }));
        } else {
            this.specialisationOptions = [];
        }
    }

    @wire(getDivision, { recordId: '$recordId'  })
    wiredDivision({ data, error }) {
        if (data) {
            this.editRecordId = data.recordId || null;
            this.divisionNumber = data.divisionNumber || '';
            this.divisionName = data.divisionName || '';
            this.divisionCode = data.divisionCode || '';
            this.termId = data.termId || null;
            this.divisionGroupId = data.divisionGroupId || null;
            this.divisionGroupName = data.divisionGroupName || null;
            this.divisionGroupIsSpecialisation = data.divisionGroupIsSpecialisation === true;
            this.specialisationId = data.specialisationId || null;
            this.capacity = data.capacity != null ? String(data.capacity) : '';
            this.divisionColor = data.divisionColor || null;
            this.isActive = data.isActive === true;
            this.createdByName = data.createdByName || '';
            this.lastModifiedByName = data.lastModifiedByName || '';
            this.ownerName = data.ownerName || '';
        } else {
            this._resetFormForNew();
            // When New from Term's related list: use Aura recordId, parentContextRecordId (from inContextOfRef), or page state/URL
            const contextId = this.recordId || this.parentContextRecordId || this.pageRecordId;
            if (contextId && !error) {
                getSObjectTypeName({ recordId: contextId })
                    .then(typeName => {
                        if (typeName === 'AcademicTerm') {
                            this.termId = contextId;
                            this.pageRecordId = contextId;
                            this.termRecordId = contextId;
                        }
                    })
                    .catch(() => {});
            }
        }
    }

    handleTermChange(event) {
        const id = event.detail?.value ?? event.detail?.recordId ?? null;
        this.termId = id;
        this.specialisationId = null;
    }

    handleDivisionGroupChange(event) {
        const id = event.detail?.value ?? event.detail?.recordId ?? null;
        this.divisionGroupId = id;
        const opt = (this.divisionGroupOptions || []).find(o => o.value === id);
        const label = event.detail?.primaryLabel ?? opt?.label;
        this.divisionGroupName = label || null;
        this.divisionGroupIsSpecialisation = opt ? opt.isSpecialisation === true : false;
        if (!this.divisionGroupIsSpecialisation) {
            this.specialisationId = null;
        }
    }

    handleSpecialisationChange(event) {
        const id = event.detail?.value ?? event.detail?.recordId ?? null;
        this.specialisationId = id;
    }

    handleFieldChange(event) {
        const field = event.target.name;
        const value = event.detail.value;
        if (field === 'divisionNumber') this.divisionNumber = value;
        if (field === 'divisionName') this.divisionName = value;
        if (field === 'divisionCode') this.divisionCode = value;
        if (field === 'capacity') this.capacity = value;
        if (field === 'divisionColor') this.divisionColor = value;
    }

    handleCheckboxChange(event) {
        this.isActive = event.target.checked;
    }

    _buildPayload() {
        let divisionName = this.divisionName || null;
        if (this.isSpecialisationOnly && !divisionName && this.specialisationId) {
            const opt = (this.specialisationOptions || []).find(o => o.value === this.specialisationId);
            if (opt) divisionName = opt.label;
        }
        return {
            recordId: this.editRecordId || null,
            divisionNumber: this.divisionNumber || null,
            divisionName: divisionName,
            divisionCode: this.divisionCode || null,
            termId: this.termId || null,
            divisionGroupId: this.divisionGroupId || null,
            specialisationId: this.specialisationId || null,
            capacity: this.capacity !== '' && this.capacity != null ? parseInt(this.capacity, 10) : null,
            divisionColor: this.divisionColor || null,
            isActive: this.isActive,
            ownerId: null
        };
    }

    _validate() {
        if (!this.termId) {
            this.errorMessage = 'Term is required.';
            return false;
        }
        if (!this.divisionGroupId) {
            this.errorMessage = 'Division Group is required.';
            return false;
        }
        if (this.isSpecialisationOnly && !this.specialisationId) {
            this.errorMessage = 'Specialisation is required for this Division Group.';
            return false;
        }
        if (!this.isSpecialisationOnly && !this.divisionName && this.divisionGroupName !== 'Fundamental' ) {
            this.errorMessage = 'Division Name is required when this Division Group does not use a specialisation.';
            return false;
        }
        if (!this.divisionColor) {
            this.errorMessage = 'Division Color is required.';
            return false;
        }
        this.errorMessage = '';
        return true;
    }

    _normalizeErrorMessage(err) {
        let msg = 'An unexpected error occurred while saving Division.';
        if (err && err.body) {
            if (Array.isArray(err.body) && err.body.length > 0) {
                msg = err.body.map(e => e && e.message).filter(Boolean).join('; ') || msg;
            } else if (err.body.message) {
                msg = err.body.message;
            } else if (err.body.output) {
                const outputMessages = [];
                const topErrors = err.body.output.errors || [];
                topErrors.forEach(e => { if (e && e.message) outputMessages.push(e.message); });
                const fieldErrors = err.body.output.fieldErrors || {};
                Object.keys(fieldErrors).forEach(fieldName => {
                    (fieldErrors[fieldName] || []).forEach(e => {
                        if (e && e.message) outputMessages.push(e.message);
                    });
                });
                if (outputMessages.length > 0) {
                    msg = outputMessages.join('; ');
                }
            }
        } else if (err && err.message) {
            msg = err.message;
        }
        msg = String(msg).replace(/Course Type/gi, 'Division Group');

        // Extract clean custom-validation message from long trigger/DML stack errors.
        // Example input includes:
        // "... first error: FIELD_CUSTOM_VALIDATION_EXCEPTION, The Term dates ...: [] Class...."
        const validationMatch = msg.match(/(FIELD_CUSTOM_VALIDATION_EXCEPTION,\s*[^:]+)(?::\s*\[\])?/i);
        if (validationMatch && validationMatch[1]) {
            return validationMatch[1].trim();
        }

        return msg;
    }

    _resetFormForNew() {
     const selectedTermId = this.termId;
        this.editRecordId = null;
        this.divisionNumber = '';
        this.divisionName = '';
        this.divisionCode = '';
        this.termId = selectedTermId;
        this.divisionGroupId = null;
        this.divisionGroupName = null;
        this.divisionGroupIsSpecialisation = false;
        this.specialisationId = null;
        this.capacity = '';
        this.divisionColor = null;
        this.isActive = false;
        this.createdByName = '';
        this.lastModifiedByName = '';
        this.ownerName = '';
        this.errorMessage = '';
        if (this.recordId) {
            getSObjectTypeName({ recordId: this.recordId })
                .then(typeName => {
                    if (typeName === 'AcademicTerm') this.termId = this.recordId;
                })
                .catch(() => {});
        }
    }

    handleSaveAndNew() {
        if (!this._validate()) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: this.errorMessage, variant: 'error' }));
            return;
        }
        this.isSaving = true;
        const payload = JSON.stringify(this._buildPayload());
        saveDivision({ payload })
            .then(() => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Division saved.', variant: 'success' }));
                this._resetFormForNew();
            })
            .catch(err => {
                const msg = this._normalizeErrorMessage(err);
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleSave() {
        if (!this._validate()) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: this.errorMessage, variant: 'error' }));
            return;
        }
        this.isSaving = true;
        const payload = JSON.stringify(this._buildPayload());
        saveDivision({ payload })
            .then(recordId => {
                this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: 'Division saved.', variant: 'success' }));
                this._resetFormForNew();
                this.dispatchEvent(new CloseActionScreenEvent());
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: { recordId, objectApiName: 'Division__c', actionName: 'view' }
                });
            })
            .catch(err => {
                const msg = this._normalizeErrorMessage(err);
                this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
        const returnToRecordId = this.recordId || this.parentContextRecordId || this.pageRecordId || null;
        this.dispatchEvent(new CustomEvent('cancel', {
            detail: { returnToRecordId },
            bubbles: true,
            composed: true
        }));
    }
}