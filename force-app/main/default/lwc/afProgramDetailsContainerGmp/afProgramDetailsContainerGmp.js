import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { validateMinMaxDate, validateNumber } from 'c/applicationFormService';

import { buildErrorSummary } from 'c/applicationFormService';

const EXAM_RULES = {
    gmat: { score: { field: 'GMAT_Total_Score__c', min: 550, max: 800 } },
    gre: { score: { field: 'GRE_Total_Score__c', min: 300, max: 340 } },
    cat: { score: { field: 'CAT_Overall_Percentile__c', min: 80, max: 100 } },
    xat: { score: { field: 'XAT_Total_Percentile__c', min: 80, max: 100 } },
    nmat: { score: { field: 'Total_NMAT_Score_Obtained__c', min: 230, max: 360 } },
    gmatFocus: { score: { field: 'GMAT_Focus_Edition_Total_Score__c', min: 525, max: 805 } }
};

const ELIGIBILITY_ERROR =
    'You do not meet the eligibility criteria, contact 9820866719 / 9820618910';


export default class AfProgramDetailsContainerGmp extends LightningElement {

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

    @track ugAcademic = {};
    @track basicAcademic = {};
    @track program = {};
    @track education = {};
    @track examSections = [];
    picklistCache = {};
    selectedBatchUpperAgeBound = null;
    // Track soft-deletions of exam sections until user saves
    // Structure: { [examKey]: { data: {...lastKnown}, removedAt: Date.now() } }
    removedExams = {};

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
            this._applyExamRulesToMetadata();
            this._injectPicklists();
            await this.fetchForm(this.application.Id);
        } catch (err) {
            console.warn("picklist load failed", err);
            this._buildMetadata();
            this._applyExamRulesToMetadata();
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

        /***********************************
         * APPLICATION SECTION (🔥 Batch moved here)
         ***********************************/

        this.metadata.instructions = {
            key: "instructions",
            note: {
                api: "SECTION_NOTE",
                type: "note",
                text: `
<b>Instructions for filling the GMP & Partner School Application Form</b><br/><br/>

• A candidate can select a maximum of two partner schools (primary & backup/secondary). In case you are not selected by the first school, you will be interviewed by the second school. Available options are based on the eligibility criteria of each business school.<br/><br/>

• Application forms for Partner schools are independent of the GMP form. Submit the GMP Application form FIRST by paying INR 2000 and then start filling the Partner School Application form. Kindly note that the Partner school interviews will be scheduled only if the respective Partner School Application Forms are completed — including transcripts and Letter of Recommendation (LOR) (Professional & Academic).<br/><br/>

• Once the Partner school Application form is complete, kindly mail the same to the partner school with a cc to: <a href="mailto:?cc=gmp.admissions@spjimr.org">gmp.admissions@spjimr.org</a><br/><br/>

• Programmes offered by US partner schools are STEM Designated.<br/><br/>

• <a href="https://www.spjimr.org/course/global-management-programme-gmp/admission/">Click here</a> to know the Important Dates of the Cohort.
`
            },
            rows: [],
            fields: [
                { api: 'SECTION_NOTE', type: 'note' }
            ]
        };


        
        this.metadata.application = {
            key: "application",
            title: "Entrance Exam Availability",
            columnSystem: 12,
            rows: [
                { columns: [{ width: 6, fields: ["Batch__c"] }] },  // 🔥 Add Batch lookup here
                {
                    columns: [
                        { width: 3, fields: ["HasExamScores__c"] },
                        { width: 4, fields: ["PlannedEntranceExams__c"] },
                        { width: 4, fields: ["PlannedExamDate__c"] },
                    ]
                },
                { columns: [{ width: 12, fields: ["CompetitiveExams__c"] }] },
                
            ],

            fields: [
                {
                    api: "HasExamScores__c",
                    type: "radio",
                    label: "Do you have entrance exam scores?",
                    required: true,
                    options: [
                        { label: "Yes", value: "Yes" },
                        { label: "No", value: "No" },
                    ],
                },
                {
                    api: "PlannedExamDate__c",
                    type: "date",
                    label: "When do you plan to give the exam?",
                    required: true,
                    visibleWhen: { "application.HasExamScores__c": "No" },
                    min: new Date().toISOString().split('T')[0],
                    max: new Date(new Date().setFullYear(new Date().getFullYear() + 1)).toISOString().split('T')[0]
                },
                {   
                    api: "PlannedEntranceExams__c", 
                    type: "text", 
                    label: "Planned Entrance Exams",
                    helpText: "If more than one exam is planned, separate them with a semicolon", 
                    visibleWhen: { "application.HasExamScores__c": "No" },
                    required: true,
                    maxlength: "255"
                },
                {
                    api: "CompetitiveExams__c",
                    type: "multipicklist",
                    label: "Select Exam(s)",
                    required: true,
                    visibleWhen: { "application.HasExamScores__c": "Yes" },
                    options: [
                        { label: "GMAT", value: "GMAT" },
                        { label: "GRE", value: "GRE" },
                        { label: "CAT", value: "CAT" },
                        { label: "XAT", value: "XAT" },
                        { label: "NMAT", value: "NMAT" },
                        { label: "GMAT Focus", value: "GMAT Focus" },
                    ],
                },

                /***********************************
                 * 🔥 Batch__c = LOOKUP with dynamic filter
                 ***********************************/
                {
                    api: "Batch__c",
                    type: "lookup",
                    label: "Select Intake Batch",
                    objectApi: "ProgramCohort",
                    required: true,
                    displayFields: {
                        primaryField: 'Name',
                        additionalFields: ['UpperAgeBound__c']
                    },
                    filter: {
                                criteria: [
                                    {
                                        fieldPath: "Program_Code__c",
                                        operator: "eq",
                                        value: 'GMP'
                                    },
                                    {
                                        fieldPath: "IsAcceptingApplications__c",
                                        operator: "eq",
                                        value: true
                                    }
                                ],
                                filterLogic: "1 AND 2"
                            } // 🔥 will be dynamically injected
                }
            ]
        };

        /***************************************
         * COMPETITIVE EXAM METADATA (unchanged)
         ***************************************/
        this.metadata.gmat = {
            key: "gmat",
            sectionLabel: "GMAT",
            columnSystem: 12,
            rows: [{ columns: [{ width: 6, fields: ["GMAT_Total_Score__c"] }] }],
            fields: [
                { api: "GMAT_Total_Score__c", type: "number", step:"0.01", max:"999", label: "GMAT Score", required: true },
            ],
        };

        this.metadata.gre = {
            key: "gre",
            sectionLabel: "GRE",
            columnSystem: 12,
            rows: [{ columns: [{ width: 6, fields: ["GRE_Total_Score__c"] }] }],
            fields: [
                { api: "GRE_Total_Score__c", type: "number", step:"0.01", max:"999", label: "GRE Score", required: true },
            ],
        };

        this.metadata.cat = {
            key: "cat",
            sectionLabel: "CAT",
            columnSystem: 12,
            rows: [{ columns: [{ width: 6, fields: ["CAT_Overall_Percentile__c"] }] }],
            fields: [
                { api: "CAT_Overall_Percentile__c", type: "number", step:"0.01", max:"999", label: "CAT Percentile", required: true },
            ],
        };

        this.metadata.xat = {
            key: "xat",
            sectionLabel: "XAT",
            columnSystem: 12,
            rows: [{ columns: [{ width: 6, fields: ["XAT_Total_Percentile__c"] }] }],
            fields: [
                { api: "XAT_Total_Percentile__c", type: "number", step:"0.01", max:"999", label: "XAT Percentile", required: true },
            ],
        };

        this.metadata.nmat = {
            key: "nmat",
            sectionLabel: "NMAT",
            columnSystem: 12,
            rows: [{ columns: [{ width: 6, fields: ["Total_NMAT_Score_Obtained__c"] }] }],
            fields: [
                { api: "Total_NMAT_Score_Obtained__c", type: "number", step:"0.01", max:"999", label: "NMAT Score", required: true },
            ],
        };

        this.metadata.gmatFocus = {
            key: "gmatFocus",
            sectionLabel: "GMAT Focus",
            columnSystem: 12,
            rows: [{ columns: [{ width: 6, fields: ["GMAT_Focus_Edition_Total_Score__c"] }] }],
            fields: [
                { api: "GMAT_Focus_Edition_Total_Score__c", type: "number", step:"0.01", max:"999", label: "GMAT Focus Score", required: true },
            ],
        };

        this.metadata.basicAcademic = {
            key: "basicAcademic",
            title: "Graduation Status",
            columnSystem: 12,
            rows: [
                { columns: [ 
                    { 
                        width: 4, fields: ["GraduationCompleted__c"]
                    },
                    // {
                    //     width: 4, fields: ["MonthAndYearOfPassing__c"]
                    // }
                ] }
            ],
            fields: [
                {
                    api: "GraduationCompleted__c",
                    type: "picklist",
                    label: "Have you completed your graduation?",
                    required: true,
                    options: [
                        { label: "Yes", value: "Yes" },
                        { label: "No", value: "No" }
                    ]
                },
                // {
                //     api: "ExpectedGraduationDate__c",
                //     type: "date",
                //     label: "Expected graduation Date",
                //     required: true,
                //     min: new Date().toISOString().split('T')[0],
                //     max: new Date(new Date().setFullYear(new Date().getFullYear() + 1)).toISOString().split('T')[0],
                //     visibleWhen: { "basicAcademic.GraduationCompleted__c": "No" },
                //     requiredWhen: { "basicAcademic.GraduationCompleted__c": "No" }
                // },
            ]
        };

        this.metadata.ugAcademic = {
            key: "ugAcademic",
            columnSystem: 12,
            rows: [
                { columns: [ { width: 4, fields: ["MonthAndYearOfPassing__c"] } ] }
            ],
            fields: [
                {
                    api: "MonthAndYearOfPassing__c",
                    type: "monthyear",
                    label: "Graduated Month and Year",
                    required: true,
                    // min:"2009-01-01",
                    // max:new Date().toISOString().split('T')[0],
                    // visibleWhen: { "basicAcademic.GraduationCompleted__c": "Yes" },
                    // requiredWhen: { "basicAcademic.GraduationCompleted__c": "Yes" }
                },
                // {
                //     api: "MonthAndYearOfPassing__c",
                //     type: "monthyear",
                //     label: "Expected graduation Month and Year",
                //     required: true,
                //     min:new Date().toISOString().split('T')[0],
                //     max: new Date(new Date().setFullYear(new Date().getFullYear() + 1)).toISOString().split('T')[0],
                //     visibleWhen: { "basicAcademic.GraduationCompleted__c": "No" },
                //     requiredWhen: { "basicAcademic.GraduationCompleted__c": "No" }
                // }
            ]
        };



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
<b>Note:</b><br/><br/>

• For ESB MBA and EBS MBA, <span style="color:#d0021b;">2 years experience required.</span><br/><br/>

• For IESEG MBA & Aston MBA, <span style="color:#d0021b;">3 years experience required</span>
                        `
                },
            rows: [
                {
                    columns: [
                        { width: 4, fields: ["PrimaryPartnerSchoolPreference__c"] },
                        { width: 4, fields: ["PrimaryPartnerProgramPreference__c"] },
                        { width: 4, fields: ["PrimaryPartnerSpecializationPreference__c"] },
                    ],
                },
                {
                    columns: [
                        { width: 4, fields: ["SecondaryPartnerSchoolPreference__c"] },
                        { width: 4, fields: ["SecondaryPartnerProgramPreference__c"] },
                        { width: 4, fields: ["SecondaryPartnerSpecializationPreference__c"] }
                    ]
                },
            ],
            // fields: [
            //     { api: "PrimaryPartnerSchoolPreference__c", type: "picklist", label: "Primary School Preference", required: true },
            //     { api: "PrimaryPartnerProgramPreference__c", type: "picklist", label: "Primary Programme Preference", required: true },
            //     { api: "PrimaryPartnerSpecializationPreference__c", type: "picklist", label: "Primary Specialisation Preference", required: true },
            //     { api: "SecondaryPartnerSchoolPreference__c", type: "picklist", label: "Secondary School Preference" },
            //     { api: "SecondaryPartnerProgramPreference__c", type: "picklist", label: "Secondary Programme Preference", required: true },
            //     { api: "SecondaryPartnerSpecializationPreference__c", type: "picklist", label: "Secondary Specialisation Preference", required: true },
            // ],
            fields: [
                { 
                    api: "PrimaryPartnerSchoolPreference__c", 
                    type: "lookup", 
                    label: "Primary School Preference", 
                    required: true, 
                    objectApi: "BatchPartnerSchool__c",
                    dynamicFilter: "primarySchool",
                    displayFields: {
                        primaryField: 'PartnerSchool__r.Name',
                    },
                }, // 🔥 will be dynamically injected  },
                { 
                    api: "PrimaryPartnerProgramPreference__c", 
                    type: "lookup", 
                    label: "Primary Programme Preference", 
                    required: true,
                    objectApi: "BatchPartnerProgram__c",
                    dynamicFilter: "primaryProgram",
                    displayFields: {
                        primaryField: 'PartnerProgram__r.Name',
                        additionalFields: ['PartnerProgram__r.ExperienceRequired__c']
                    },
                    visibleWhen: { "programDetail.PrimaryPartnerSchoolPreference__c": '__notNull' },
                },
                { 
                    api: "PrimaryPartnerSpecializationPreference__c",
                    type: "lookup", 
                    label: "Primary Specialisation Preference", 
                    required: true, 
                    objectApi: "Specialisation__c",
                    dynamicFilter: "primarySpecialization",
                    matchingInfo : {
                        primaryField: { fieldPath: 'Specialisation_Name__r.Name'},
                    },
                    displayFields: {
                        primaryField: 'Specialisation_Name__r.Name',
                    },
                    visibleWhen: { "programDetail.PrimaryPartnerProgramPreference__c": '__notNull' },
                },
                { 
                    api: "SecondaryPartnerSchoolPreference__c", 
                    type: "lookup",
                    label: "Secondary School Preference",
                    required: true, 
                    objectApi: "BatchPartnerSchool__c",
                    dynamicFilter: "secondarySchool",
                    displayFields: {
                        primaryField: 'PartnerSchool__r.Name',
                    },
                },
                { 
                    api: "SecondaryPartnerProgramPreference__c",
                    type: "lookup", 
                    label: "Secondary Programme Preference", 
                    required: true,
                    objectApi: "BatchPartnerProgram__c",
                    dynamicFilter: "secondaryProgram",
                    displayFields: {
                        primaryField: 'PartnerProgram__r.Name',
                        additionalFields: ['PartnerProgram__r.ExperienceRequired__c']
                    },
                    visibleWhen: { "programDetail.SecondaryPartnerSchoolPreference__c": '__notNull' },

                },
                { 
                    api: "SecondaryPartnerSpecializationPreference__c", 
                    type: "lookup", 
                    label: "Secondary Specialisation Preference", 
                    required: true,
                    objectApi: "Specialisation__c",
                    dynamicFilter: "secondarySpecialization",
                    matchingInfo : {
                        primaryField: { fieldPath: 'Specialisation_Name__r.Name'},
                    },
                    displayFields: {
                        primaryField: 'Specialisation_Name__r.Name',
                    },
                    visibleWhen: { "programDetail.SecondaryPartnerProgramPreference__c": '__notNull' },
                },
            ],
        };
    }

    get primarySchool() {
        return {
            criteria: [
                {
                    fieldPath: "Batch__c",
                    operator: "eq",
                    value: this.application?.Batch__c || null
                },
                // {
                //     fieldPath: "Id",
                //     operator: "ne",
                //     value: this.program?.SecondaryPartnerSchoolPreference__c || null
                // }
            ],
        };
    }

    get primaryProgram() {
        return {
            criteria: [
                {
                    fieldPath: "BatchPartnerSchool__c",
                    operator: "eq",
                    value: this.program?.PrimaryPartnerSchoolPreference__c || null
                },
                // {
                //     fieldPath: "Id",
                //     operator: "ne",
                //     value: this.program?.SecondaryPartnerProgramPreference__c || null
                // }
            ],
        };
    }

    get primarySpecialization() {
        return {
            criteria: [
                {
                    fieldPath: "BatchPartnerProgram__c",
                    operator: "eq",
                    value: this.program?.PrimaryPartnerProgramPreference__c || null
                },
                {
                    fieldPath: "Id",
                    operator: "ne",
                    value: this.program?.SecondaryPartnerSpecializationPreference__c || null
                },
                {
                    fieldPath: "Is_Active__c",
                    operator: "eq",
                    value: true
                },
            ],
            filterLogic: "1 AND 2 AND 3"
        };
    }

    get secondarySchool() {
        return {
            criteria: [
                {
                    fieldPath: "Batch__c",
                    operator: "eq",
                    value: this.application?.Batch__c || null
                },
                // {
                //     fieldPath: "Id",
                //     operator: "ne",
                //     value: this.program?.PrimaryPartnerSchoolPreference__c || null
                // }
            ]
        };
    }

    get secondaryProgram() {
        return {
            criteria: [
                {
                    fieldPath: "BatchPartnerSchool__c",
                    operator: "eq",
                    value: this.program?.SecondaryPartnerSchoolPreference__c || null
                },
                // {
                //     fieldPath: "Id",
                //     operator: "ne",
                //     value: this.program?.PrimaryPartnerProgramPreference__c || null
                // }
            ],
        };
    }

    get secondarySpecialization() {
        return {
            criteria: [
                {
                    fieldPath: "BatchPartnerProgram__c",
                    operator: "eq",
                    value: this.program?.SecondaryPartnerProgramPreference__c || null
                },
                {
                    fieldPath: "Id",
                    operator: "ne",
                    value: this.program?.PrimaryPartnerSpecializationPreference__c || null
                },
                {
                    fieldPath: "Is_Active__c",
                    operator: "eq",
                    value: true
                },
            ],
            filterLogic: "1 AND 2 AND 3"
        };
    }

    _applyExamRulesToMetadata() {
        Object.keys(EXAM_RULES).forEach(sectionKey => {
            const rules = EXAM_RULES[sectionKey];
            const meta = this.metadata[sectionKey];
            if (!meta) return;

            meta.fields.forEach(f => {
                if (rules.score && f.api === rules.score.field) {
                    f.min = rules.score.min;
                    f.max = rules.score.max;
                    f.messageWhenRangeUnderflow = ELIGIBILITY_ERROR;
                    f.messageWhenRangeOverflow = `${meta.sectionLabel} should not exceed ${f.max}`;
                    f.skipOnChangeValidation = true;
                }
            });
        });
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
        // setOptions("programDetail", "PrimaryPartnerProgramPreference__c", toOptions(pick.PrimaryPartnerProgramPreference__c));
        // setOptions("programDetail", "PrimaryPartnerSpecializationPreference__c", toOptions(pick.PrimaryPartnerSpecializationPreference__c));
        // setOptions("programDetail", "SecondaryPartnerSchoolPreference__c", toOptions(pick.SecondaryPartnerSchoolPreference__c));
        // setOptions("programDetail", "SecondaryPartnerProgramPreference__c", toOptions(pick.SecondaryPartnerProgramPreference__c));
        // setOptions("programDetail", "SecondaryPartnerSpecializationPreference__c", toOptions(pick.SecondaryPartnerSpecializationPreference__c));
    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfProgramDetailsContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfProgramDetailsContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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
     * Fetch: application → programDetail → exams
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
            * 2️⃣ Parse selected exam keys
            * ---------------------------------------------------- */
            const parse = (v) => (v || "").split(";").map(x => x.trim()).filter(Boolean);
            const selectedExams = parse(this.application.CompetitiveExams__c);
            const examKeys = selectedExams
                .map(ex => this.recordToLogical[ex.toUpperCase()])
                .filter(Boolean);

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

            /* COMPETITIVE EXAM SECTIONS */
            examKeys.forEach(key => {
                const meta = getMeta(key);

                parentsRequest.parents.push({
                    logicalName: meta.logicalName,
                    sobject: meta.sobject,
                    fields: meta.fieldsToQuery,
                    filters: [
                        ...buildFilters(meta, appId),
                        { field: "Exam_Name__c", value: meta.recordName }
                    ]
                });
            });

            /* BASIC ACADEMIC */
            const baMeta = getMeta("basicAcademic");
            parentsRequest.parents.push({
                logicalName: baMeta.logicalName,
                sobject: baMeta.sobject,
                fields: baMeta.fieldsToQuery,
                filters: buildFilters(baMeta, appId)
            });

            /* UG ACADEMIC */
            const ugMeta = getMeta("ugAcademic");
            parentsRequest.parents.push({
                logicalName: ugMeta.logicalName,
                sobject: ugMeta.sobject,
                fields: ugMeta.fieldsToQuery,
                filters: buildFilters(ugMeta, appId)
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
            
            this.basicAcademic = resp.basicAcademic || {};
            this.education.basicAcademic = this.basicAcademic;

            this.ugAcademic = resp.ugAcademic || {};
            this.education.ugAcademic = this.ugAcademic;

            examKeys.forEach(k => (this.education[k] = resp[k] || {}));

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
        
        const parse = (v) => (v || "").split(";").map(s => s.trim()).filter(Boolean);
        const selectedExams = parse(this.application.CompetitiveExams__c)
            .map(ex => this.recordToLogical[ex.toUpperCase()])
            .filter(Boolean);

        const sections = [];

        // 0) Instruction
        sections.push(this._buildSectionRenderModel("instructions"));

        // 1) Application
        sections.push(this._buildSectionRenderModel("application"));

        const hasScores = this.application.HasExamScores__c === "Yes";

        // 2) Selected exam score fields – only if Yes
        if (hasScores) {
            selectedExams.forEach(k => {
                if (this.metadata[k]) sections.push(this._buildSectionRenderModel(k));
            });
        }

        // 3) Basic Academic Detail (Graduation Completed)
        sections.push(this._buildSectionRenderModel("basicAcademic"));

        // 4) UG Academic Detail (Graduation Year)
        sections.push(this._buildSectionRenderModel("ugAcademic"));

        // 5) Programme Detail (always last)
        sections.push(this._buildSectionRenderModel("programDetail"));

        this.examSections = sections;
    }

    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta) return null;

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
                        if (api === "CompetitiveExams__c") {
                            value = (this.application.CompetitiveExams__c || "")
                                .split(";")
                                .map(v => v.trim())
                                .filter(Boolean);
                        } else {
                            value = this.application[api] ?? null;
                        }
                    } else if (sectionKey === "programDetail") {
                        value = this.program[api] ?? null;
                    } else {
                        value = (this.education[sectionKey] || {})[api] ?? null;
                    }

                    // Clone metadata (so we don't mutate original definition)
                    const metaForRender = { ...fMeta, sectionKey };

                    if (sectionKey === "ugAcademic" && fMeta.api === 'MonthAndYearOfPassing__c') {
                        const isCompleted = this.basicAcademic?.GraduationCompleted__c === 'Yes';

                        if (isCompleted) {
                            //metaForRender.min = "2009-01-01";
                            metaForRender.min = new Date(new Date().setFullYear((new Date().getFullYear() - (parseInt(this.selectedBatchUpperAgeBound || 30))) + 20)).toISOString().split('T')[0];
                            metaForRender.max = new Date().toISOString().split('T')[0];
                            metaForRender.label = "Graduated Month and Year";
                        } else {
                            metaForRender.min = new Date().toISOString().split('T')[0];
                            metaForRender.max = new Date(new Date().setFullYear(new Date().getFullYear() + 1))
                                .toISOString().split('T')[0];
                            metaForRender.label = "Expected graduation Month and Year";
                        }
                    }

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

            if(api == "Batch__c") {
                // User changes come through lookupchange -> handleSectionFieldChange.
                if (additionalFields?.UpperAgeBound__c !== undefined) {
                    this.selectedBatchUpperAgeBound = additionalFields.UpperAgeBound__c;
                } else if (!normalized) {
                    this.selectedBatchUpperAgeBound = null;
                }

                this.program.PrimaryPartnerSchoolPreference__c = null;
                this.program.SecondaryPartnerSchoolPreference__c = null;
                this.program.PrimaryPartnerProgramPreference__c = null;
                this.program.SecondaryPartnerProgramPreference__c = null;
                this.program.PrimaryPartnerSpecializationPreference__c = null
                this.program.SecondaryPartnerSpecializationPreference__c = null;
            }

            if (api === "CompetitiveExams__c") {
                const parse = (v) =>
                    (v || "").split(";").map(s => s.trim()).filter(Boolean);

                const selected = parse(this.application.CompetitiveExams__c)
                    .map(ex => this.recordToLogical[ex.toUpperCase()])
                    .filter(Boolean);

                // -----------------------------------------------------------
                // 1) ADD missing exam blocks (restore from removedExams if present)
                // -----------------------------------------------------------
                selected.forEach(k => {
                    // If the user re-selected an exam that was recently unselected,
                    // restore its previously held state (including Id), else create new object.
                    if (!this.education[k]) {
                        if (this.removedExams && this.removedExams[k] && this.removedExams[k].data) {
                            this.education[k] = { ...this.removedExams[k].data };
                            // Once restored, clear from removed list
                            delete this.removedExams[k];
                        } else {
                            this.education[k] = {};
                        }
                    }
                });

                // -----------------------------------------------------------
                // 2) SOFT-REMOVE ONLY competitive exam sections (DYNAMIC)
                //    Keep in removedExams, do not delete immediately.
                //    This prevents losing Id and helps avoid duplicate inserts on reselect.
                // -----------------------------------------------------------
                const examKeys = context.parents
                    .filter(p => p.sobject === "Competitive_Exam_Details__c")
                    .map(p => p.logicalName);

                examKeys.forEach(k => {
                    if (!selected.includes(k)) {
                        if (!this.removedExams) this.removedExams = {};
                        // Cache the last known state so it can be restored if reselected
                        this.removedExams[k] = { data: { ...(this.education[k] || {}) }, removedAt: Date.now() };
                        // Do NOT delete the object to preserve Id in memory; simply stop rendering via selected list.
                        // If you want to clear value fields immediately from UI perspective, you could do it here
                        // but keep Id so payload can delete on save if still unselected.
                    }
                });
            }


            this.education.application = { ...this.application };
            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === "basicAcademic") {
            const oldValue = this.basicAcademic[api];
            this.basicAcademic[api] = normalized;
            this.education.basicAcademic = { ...this.basicAcademic };

            if (api === "GraduationCompleted__c" && oldValue !== normalized) {
                this.ugAcademic.MonthAndYearOfPassing__c = null;
                this.education.ugAcademic = { ...this.ugAcademic };
            }

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === "ugAcademic") {
            this.ugAcademic[api] = normalized;
            this.education.ugAcademic = { ...this.ugAcademic };
            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === "programDetail") {
            this.program[api] = normalized;
            this.education.programDetail = this.program;

            if (api === "PrimaryPartnerSchoolPreference__c") {
                this.program.PrimaryPartnerProgramPreference__c = null;
                this.program.PrimaryPartnerSpecializationPreference__c = null;
            }

            if (api === "PrimaryPartnerProgramPreference__c") {
                this.program.PrimaryPartnerSpecializationPreference__c = null;
            }

            if (api === "SecondaryPartnerSchoolPreference__c") {
                this.program.SecondaryPartnerProgramPreference__c = null;
                this.program.SecondaryPartnerSpecializationPreference__c = null;
            }

            if (api === "SecondaryPartnerProgramPreference__c") {
                this.program.SecondaryPartnerSpecializationPreference__c = null;
            }

            this._buildRenderModelAll();
            return;
        }

        // exam sections
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

            // lookupset is only for resolving an already-selected lookup value in edit mode.
            if (api === 'Batch__c' && additionalFields?.UpperAgeBound__c !== undefined) {
                this.selectedBatchUpperAgeBound = additionalFields.UpperAgeBound__c;
                this.education.application = { ...this.application };
                this._buildRenderModelAll();
                return;
            }
        }
        
        //for others record picker
        this.education[sectionKey].Display ||= {};
        this.education[sectionKey].Display[api] = displayValue;

        this.education[sectionKey].additionalFields ||= {};
        this.education[sectionKey].additionalFields[api] = additionalFields;


        if(['PrimaryPartnerProgramPreference__c', 'SecondaryPartnerProgramPreference__c'].includes(api)){
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

        // 🛡 First render / safety net
        if (!this.examSections || this.examSections.length === 0) {
            this._buildRenderModelAll();
            return;
        }

        this.examSections = this.examSections.map(sec => {
            if (!sectionKeys.includes(sec.key)) {
                return sec; // untouched
            }
            return this._buildSectionRenderModel(sec.key);
        }).filter(Boolean);
    }

    SECTION_DEPENDENCIES = {
        programDetail: [
            'PrimaryPartnerProgramPreference__c',
            'SecondaryPartnerProgramPreference__c',
        ]
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
        appMeta.fields.forEach(f => {
            if (f.required && this.isFieldVisible("application", f)) {
                const v = this.application[f.api];
                if (v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0)) {
                    addError("application", f.api, `${f.label} is required`);
                }
            }
        });

        const hasScores = this.application.HasExamScores__c === "Yes";

        /********************************************
         * 2️⃣ Validate EXAMS IF hasScores = Yes
         ********************************************/
        if (hasScores) {
            const parse = (v) => (v || "").split(";").map(s => s.trim()).filter(Boolean);
            const selectedExams = parse(this.application.CompetitiveExams__c)
                .map(ex => this.recordToLogical[ex.toUpperCase()])
                .filter(Boolean);

            selectedExams.forEach(sectionKey => {
                const meta = this.metadata[sectionKey];
                const data = this.education[sectionKey] || {};

                if (!meta) return;

                meta.fields.forEach(f => {
                    if (f.required && this.isFieldVisible(sectionKey, f)) {
                        const v = data[f.api];
                        if (v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0)) {
                            addError(sectionKey, f.api, `${f.label} is required`);
                        }
                    }

                    if (this.isFieldVisible(sectionKey, f) && f.type === 'number' && ['gre', 'gmat', 'gmatFocus', 'cat', 'xat', 'nmat'].includes(sectionKey)) {
                        const v = data[f.api];
                        const err = validateNumber(f, v);
                        if (err) {
                            if(err.includes('decimal')){
                                addError(sectionKey, f.api, err);
                            } else {
                                addError(sectionKey, f.api, '');
                            }
                        }
                    }
                });


            });
        }


        /********************************************
         * 3️⃣ Validate BASIC ACADEMIC
         ********************************************/
        const baMeta = this.metadata.basicAcademic;
        const baData = this.basicAcademic || {};

        baMeta.fields.forEach(f => {
            if (f.required && this.isFieldVisible("basicAcademic", f)) {
                const v = baData[f.api];
                if (!v) addError("basicAcademic", f.api, `${f.label} is required`);
            }
        });

        /********************************************
         * 4️⃣ Validate UG ACADEMIC
         ********************************************/
        if (baData.GraduationCompleted__c === "Yes" || baData.GraduationCompleted__c === "No") {
            const ugMeta = this.metadata.ugAcademic;
            const ugData = this.ugAcademic || {};
            const isGraduationCompleted = baData.GraduationCompleted__c === "Yes";

            ugMeta.fields.forEach(f => {
                const visible = this.isFieldVisible("ugAcademic", f);

                if (visible && f.required) {
                    const v = ugData[f.api];
                    const fieldLabel =
                        f.api === "MonthAndYearOfPassing__c"
                            ? (isGraduationCompleted
                                ? "Graduated Month and Year"
                                : "Expected graduation Month and Year")
                            : f.label;

                    if (!v) {
                        addError("ugAcademic", f.api, `${fieldLabel} is required`);
                    }
                }
            });
        }

        /********************************************
         * 5️⃣ Validate PROGRAMME DETAIL (always required)
         ********************************************/
        const pdMeta = this.metadata.programDetail;
        const pdData = this.program || {};

        pdMeta.fields.forEach(f => {
            const isVisible = this.isFieldVisible("programDetail", f);

            // Skip invisible fields completely
            if (!isVisible) return;

            if (f.required) {
                const v = pdData[f.api];
                if (v === null || v === undefined || v === "" ||
                    (Array.isArray(v) && v.length === 0)) {
                    addError("programDetail", f.api, `${f.label} is required`);
                }
            }
        });

        /********************************************
         * 6.5️⃣ Validate experience requirement
         ********************************************/
        if (baData.GraduationCompleted__c === "Yes" || baData.GraduationCompleted__c === "No") {

            const graduationDateStr = this.ugAcademic?.MonthAndYearOfPassing__c;

            if (graduationDateStr) {

                const gradDate = new Date(graduationDateStr.replace(" ", "T"));
                const now = new Date();

                const diffYears = (now - gradDate) / (1000 * 60 * 60 * 24 * 365.25);

                const programAdditional =
                    this.education?.programDetail?.additionalFields || {};

                const checkProgram = (api) => {

                    const exp = Number(
                        programAdditional?.[api]?.["PartnerProgram__r.ExperienceRequired__c"] ?? 0
                    );

                    if (exp && diffYears < exp) {

                        addError(
                            "programDetail",
                            api,
                            `Minimum ${exp} years of experience required`
                        );
                    }
                };

                checkProgram("PrimaryPartnerProgramPreference__c");
                checkProgram("SecondaryPartnerProgramPreference__c");
            }
        }

        /********************************************
         * 6️⃣ Validate date (min or max)
         ********************************************/
        Object.keys(this.metadata).forEach(sectionKey => {
            const sectionMeta = this.metadata[sectionKey];
            const sectionData = this.education[sectionKey];
            if (!sectionData) return;

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
        const wrapper = this.template.querySelector("c-af-program-details");
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

            // 🔥 Force Exam_Name__c for competitive exam details
            if (meta.sobject === "Competitive_Exam_Details__c") {
                block.fields.Exam_Name__c = meta.recordName;  
            }

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
        // Ensure removedExams exists
        this.removedExams = this.removedExams || {};

        // 1️⃣ APPLICATION (dynamic + extra normalization fields)
        const appExtra = {
            HasExamScores__c: this.application.HasExamScores__c,
            PlannedExamDate__c: this.application.PlannedExamDate__c,
            CompetitiveExams__c: this.application.CompetitiveExams__c,
            Batch__c: this.application.Batch__c
        };

        // If user indicates no exam scores, clear CompetitiveExams__c to avoid stale values
        if (appExtra.HasExamScores__c === 'No' || appExtra.HasExamScores__c === false) {
            appExtra.CompetitiveExams__c = '';
        }

        out.application = this._buildParentBlock("application", this.application, appExtra);

        const gradDone = this.basicAcademic.GraduationCompleted__c === "Yes";
        const basicAcademicForSave = { ...this.basicAcademic };

        if (!gradDone) {
            this.ugAcademic.DegreeStatus__c = 'Pursuing';
            const normalizedPassingDate = this._normalizeValue(
                'MonthAndYearOfPassing__c',
                this.ugAcademic?.MonthAndYearOfPassing__c,
                this.metadata?.ugAcademic?.fields?.find(f => f.api === 'MonthAndYearOfPassing__c')
            );
            basicAcademicForSave.ExpectedGraduationDate__c = normalizedPassingDate
                ? String(normalizedPassingDate).substring(0, 10)
                : null;
        } else if (gradDone) {
            this.ugAcademic.DegreeStatus__c = 'Completed';
            basicAcademicForSave.ExpectedGraduationDate__c = null;
        }

        // 2️⃣ BASIC ACADEMIC (always save)
        out.basicAcademic = this._buildParentBlock("basicAcademic", basicAcademicForSave);

        // 3️⃣ UG ACADEMIC
        out.ugAcademic = this._buildParentBlock("ugAcademic", this.ugAcademic);

        // 4️⃣ PROGRAMME DETAIL (always save)
        out.programDetail = this._buildParentBlock("programDetail", this.program);

        // ------------------------------------------------------------
        // 5️⃣ COMPETITIVE EXAMS (dynamic + delete-all if No scores)
        // ------------------------------------------------------------

        const hasScores = this.application.HasExamScores__c === "Yes";
        // If there are no scores, also ensure local state is consistent for downstream logic
        if (!hasScores) {
            // Prevent any accidental upsert of exam sections
            // Keep removedExams cache for safety, but ensure selected list is effectively empty
            this.application.CompetitiveExams__c = '';
        }
        const parse = (v) => (v || "").split(";").map(s => s.trim()).filter(Boolean);

        const selectedKeys = parse(this.application.CompetitiveExams__c)
            .map(ex => this.recordToLogical[ex.toUpperCase()])
            .filter(Boolean);

        // Build a quick lookup for removed exams to drive deletion on save
        const removedLookup = {};
        Object.keys(this.removedExams || {}).forEach(k => {
            removedLookup[k] = true;
        });

        const examKeys = ["gmat", "gre", "cat", "xat", "nmat", "gmatFocus"];

        examKeys.forEach(key => {
            const meta = this._getParentMeta(key);
            if (!meta) return;

            // Prefer current education state; if never created in this session, fall back to removed cache

            let data;

            if (this.education[key] && Object.keys(this.education[key]).length) {
                data = this.education[key]; // always trust current state
            } else if (this.removedExams[key]) {
                data = this.removedExams[key].data; // only if truly removed
            } else {
                data = {};
            }

            // ❌ CASE: HasExamScores = NO → delete ALL competitive exam records
            if (!hasScores) {
                // If user has no scores, delete any existing record for all exams if present
                if (data.Id) {
                    out[key] = this._buildParentBlock(key, data, {}, true);
                }
                return; // skip save
            }

            // ✔️ CASE: HasExamScores = YES → save only selected exams
            const isSelected = selectedKeys.includes(key);

            if (!isSelected) {
                // If it is explicitly removed and existed (has Id), send delete block
                if (removedLookup[key] && data.Id) {
                    out[key] = this._buildParentBlock(key, data, {}, true);
                }
                // If removed and never saved (no Id), do nothing
            } else {
                // Selected: if we had a removed copy with only Id, we can choose to clear value fields
                // so server updates won't resurrect stale values; but server will accept provided fields.
                out[key] = this._buildParentBlock(key, data);
            }
        });

        return out;
    }
    
    @api async saveForm() {
        if(this.isReadOnly) return true;

        const hasScores = this.application.HasExamScores__c === "Yes";
        if(hasScores) {
            this.application.PlannedExamDate__c = null;
            this.application.PlannedEntranceExams__c = '';
        }

        this.isLoading = true;
        if (!this.validateAll()) {
            console.error('Validation failed');
            this.template.querySelector('c-af-program-details').reportValidity();
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