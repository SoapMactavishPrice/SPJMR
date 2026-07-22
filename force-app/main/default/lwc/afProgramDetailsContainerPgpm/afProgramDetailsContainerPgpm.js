import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { validateMinMaxDate, validateNumber } from 'c/applicationFormService';

import { buildErrorSummary } from 'c/applicationFormService';


export default class AfProgramDetailsContainerPgpm extends LightningElement {

    isLoading = true; // Start spinner immediately

    application = { Id: '' };

    _applicationId;
    
    @api
    set applicationId(value) {
        this._applicationId = value;
        this.application.Id = value;   // <-- assign to your class-level property
    }
    
    get applicationId() {
        return this._applicationId;
    }

    @track program = {};
    @track education = {};
    @track allSections = [];
    picklistCache = {};
    selectedBatchUpperAgeBound = null;
    
    recordToLogical = {};

    async connectedCallback() {
        if (context.parents && Array.isArray(context.parents)) {
            context.parents.forEach((p) => {
                if (p?.recordName) {
                    this.recordToLogical[p.recordName.toUpperCase()] = p.logicalName;
                }
            });
        }

        try {
            const data = await getAllPicklistsForObjects({
                            objectApiNames: ["Program_Detail__c", "Application__c"],
                        })//Note to self: same logic needs to be replicated in other components, or made as a utility
            if (data && data.length > 0) {
                const bundle = data[0]; // Get the first (and only) bundle for Academic__c
                if (bundle && bundle.defaultSet) {
                    // Convert to flat structure for easy access
                    this.picklistCache = {};
                    this.dependentCache = {};
                    
                    for (const [fieldApiName, fieldSet] of Object.entries(bundle.defaultSet)) {
                        // Store all picklist options
                        this.picklistCache[fieldApiName] = fieldSet.options.map(option => ({
                            label: option.label,
                            value: option.value
                            // Note: validForBase64 is null in current Apex implementation
                        }));
                        
                        // If this is a dependent field, store the dependency info
                        if (fieldSet.dependent && fieldSet.controllingFieldApiName) {
                            // Store the controlling field relationship for later use
                            this.dependentCache[fieldApiName] = {
                                controllingField: fieldSet.controllingFieldApiName,
                                options: fieldSet.options
                            };
                        }
                    }

                }
            }

            this._buildMetadata();
            this._injectPicklists();
            await this.fetchForm(this.application.Id);
        } catch (err) {
            console.warn("picklist load failed", err);
            this._buildMetadata();
            this._injectPicklists();
            await this.fetchForm(this.application.Id);
        } finally {
            this.isLoading = false;
        }

    }

    get contextBlock() {
        return {
            ...this.education,
            application: this.application,
            programDetail: this.program,
        };
    }

    /***********************************
     * METADATA DEFINITIONS
     ***********************************/
    _buildMetadata() {
        this.metadata = {};

        this.metadata.instructions = {}

        this.metadata.application = {};

        /***********************************
         * PROGRAMME DETAIL (last)
         ***********************************/
        this.metadata.programDetail = {
            key: "programDetail",
            title: "Programme Details",
            columnSystem: 12,
                note: {
                    api: "SECTION_NOTE",
                    type: "note",
                    text: `
<div style="background:#f3f3f3; padding:16px; border-radius:4px;">

    <div>
        <b>Please Note:</b>
        PGPM is a General Management programme where candidates will be allowed to choose one functional major from the following options. Further details on the architecture for the programme is available on
        <a href="https://www.spjimr.org/course/post-graduate-programme-in-management-pgpm/curriculum/" target="_blank">
            https://www.spjimr.org/course/post-graduate-programme-in-management-pgpm/curriculum/
        </a>
    </div>

    <div style="display:flex; justify-content:center; margin-top:16px;">
        <div style="text-align:left;">
            <b>Functional Majors:</b>
            <ul style="margin-top: 0.35rem; padding-left: 2.5rem; list-style-type: disc;">
                <li>Operations and Supply Chain Management</li>
                <li>Information Management &amp; Analytics</li>
                <li>Sales &amp; Marketing</li>
                <li>Finance</li>
                <li>Human Resource Management</li>
            </ul>
        </div>
    </div>

</div>
                `
            },
            rows: [
                {
                    columns: [
                        { width:11, fields: ["ProgramElegibilityInstruction__c"] },
                    ],
                },
                {
                    columns: [
                        { width:4, fields: ["ProgramElegibilityAcceptance__c"] },
                    ],
                },
            ],
            fields: [
                {
                    api: "ProgramElegibilityInstruction__c",
                    type: 'richtext',
                    value: `
                        I confirm that I have read, understood, and accept the eligibility criteria as outlined in the Eligibility Document.
                        <br/>
                        To refer to the Eligibility Document, click here: <a href="https://www.spjimr.org/wp-content/uploads/2024/04/pgpm-eligibility-class-of-2025.pdf" target="_blank">
                            https://www.spjimr.org/wp-content/uploads/2024/04/pgpm-eligibility-class-of-2025.pdf
                        </a>
                    `,
                },
                {
                    api: "ProgramElegibilityAcceptance__c",
                    type: "checkbox",
                    shortLabel: "Acceptance of eligibility criteria",
                    required: true,
                    label: "I agree",
                }
            ],
        };
    }


