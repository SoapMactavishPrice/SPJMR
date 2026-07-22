// afTermsAndConditionsContainerGmp.js
import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import { buildErrorSummary } from "c/applicationFormService";

export default class AfProfileInformationContainerGmp extends LightningElement {

    isLoading = true; // Start spinner immediately

    application = { Id: 'a0EC10000048Qd1MAE' };

    _applicationId;
    
    @api
    set applicationId(value) {
        this._applicationId = value;
        this.application.Id = value;   // <-- assign to your class-level property
    }
    
    get applicationId() {
        return this._applicationId;
    }

    // model follows BasicDetails pattern: profileInformation.{purposeStatement, essay}
    @track profileInformation = {
        purposeStatement: {},
        essay: {}
    };

    metadata = {};
    @track sectionModel = [];

    picklistCache = {};
    dependentCache = {};

    async connectedCallback() {
        // load picklists first (BasicDetails pattern)
        try {
            const data = await getAllPicklistsForObjects({ objectApiNames: ["Application__c"] });
            if (data && data.length && data[0].defaultSet) {
                const bundle = data[0];
                this.picklistCache = {};
                this.dependentCache = {};

                for (const [api, field] of Object.entries(bundle.defaultSet)) {
                    this.picklistCache[api] = (field.options || []).map((o) => ({
                        label: o.label,
                        value: o.value
                    }));

                    if (field.dependent && field.controllingFieldApiName) {
                        this.dependentCache[api] = {
                            controllingField: field.controllingFieldApiName,
                            options: field.options
                        };
                    }
                }
            }

            this._buildMetadataSkeleton();
            this._injectPicklists();

            if (this.application?.Id) {
                await this.fetchForm(this.application.Id);
            } else {
                this._buildRenderModelAll();
            }
        } catch (err) {
            // fallback: still build metadata & render model
            console.warn("Picklist load failed", err);
            this._buildMetadataSkeleton();
            this._injectPicklists();
            if (this.application?.Id) await this.fetchForm(this.application.Id);
            else this._buildRenderModelAll();
        } finally {
            this.isLoading = false;
        }

    }

    _buildDynamicCertificateMetadata(){
        // -------- Language --------
        const selectedEssay = this.profileInformation.essay.ChoiceOfEssay__c || "";

        const convertToPascalCase = (label) => {
            return label
                .trim()
                .replace(/[^a-zA-Z0-9 ]/g, "")
                .split(/\s+/)
                .map((eachWord) => {
                    return eachWord.charAt(0).toUpperCase() + eachWord.slice(1);
                })
                .join('');
        };

        const convertToTitleCase = (api) => {
            return api
                .trim()
                .replace(/[^a-zA-Z0-9 ]/g, "")
                .split(/\s+/)
                .map((eachWord) => {
                    return eachWord.toUpperCase();
                })
                .join("_");
        }

        this.metadata.essay.fields = [
            {
                api: "ChoiceOfEssay__c",
                type: "picklist",
                label: "Choose one of the following",
                required: true,
            },
            {
                api: "Essay__c",
                type: "textarea",
                label: `${selectedEssay}`,
                shortLabel: "Essay",
                helpText: "Max 200 words",
                // docCode: `DOC_ESSAY_${convertToTitleCase(selectedEssay)}`,
                // maxFiles: 1,
                required: true,
                maxlength:"32768",
                visibleWhen: { "essay.ChoiceOfEssay__c": "__notNull" }
            }
        ]

        this.metadata.essay.rows = [
            {
                columns: [
                    { 
                        width: 4, 
                        fields: ["ChoiceOfEssay__c"] 
                    },
                ]
            },
            {
                columns: [
                    {
                        width: 9,
                        fields: ["Essay__c"]
                    },
                ]
            }
        ];

        this._applyReadOnlyMode();

    }

    /* ===========================================================
       BUILD METADATA (skeleton) — follows BasicDetails style
       =========================================================== */
    _buildMetadataSkeleton() {

        this.metadata = {
            purposeStatement: {
                key: "purposeStatement",
                title: "Statement of purpose",
                columnSystem: 12,
                rows: [
                    {
                        columns: [
                            { width: 9, fields: ["ShortTermLongTermGoal__c"] },
                        ]
                    },
                    {
                        columns: [
                            { width: 9, fields: ["AdditonalInformationOnSelf__c"] },
                        ]
                    },
                ],
                fields: [
                    { api: "ShortTermLongTermGoal__c", maxlength:"32768", type: "textarea", label: "Discuss your short term and long term goals, and how this program will help you achieve them", shortLabel:"Short and Long term goals", required: true, placeholder:"Enter Details", helpText:"Max 100 words" },
                    { api: "AdditonalInformationOnSelf__c", maxlength:"32768", type: "textarea", label: "Please furnish any other details which you think would help us understand you better or could strengthen your candidature", shortLabel:"Additional information", required: true, placeholder:"Example - formative years, responsibilities shouldered, family background, adversity faced in life, personal interests, etc", helpText:"Max 100 words" },
                ]
            },

            essay : {
                key: "essay",
                title: "Essay Question",
                columnSystem: 12,

                rows: [],

                fields: []
            }

        };
    }

