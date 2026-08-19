import { LightningElement, api, track } from "lwc";
import fetchDynamic from "@salesforce/apex/ApFormDataController.fetchDynamic";
import saveParents from "@salesforce/apex/ApFormDataController.saveParents";
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import getAllPicklistsForObjects from "@salesforce/apex/AcademicFormController.getAllPicklistsForObjects";

import { context } from "./context";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { validateMinMaxDate, validateNumber } from 'c/applicationFormService';

import { buildErrorSummary } from 'c/applicationFormService';


export default class AfProgramDetailsContainerPgdm extends LightningElement {

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
            programSelection: this.program,

            otherResources: {
                requireProgramPreference: this._containsMultipleOptions(
                    this.education.programSelection?.ProgrammesInterestedIn__c
                ),

                showSpecialisationInfoLinks: this._containsValue(
                    this.education.programSelection?.ProgrammesInterestedIn__c,
                    'Post Graduate Diploma in Management'
                ),

                requireSpecialisationPreference: this._containsValue(
                    this.education.programSelection?.ProgrammesInterestedIn__c,
                    'Post Graduate Diploma in Management'
                ),

                secondarySpecialisationSelected: !!this.education.programSelection?.SecondarySpecialisationPreference__c,

                requireSpecialInterest1: this._containsValue(
                    this.education.programSelection?.Reasons_I_have_Specialization_1__c,
                    'Special interest in this area'
                ),

                requireSpecialInterest2: this._containsValue(
                    this.education.programSelection?.Reasons_I_have_Specialization_2__c,
                    'Special interest in this area'
                ),

                requireAreaOfFocus: this._containsValue(
                    this.education.programSelection?.ProgrammesInterestedIn__c,
                    'Post Graduate Diploma in Management (Business Management)'
                )
            }
        };
    }

    /***********************************
     * METADATA DEFINITIONS
     ***********************************/
    _buildMetadata() {
        this.metadata = {};

        this.metadata.instructions = {
            key: "instructions",
            title: "Instructions",
            columnSystem: 12,
            note: {
                api: "SECTION_NOTE",
                type: "note",
                text: `
                    <div style="
                        padding: 14px 18px;
                        background: #f3f3f3;
                        border: 1px solid #d8d8d8;
                        border-radius: 4px;
                        font-size: 14px;
                        line-height: 1.45;
                    ">

                        <p style="margin: 0 0 12px 0;">
                            This application form is organised into six sections.
                            Click the relevant section to fill in details.
                            This application form is common for both programmes
                            PGDM and PGDM (BM).
                        </p>

                        <ol style="margin: 0; padding-left: 20px;">
                            <li style="margin-bottom: 8px;">
                                Every mandatory field is marked with a
                                <span style="color: red; font-weight: 700;">red asterisk (*)</span>.
                                They must be filled accurately for your application
                                to be considered valid.
                            </li>

                            <li style="margin-bottom: 8px;">
                                The final submission of your application form is allowed
                                only after the acceptance of declaration.
                                <ul style="margin-top: 6px; padding-left: 20px;">
                                    <li>
                                        The changes made are auto-saved once all mandatory
                                        fields are filled for that particular section.
                                    </li>
                                    <li>
                                        Please note that your form will be
                                        <b>Read Only</b> and closed for editing once you make the payment.
                                    </li>
                                </ul>
                            </li>

                            <li style="margin-bottom: 8px;">
                                <b>Application fees payment:</b>
                                <ul style="margin-top: 6px; padding-left: 20px;">
                                    <li>
                                        <b>Application fees payment if applied separately to each programme:</b>
                                        <ul style="margin-top: 4px; padding-left: 20px;">
                                            <li>PGDM application fee is INR 2000/-.</li>
                                            <li>PGDM (BM) application fee is INR 2000/-.</li>
                                        </ul>
                                    </li>

                                    <li style="margin-top: 6px;">
                                        <b>Application fees payment if applied to both programmes together:</b>
                                        <ul style="margin-top: 4px; padding-left: 20px;">
                                            <li>
                                                The application fees for PGDM &amp; PGDM (BM)
                                                when applied together is INR 3000/-.
                                            </li>
                                        </ul>
                                    </li>

                                    <li style="margin-top: 6px;">
                                        Once you have completed filling the form, you should
                                        proceed for making the payment by clicking
                                        <b>Pay application fees</b>.
                                    </li>

                                    <li style="margin-top: 6px;">
                                        You can pay your application fee through
                                        Credit/Debit card, Net banking online.
                                        The process for payment is described in each option.
                                    </li>
                                </ul>
                            </li>

                            <li>
                                If at any stage of the admission process, it is found that
                                the applicant does not satisfy the eligibility criteria or
                                the information furnished by them is incorrect, their
                                application towards the Programme will stand cancelled
                                and fees will be forfeited.
                            </li>
                        </ol>
                    </div>
                `
            },
            rows: [],
            fields: []
        };

        this.metadata.application = {};

        /***********************************
         * PROGRAMME DETAIL (last)
         ***********************************/
        this.metadata.programDetail = {
            key: "programDetail",
            title: "Programme Detail",
            columnSystem: 12,
                note: {
                    api: "SECTION_NOTE",
                    type: "note",
                    text: `
<div style="font-size:14px; line-height:1.55;">

    <p style="margin:0 0 14px 0;">
        <b>Please Note:</b>
        PGDM &amp; PGDM (BM) programme is a two-year, full-time residential programme.
        It is for candidates who are either freshers or with less than 5 years of work
        experience. While PGDM has a specialisation focus, PGDM (BM) offers candidates
        flexibility to pursue General Management courses in depth with an option to
        choose minor specialisation and electives of their interest.
        Further details on the programme is available on:
    </p>

    <p style="margin:0 0 10px 0;">
        <b>PGDM</b> -
        <a href="https://www.spjimr.org/course/post-graduate-diploma-in-management-pgdm/"
           target="_blank">
            https://www.spjimr.org/course/post-graduate-diploma-in-management-pgdm/
        </a>
    </p>

    <p style="margin:0 0 16px 0;">
        <b>PGDM (BM)</b> -
        <a href="https://www.spjimr.org/course/post-graduate-diploma-in-management-business-management/"
           target="_blank">
            https://www.spjimr.org/course/post-graduate-diploma-in-management-business-management/
        </a>
    </p>
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
                    <div style="font-size:14px; line-height:1.55;">
                        <p style="margin:0 0 10px 0;">
                            I confirm that I have read, understood, accept the eligibility criteria as
                            outlined in the eligibility document.
                        </p>

                        <ul style="margin:0; padding-left:28px;">
                            <li style="margin-bottom:8px;">
                                To refer to the eligibility document of PGDM programme
                                (Indian applicant)
                                <a href="YOUR_PGDM_INDIAN_ELIGIBILITY_LINK" target="_blank">
                                    click here
                                </a>
                            </li>

                            <li style="margin-bottom:8px;">
                                To refer to the eligibility document of PGDM programme
                                (International applicant only)
                                <a href="YOUR_PGDM_INTERNATIONAL_ELIGIBILITY_LINK" target="_blank">
                                    click here
                                </a>
                            </li>

                            <li>
                                To refer to the eligibility document of PGDM (BM) programme
                                <a href="YOUR_PGDM_BM_ELIGIBILITY_LINK" target="_blank">
                                    click here
                                </a>
                            </li>
                        </ul>

                    </div>
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

        this.metadata.programSelection = {
            key: "programSelection",
            title: "Programme Selection",
            columnSystem: 12,
            layout: 'fluid',
                note: {
                    api: "SECTION_NOTE",
                    type: "note",
                    text: `
Choose the programme you wish to apply for
                `
            },
            fields: [
                {
                    api: "ProgrammesInterestedIn__c",
                    span: 4,
                    shortLabel: "Programme Selection",
                    required: true,
                    label: "Select programme(s) you wish to apply for", 
                    type: "multipicklist", 
                },
                { 
                    api:'PrimaryProgramPreference__c', 
                    span: 4, 
                    type:'picklist', 
                    label:'Please select your preference 1',
                    shortLabel: 'Preference 1',
                    required: true,
                    visibleWhen: {
                        'otherResources.requireProgramPreference': true
                    },
                    requiredWhen: {
                        'otherResources.requireProgramPreference': true
                    }
                },
                { 
                    api:'SecondaryProgramPreference__c', 
                    span: 4, 
                    type:'picklist', 
                    label:'Preference 2',
                    shortLabel: 'Preference 2',
                    required: true,
                    readOnly: true,
                    visibleWhen: {
                        'otherResources.requireProgramPreference': true
                    },
                    requiredWhen: {
                        'otherResources.requireProgramPreference': true
                    }
                },
                {
                    api: "SpecialisationInformation__c",
                    type: 'richtext',
                    span: 11,
                    value: `
                       <div>
                            <a href="YOUR_IMA_LINK" target="_blank">
                                &#128229; Click here for more information on Information Management &amp; Analytics (IM &amp; A) Specialization
                            </a><br>
                            <a href="YOUR_MARKETING_LINK" target="_blank">
                                &#128229; Click here for more information on Marketing Specialization
                            </a><br>
                            <a href="YOUR_OSCM_LINK" target="_blank">
                                &#128229; Click here for more information on Operations &amp; Supply Chain Management (OSCM) Specialization
                            </a><br>
                            <a href="YOUR_FINANCE_LINK" target="_blank">
                                &#128229; Click here for more information on Finance Specialization
                            </a>
                        </div>
                    `,
                    visibleWhen: {
                        'otherResources.showSpecialisationInfoLinks': true
                    },
                },
                {
                    api: "PrimarySpecialisationPreference__c", 
                    type: "lookup", 
                    label: "Specialisation 1 for PGDM",
                    span: 5,
                    required: true,
                    objectApi: "Specialisation__c",
                    dynamicFilter: "getPrimarySpecialisations",
                    matchingInfo : {
                        primaryField: { fieldPath: 'Specialisation_Name__r.Name'},
                    },
                    displayFields: {
                        primaryField: 'Specialisation_Name__r.Name',
                    },
                    visibleWhen: {
                        'otherResources.requireSpecialisationPreference': true
                    },
                    requiredWhen: {
                        'otherResources.requireSpecialisationPreference': true
                    }
                },
                {
                    api: "SecondarySpecialisationPreference__c", 
                    type: "lookup", 
                    label: "Specialisation 2 for PGDM",
                    span: 5,
                    objectApi: "Specialisation__c",
                    dynamicFilter: "getSecondarySpecialisations",
                    matchingInfo : {
                        primaryField: { fieldPath: 'Specialisation_Name__r.Name'},
                    },
                    displayFields: {
                        primaryField: 'Specialisation_Name__r.Name',
                    },
                    visibleWhen: {
                        'otherResources.requireSpecialisationPreference': true
                    }

                },
                {
                    api: "Reasons_I_have_Specialization_1__c",
                    span: 5,
                    shortLabel: "Specialisation preference reason",
                    required: true,
                    label: "Reasons I have (Specialisation 1)", 
                    type: "multipicklist",
                    visibleWhen: {
                        'otherResources.requireSpecialisationPreference': true
                    },
                    requiredWhen: {
                        'otherResources.requireSpecialisationPreference': true
                    }
                },
                {
                    api: "Reasons_I_have_Specialization_2__c",
                    span: 5,
                    shortLabel: "Specialisation preference reason",
                    required: true,
                    label: "Reasons I have (Specialisation 2)", 
                    type: "multipicklist", 
                    visibleWhen: {
                        'otherResources.secondarySpecialisationSelected': true
                    },
                    requiredWhen: {
                        'otherResources.secondarySpecialisationSelected': true
                    }
                },
                {
                    api: 'OtherSpecialisation1InterestReason__c', 
                    span: 5, 
                    maxlength: '2000',
                    type: 'textarea',
                    shortLabel: "Special interest reason (Specialisation 1)",
                    label: 'Mention special interest reason (Specialisation 1)',
                    maxWords: 50,
                    showCounter: true,
                    helpText:"Max. 50 words",
                    visibleWhen: {
                        'otherResources.requireSpecialInterest1': true
                    },
                    requiredWhen: {
                        'otherResources.requireSpecialInterest1': true
                    }
                },
                {
                    api: 'OtherSpecialisation2InterestReason__c',
                    span: 5, 
                    maxlength: '2000',
                    type: 'textarea',
                    shortLabel: "Special interest reason (Specialisation 2)",
                    label: 'Mention special interest reason (Specialisation 2)',
                    maxWords: 50,
                    showCounter: true,
                    helpText:"Max. 50 words",
                    visibleWhen: {
                        'otherResources.requireSpecialInterest2': true
                    },
                    requiredWhen: {
                        'otherResources.requireSpecialInterest2': true
                    }
                },
                { 
                    api:'AreaOfInterest__c', 
                    span: 5, 
                    type:'picklist', 
                    label:'Based on academic background, work experience and career aspirations, which focus area are you most interested in?',
                    shortLabel: 'Area of Interest',
                    required: true,
                    visibleWhen: {
                        'otherResources.requireAreaOfFocus': true
                    },
                    helpText:"For PGDM(BM) programme",
                    requiredWhen: {
                        'otherResources.requireAreaOfFocus': true
                    }
                },
                {
                    api: 'ReasonsForAreaOfInterest__c',
                    span: 5, 
                    maxlength: '2000',
                    type: 'textarea',
                    shortLabel: "Reason for Area of Interest",
                    label: 'Provide reason for Area of Interest',
                    maxWords: 50,
                    showCounter: true,
                    helpText:"Max. 50 words",
                    visibleWhen: {
                        'otherResources.requireAreaOfFocus': true
                    },
                    requiredWhen: {
                        'otherResources.requireAreaOfFocus': true
                    }
                },
            ],
        };

        
    }

    get getPrimarySpecialisations() {
        
        return {
            criteria: [
                {
                    fieldPath: 'Batch__c',
                    operator: 'eq',
                    value: this.application.Batch__c
                },
                {
                    fieldPath: 'Program__c',
                    operator: 'eq',
                    value: this.application.Program__c
                },
                {
                    fieldPath: "Is_Active__c",
                    operator: "eq",
                    value: true
                },
                {
                    fieldPath: "Id",
                    operator: "ne",
                    value: this.education.programSelection.SecondarySpecialisationPreference__c || null
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.programSelection.PrimarySpecialisationPreference__c
                },
            ],
            filterLogic: "(1 AND 2 AND 3 AND 4) OR 5",
        };
    }

    get getSecondarySpecialisations() {
        
        return {
            criteria: [
                {
                    fieldPath: 'Batch__c',
                    operator: 'eq',
                    value: this.application.Batch__c
                },
                {
                    fieldPath: 'Program__c',
                    operator: 'eq',
                    value: this.application.Program__c
                },
                {
                    fieldPath: "Is_Active__c",
                    operator: "eq",
                    value: true
                },
                {
                    fieldPath: "Id",
                    operator: "ne",
                    value: this.education.programSelection.PrimarySpecialisationPreference__c || null
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.programSelection.SecondarySpecialisationPreference__c
                },
            ],
            filterLogic: "(1 AND 2 AND 3 AND 4) OR 5",
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

        setOptions("programSelection", "ProgrammesInterestedIn__c", toOptions(pick.ProgrammesInterestedIn__c));    
        setOptions("programSelection", "PrimaryProgramPreference__c", toOptions(pick.PrimaryProgramPreference__c));
        setOptions("programSelection", "SecondaryProgramPreference__c", toOptions(pick.SecondaryProgramPreference__c));
        setOptions("programSelection", "Reasons_I_have_Specialization_1__c", toOptions(pick.Reasons_I_have_Specialization_1__c));
        setOptions("programSelection", "Reasons_I_have_Specialization_2__c", toOptions(pick.Reasons_I_have_Specialization_2__c));
        setOptions("programSelection", "AreaOfInterest__c", toOptions(pick.AreaOfInterest__c));
    }

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfProgramDetailsContainerPgdm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfProgramDetailsContainerPgdm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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
            this.education.programSelection = this.program;
            
            this._cleanupHiddenFields('programSelection');
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

        // 2) Programme Detail
        sections.push(this._buildSectionRenderModel("programDetail"));

        // 3) Programme Detail (always last)
        sections.push(this._buildSectionRenderModel("programSelection"));

        this.allSections = sections.filter(Boolean);

    }

    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];

        if (!meta || !Array.isArray(meta.fields)) return null;

        const section = { key: sectionKey, title: meta.title, rows: [] };
        const secData = this._getSectionData(sectionKey);

        const isSequential = this._isSequentialSection(sectionKey);

        if (meta.layout === 'fluid') {
            section.rows = isSequential
                ? this._buildSequentialFluidRows(
                    sectionKey,
                    meta,
                    secData
                )
                : this._buildFluidRows(
                    sectionKey,
                    meta,
                    secData
                );

            return section;
        }


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
                    const metaForRender = this._resolveFieldMeta(meta.key, { ...fMeta, sectionKey: meta.key });
                    if (metaForRender.visible === false) {
                        return;
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

    _resolveFieldMeta(sectionKey, fieldMeta) {
        console.log('_resolveFieldMeta called');
        const resolved = { ...fieldMeta };
        const isSequential = this._isSequentialSection(sectionKey);
        resolved.visible = this._computeFieldVisible(resolved, sectionKey, resolved.sequence);

        if (this.isReadOnly) {
            resolved.readOnly = true;
            if (isSequential) {
                resolved.required = false;
                delete resolved.visibleWhen;
                delete resolved.requiredWhen;
            }

            return resolved;
        }

        let baseRequired = false;

        if (this.requiredFieldsMap[sectionKey]?.includes(resolved.api)) {

            /*if (resolved.sequence === 1) {
                baseRequired = true;
            }
            else*/ if (this._isRowActive(sectionKey, resolved.sequence)) {
                baseRequired = true;
            }
        }

        resolved.required =
            baseRequired ||
            this._computeFieldRequired(
                resolved,
                sectionKey,
                resolved.sequence
            );

        resolved.disabled =
            this._computeFieldDisabled(
                resolved,
                sectionKey,
                resolved.sequence
            );

        resolved.readOnly = this._computeFieldReadOnly(resolved, sectionKey, resolved.sequence);

        if (isSequential) {
            resolved.required = baseRequired || this._computeFieldRequired(resolved, sectionKey, resolved.sequence);
            delete resolved.visibleWhen;
            delete resolved.requiredWhen;
        }

        return resolved;
    }

    requiredFieldsMap = {
    };

    _isSequentialSection(sectionKey) {
        const meta = this.metadata?.[sectionKey];
        return !!(
            meta?.useSequenceKey ||
            (meta?.fields || []).some(
                f => f.sequence !== undefined && f.sequence !== null && f.sequence !== ''
            )
        );
    }

    _getSectionData(sectionKey) {
        if (sectionKey === 'application') {
            return this.application || {};
        }

        if (sectionKey === 'programDetail') {
            return this.program || {};
        }

        return this.education?.[sectionKey] || {};
    }

    _resolveFieldConditionValue(path, sectionKey, sequence) {
        console.log('_resolveFieldConditionValue started');
        const parts = String(path || '').split('.');
        if (!parts.length) return undefined;

        if (path === 'otherResources.requireProgramPreference') {
            return this._containsMultipleOptions(
                this.education.programSelection?.ProgrammesInterestedIn__c
            );
        }

        if (path === 'otherResources.showSpecialisationInfoLinks') {
            return this._containsValue(
                this.education.programSelection?.ProgrammesInterestedIn__c,
                'Post Graduate Diploma in Management'
            );
        }

        if (path === 'otherResources.requireSpecialisationPreference') {
            return this._containsValue(
                this.education.programSelection?.ProgrammesInterestedIn__c,
                'Post Graduate Diploma in Management'
            );
        }

        if (path === 'otherResources.secondarySpecialisationSelected') {
            return !!this.education.programSelection?.SecondarySpecialisationPreference__c;
        }

        if (path === 'otherResources.requireSpecialInterest1') {
            return this._containsValue(
                this.education.programSelection?.Reasons_I_have_Specialization_1__c,
                'Special interest in this area'
            );
        }

        if (path === 'otherResources.requireSpecialInterest2') {
            return this._containsValue(
                this.education.programSelection?.Reasons_I_have_Specialization_2__c,
                'Special interest in this area'
            );
        }

        if (path === 'otherResources.requireAreaOfFocus') {
            return this._containsValue(
                this.education.programSelection?.ProgrammesInterestedIn__c,
                'Post Graduate Diploma in Management (Business Management)'
            );
        }

        // For sequential sections like achievements[seq]
        if (
            sequence !== null &&
            sequence !== undefined &&
            this._isSequentialSection(sectionKey) &&
            parts[0] === sectionKey
        ) {
            let cur = this._getSectionData(sectionKey)?.[sequence];
            for (let i = 1; i < parts.length; i++) {
                if (cur == null) return undefined;
                cur = cur[parts[i]];
            }
            return cur;
        }

        let cur = this.contextBlock;
        for (const part of parts) {
            if (cur == null) return undefined;
            cur = cur[part];
        }
        return cur;
    }

    _containsValue(fieldValue, targetValue) {
        if (!fieldValue) return false;

        if (Array.isArray(fieldValue)) {
            return fieldValue.includes(targetValue);
        }

        return String(fieldValue)
            .split(';')
            .map(v => v.trim())
            .includes(targetValue);
    }

    _containsMultipleOptions(fieldValue) {
        if (!fieldValue) return false;

        if (Array.isArray(fieldValue)) {
            return fieldValue.length > 1;
        }

        return String(fieldValue)
            .split(';')
            .map(v => v.trim())
            .length > 1;
    }

    _buildFluidRows(sectionKey, meta, sectionData, groupFilter) {
        const cs = meta.columnSystem || 12;
        const rows = [];

        let row = {
            columns: [],
            used: 0
        };

        (meta.fields || [])
            .filter(f => f.type !== 'note')
            .forEach(f => {

                const fieldGroup = f.group || 'default';

                if (groupFilter && fieldGroup !== groupFilter) {
                    return;
                }

                const metaForRender = this._resolveFieldMeta(
                    sectionKey,
                    {
                        ...f,
                        sectionKey
                    }
                );

                if (metaForRender.visible === false) {
                    return;
                }

                const span = metaForRender.span || 3;

                if (row.used + span > cs) {
                    if (row.columns.length) {
                        rows.push({
                            key: `${meta.key}-fluid-${rows.length}`,
                            style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
                            columns: row.columns
                        });
                    }

                    row = {
                        columns: [],
                        used: 0
                    };
                }

                this._applyDynamicFilter(metaForRender);

                row.columns.push({
                    key: `${meta.key}-${f.api}`,
                    widthStyle: `grid-column: span ${span};`,
                    fields: [{
                        key: `${meta.key}-${f.api}`,
                        meta: metaForRender,
                        value: this._getValueForField(sectionKey, f.api)
                    }]
                });

                row.used += span;
            });

        if (row.columns.length) {
            rows.push({
                key: `${meta.key}-fluid-${rows.length}`,
                style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
                columns: row.columns
            });
        }

        return rows;
    }

    _buildSequentialFluidRows(sectionKey, meta, sectionData, groupFilter) {
        const cs = meta.columnSystem || 12;
        const sequences = this._getSequenceList(sectionKey, sectionData);
        const rows = [];
        let fluidRowIdx = 0;

        // Static section note
        if (meta.note) {
            rows.push({
                key: `${meta.key}-note-row`,
                style: `margin-bottom: 10px;`,
                columns: [{
                    key: `${meta.key}-note-col`,
                    widthStyle: `grid-column: span ${cs};`,
                    fields: [{
                        key: `${meta.key}-NOTE`,
                        meta: {
                            ...meta.note,
                            sectionKey
                        },
                        value: meta.note.text
                    }]
                }]
            });
        }

        sequences.forEach((seq, seqIdx) => {
             
            let row = { columns: [], used: 0 };

            (meta.fields || [])
                .filter(f => {
                        if (f.type === 'note') {
                            return false;
                        }

                        // Academic-style metadata sequence
                        if (
                            f.sequence !== undefined &&
                            f.sequence !== null &&
                            f.sequence !== ''
                        ) {
                            return Number(f.sequence) === Number(seq);
                        }

                        // Achievements style
                        return true;
                    })
                .forEach(f => {
                    const fieldGroup = f.group || 'default';
                    if (groupFilter && fieldGroup !== groupFilter) return;

                    const metaForRender = this._resolveFieldMeta(sectionKey, {
                        ...f,
                        sectionKey,
                        sequence: seq
                    });

                    if (metaForRender.visible === false) return;

                    const span = metaForRender.span || 3;

                    if (row.used + span > cs) {
                        rows.push({
                            key: `${meta.key}-fluid-${seqIdx}-${fluidRowIdx++}`,
                            style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
                            columns: row.columns
                        });
                        row = { columns: [], used: 0 };
                    }

                    this._applyDynamicFilter(metaForRender);

                    row.columns.push({
                        key: `${meta.key}-${f.api}-${seq}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: [{
                            key: `${meta.key}-${f.api}-${seq}`,
                            meta: metaForRender,
                            value: this._getValueForField(sectionKey, f.api, seq)
                        }]
                    });

                    row.used += span;
                });

            if (row.columns.length) {
                rows.push({
                    key: `${meta.key}-fluid-${seqIdx}-${fluidRowIdx++}`,
                    style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
                    columns: row.columns
                });
            }
        });

        return rows;
    }

    _getSequenceList(sectionKey, sectionData = this._getSectionData(sectionKey)) {
        const sequenceSet = new Set();

        (this.metadata[sectionKey]?.fields || []).forEach(f => {
            if (f.sequence !== undefined && f.sequence !== null && f.sequence !== '') {
                sequenceSet.add(Number(f.sequence));
            }
        });

        Object.keys(sectionData || {}).forEach(key => {
            if (/^\d+$/.test(String(key))) {
                sequenceSet.add(Number(key));
            }
        });

        const result = Array.from(sequenceSet)
            .filter(Number.isFinite)
            .sort((a, b) => a - b);

        return result.length ? result : [1];
    }

    _getValueForField(sectionKey, api, sequence) {
        const sectionData = this._getSectionData(sectionKey);

        if (this._isSequentialSection(sectionKey)) {
            if (!sequence) return null;
            return sectionData?.[sequence]?.[api] ?? null;
        }

        return sectionData?.[api] ?? null;
    }

    _computeFieldDisabled(
        fieldMeta,
        sectionKey = fieldMeta?.sectionKey,
        sequence = fieldMeta?.sequence
    ) {
        
        if (!fieldMeta?.disableWhen) {
            return false;
        }

        return this._conditionsMatchForField(
            fieldMeta.disableWhen,
            sectionKey,
            sequence
        );
    }

    _isRowActive(sectionKey, seq) {
        const rec = this._getSectionData(sectionKey)?.[seq];
        if (!rec) return false;

        const meta = this.metadata?.[sectionKey];
        const activationFields =
            meta?.activationFields ||
            this.requiredFieldsMap[sectionKey] ||
            (meta?.fields || [])
                .filter(
                    field =>
                        field.type !== 'note' &&
                        field.api &&
                        field.api !== 'Id'
                )
                .map(field => field.api);

        return activationFields.some(field =>
            rec[field] !== null &&
            rec[field] !== '' &&
            rec[field] !== undefined
        );
    }

    _applyDynamicFilter(metaForRender) {
        if (!metaForRender?.dynamicFilter) return;

        const getter = this[metaForRender.dynamicFilter];

        if (getter === undefined) return;

        metaForRender.filter =
            typeof getter === 'function'
                ? getter.call(this)
                : getter;
    }

    _conditionsMatchForField(conditions, sectionKey, sequence) {
        console.log('_conditionsMatchForField started');
        if (!conditions) return true;

        const conds = Array.isArray(conditions) ? conditions : [conditions];
        return conds.every(cond => {
            const key = Object.keys(cond)[0];
            const expected = cond[key];
            const cur = this._resolveFieldConditionValue(key, sectionKey, sequence);

            if (expected === '__notNull' || expected === '__notEmpty') {
                return cur !== null && cur !== undefined && cur !== '';
            }

            return String(cur) === String(expected);
        });
    }

    _computeFieldVisible(fieldMeta, sectionKey = fieldMeta?.sectionKey, sequence = fieldMeta?.sequence) {
        console.log('_computeFieldVisible started');
        if (fieldMeta?.visible === false) return false;
        if (!fieldMeta?.visibleWhen) return true;
        return this._conditionsMatchForField(fieldMeta.visibleWhen, sectionKey, sequence);
    }

    _computeFieldRequired(fieldMeta, sectionKey = fieldMeta?.sectionKey, sequence = fieldMeta?.sequence) {
        const baseRequired = !!fieldMeta?.required;
        if (!fieldMeta?.requiredWhen) return baseRequired;
        return this._conditionsMatchForField(fieldMeta.requiredWhen, sectionKey, sequence);
    }

    _computeFieldReadOnly(fieldMeta, sectionKey = fieldMeta?.sectionKey, sequence = fieldMeta?.sequence) {
        const baseReadOnly = !!fieldMeta?.readOnly;
        if (!fieldMeta?.readOnlyWhen) return baseReadOnly;
        return ( baseReadOnly || this._conditionsMatchForField(fieldMeta.readOnlyWhen, sectionKey, sequence));
    }

    /**********************************************
     * Field Change Handler
     **********************************************/
    handleSectionFieldChange(e) {
        const { api, value, sectionKey, additionalFields, sequence } = e.detail;

        this.education[sectionKey] = this.education[sectionKey] || {};

        // get meta for normalization
        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);
        const normalized = this._normalizeValue(api, value, fieldMeta);
        console.log(
            'ProgrammesInterestedIn:',
            normalized,
            JSON.stringify(normalized)
        );

        if (
            sectionKey === 'programSelection' &&
            (
                api === 'ProgrammesInterestedIn__c' ||
                api === 'PrimaryProgramPreference__c'
            )
        ) {
            this.program[api] = normalized;
            this.education.programSelection = this.program;

            this._syncSecondaryProgramPreference();
            this._cleanupHiddenFields(sectionKey);
            this._buildRenderModelAll();

            return;
        }

        if (this._isSequentialSection(sectionKey)) {
            this.education[sectionKey][sequence] ||= {};
            this.education[sectionKey][sequence][api] = normalized;
            this.education[sectionKey][sequence].additionalFields ||= {};
            this.education[sectionKey][sequence].additionalFields[api] = additionalFields;
            this._cleanupHiddenFields(sectionKey);
            this._buildRenderModelAll();
            return;
        }

        this.education[sectionKey].additionalFields ||= {};
        this.education[sectionKey].additionalFields[api] = additionalFields;

        if (sectionKey === "application") {
            this.application[api] = normalized;

            this.education.application = { ...this.application };
            this._cleanupHiddenFields(sectionKey);
            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === "programDetail") {
            this.program[api] = normalized;
            this.education.programDetail = this.program;

            this._cleanupHiddenFields(sectionKey);
            this._buildRenderModelAll();
            return;
        }

        this.education[sectionKey] = this.education[sectionKey] || {};
        this.education[sectionKey][api] = normalized;

        this._cleanupHiddenFields(sectionKey);
        this._buildRenderModelAll();
    }

    _syncSecondaryProgramPreference() {
        const selected = this.education.programSelection?.ProgrammesInterestedIn__c;
        const primary = this.education.programSelection?.PrimaryProgramPreference__c;

        const programmes = Array.isArray(selected)
            ? selected
            : String(selected || '')
                .split(';')
                .map(v => v.trim())
                .filter(Boolean);

        let secondary = null;

        if (programmes.length === 2 && primary) {
            secondary = programmes.find(program => program !== primary) || null;
        }

        this.program.SecondaryProgramPreference__c = secondary;
        this.education.programSelection = this.program;
    }

    handleLookupSet(e){
        const { api, value, displayValue, sectionKey, additionalFields, sequence } = e.detail;

        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);
        const normalized = this._normalizeValue(api, value, fieldMeta);

        this.education[sectionKey] = this.education[sectionKey] || {};

        if (this._isSequentialSection(sectionKey)) {
            this.education[sectionKey][sequence] ||= {};
            this.education[sectionKey][sequence][api] = normalized;
            this.education[sectionKey][sequence].Display ||= {};
            this.education[sectionKey][sequence].Display[api] = displayValue;
            this.education[sectionKey][sequence].additionalFields ||= {};
            this.education[sectionKey][sequence].additionalFields[api] = additionalFields;
            this._buildRenderModelAll();
            return;
        }

        this.education[sectionKey][api] = normalized;

        if(sectionKey === 'programDetail'){
            this.program[api] = normalized;
        }

        if (sectionKey === 'application') {
            this.application[api] = normalized;
        }

        if (sectionKey === 'programSelection') {
            this.program[api] = normalized;
            this.education.programSelection = this.program;
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

    _cleanupHiddenFields(sectionKey) {
        const meta = this.metadata?.[sectionKey];
        if (!meta?.fields?.length) return;

        const data = this._getSectionData(sectionKey);
        if (!data) return;

        meta.fields.forEach(field => {
            const resolved = this._resolveFieldMeta(sectionKey, {
                ...field,
                sectionKey
            });

            if (resolved.visible !== false) return;

            const api = field.api;

            // Already empty
            if (
                data[api] === null ||
                data[api] === undefined ||
                data[api] === ''
            ) {
                return;
            }

            data[api] = null;

            // Lookup display value must also be cleared
            if (data.Display?.[api] !== undefined) {
                data.Display[api] = null;
            }

            // Additional fields must also be cleared
            if (data.additionalFields?.[api] !== undefined) {
                data.additionalFields[api] = null;
            }
        });
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
                const resolved = this._resolveFieldMeta("application", { ...f, sectionKey: "application" });
                if (resolved.visible === false || !resolved.required) {
                    return;
                }

                    let v = this.application[f.api];
                    if(resolved.type === "checkbox" && v === false){
                        v = undefined;
                    }
                    if (v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0)) {
                        addError("application", f.api, `${resolved?.shortLabel || resolved.label || resolved.api} is required`);
                    }
            });
        }


        /********************************************
         * 3️⃣ Validate PROGRAMME DETAIL (always required)
         ********************************************/
        const pdMeta = this.metadata.programDetail;
        const pdData = this.program || {};

        pdMeta.fields.forEach(f => {
            const resolved = this._resolveFieldMeta("programDetail", { ...f, sectionKey: "programDetail" });

            // Skip invisible fields completely
            if (resolved.visible === false) return;

            if (resolved.required) {
                let v = pdData[resolved.api];
                if(resolved.type === "checkbox" && v === false){
                    v = undefined;
                }
                if (v === null || v === undefined || v === "" ||
                    (Array.isArray(v) && v.length === 0)) {
                    addError("programDetail", resolved.api, `${resolved?.shortLabel || resolved.label || resolved.api} is required`);
                }
            }
        });

        /********************************************
         * 4️⃣ VALIDATE PROGRAMME SELECTION
         ********************************************/
        const psMeta = this.metadata.programSelection;
        const psData = this.program || {};

        psMeta.fields.forEach(f => {
            const resolved = this._resolveFieldMeta(
                "programSelection",
                { ...f, sectionKey: "programSelection" }
            );

            if (resolved.visible === false || !resolved.required) {
                return;
            }

            let v = psData[resolved.api];

            if (
                v === null ||
                v === undefined ||
                v === "" ||
                (Array.isArray(v) && v.length === 0)
            ) {
                addError(
                    "programSelection",
                    resolved.api,
                    `${resolved?.shortLabel || resolved.label || resolved.api} is required`
                );
            }
        });


        /********************************************
         * 6️⃣ Validate date (min or max)
         ********************************************/
        Object.keys(this.metadata).forEach(sectionKey => {
            const sectionMeta = this.metadata[sectionKey];
            const sectionData = this._getSectionData(sectionKey);
            if (!sectionData || !Array.isArray(sectionMeta?.fields)) return;

            if (this._isSequentialSection(sectionKey)) {
                this._getSequenceList(sectionKey, sectionData).forEach(seq => {
                    sectionMeta.fields.forEach(f => {
                        const resolved = this._resolveFieldMeta(sectionKey, {
                            ...f,
                            sectionKey,
                            sequence: seq
                        });

                        if (resolved.visible === false) return;

                        if (resolved.required) {
                            let v = this._getValueForField(sectionKey, resolved.api, seq);
                            if (resolved.type === "checkbox" && v === false) {
                                v = undefined;
                            }
                            if (v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0)) {
                                addError(sectionKey, `${resolved.api}__${seq}`, `${resolved?.shortLabel || resolved.label || resolved.api} is required`);
                            }
                        }

                        if (resolved.type != 'date' && !resolved.min && !resolved.max) return;

                        const res = validateMinMaxDate(resolved, this._getValueForField(sectionKey, resolved.api, seq));
                        if (res != null) {
                            addError(sectionKey, `${resolved.api}__${seq}`, '');
                        }
                    });
                });
                return;
            }

            sectionMeta.fields.forEach(f => {
                const resolved = this._resolveFieldMeta(sectionKey, { ...f, sectionKey });

                // Skip invisible fields completely
                if (resolved.visible === false) return;
                if (resolved.type != 'date' && !resolved.min && !resolved.max) return;

                const res = validateMinMaxDate(resolved, sectionData[resolved.api]);
                if (res!=null) {
                    addError(sectionKey, resolved.api, '');
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
        return this._computeFieldVisible(fieldMeta, sectionKey, fieldMeta?.sequence);
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

        this._cleanupHiddenFields('programSelection');
        this._cleanupHiddenFields('programDetail');

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