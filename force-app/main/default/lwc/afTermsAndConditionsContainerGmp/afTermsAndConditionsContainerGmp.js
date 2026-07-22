// afTermsAndConditionsContainerGmp.js
import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';
import fetchMetadataBulk from "@salesforce/apex/ApFormDataController.fetchMetadataBulk";

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { buildErrorSummary, convertToTitleCase } from "c/applicationFormService";

export default class AfTermsAndConditionsContainerGmp extends LightningElement {

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

    // model follows BasicDetails pattern: tc.{terms, documents, certificates}
    @track tc = {
        terms: {},
        basicAcademic: {},
        documents: {},
        otherDocuments: {},
        certificates: {}
    };

    metadata = {};
    @track sectionModel = [];

    picklistCache = {};
    dependentCache = {};

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

            const metaResp = await fetchMetadataBulk({
                requests: [
                    {
                        metadataName: 'Discounted_Progam_Code__mdt',
                        fields: ['ProgramCode__c','StartingRange__c','EndingRange__c'],
                        filters: [
                            { field: 'MasterLabel', operator: '=', value: 'GMP' }
                        ]
                    }
                ]
            });

            // store as map for fast lookup
            this.programRangeList = metaResp?.Discounted_Progam_Code__mdt || [];

            if (!this.programRangeList.length) {
                console.warn('No metadata found for Label = GMP');
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
        // -------- Competitive --------
        const competitiveExams = (this.tc.terms.CompetitiveExams__c || "")
            .split(";")
            .map(e => e.trim())
            .filter(Boolean);

        const competitiveFields = competitiveExams.map(exam => {
            const safe = exam.replace(/[^A-Za-z0-9]/g, "");
            return {
                api: `${safe}CompetitiveCertificate__c`,
                type: "file",
                label: `${exam} Score Card`,
                docCode: `DOC_COMPETITIVE_${safe}`,
                maxFiles: 1,
                accept : ['.png', '.jpg', '.jpeg', '.pdf'],
                required: true,
                visibleWhen: { "terms.CompetitiveExams__c": "__notEmpty" }
            };
        });


        // -------- Language --------
        const languageExams = (this.tc.terms.LanguageProficiencyExams__c || "")
            .split(";")
            .map(e => e.trim())
            .filter(Boolean);

        const languageFields = languageExams.map(exam => {
            const safe = exam.replace(/[^A-Za-z0-9]/g, "") || "Language";

            return {
                api: `${safe}LanguageCertificate__c`,
                type: "file",
                label: `${exam} Certificate`,
                docCode: `DOC_LANGUAGE_${safe}`,
                maxFiles: 1,
                accept : ['.png', '.jpg', '.jpeg', '.pdf'],
                required: true,
                visibleWhen: { "terms.HasLanguageProficiency__c": "Yes" }
            };
        });

        const allCertificateFields = [...competitiveFields, ...languageFields];

        const certificateRows = [];

        for (let i = 0; i < allCertificateFields.length; i += 2) {
            certificateRows.push({
                columns: [
                    {
                        width: 6,
                        fields: [allCertificateFields[i].api]
                    },
                    ...(allCertificateFields[i + 1]
                        ? [{ width: 6, fields: [allCertificateFields[i + 1].api] }]
                        : [{ width: 6, fields: [] }])
                ]
            });
        }

        this.metadata.certificates.rows = certificateRows;
        this.metadata.certificates.fields = allCertificateFields;

        let academicRows = [];
        let academicFields = [];

        // -------- documents --------
        if(this.tc.basicAcademic.AfterTen__c == "12th") {
            academicRows.push({ columns: [{ width: 6, fields: ["ClassX_Document__c"] }, { width: 6, fields: ["ClassXII_Document__c"] } ] });
            academicFields.push({ api: "ClassX_Document__c", type: "file", label: "Class X Marksheet", docCode: "DOC_CLASS_X", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
            academicFields.push({ api: "ClassXII_Document__c", type: "file", label: "Class XII Marksheet", docCode: "DOC_CLASS_XII", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
        }
        if(this.tc.basicAcademic.AfterTen__c == "diploma") {
            academicRows.push({ columns: [{ width: 6, fields: ["ClassX_Document__c"] }, { width: 6, fields: ["Diploma_Document__c"] } ] });
            academicFields.push({ api: "ClassX_Document__c", type: "file", label: "Class X Marksheet", docCode: "DOC_CLASS_X", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
            academicFields.push({ api: "Diploma_Document__c", type: "file", label: "Diploma Marksheet", docCode: "DOC_DIPLOMA", maxFiles: 10, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
        }
        if(this.tc.basicAcademic.AfterTen__c == "both"){
            academicRows.push({ columns: [{ width: 6, fields: ["ClassX_Document__c"] }, { width: 6, fields: ["ClassXII_Document__c"] } ] });
            academicRows.push({ columns: [{ width: 6, fields: ["Diploma_Document__c"] }] });
            academicFields.push({ api: "ClassX_Document__c", type: "file", label: "Class X Marksheet", docCode: "DOC_CLASS_X", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
            academicFields.push({ api: "ClassXII_Document__c", type: "file", label: "Class XII Marksheet", docCode: "DOC_CLASS_XII", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
            academicFields.push({ api: "Diploma_Document__c", type: "file", label: "Diploma Marksheet", docCode: "DOC_DIPLOMA", maxFiles: 10, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true });
        }
        if(this.tc.basicAcademic.GraduationCompleted__c == "Yes" && (this.tc.basicAcademic.AnyPostGraduation__c == "No" || this.tc.basicAcademic.AnyPostGraduation__c ===false)) {
            academicRows.push({ columns: [{ width: 6, fields: ["Graduation_Document__c"] }] });
            academicFields.push({ api: "Graduation_Document__c", type: "file", label: "Graduation Marksheet", docCode: "DOC_GRAD", maxFiles: 14 , accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true })
        }
        if((this.tc.basicAcademic.GraduationCompleted__c == "No" || this.tc.basicAcademic.GraduationCompleted__c === false) && this.tc.basicAcademic.AnyPostGraduation__c == "Yes") {
            academicRows.push({ columns: [{ width: 6, fields: ["PostGraduation_Document__c"] }] });
            academicFields.push({ api: "PostGraduation_Document__c", type: "file", label: "Post Graduation Marksheet", docCode: "DOC_POST_GRAD", maxFiles: 10, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true })
        }
        if(this.tc.basicAcademic.GraduationCompleted__c == "Yes" && this.tc.basicAcademic.AnyPostGraduation__c == "Yes") {
            academicRows.push({ columns: [{ width: 6, fields: ["Graduation_Document__c"] }, { width: 6, fields: ["PostGraduation_Document__c"] }] });
            academicFields.push({ api: "Graduation_Document__c", type: "file", label: "Graduation Marksheet", docCode: "DOC_GRAD", maxFiles: 14, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true })
            academicFields.push({ api: "PostGraduation_Document__c", type: "file", label: "Post Graduation Marksheet", docCode: "DOC_POST_GRAD", maxFiles: 10, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required: true })
        }

        this.metadata.documents.rows = academicRows;
        this.metadata.documents.fields = academicFields;

    }

    /* ===========================================================
       BUILD METADATA (skeleton) — follows BasicDetails style
       =========================================================== */
    _buildMetadataSkeleton() {

        this.metadata = {
            terms: {
                key: "terms",
                title: "Terms & Conditions",
                columnSystem: 12,
                rows: [
                    {
                        columns: [
                            { width: 6, fields: ["ReferralSource__c"] },
                            { width: 6, fields: ["ReferralName__c"] }
                        ]
                    },
                    {
                        columns: [
                            { width: 6, fields: ["OtherProgrammeApplied__c"] },
                            { width: 6, fields: ["OtherProgrammeRegNo__c"] }
                        ]
                    },
                    {
                        columns:[
                            {width: 12, fields: ["TC_NOTE"]}
                        ]
                    },
                    {
                        columns: [{ width: 12, fields: ["AgreeToTerms__c"] }]
                    }
                ],
                fields: [
                    { api: "ReferralSource__c", type: "picklist", label: "How did you get to know about the Institute?", required: true, options: [] },
                    { api: "ReferralName__c", type: "text", label: "Referral Name", helpText: "Required only if you selected Alumni / Friends / Current Student", maxlength: '100', },
                    { api: "OtherProgrammeApplied__c", type: "picklist", label: "Have you applied for any other SPJIMR Programme?", helpText:"Applicants previously registered for PGDM/PGPM may claim a 50% waiver on the GMP application fees. Please enter your valid Registration Number to avail it.",required: false, options: [] },
                    { api: "OtherProgrammeRegNo__c", type: "text", label: "Registration Number", required: true, maxlength: '20', visibleWhen : { "terms.OtherProgrammeApplied__c": "__notNull" } },
                    { 
                        api: "TC_NOTE", 
                        type: "note",
                        text: `
<b>Terms & Conditions</b><br/>
1. The right to carry out the admission process for Global Management Programme lies with SPJIMR.<br/>
2. SPJIMR reserves the exclusive right to reject any application for incorrect or insufficient information.<br/>
3. A non-refundable application fee of INR 2000 is required.<br/>
4. All disputes fall under the jurisdiction of Mumbai.<br/>
5. SPJIMR may communicate with you via email.
                        `
                    },
                    { api: "AgreeToTerms__c", type: "checkbox", label: "I declare that I have read and agree to the Terms and Conditions.", shortLabel:"Terms & Conditions" ,required: true }
                ]
            },

            // file placeholders (metadata only — NOT included in context)
            documents: {
                key: "documents",
                title: "Academic Document Uploads",
                columnSystem: 12,
                rows: [],
                fields: []
            },

            otherDocuments: {
                key: "otherDocuments",
                title: "Other Document Uploads",
                columnSystem: 12,
                rows: [
                    { columns: [{ width: 6, fields: ["ExtraCurricularAchivements_Document__c"] }, { width: 6, fields: ["LOR_Academic_Document__c"] },] },
                    { columns: [{ width: 6, fields: ["Resume_Document__c"] }, { width: 6, fields: ["LOR_Professional_Document__c"] },] },
                    { columns: [{ width: 6, fields: ["AppointmentOrder_Document__c"] }, { width: 6, fields: ["SalarySlip_Document__c"] }] },
                    { columns: [{ width: 6, fields: ["Experience_Letter__c"] }] }
                ],
                fields: [
                    { api: "Resume_Document__c", type: "file", label: "Resume", docCode: "DOC_RESUME", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], required:true },
                    { api: "LOR_Academic_Document__c", type: "file", label: "LOR (Academic)", docCode: "DOC_LOR_ACAD", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'] },
                    { api: "LOR_Professional_Document__c", type: "file", label: "LOR (Professional)", docCode: "DOC_LOR_PROF", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], visibleWhen: { "terms.HasWorkExperience__c": "Yes" } },
                    { api: "ExtraCurricularAchivements_Document__c", type: "file", label: "Extra-Curricular Achivements (Max 3)", shortLabel:'Extra-Curricular Achivements', docCode: "DOC_EXTRA_CURRICULAR_ACTIVITIES", maxFiles: 3, accept : ['.png', '.jpg', '.jpeg', '.pdf'] },
                    { api: "AppointmentOrder_Document__c", type: "file", label: "Appointment Letter", docCode: "DOC_APPOINTMENT_ORDER", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], visibleWhen: { "terms.HasWorkExperience__c": "Yes" } },
                    { api: "SalarySlip_Document__c", type: "file", label: "Salary Slip", docCode: "DOC_SALARY_SLIP", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], visibleWhen: { "terms.HasWorkExperience__c": "Yes" } },
                    { api: "Experience_Letter__c", type: "file", label: "Experience Letter", docCode: "DOC_EXPERIENCE_LETTER", maxFiles: 1, accept : ['.png', '.jpg', '.jpeg', '.pdf'], visibleWhen: { "terms.HasWorkExperience__c": "Yes" } },
                ]
            },

            certificates : {
                key: "certificates",
                title: "Entrance Exam Score Card",
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

        setOptions("terms", "ReferralSource__c", toOptions(pick.ReferralSource__c));
        setOptions("terms", "OtherProgrammeApplied__c", toOptions(pick.OtherProgrammeApplied__c));

    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfTermsAndConditionsContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfTermsAndConditionsContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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

            // Map response into section-scoped model (BasicDetails style)
            // terms data comes from resp.application (logicalName 'application' per context)
            this.tc.terms = resp.application || {};
            this.tc.basicAcademic = resp.basicAcademic || {};

            // documents & certificates remain empty objects (uploader will populate)
            this.tc.documents = this.tc.documents || {};
            this.tc.otherDocuments = this.tc.otherDocuments || {};
            this.tc.certificates = this.tc.certificates || {};

            this.tc.applicationId = this.application?.Id;

            this._updateDynamicRequired();

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
        const keys = ["terms", "documents", "otherDocuments"];
        if(this.metadata.certificates.fields.length > 0) {
            keys.push("certificates");
        }
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

                    // non-note fields -> come from tc[sectionKey]
                    if (fMeta.type !== "note") {
                        val = this.tc[sectionKey] ? this.tc[sectionKey][api] ?? null : null;
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

        if (!this.tc[sectionKey]) this.tc[sectionKey] = {};

        this.tc[sectionKey][api] = files?.length ? documentId : undefined;
        this.tc[sectionKey].fileInfo ||= {}
        this.tc[sectionKey].fileInfo[api] = {fileLength: files?.length, files: files};

        // Rebuild render model so uploaders reflect new state
        this._buildRenderModelAll();
    }
    

    /* ===========================================================
       FIELD CHANGE (BasicDetails pattern)
       event.detail: { api, value, sectionKey }
       =========================================================== */
    handleSectionFieldChange(event) {
        let { api, value, sectionKey, browserEventType } = event.detail;

        const titleCaseFields = [
            'ReferralName__c'
        ];
        
        if (titleCaseFields.includes(api) && typeof value === 'string') {
            if(browserEventType === 'blur'){
                value = convertToTitleCase(value);
            }
        }

        const fieldMeta = this.metadata[sectionKey]?.fields?.find((f) => f.api === api) || {};

        const normalized = this._normalizeValue(api, value, fieldMeta);

        if (!this.tc[sectionKey]) this.tc[sectionKey] = {};
        this.tc[sectionKey][api] = normalized;

        this._updateDynamicRequired();

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

            let cur = this.tc; // same as renderer

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

    _updateDynamicRequired() {
        const termsFields = this.metadata?.terms?.fields || [];

        termsFields.forEach(f => {
            if (f.api === "ReferralName__c") {
                const source = this.tc?.terms?.ReferralSource__c;

                f.required = ["Alumni", "Friends/Relatives", "Current Student"].includes(source);
            }
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
                    const val = this.tc[sectionKey] ? this.tc[sectionKey][f.api] : undefined;
                    let empty = val === "" || val === null || val === undefined || (Array.isArray(val) && val.length === 0);
                    if(f.type === "checkbox" && val === false){
                        empty = true;
                    }
                    if (empty) {
                        errors[sectionKey] = errors[sectionKey] || {};
                        errors[sectionKey][f.api] = `${f?.shortLabel || f.label || f.api} is required`;
                    }
                }

                if (f.api === 'OtherProgrammeRegNo__c') {
                    const value = this.tc[sectionKey]?.[f.api];

                    // run only if user entered something
                    if (value) {
                        const isValid = this._validateProgramRange(value);

                        if (!isValid) {
                            errors[sectionKey] = errors[sectionKey] || {};
                            errors[sectionKey][f.api] = `Enter a valid Registration Number to vail the  waiver.`;
                        }

                        if (isValid && !this.hasShownWaiverToast) {
                            this.hasShownWaiverToast = true;

                            this.dispatchEvent(
                                new ShowToastEvent({
                                    title: 'Eligible for Waiver',
                                    message: "You're eligible for a 50% waiver on the GMP application fee. The discount is already applied to your order.",
                                    variant: 'success',
                                    mode: 'sticky'
                                })
                            );
                        }
                    }
                }

                if(['documents','certificates','otherDocuments'].includes(sectionKey)){
                    const fileLength = this.tc?.[sectionKey]?.fileInfo?.[f.api]?.fileLength ?? 0;
                    const maxAllowed = Number(f.maxFiles || 0);

                    if (maxAllowed > 0 && fileLength > maxAllowed) {
                        errors[sectionKey] = errors[sectionKey] || {};
                        errors[sectionKey][f.api] = `${f?.shortLabel || f.label || f.api} cannot exceed ${maxAllowed} files (Currently uploaded: ${fileLength})`;
                    }
                }
            });
        });

        // dispatch errors to wrapper (BasicDetails pattern)
        const wrapper = this.template.querySelector("c-af-terms-and-conditions");
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

    hasShownWaiverToast = false;

    _validateProgramRange(value) {

        if (!value) return true;

        const ranges = this.programRangeList || [];
        if (!ranges.length) return true;

        const sortedRanges = ranges; // already sorted in connectedCallback

        return sortedRanges.some(config => {

            const prefix = config.ProgramCode__c;

            if (!value.startsWith(prefix)) return false;

            const afterPrefix = value.slice(prefix.length);

            // ✅ enforce numeric
            if (!afterPrefix || !/^\d+$/.test(afterPrefix)) return false;

            // ✅ enforce length using metadata
            const expectedLength = config.StartingRange__c.length;

            if (value.length !== expectedLength) return false;

            // ✅ final range check
            return value >= config.StartingRange__c &&
                value <= config.EndingRange__c;
        });
    }

    /* ===========================================================
       BUILD SAVE PAYLOAD (only terms is saved to Application__c per context)
       =========================================================== */
    buildSavePayload() {
        
        // Clear OtherProgrammeRegNo__c only on save when OtherProgrammeApplied__c is blank/not 'Yes'
        if (this.tc?.terms) {
            const applied = this.tc.terms.OtherProgrammeApplied__c;
            const isBlankOrNotYes =
                applied === null || applied === undefined || applied === '' || applied == 'None';
            if (isBlankOrNotYes) {
                this.tc.terms.OtherProgrammeRegNo__c = null;
            }
        }

        const out = {};

        context.parents.forEach((p) => {
            if (p.logicalName == 'basicAcademic') return;
            const logical = p.logicalName; // "application"
            const model = this.tc.terms || {};

            // Safety net: enforce clearing before mapping to fields
            const applied = model.OtherProgrammeApplied__c;
            if (applied === null || applied === undefined || applied === '' || applied == 'None') {
                model.OtherProgrammeRegNo__c = null;
            }

            const block = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: {}
            };

            (p.fieldsToQuery || []).forEach((api) => {
                if(p.sobject === "Application__c" && api === "Application__c") return;
                if(p.sobject === "Application__c" && api === "Application_Status__c") return;
                if (api === "Id") {
                    if (model.Id) block.fields.Id = model.Id;
                } else {
                    block.fields[api] = model[api] ?? this.application[api] ?? null;
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
                newStage: 'Terms and Conditions' 
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