    /**********************************************
     * Picklist injection
     **********************************************/

    dependentCache = {};

    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr => (arr || []).map(x => ({ label: x.label || x.Label || x, value: x.value || x.Value || x }));
        const setOptions = (sectionKey, api, options) => {
            const f = (this.metadata[sectionKey].fields || []).find(x => x.api.toLowerCase() === api.toLowerCase());
            if (f) f.options = options;
        };
        // setOptions("programDetail", "PrimaryPartnerSchoolPreference__c", toOptions(pick.PrimaryPartnerSchoolPreference__c));
    
    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfProgramDetailsContainerPgpm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfProgramDetailsContainerPgpm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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

    /**********************************************
     * Fetch: application → programDetail
     **********************************************/
    async fetchForm(appId) {
        if (!appId) return;

        const getMeta = (key) => context.parents.find(p => p.logicalName === key);
        const buildFilters = (meta, appId) => {
            const f = [
                { field: meta.parentLookupField || "Application__c", value: appId }
            ];
            if (meta.filter) {
                Object.keys(meta.filter).forEach(x => {
                    f.push({ field: x, value: meta.filter[x] });
                });
            }
            return f;
        };

        try {
            /* ----------------------------------------------------
            * 1️⃣ Fetch Application (ALWAYS by Id only)
            * ---------------------------------------------------- */
            const rootMeta = getMeta("application");
            const appReq = {
                parents: [
                    {
                        logicalName: "application",
                        sobject: rootMeta.sobject,
                        fields: rootMeta.fieldsToQuery,
                        filters: [{ field: "Id", value: appId }]
                    }
                ],
                children: []
            };

            const appResp = await fetchDynamic({ requestJson: JSON.stringify(appReq) });
            this.application = appResp.application || {};
            this.education = { application: this.application };

            /* ----------------------------------------------------
            * 3️⃣ Build parent fetch request dynamically
            * ---------------------------------------------------- */
            const parentsRequest = { parents: [], children: [] };

            /* PROGRAMME DETAIL */
            const pdMeta = getMeta("programDetail");
            parentsRequest.parents.push({
                logicalName: pdMeta.logicalName,
                sobject: pdMeta.sobject,
                fields: pdMeta.fieldsToQuery,
                filters: buildFilters(pdMeta, appId)
            });

            /* ----------------------------------------------------
            * 4️⃣ Execute the fetch
            * ---------------------------------------------------- */
            const resp = await fetchDynamic({ requestJson: JSON.stringify(parentsRequest) });

            /* ----------------------------------------------------
            * 5️⃣ Map data into JS state
            * ---------------------------------------------------- */
            this.program = resp.programDetail || {};
            this.education.programDetail = this.program;
            
            this._applyReadOnlyMode();

            /* ----------------------------------------------------
            * 6️⃣ Rebuild render model
            * ---------------------------------------------------- */
            this._buildRenderModelAll();

        } catch (e) {
            console.error("fetchForm error", e);
        }
    }



