import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { buildErrorSummary, convertToTitleCase } from "c/applicationFormService";

export default class AfUploadDocumentsContainerPgpm extends LightningElement {

    isLoading = true; // Start spinner immediately

    application = { Id: 'a0EC10000048Qd1MAE', RequiredFilesUploaded__c: 'Yes' };

    _applicationId;
    
    @api
    set applicationId(value) {
        this._applicationId = value;
        this.application.Id = value;   // <-- assign to your class-level property
    }
    
    get applicationId() {
        return this._applicationId;
    }

    @track personalDetails = {};

    // model follows BasicDetails pattern: document.{application, documents}
    @track document = {
        application: {},
        basicAcademic: {},
        documents: {},
        otherDocuments: {},
        personalDetails: {}
    };

    metadata = {};
    @track sectionModel = [];

    picklistCache = {};
    dependentCache = {};

    ACADEMIC_DOCUMENTS = {
        CLASS_X_MARKSHEET: {
            api: "ClassX_Marksheet__c",
            label: "Upload Your 10th Marksheet",
            docCode: "DOC_CLASS_X_MARKSHEET",
            shortLabel: '10th Marksheet'
        },

        CLASS_X_CERTIFICATE: {
            api: "ClassX_Certificate__c",
            label: "Upload Your 10th Certificate",
            docCode: "DOC_CLASS_X_CERTIFICATE",
            required: false,
            shortLabel: '10th Certificate'
        },

        CLASS_XII_MARKSHEET: {
            api: "ClassXII_Marksheet__c",
            label: "Upload Your 12th Marksheet",
            docCode: "DOC_CLASS_XII_MARKSHEET",
            shortLabel: '12th Marksheet'
        },

        CLASS_XII_CERTIFICATE: {
            api: "ClassXII_Certificate__c",
            label: "Upload Your 12th Certificate",
            docCode: "DOC_CLASS_XII_CERTIFICATE",
            required: false,
            shortLabel: '12th Certificate'
        },

        DIPLOMA_MARKSHEET: {
            api: "Diploma_Marksheet__c",
            label: "Upload Your Diploma Marksheet",
            docCode: "DOC_DIPLOMA_MARKSHEET",
            maxFiles: 10,
            shortLabel: 'Diploma Marksheet',
        },

        DIPLOMA_CERTIFICATE: {
            api: "Diploma_Certificate__c",
            label: "Upload Your Diploma Certificate",
            docCode: "DOC_DIPLOMA_CERTIFICATE",
            shortLabel: 'Diploma Certificate'
        },

        GRADUATION_MARKSHEET: {
            api: "Graduation_Marksheet__c",
            label: "Upload Your Graduation Marksheet",
            docCode: "DOC_GRAD_MARKSHEET",
            maxFiles: 10,
            shortLabel: 'Graduation Marksheet',
        },

        GRADUATION_CERTIFICATE: {
            api: "Graduation_Certificate__c",
            label: "Upload Your Graduation Certificate",
            docCode: "DOC_GRAD_CERTIFICATE",
            required: true,
            shortLabel: 'Graduation Certificate'
        },

        POST_GRADUATION_MARKSHEET: {
            api: "PostGraduation_Marksheet__c",
            label: "Upload Your Post Graduation Marksheet",
            docCode: "DOC_PG_MARKSHEET",
            maxFiles: 10,
            required: true,
            shortLabel: 'Post Graduation Marksheet'
        },

        POST_GRADUATION_CERTIFICATE: {
            api: "PostGraduation_Certificate__c",
            label: "Upload Your Post Graduation Certificate",
            docCode: "DOC_PG_CERTIFICATE",
            shortLabel: 'Post Graduation Certificate'
        },

        CONVERSION_FACTOR: {
            api: "ConversionFactorCertificate__c",
            label: "Upload Conversion factor Certificate",
            docCode: "DOC_CONVERSION_FACTOR",
            required: false,
            span: 12,
            shortLabel: 'Conversion factor Certificate'
        }
    };

