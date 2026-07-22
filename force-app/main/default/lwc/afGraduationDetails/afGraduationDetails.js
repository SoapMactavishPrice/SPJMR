import { LightningElement, api } from 'lwc';

export default class AfGraduationDetails extends LightningElement {
    @api sections = [];
    @api context = {};

    handleFieldChange(e) {
        this.dispatchEvent(new CustomEvent('sectionfieldchange', { detail: e.detail, bubbles: true, composed: true }));
    }

    /**
     * Apply per-field errors to child field renderers.
     * errorsByApi: { [fieldApi:string]: message }
     */
    @api applyErrors(errors = {}, subSectionKey = '') {
        const fields = this.template.querySelectorAll('c-af-field-renderer');

        fields.forEach(f => {
            const api = f.apiName || f.field?.api;
            const seq = f.field?.sequence || null;
            const sectionMatch = !subSectionKey || subSectionKey === f.sectionName;

            if (!sectionMatch || !api) {
                // Not our section → ignore and clear
                f.clearError();
                return;
            }

            let msg = null;

            // --- MULTI-ROW GRID: use row → field structure ---
            if (seq && errors[seq] && errors[seq][api]) {
                msg = errors[seq][api];
            }
            // --- SINGLE ROW SECTIONS ---
            else if (!seq && errors[api]) {
                msg = errors[api];
            } else if(errors[api]) {
                msg = errors[api];
            }

            // APPLY FINAL RESULT
            if (msg) {
                f.setError(msg);
            } else {
                f.clearError();
            }
        });
    }

}