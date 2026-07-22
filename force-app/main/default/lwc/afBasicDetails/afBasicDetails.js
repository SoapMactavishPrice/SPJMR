import { LightningElement, api } from 'lwc';

export default class AfProgramDetails extends LightningElement {

    @api context = {};  // full education/context passed to renderer

    handleFieldChange(e) {
        this.dispatchEvent(new CustomEvent('sectionfieldchange', { detail: e.detail, bubbles: true, composed: true }));
    }

     /**
     * Apply per-field errors to child field renderers.
     * errorsByApi: { [fieldApi:string]: message }
     */
    @api applyErrors(errorsByApi = {}, subSectionKey = '') {
        const renderers = this.template.querySelectorAll('c-af-field-renderer');

        renderers.forEach(r => {
            // Normalize apiName
            const apiName = r.apiName && r.apiName.trim()
                ? r.apiName
                : (r.field?.api || null);

            const isSameSection = subSectionKey=='' ? true : subSectionKey === r.sectionName;

            if (isSameSection && apiName && errorsByApi.hasOwnProperty(apiName)) {
                r.setError(errorsByApi[apiName]);
            } else if (isSameSection) {
                r.clearError();
            }
            // do NOT clear errors of other subSections
        });
    }

    @api async validatePhoneField() {        
        const afFieldRendererCmps = this.template.querySelectorAll('c-af-field-renderer');
        let err = [];
        afFieldRendererCmps.forEach(fr => {
            if (!fr.validatePhoneField) return;
            err.push(fr.validatePhoneField());
        });
        return err.filter(e => e != null).filter(e => e.message != null && e.message != '');
    }

    //added so that blank columns dont appear. This method is fired in afFieldRenderer's renderedCallback
    handleVisibilityChange(e) {
        const { api, sequence, sectionKey, visible } = e.detail;

        const newSections = this._sections.map(section => {
            if (section.key !== sectionKey) return section;

            return {
                ...section,
                rows: section.rows.map(row => ({
                    ...row,
                    columns: row.columns.map(col => {
                        const match = col.fields?.some(
                            f =>
                                f.meta.api === api &&
                                (
                                    sequence == null ||
                                    f.meta.sequence === sequence
                                )
                        );
                        if (!match) return col;

                        const fieldKey =
                            sequence != null
                                ? `${api}#${sequence}`
                                : api;

                        const fieldVisibility = {
                            ...(col._fieldVisibility || {})
                        };

                        fieldVisibility[fieldKey] = visible;

                        return {
                            ...col,
                            _fieldVisibility: fieldVisibility,
                            _hasVisibleField: Object.values(fieldVisibility).some(v => v === true)
                        };
                    })
                }))
            };
        });
        this._sections = newSections;
    }

    _sections = [];

    @api
    get sections() {
        return this._sections;
    }
    set sections(value) {
        this._sections = (value || []).map(section => ({
            ...section,
            rows: section.rows.map(row => ({
                ...row,
                columns: row.columns.map(col => ({
                    ...col,
                    // ✅ default visible unless already explicitly set
                    _hasVisibleField: col._hasVisibleField ?? true
                }))
            }))
        }));
    }


}