    _buildAcademicDocumentFields() {

        const docs = [];
        const catalog = this.ACADEMIC_DOCUMENTS;

        // 10th always
        docs.push(
            catalog.CLASS_X_MARKSHEET,
            catalog.CLASS_X_CERTIFICATE
        );

        // 12th
        if (
            this.document.basicAcademic.AfterTen__c === "12th" ||
            this.document.basicAcademic.AfterTen__c === "both"
        ) {
            docs.push(
                catalog.CLASS_XII_MARKSHEET,
                catalog.CLASS_XII_CERTIFICATE
            );
        }

        if (
            this.document.basicAcademic.AfterTen__c === "Diploma" ||
            this.document.basicAcademic.AfterTen__c === "both"
        ) {
            docs.push(
                catalog.DIPLOMA_MARKSHEET,
                catalog.DIPLOMA_CERTIFICATE
            );
        }

        // Graduation
        if (this.document.basicAcademic.GraduationCompleted__c === "Yes") {
            docs.push(
                catalog.GRADUATION_MARKSHEET,
                catalog.GRADUATION_CERTIFICATE
            );
        }

        // Post Graduation
        if (this.document.basicAcademic.AnyPostGraduation__c === "Yes") {
            docs.push(
                catalog.POST_GRADUATION_MARKSHEET,
                catalog.POST_GRADUATION_CERTIFICATE
            );
        }

        // Conversion Factor
        docs.push(
            catalog.CONVERSION_FACTOR
        );

        return docs.map(d => this.createDocumentField(d));
    }

