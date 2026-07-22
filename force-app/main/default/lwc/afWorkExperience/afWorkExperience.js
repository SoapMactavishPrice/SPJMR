import { LightningElement, api } from 'lwc';

export default class AfWorkExperience extends LightningElement {
    @api sections = []; // array of section renderModel objects
    @api context = {};  // full education/context passed to renderer

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
                f.clearError();
                return;
            }

            let msg = null;

            // 1) Row-based error map: errors = { 1:{api:msg}, 2:{...} }
            if (seq && errors[seq] && errors[seq][api]) {
                msg = errors[seq][api];
            }

            // 2) Flat sequential error map: errors = {"api__seq": msg}
            if (!msg && seq) {
                const keyWithSeq = `${api}__${seq}`;
                if (errors[keyWithSeq]) msg = errors[keyWithSeq];
            }

            // 3) Single-row sections: errors = { api: msg }
            if (!msg && errors[api]) {
                msg = errors[api];
            }

            // APPLY RESULT
            if (msg) f.setError(msg);
            else f.clearError();
        });
    }

}