    /* ===========================================================
       INJECT PICKLISTS (BasicDetails style)
       =========================================================== */
    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = (arr) => (arr || []).map((o) => ({ label: o.label || o, value: o.value || o }));

        const setOptions = (sectionKey, api, values) => {
            const s = this.metadata[sectionKey];
            if (!s) return;
            const f = s.fields.find((x) => x.api === api);
            if (f) f.options = values;
        };

        setOptions("essay", "ChoiceOfEssay__c", toOptions(pick.ChoiceOfEssay__c));
    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfProfileInformationContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfProfileInformationContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
    }

    _applyReadOnlyMode() {
        if (!this.isReadOnly) return;

        Object.values(this.metadata).forEach(section => {
            if (!section.fields) return;
            section.fields.forEach(f => {
                f.readOnly = true;
            });


        });
    }


    /* ===========================================================
       FETCH (context-driven; BasicDetails pattern for mapping)
       =========================================================== */
    async fetchForm(appId) {
        try {
            // build request from context parents
            const request = { parents: [], children: [] };

            context.parents.forEach((p) => {
                request.parents.push({
                    logicalName: p.logicalName,
                    sobject: p.sobject,
                    fields: p.fieldsToQuery,
                    filters: [{ field: p.sobject == "Application__c" ? "Id" : context.parentLookupField, value: appId }]
                });
            });

            const resp = await fetchDynamic({ requestJson: JSON.stringify(request) });

            this.application.Application_Status__c = resp?.application?.Application_Status__c;
            this.application.Assignment_Status__c = resp?.application?.Assignment_Status__c;

            const app = resp.application || {};

            // PURPOSE
            this.profileInformation.purposeStatement = {
                ShortTermLongTermGoal__c: app.ShortTermLongTermGoal__c,
                AdditonalInformationOnSelf__c: app.AdditonalInformationOnSelf__c
            };

            // ESSAY
            this.profileInformation.essay = {
                ChoiceOfEssay__c: app.ChoiceOfEssay__c,
                Essay__c: app.Essay__c
            };


            this.profileInformation.applicationId = this.application?.Id;

            this._buildDynamicCertificateMetadata();
            this._injectPicklists();

            // Build render model
            this._buildRenderModelAll();
        } catch (e) {
            console.error("fetchForm error", e);
        }
    }

    /* ===========================================================
       RENDER MODEL (BasicDetails style)
       =========================================================== */
    _buildRenderModelAll() {
        this._buildDynamicCertificateMetadata();
        this._injectPicklists();
        const keys = ["purposeStatement", "essay"];
        this.sectionModel = keys.map((k) => this._buildSectionRenderModel(k)).filter(Boolean);
    }

    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta) return null;

        const section = { key: meta.key, title: meta.title, rows: [] };

        // note (if present and not inline)
        if (meta.note && !meta.noteInline) {
            section.rows.push({
                key: `${sectionKey}-note-row`,
                style: `margin-bottom: 10px;`,
                columns: [{
                    key: `${sectionKey}-note-col`,
                    widthStyle: 'grid-column: span 12;',
                    fields: [{
                        key: `${sectionKey}-NOTE`,
                        meta: { ...meta.note, sectionKey },
                        value: meta.note.text
                    }]
                }]
            });
        }


        (meta.rows || []).forEach((r, rIdx) => {
            const row = {
                key: `${sectionKey}-row-${rIdx}`,
                style: `display:grid;grid-template-columns:repeat(${meta.columnSystem},1fr);gap:8px;margin-bottom:8px;`,
                columns: []
            };

            (r.columns || []).forEach((col, cIdx) => {
                const colObj = { key: `${sectionKey}-col-${rIdx}-${cIdx}`, widthStyle: `grid-column: span ${col.width}`, fields: [] };

                (col.fields || []).forEach((api) => {
                    const fMeta = (meta.fields || []).find((f) => f.api === api) || {};
                    let val = null;

                    // non-note fields -> come from profileInformation[sectionKey]
                    if (fMeta.type !== "note") {
                        val = this.profileInformation[sectionKey] ? this.profileInformation[sectionKey][api] ?? null : null;
                    } else {
                        val = fMeta.text || "";
                    }

                    colObj.fields.push({
                        key: `${sectionKey}-${api}`,
                        meta: { ...fMeta, sectionKey },
                        value: val
                    });
                });

                if (colObj.fields.length) row.columns.push(colObj);
            });

            section.rows.push(row);
        });

        return section;
    }

    /* ===========================================================
       DOCUMENT UPLOAD HANDLER (BasicDetails pattern)
       event.detail: { documentId, files, api, sectionKey }
       =========================================================== */
    handleDocsFetched(event) {
        const { documentId, files, api, sectionKey } = event.detail;

        if (!this.profileInformation[sectionKey]) this.profileInformation[sectionKey] = {};

        this.profileInformation[sectionKey][api] = files?.length ? documentId : undefined;

        // Rebuild render model so uploaders reflect new state
        this._buildRenderModelAll();
    }

    /* ===========================================================
       FIELD CHANGE (BasicDetails pattern)
       event.detail: { api, value, sectionKey }
       =========================================================== */
    handleSectionFieldChange(event) {
        const { api, value, sectionKey } = event.detail;
        const fieldMeta = this.metadata[sectionKey]?.fields?.find((f) => f.api === api) || {};

        const normalized = this._normalizeValue(api, value, fieldMeta);

        if (!this.profileInformation[sectionKey]) this.profileInformation[sectionKey] = {};
        this.profileInformation[sectionKey][api] = normalized;

        this._buildDynamicCertificateMetadata();
        this._injectPicklists();
        // Rebuild render model to reflect changes (visibility etc)
        this._buildRenderModelAll();
    }

    /* ===========================================================
       NORMALIZER (copy of BasicDetails normalizer, kept small)
       =========================================================== */
    _normalizeValue(api, value, fieldMeta = {}) {
        if (fieldMeta.type === "number") {
            if (value === "" || value === null || value === undefined) return null;
            const n = Number(value);
            return isNaN(n) ? null : n;
        }

        if (fieldMeta.type === "date") {
            return value || null;
        }

        if (fieldMeta.type === "radio" || fieldMeta.type === "picklist") {
            return value ? String(value) : null;
        }

        if(fieldMeta.type === "checkbox") {
            return value ? true : false;
        }

        if (typeof value === "string") {
            return value.trim();
        }

        return value;
    }

    /* ===========================================================
       VISIBILITY HELPER (same style as BasicDetails)
       =========================================================== */
    _isFieldVisible(fieldMeta) {
        // Explicitly hidden fields
        if (fieldMeta.visible === false) return false;

        // No visibility rules → always visible
        if (!fieldMeta.visibleWhen) return true;

        const conds = Array.isArray(fieldMeta.visibleWhen)
            ? fieldMeta.visibleWhen
            : [fieldMeta.visibleWhen];

        return conds.every(c => {
            const key = Object.keys(c)[0];
            const expected = c[key];
            const parts = key.split(".");

            let cur = this.profileInformation; // same as renderer

            // Safe traversal
            for (let p of parts) {
                if (cur === undefined || cur === null) {
                    cur = undefined;
                    break;
                }
                cur = cur[p];
            }

            // ⭐ Special rule support
            if (expected === "__notNull") {
                return cur !== null && cur !== undefined && cur !== "";
            }

            if (expected === "__notEmpty") {
                if (Array.isArray(cur)) return cur.length > 0;
                return cur !== null && cur !== undefined && cur !== "";
            }


            // Normal comparison
            return cur == expected;
        });
    }

    /* ===========================================================
       VALIDATION (BasicDetails pattern)
       - returns boolean (true if valid)
       - applies errors to wrapper via wrapper.applyErrors(errorsForSection, sectionKey)
       =========================================================== */
    validateAll() {
        const errors = {};

        Object.keys(this.metadata).forEach((sectionKey) => {
            const meta = this.metadata[sectionKey];
            (meta.fields || []).forEach((f) => {
                // skip note fields
                if (f.type === "note") return;

                // skip invisible
                if (!this._isFieldVisible(f)) return;

                // required check
                if (f.required) {
                    const val = this.profileInformation[sectionKey] ? this.profileInformation[sectionKey][f.api] : undefined;
                    let empty = val === "" || val === null || val === undefined || (Array.isArray(val) && val.length === 0);
                    if(f.type === "checkbox" && val === false){
                        empty = true;
                    }
                    if (empty) {
                        errors[sectionKey] = errors[sectionKey] || {};
                        errors[sectionKey][f.api] = `${f?.shortLabel || f.label || f.api} is required`;
                    }
                }
            });
        });

        const validateWordLimit = (text, limit = 200) => {
            if (!text) {
                return { isValid: true, count: 0 };
            }

            const words = text.trim().split(/\s+/).filter(Boolean);
            const count = words.length;

            return {
                isValid: count <= limit,
                count
            };
        }

        if(this.profileInformation.purposeStatement.ShortTermLongTermGoal__c){
            const { isValid, count } = validateWordLimit(this.profileInformation.purposeStatement.ShortTermLongTermGoal__c, 100);
            if(!isValid){
                errors.purposeStatement = errors.purposeStatement || {};
                errors.purposeStatement.ShortTermLongTermGoal__c = `Should not exceed 100 words. You have ${count} words`;
            }
        }

        if(this.profileInformation.purposeStatement.AdditonalInformationOnSelf__c){
            const { isValid, count } = validateWordLimit(this.profileInformation.purposeStatement.AdditonalInformationOnSelf__c, 100);
            if(!isValid){
                errors.purposeStatement = errors.purposeStatement || {};
                errors.purposeStatement.AdditonalInformationOnSelf__c = `Should not exceed 100 words. You have ${count} words`;
            }
        }

        if(this.profileInformation.essay.ChoiceOfEssay__c){
            const { isValid, count } = validateWordLimit(this.profileInformation.essay.Essay__c, 200);
            if(!isValid){
                errors.essay = errors.essay || {};
                errors.essay.Essay__c = `Should not exceed 200 words. You have ${count} words`;
            }
        }

        // dispatch errors to wrapper (BasicDetails pattern)
        const wrapper = this.template.querySelector("c-af-profile-information");
        if (wrapper) {
            Object.keys(errors).forEach((sectionKey) => {
                const errorsForSection = errors[sectionKey] || {};
                wrapper.applyErrors(errorsForSection, sectionKey);
            });
        }

        const hasErrors = Object.values(errors)
            .some(sec => sec && Object.keys(sec).length > 0);

        if (hasErrors) {
            const errorMessage = buildErrorSummary(errors, this.metadata);
            if (errorMessage) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                }));
            }
        }

        return Object.keys(errors).length === 0;
    }

    /* ===========================================================
       BUILD SAVE PAYLOAD (only purposeStatement is saved to Application__c per context)
       =========================================================== */
    buildSavePayload() {
        const out = {};

        context.parents.forEach((p) => {
            const logical = p.logicalName; // "application"
            const model = {
                Id: this.application.Id,

                // PURPOSE
                ShortTermLongTermGoal__c: this.profileInformation.purposeStatement.ShortTermLongTermGoal__c,

                AdditonalInformationOnSelf__c: this.profileInformation.purposeStatement.AdditonalInformationOnSelf__c,

                // ESSAY
                ChoiceOfEssay__c: this.profileInformation.essay.ChoiceOfEssay__c,

                Essay__c: this.profileInformation.essay.Essay__c
            };

            const block = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: {}
            };

            (p.fieldsToQuery || []).forEach((api) => {
                if(p.sobject === "Application__c" && api === "Application__c") return;
                if(p.sobject === "Application__c" && api === "Application_Status__c") return;
                if(p.sobject === "Application__c" && api === "Assignment_Status__c") return;
                if (api === "Id") {
                    if (model.Id) block.fields.Id = model.Id;
                } else {
                    block.fields[api] = model[api] ?? null;
                }
            });

            // add parent lookup ONLY if this is NOT Application__c
            if (p.sobject !== "Application__c") {
                block.fields[context.parentLookupField] = this.application?.Id;
            }

            out[logical] = block;
        });

        return out;
    }

    /* ===========================================================
       SAVE (BasicDetails/ProgramDetails pattern)
       =========================================================== */
    @api async saveForm() {
        if(this.isReadOnly) return true;        
        // run client-side validation first
        this.isLoading = true;
        if (!this.validateAll()) {
            this.isLoading = false;
            return false;
        }

        const payload = this.buildSavePayload();

        try {
            await saveParents({ payloadJson: JSON.stringify(payload) });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: "Saved successfully",
                    variant: 'success'
                })
            );

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Profile Information' 
            });

            // refresh server data
            if (this.application?.Id) await this.fetchForm(this.application.Id);

            return true;
        } catch (e) {
            console.error("save error", e);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Save failed",
                    message: "Please try again.",
                    variant: "error"
                })
            );
            return false;
        } finally {
            this.isLoading = false;
        }
    }
}