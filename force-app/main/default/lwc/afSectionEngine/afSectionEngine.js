import { LightningElement, api } from 'lwc';

export default class AfSectionEngine extends LightningElement {
    @api context = {};
    @api title = '';
    _sections = [];

    @api collapseHiddenColumns = false;

    @api
    get sections() {
        return this._sections;
    }
    set sections(value) {
        this._sections = this._normalizeSections(value);
    }

    get showTitle() {
        return !!this.title && this._sections.length > 0;
    }

    get fieldRenderers() {
        return Array.from(this.template.querySelectorAll('c-af-field-renderer'));
    }

    _normalizeSections(value) {
        return (value || []).map(section => ({
            ...section,
            renderKey: section.renderKey || section.key,
            sectionName: section.sectionName || section.key,
            rows: (section.rows || []).map(row => ({
                ...row,
                columns: (row.columns || []).map(col => ({
                    ...col,
                    _fieldVisibility: { ...(col._fieldVisibility || {}) },
                    _hasVisibleField: col._hasVisibleField ?? true
                }))
            }))
        }));
    }

    handleFieldChange(e) {
        this.dispatchEvent(new CustomEvent('sectionfieldchange', { detail: e.detail, bubbles: true, composed: true }));
    }

    handleActionClick(e) {
        this.dispatchEvent(new CustomEvent('sectionaction', { detail: e.detail, bubbles: true, composed: true }));
    }

    handleVisibilityChange(e) {
        if (!this.collapseHiddenColumns) return;

        const d = e?.detail || {};
        const api = d.api || null;
        const sequence = d.sequence ?? null;
        const sectionKey = d.sectionKey || null;
        const visible = d.visible;

        if (!sectionKey || !api || !this._sections.length) return;

        const fieldKey = sequence !== null && sequence !== undefined && sequence !== '' ? `${api}#${sequence}` : api;
        let changed = false;

        const nextSections = this._sections.map(section => {
            if (section.key !== sectionKey) return section;

            let sectionChanged = false;
            const rows = (section.rows || []).map(row => {
                let rowChanged = false;
                const columns = (row.columns || []).map(col => {
                    const matchesField = (col.fields || []).some(f => {
                        const meta = f.meta || {};
                        return meta.api === api && (sequence === null || sequence === undefined || sequence === '' || meta.sequence === sequence);
                    });
                    if (!matchesField) return col;

                    const currentVisibility = col._fieldVisibility?.[fieldKey];
                    if (currentVisibility === visible) return col;

                    const fieldVisibility = { ...(col._fieldVisibility || {}), [fieldKey]: visible };
                    rowChanged = true;
                    sectionChanged = true;
                    changed = true;

                    return {
                        ...col,
                        _fieldVisibility: fieldVisibility,
                        _hasVisibleField: Object.values(fieldVisibility).some(v => v === true)
                    };
                });
                return rowChanged ? { ...row, columns } : row;
            });

            return sectionChanged ? { ...section, rows } : section;
        });

        if (changed) {
            this._sections = nextSections;
        }
    }


    _resolveError(errors, api, sequence, sectionKey) {
        if (!errors || !api) return null;

        const hasSeq = sequence !== null && sequence !== undefined && sequence !== '';
        if (hasSeq) {
            const seqKey = String(sequence);
            const rowErrors = errors[seqKey];
            if (rowErrors && typeof rowErrors === 'object' && !Array.isArray(rowErrors) && Object.prototype.hasOwnProperty.call(rowErrors, api)) {
                return rowErrors[api];
            }

            console.log(
                'resolve',
                sectionKey,
                api,
                sequence,
                JSON.stringify(errors)
            );

            const sectionSeqKey =
                `${sectionKey}__${api}__${seqKey}`;

            if (Object.prototype.hasOwnProperty.call(errors, sectionSeqKey)) {
                return errors[sectionSeqKey];
            }

            const flatSeqKey = `${api}__${seqKey}`;

             const sectionErrors = errors?.[sectionKey];
            if (sectionErrors &&Object.prototype.hasOwnProperty.call(sectionErrors, flatSeqKey)) {
                return sectionErrors[flatSeqKey];
            }

            if (Object.prototype.hasOwnProperty.call(errors, flatSeqKey)) {
                return errors[flatSeqKey];
            }
        }

        const sectionErrors = errors?.[sectionKey];

        if (
            sectionErrors &&
            Object.prototype.hasOwnProperty.call(sectionErrors, api)
        ) {
            return sectionErrors[api];
        }

        if (Object.prototype.hasOwnProperty.call(errors, api)) {
            return errors[api];
        }

        return null;
    }

    @api applyErrors(errors = {}, subSectionKey = '') {
        const map = errors && typeof errors === 'object' ? errors : {};

        this.fieldRenderers.forEach(r => {
            const api = (r.apiName || r.field?.api || '').trim();
            const sequence = r.field?.sequence ?? null;
            const sectionMatch = !subSectionKey || subSectionKey === r.sectionName;

            if (!sectionMatch) return;
            if (!api) {
                r.clearError();
                return;
            }

            const msg = this._resolveError(map, api, sequence, r.sectionName);
            if (msg) r.setError(msg);
            else r.clearError();
        });
    }

    @api reportValidity() {
        this.fieldRenderers.forEach(r => {
            if (typeof r.reportValidity === 'function') r.reportValidity();
        });
    }

    @api checkValidity() {
        let valid = true;
        this.fieldRenderers.forEach(r => {
            if (typeof r.checkValidity === 'function') {
                valid = r.checkValidity() && valid;
            }
        });
        return valid;
    }

    @api validatePhoneField() {
        const errors = [];
        this.fieldRenderers.forEach(fr => {
            if (typeof fr.validatePhoneField !== 'function') return;
            const result = fr.validatePhoneField();
            const items = Array.isArray(result) ? result : [result];
            items.filter(Boolean).forEach(err => {
                if (!err.message) return;
                errors.push({
                    section: err.section || fr.sectionName || '',
                    api: err.api || fr.apiName || fr.field?.api || '',
                    sequence: err.sequence ?? fr.field?.sequence ?? null,
                    message: err.message
                });
            });
        });
        return errors;
    }
}