    /**********************************************
     * Render model builder
     **********************************************/
    _buildRenderModelAll() {
        
        const sections = [];

        // 0) Instruction
        sections.push(this._buildSectionRenderModel("instructions"));

        // 1) Application
        sections.push(this._buildSectionRenderModel("application"));

        // 2) Programme Detail (always last)
        sections.push(this._buildSectionRenderModel("programDetail"));

        this.allSections = sections.filter(Boolean);

    }

    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta || !Array.isArray(meta.rows) || !Array.isArray(meta.fields)) return null;

        const section = { key: sectionKey, title: meta.title, rows: [] };

        /* NOTE ROW (static) */
        if (meta.note) {
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

        meta.rows.forEach((r, rIdx) => {
            const row = {
                key: `${sectionKey}-row-${rIdx}`,
                style: `display:grid;grid-template-columns:repeat(${meta.columnSystem},1fr);gap:8px;margin-bottom:8px;`,
                columns: []
            };

            r.columns.forEach((col, cIdx) => {
                const colObj = {
                    key: `${sectionKey}-col-${rIdx}-${cIdx}`,
                    widthStyle: `grid-column: span ${col.width};`,
                    fields: []
                };

                col.fields.forEach(api => {
                    const fMeta = meta.fields.find(f => f.api === api);
                    if (!fMeta) return;

                    let value = null;

                    if (sectionKey === "application") {
                        value = this.application[api] ?? null;
                    } else if (sectionKey === "programDetail") {
                        value = this.program[api] ?? null;
                    } else {
                        value = (this.education[sectionKey] || {})[api] ?? null;
                    }

                    // Clone metadata (so we don't mutate original definition)
                    const metaForRender = { ...fMeta, sectionKey };

                    if (metaForRender.type === "date") {
                        if (!metaForRender.min) delete metaForRender.min;
                        if (!metaForRender.max) delete metaForRender.max;
                    }

                    // ----- ⭐ Inject dynamic filter if defined -----
                    if (metaForRender.dynamicFilter && this[metaForRender.dynamicFilter] !== undefined) {
                        const dyn = this[metaForRender.dynamicFilter];

                        // If it's a function → call it
                        if (typeof dyn === "function") {
                            metaForRender.filter = dyn.call(this);
                        }
                        // If it's a getter → dyn is already the filter object
                        else {
                            metaForRender.filter = dyn;
                        }
                    }

                    colObj.fields.push({
                        key: `${sectionKey}-${api}`,
                        meta: metaForRender,
                        value
                    });
                    // -----------------------------------------------

                });

                if (colObj.fields.length) row.columns.push(colObj);
            });

            section.rows.push(row);
        });

        return section;
    }

    /**********************************************
     * Field Change Handler
     **********************************************/
    handleSectionFieldChange(e) {
        const { api, value, sectionKey, additionalFields } = e.detail;

        this.education[sectionKey] = this.education[sectionKey] || {};

        this.education[sectionKey].additionalFields ||= {};
        this.education[sectionKey].additionalFields[api] = additionalFields;

        // get meta for normalization
        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);
        const normalized = this._normalizeValue(api, value, fieldMeta);

        if (sectionKey === "application") {
            this.application[api] = normalized;

            this.education.application = { ...this.application };
            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === "programDetail") {
            this.program[api] = normalized;
            this.education.programDetail = this.program;

            this._buildRenderModelAll();
            return;
        }

        this.education[sectionKey] = this.education[sectionKey] || {};
        this.education[sectionKey][api] = normalized;

        this._buildRenderModelAll();
    }

    handleLookupSet(e){
        const { api, value, displayValue, sectionKey, additionalFields } = e.detail;

        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);
        const normalized = this._normalizeValue(api, value, fieldMeta);

        this.education[sectionKey] = this.education[sectionKey] || {};
        this.education[sectionKey][api] = normalized;

        if(sectionKey === 'programDetail'){
            this.program[api] = normalized;
        }

        if (sectionKey === 'application') {
            this.application[api] = normalized;
        }
        
        //for others record picker
        this.education[sectionKey].Display ||= {};
        this.education[sectionKey].Display[api] = displayValue;

        this.education[sectionKey].additionalFields ||= {};
        this.education[sectionKey].additionalFields[api] = additionalFields;


        if([].includes(api)){
            this._handleLookupDrivenRerender(api);
        }

    }

    _handleLookupDrivenRerender(api) {
        const affectedSections = [];

        Object.entries(this.SECTION_DEPENDENCIES).forEach(
            ([section, fields]) => {
                if (fields.includes(api)) {
                    affectedSections.push(section);
                }
            }
        );

        if (affectedSections.length) {
            this._rebuildSections([...new Set(affectedSections)]);
        }
    }

    _rebuildSections(sectionKeys) {

        this.allSections = this.allSections.map(sec => {
            if (!sectionKeys.includes(sec.key)) {
                return sec; // untouched
            }
            return this._buildSectionRenderModel(sec.key);
        }).filter(Boolean);
    }

    SECTION_DEPENDENCIES = {
        programDetail: []
    };


    _normalizeValue(api, val, fieldMeta) {
        if (!fieldMeta) return val;

        // ----------------------------
        // NUMBER
        // ----------------------------
        if (fieldMeta.type === 'number') {
            const n = Number(val);
            return isNaN(n) ? null : n;
        }

        // --------------------------------------------------------
        // MONTHYEAR (YYYY-MM or YYYY-MM-DD) → YYYY-MM-DD 00:00:00
        // --------------------------------------------------------
        if (fieldMeta.type === 'monthyear') {
            if (val == null) return null;

            val = String(val).trim();
            if (!val) return null;

            let normalized = null;

            // YYYY-MM → YYYY-MM-01
            if (/^\d{4}-\d{2}$/.test(val)) {
                normalized = `${val}-01`;
            }
            // YYYY-MM-DD → use first 10 chars
            else if (/^\d{4}-\d{2}-\d{2}/.test(val)) {
                normalized = val.substring(0, 10);
            }

            if (!normalized) return null;

            return `${normalized} 00:00:00`;
        }

        // --------------------------------------------------------
        // DATE (UI gives YYYY-MM-DD) → also return same unified format
        // --------------------------------------------------------
        if (fieldMeta.type === 'date') {
            if (!val) return null;

            // Ensure valid date
            const d = new Date(val);
            if (isNaN(d)) return null;

            const yyyy = d.getFullYear();
            const mm = String(d.getMonth() + 1).padStart(2, '0');
            const dd = String(d.getDate()).padStart(2, '0');

            return `${yyyy}-${mm}-${dd} 00:00:00`;   // ★ EXACT SAME FORMAT AS MONTHYEAR
        }

        // ----------------------------
        // BOOLEAN
        // ----------------------------
        if (fieldMeta.type === 'boolean' || fieldMeta.isBoolean === true) {
            return (val === true || val === 'true');
        }

        // ----------------------------
        // CURRENCY → always 2 decimals
        // ----------------------------
        if (fieldMeta.type === 'currency') {
            if (val === null || val === '' || val === undefined) return null;
            const n = Number(val);
            return isNaN(n) ? null : Number(n.toFixed(2));
        }

        if(fieldMeta.type === "checkbox") {
            return val ? true : false;
        }

        // ----------------------------
        // DEFAULT (text, picklist)
        // ----------------------------
        if (val === undefined || val === null) return null;

        if (typeof val === 'string') val = val.trim();

        return val === '' ? null : val;
    }

    validateAll() {
        const errors = {};
        const addError = (section, api, msg) => {
            if (!errors[section]) errors[section] = {};
            errors[section][api] = msg;
        };

        /********************************************
         * 1️⃣ Validate APPLICATION (mandatory always)
         ********************************************/
        const appMeta = this.metadata.application;
        if (Array.isArray(appMeta?.fields)) {
            appMeta.fields.forEach(f => {
                if (f.required && this.isFieldVisible("application", f)) {

                    let v = this.application[f.api];
                    if(f.type === "checkbox" && v === false){
                        v = undefined;
                    }
                    if (v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0)) {
                        addError("application", f.api, `${f?.shortLabel || f.label || f.api} is required`);
                    }
                }
            });
        }


        /********************************************
         * 3️⃣ Validate PROGRAMME DETAIL (always required)
         ********************************************/
        const pdMeta = this.metadata.programDetail;
        const pdData = this.program || {};

        pdMeta.fields.forEach(f => {
            const isVisible = this.isFieldVisible("programDetail", f);

            // Skip invisible fields completely
            if (!isVisible) return;

            if (f.required) {
                let v = pdData[f.api];
                if(f.type === "checkbox" && v === false){
                    v = undefined;
                }
                if (v === null || v === undefined || v === "" ||
                    (Array.isArray(v) && v.length === 0)) {
                    addError("programDetail", f.api, `${f?.shortLabel || f.label || f.api} is required`);
                }
            }
        });


        /********************************************
         * 6️⃣ Validate date (min or max)
         ********************************************/
        Object.keys(this.metadata).forEach(sectionKey => {
            const sectionMeta = this.metadata[sectionKey];
            const sectionData = this.education[sectionKey];
            if (!sectionData || !Array.isArray(sectionMeta?.fields)) return;

            sectionMeta.fields.forEach(f => {
                const isVisible = this.isFieldVisible(sectionKey, f);

                // Skip invisible fields completely
                if (!isVisible) return;
                if (f.type != 'date' && !f.min && !f.max) return;

                const res = validateMinMaxDate(f, sectionData[f.api]);
                if (res!=null) {
                    addError(sectionKey, f.api, '');
                }
            });
        });

        /********************************************
         * Send errors to renderer
         ********************************************/
        const wrapper = this.template.querySelector("c-af-section-engine");
        if (wrapper) {
            Object.keys(errors).forEach(sectionKey => {
                wrapper.applyErrors(errors[sectionKey], sectionKey);
            });
        }

        if (Object.keys(errors).length > 0) {
            const errorMessage = buildErrorSummary(errors, this.metadata);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: errorMessage,
                variant: 'error',
                mode: 'sticky'
            }));
            return false;
        }

        /********************************************
         * Pass/Fail
         ********************************************/
        return Object.keys(errors).length === 0;
    }

    isFieldVisible(sectionKey, fieldMeta) {
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

            let cur = this.contextBlock; // same as renderer

            // Safe traversal
            for (let p of parts) {
                if (cur === undefined || cur === null) {
                    cur = undefined;
                    break;
                }
                cur = cur[p];
            }

            // ⭐ Special rule support
            if (expected === "__notEmpty" || expected === "__notNull") {
                return cur !== null && cur !== undefined && cur !== "";
            }

            // Normal comparison
            return cur == expected;
        });
    }



    _buildParentBlock(logicalName, data, extraFields = {}, markDelete = false) {
        const meta = this._getParentMeta(logicalName);
        if (!meta) return null;

        const block = {
            sobject: meta.sobject,
            recordName: meta.recordName
        };

        if (markDelete) {
            block.delete = true;
            block.fields = { Id: data.Id };
        } else {
            block.fields = {};

            // Copy fields dynamically
            meta.fieldsToQuery.forEach(api => {
                if (api === meta.parentLookupField) return;
                if (meta.sobject === "Application__c" && api === "Application_Status__c") return;
                block.fields[api] = data[api] ?? null;
            });

            if (meta?.parentLookupField) {
                block.fields[meta.parentLookupField] = this.application.Id;
            }

            Object.assign(block.fields, extraFields);
        }

        if (meta.filter) {
            block.filter = meta.filter;   // Map from context
        }

        return block;
    }

    _getParentMeta(logicalName) {
        if (!context.parents) return null;
        return context.parents.find(p => p.logicalName === logicalName) || null;
    }

    /**********************************************
     * SAVE PAYLOAD
     **********************************************/
    buildParentSavePayload() {
        const out = {};
       
        // 1️⃣ APPLICATION (dynamic + extra normalization fields)
        const appExtra = {
            Batch__c: this.application.Batch__c
        };

        out.application = this._buildParentBlock("application", this.application, appExtra);

        // 4️⃣ PROGRAMME DETAIL (always save)
        out.programDetail = this._buildParentBlock("programDetail", this.program);

        return out;
    }
    
    @api async saveForm() {
        if(this.isReadOnly) return true;

        this.isLoading = true;
        if (!this.validateAll()) {
            console.error('Validation failed');
            this.template.querySelector('c-af-section-engine').reportValidity();
            this.isLoading = false;
            return false;
        }

        const payload = this.buildParentSavePayload();

        try {
            await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify(payload),
            });

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Programme Details' 
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Saved successfully',
                variant: 'success',
            }));

            await this.fetchForm(this.application.Id);
            return true
            
        } catch (err) {
            console.error('save error', err);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Save failed',
                message: 'Please try again',
                variant: 'error',
            }));
            return false;
        } finally {
            this.isLoading = false;
        }
        
    }
}