import { LightningElement, api } from 'lwc';

export default class AfTermsAndConditions extends LightningElement {
    @api sections = []; // array of section renderModel objects
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

}