    async connectedCallback() {
        // load picklists first (BasicDetails pattern)

        try {
            const data = await getAllPicklistsForObjects({ objectApiNames: ["Application__c"] })
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

        const academicFields =
            this._buildAcademicDocumentFields();

        this.metadata.documents.fields =
            academicFields;

        const workFields = [];

        if (this.document.application.HasWorkExperience__c === "Yes") {

            workFields.push(
                this.createDocumentField({
                    api: "OfferLetter_Document__c",
                    label: "Upload Your Offer Letter (Latest company)",
                    shortLabel: 'Offer Letter',
                    docCode: "DOC_OFFER_LETTER",
                })
            );

            workFields.push(
                this.createDocumentField({
                    api: "SalarySlip_Document__c",
                    label: "Upload Your pay slip of last 3 months (current Organisation only)",
                    shortLabel: 'Pay slip',
                    docCode: "DOC_SALARY_SLIP",
                })
            );

            for (let i = 1; i < this.workExperienceCount; i++) {

                workFields.push(
                    this.createDocumentField({
                        api: `Work_Experience_Certificate_${i}__c`,
                        label: `Upload Your Work Experience Certificate ${i}`,
                        shortLabel: `Work Experience Certificate ${i}`,
                        docCode: `DOC_WORK_EXP_${i}`,
                        maxFiles: 1,
                        required: true,
                    })
                );
            }

        }

        this.metadata.workDocs.fields = workFields;

        const identityFields = [];

        if (this.personalDetails?.PassportNumber__c) {

            identityFields.push(
                this.createDocumentField({
                    api: "Passport__c",
                    label: "Passport",
                    docCode: "DOC_PASSPORT",
                    helpText: "Upload first and last page of passport"
                })
            );
        }

        if (this.personalDetails?.AadhaarCardNumber__c) {

            identityFields.push(
                this.createDocumentField({
                    api: "Aadhaar__c",
                    label: "Aadhaar",
                    docCode: "DOC_AADHAAR",
                    helpText: "Upload front and back side"
                })
            );
        }

        this.metadata.identity.fields = identityFields;

    }

    /* ===========================================================
       BUILD METADATA (skeleton) — follows BasicDetails style
       =========================================================== */
    _buildMetadataSkeleton() {

        this.metadata = {

            // file placeholders (metadata only — NOT included in context)
            documents: {
                key: "documents",
                title: "Education Documents",
                columnSystem: 12,
                layout: "fluid",
                fields: []
            },

            identity: {
                key: "identity",
                title: "Identity Document Uploads",
                columnSystem: 12,
                layout: "fluid",
                fields: []
            },

            workDocs: {
                key: "workDocs",
                title: "Work Experience Documents",
                columnSystem: 12,
                layout: "fluid",
                fields: []
            },

            otherDocuments: {
                key: "otherDocuments",
                title: "Academic / Professional Achievement Documents",
                columnSystem: 12,
                layout: "fluid",
                fields: [
                    {
                        api: "AcademicProfessionalAchievements__c",
                        span: 12,
                        type: "file",
                        label: "Upload academic/professional achievement documents",
                        shortLabel: "Achievement Documents",
                        docCode: "DOC_ACHIEVEMENTS",
                        maxFiles: 10,
                        accept: ['.png', '.jpg', '.jpeg', '.pdf']
                    }
                ]
            }

        };
    }

    /* ===========================================================
       INJECT PICKLISTS (BasicDetails style)
       =========================================================== */
    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr =>
            (arr || []).map(o => ({ label: o.label || o, value: o.value || o }));

        const setOptions = (sectionKey, api, arr) => {
            const sec = this.metadata[sectionKey];
            if (!sec) return;

            const f = sec.fields.find(x => x.api === api);
            if (!f) return;

            const values = [...arr]; // ← copy to avoid mutating shared array

            if (!f.required) {
                values.push({ label: "None", value: "" });
            }

            f.options = values;
        };

    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfUploadDocumentsContainerPgpm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfUploadDocumentsContainerPgpm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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

            context.children.forEach(c => {
                request.children.push({
                    logicalName: c.logicalName,
                    sobject: c.sobject,
                    fields: c.fieldsToQuery,
                    useSequenceKey : c.useSequenceKey,
                    childKeyField: c.childKeyField,
                    filters: [
                        {
                            field: c.parentLookupField,   // Application__c
                            value: appId
                        },
                        ...(c.filters || [])
                    ]
                });
            });

            

            const resp = await fetchDynamic({ requestJson: JSON.stringify(request) });
            this.application.Application_Status__c = resp?.application?.Application_Status__c;
            this.application.Assignment_Status__c = resp?.application?.Assignment_Status__c;

            //identity documents
            this.personalDetails.PassportNumber__c = resp?.personalDetails?.PassportNumber__c;
            this.personalDetails.AadhaarCardNumber__c = resp?.personalDetails?.AadhaarCardNumber__c;

            //work experience
            console.log('workExperienceCount '+JSON.stringify(resp.workExperience));
            const workExperience = resp?.workExperience;

            this.workExperienceCount = Object.entries(workExperience || {}).length;
            
            // Map response into section-scoped model (BasicDetails style)
            // application data comes from resp.application (logicalName 'application' per context)
            this.document.application = resp.application || {};
            this.document.basicAcademic = resp.basicAcademic || {};
            this.personalDetails = resp.personalDetails || {};

            // documents remain empty objects (uploader will populate)
            this.document.documents = this.document.documents || {};
            this.document.otherDocuments = this.document.otherDocuments || {};

            this.document.applicationId = this.application?.Id;

            this._buildDynamicCertificateMetadata();

            this._applyReadOnlyMode();
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
        this._applyReadOnlyMode();

        const keys = [];

        if (this.metadata.identity.fields.length) {
            keys.push("identity");
        }

        keys.push("documents");

        if (this.metadata.workDocs.fields.length) {
            keys.push("workDocs");
        }

        keys.push("otherDocuments");

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

        const rows =
            meta.layout === 'fluid'
                ? this._buildFluidMetadataRows(meta)
                : (meta.rows || []);

        rows.forEach((r, rIdx) => {
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

                    // non-note fields -> come from document[sectionKey]
                    if (fMeta.type !== "note") {
                        val = this.document[sectionKey] ? this.document[sectionKey][api] ?? null : null;
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

    _buildFluidMetadataRows(meta) {

        const rows = [];
        const cs = meta.columnSystem || 12;

        let currentRow = {
            columns: []
        };

        let used = 0;

        (meta.fields || []).forEach(field => {

            if (!this._isFieldVisible(field)) {
                return;
            }

            const span = field.span || 6;

            if ((used + span) > cs) {

                rows.push(currentRow);

                currentRow = {
                    columns: []
                };

                used = 0;
            }

            currentRow.columns.push({
                width: span,
                fields: [field.api]
            });

            used += span;
        });

        if (currentRow.columns.length) {
            rows.push(currentRow);
        }

        return rows;
    }

    createDocumentField({
        api,
        label,
        shortLabel,
        docCode,
        maxFiles = 1,
        required = true,
        span = 6,
        helpText
    }){
        return {
            api,
            type: "file",
            label,
            shortLabel,
            docCode,
            maxFiles,
            accept: ['.png', '.jpg', '.jpeg', '.pdf'],
            required,
            span,
            helpText
        };
    }

    /* ===========================================================
       DOCUMENT UPLOAD HANDLER (BasicDetails pattern)
       event.detail: { documentId, files, api, sectionKey }
       =========================================================== */
    handleDocsFetched(event) {
        const { documentId, files, api, sectionKey } = event.detail;

        if (!this.document[sectionKey]) this.document[sectionKey] = {};

        this.document[sectionKey][api] = files?.length ? documentId : undefined;
        this.document[sectionKey].fileInfo ||= {}
        this.document[sectionKey].fileInfo[api] = {fileLength: files?.length, files: files};

        console.log('handleDocsFetched '+JSON.stringify(this.document[sectionKey].fileInfo));

        // Rebuild render model so uploaders reflect new state
        this._buildRenderModelAll();
    }
    

    /* ===========================================================
       FIELD CHANGE (BasicDetails pattern)
       event.detail: { api, value, sectionKey }
       =========================================================== */
    handleSectionFieldChange(event) {
        let { api, value, sectionKey, browserEventType } = event.detail;

        const fieldMeta = this.metadata[sectionKey]?.fields?.find((f) => f.api === api) || {};

        const normalized = this._normalizeValue(api, value, fieldMeta);

        if (!this.document[sectionKey]) this.document[sectionKey] = {};
        this.document[sectionKey][api] = normalized;

        this._buildDynamicCertificateMetadata();
        this._applyReadOnlyMode();
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

            let cur = this.document; // same as renderer

            // Safe traversal
            for (let p of parts) {
                if (cur === undefined || cur === null) {
                    cur = undefined;
                    break;
                }
                cur = cur[p];
            }

            // ⭐ Special rule support
            if (Array.isArray(expected)) {
                return expected.includes(cur);
            }

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
                    const val = this.document[sectionKey] ? this.document[sectionKey][f.api] : undefined;
                    let empty = val === "" || val === null || val === undefined || (Array.isArray(val) && val.length === 0);
                    if(f.type === "checkbox" && val === false){
                        empty = true;
                    }
                    if (empty) {
                        errors[sectionKey] = errors[sectionKey] || {};
                        errors[sectionKey][f.api] = `${f?.shortLabel || f.label || f.api} is required`;
                    }
                }

                if(['identity','documents','workDocs','otherDocuments'].includes(sectionKey)){
                    const fileLength = this.document?.[sectionKey]?.fileInfo?.[f.api]?.fileLength ?? 0;
                    const maxAllowed = Number(f.maxFiles || 0);

                    if (maxAllowed > 0 && fileLength > maxAllowed) {
                        errors[sectionKey] = errors[sectionKey] || {};
                        errors[sectionKey][f.api] = `${f?.shortLabel || f.label || f.api} cannot exceed ${maxAllowed} files (Currently uploaded: ${fileLength})`;
                    }
                }
            });
        });

        // dispatch errors to wrapper (BasicDetails pattern)
        const wrapper = this.template.querySelector("c-af-section-engine");
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
       BUILD SAVE PAYLOAD (only application is saved to Application__c per context)
       =========================================================== */
    buildSavePayload() {

        const out = {};

        context.parents.forEach((p) => {
            if (p.logicalName == 'basicAcademic') return;
            const logical = p.logicalName; // "application"

            const block = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: {}
            };

            (p.fieldsToQuery || []).forEach((api) => {
                if(p.sobject === "Application__c" && api === "Application__c") return;
                if(p.sobject === "Application__c" && api === "Application_Status__c") return;
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

        console.log('payload '+JSON.stringify(payload));

        try {
            //await saveParents({ payloadJson: JSON.stringify(payload) });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: "Saved successfully",
                    variant: 'success'
                })
            );

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Upload Documents'
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