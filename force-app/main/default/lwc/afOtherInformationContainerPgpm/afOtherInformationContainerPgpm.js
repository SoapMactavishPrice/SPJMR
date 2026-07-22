import { LightningElement, track, api } from 'lwc';
import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveChildren from '@salesforce/apex/ApFormDataController.saveChildren';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { buildErrorSummary } from "c/applicationFormService";
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import fetchMetadataBulk from '@salesforce/apex/ApplicationFormController.fetchMetadataBulk';

import { validateNumber, validateTextConstraints } from "c/applicationFormService";

import { context as context } from './context';

const ACHIEVEMENT_MAX_ROWS = 3;

export default class AfOtherInformationContainerPgpm extends LightningElement {

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

    picklistCache = {};
    dependentCache = {};
    customDropdownCache = {};

    @track other = {
        achievements: { isSequential: false },
        achievementsVisibleRows: 1,
        achievementsActions: {},
        achievementsDeleted: [],
        medicalHistory: {},
        informationSource: {},
        otherDetails: {},

        questionnaire: {}


    };


    metadata = {};
    @track sectionModel = [];

    async connectedCallback() {
        this._buildMetadataSkeleton();

        try {
            const data = await getAllPicklistsForObjects({ objectApiNames: ['Academic_Achievements__c', 'Application__c'] })
            
            const merged = {
                defaultSet: {},
                recordTypeSet: {},
                customDropdowns: {}
            };

            if (Array.isArray(data)) {
                data.forEach(b => {
                    if (!b) return;

                    if (b.defaultSet) {
                        Object.entries(b.defaultSet).forEach(([api, cfg]) => {
                            merged.defaultSet[api] = cfg;
                        });
                    }

                    if (b.recordTypeSet) {
                        Object.entries(b.recordTypeSet).forEach(([rtId, fields]) => {
                            merged.recordTypeSet[rtId] =
                                merged.recordTypeSet[rtId] || {};

                            Object.entries(fields || {}).forEach(([api, cfg]) => {
                                merged.recordTypeSet[rtId][api] = cfg;
                            });
                        });
                    }

                    if (b.customDropdowns) {
                        Object.entries(b.customDropdowns).forEach(([api, configs]) => {
                            merged.customDropdowns[api] = configs;
                        });
                    }
                });
            }

            this.customDropdownCache =
                merged.customDropdowns || {};

            this.picklistCache = merged;
            this.dependentCache = {};

            this._injectPicklists();
            this._updateActionState();
            this._buildRenderModelAll();

            await this.fetchForm();
        } catch (err) {
            console.warn('Picklist fetch failed', err);
            this._injectPicklists();
            this._buildRenderModelAll();
            await this.fetchForm();
        } finally {
            this.isLoading = false;
        }
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

    resolveCustomDropdown(api) {

        const configs =
            this.customDropdownCache?.[api] || [];

        return configs.find(
            x => x.context === 'Program.PGPM'
        );
    }

    /* ------------------------------------------------------------
       METADATA (grid layout + field definitions)
    ------------------------------------------------------------- */
    _buildMetadataSkeleton() {
        const cs = 12;

        this.metadata.achievements = {
            key: 'achievements',
            title: 'Achievements',
            columnSystem: 10,
            layout: 'fluid',
            fields: [
                { api:'Title_of_the_Award__c', span: 2, type:'text', label:'Title of the Award', maxlength: '60', },
                { 
                    api: "Institute_Granting_the_Award__c", 
                    type: "text", 
                    label: "Institute Granting the Award", 
                    span: 2,
                    maxlength: '200',
                },
                { api:'Year__c', span: 2, type:'picklist', label:'Year' },
                { api:'Award_Position__c', span: 2, type:'picklist', label:'Award / Position' },
                { api:'Level__c', span: 2, type:'picklist', label:'Level' },
                { api:'Describe_the_Award_Max_25_words__c', span: 3, type:'textarea', label:'Describe the Award(Max. 25 words)', maxlength: '2000', maxWords: 25, showCounter: true, }
            ]
        };

        this.metadata.achievementsActions = {
            key: 'achievementsActions',
            title: 'Achievement Actions',
            columnSystem: 12,
            hideTitle: true,
            rows: [
                {
                    columns: [
                        { width: 8, fields: [] }, { width: 2, fields: ['AddMore'] }, { width: 2, fields: ['Remove'] }
                    ]
                },
            ],
            fields: [
                {
                    api: 'AddMore',
                    type: 'button',
                    label: '➕ Add More',
                    action: 'addMoreWe',
                    disableWhen: { 'achievementsActions.fullCapacity': true },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeWe',
                    disableWhen: { 'achievementsActions.noneToRemove': true },
                    variant: 'brand'
                }
            ]
        };

        this.metadata.medicalHistory = {
            key: 'medicalHistory',
            title: 'Medical History',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 12, fields: ['AnyMedicalIssue__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['MedicalIssueDetails__c'] }
                    ]
                },
                 {
                    columns: [
                        { width: 12, fields: ['UnderAnyMedication__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['MedicationDetails__c'] }
                    ]
                },
            ],
            fields: [
                { 
                    api:'AnyMedicalIssue__c', 
                    span: 2, 
                    type:'picklist', 
                    label:'1. PGPM is a fairly intense programme that demands long study hours, group assignments and multi-tasking. Please highlight if there are any (Physical or Mental) ailment / wellness issues that might interfere with your complete participation in the programme and for which you might need special support from SPJIMR.',
                    shortLabel: 'Any wellness issues',
                    required: true
                },
                { 
                    api:'MedicalIssueDetails__c', 
                    span: 3, 
                    type:'textarea', 
                    label:'Please Specify', 
                    maxlength: '2000',
                    visibleWhen: {
                        'medicalHistory.AnyMedicalIssue__c': 'Yes'
                    },
                    requiredWhen: {
                        'medicalHistory.AnyMedicalIssue__c': 'Yes'
                    }
                },
                { 
                    api:'UnderAnyMedication__c', 
                    span: 2, 
                    type:'picklist', 
                    label:'2. In connection to the question above, are you on any sort of prescribed medication and / or treatment?',
                    shortLabel: 'Under any Medication',
                    required: true
                },
                { 
                    api:'MedicationDetails__c', 
                    span: 3, 
                    type:'textarea', 
                    label:'Please Specify', 
                    maxlength: '2000',
                    visibleWhen: {
                        'medicalHistory.UnderAnyMedication__c': 'Yes'
                    },
                    requiredWhen: {
                        'medicalHistory.UnderAnyMedication__c': 'Yes'
                    }
                },
            ]
        };

        this.metadata.questionnaire = {
            key: 'questionnaire',
            title: 'Questionnaire',
            columnSystem: 12,
            rows: [],
            fields: []
        };

        this.metadata.informationSource = {
            key: 'informationSource',
            title: 'Information Source',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 5, fields: ['ReferralSource__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 5, fields: ['OtherReferralSource__c'] }
                    ]
                }
            ],
            fields: [
                { api: "ReferralSource__c", span: 4, type: "picklist", label: "How did you get to know about the Institute?", options: [] },
                { 
                    api: "OtherReferralSource__c", 
                    type: "text", 
                    label: "Enter Other Information Source", 
                    span: 2,
                    requiredWhen: { "otherResources.showOtherInformationSource": true},
                    visibleWhen: { "otherResources.showOtherInformationSource":true}, 
                    maxlength: '60',
                },
            ]
        };

        this.metadata.otherDetails = {
            key: 'otherDetails',
            title: 'Other Details',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 12, fields: ['InterestedInOtherProgram__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['OtherProgramsInterestedIn__c'] }
                    ]
                },
                 {
                    columns: [
                        { width: 12, fields: ['AppliedInPastYear__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['ProgramsAppliedInPastYear__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['OtherProgramsAppliedInPastYear__c'] }
                    ]
                },
            ],
            fields: [
                { 
                    api:'InterestedInOtherProgram__c', 
                    type:'picklist', 
                    label:'Are you interested in knowing about other SPJIMR programmes?',
                    shortLabel: 'Intrest in other programmes',
                    required: true,
                },
                { 
                    api: "OtherProgramsInterestedIn__c", 
                    label: "Which programme?", 
                    type: "multipicklist", 
                    requiredWhen: { 
                        "otherDetails.InterestedInOtherProgram__c": 'Yes'
                    },
                    visibleWhen: {
                        'otherDetails.InterestedInOtherProgram__c': 'Yes'
                    }
                },
                { 
                    api:'AppliedInPastYear__c', 
                    type:'picklist', 
                    label:'Have you applied to any other programmes at SPJIMR in the last one year?',
                    shortLabel: 'Applied Programmes in past',
                    required: true,
                },
                { 
                    api: "ProgramsAppliedInPastYear__c", 
                    label: "Select the course you applied for:", 
                    type: "multipicklist", 
                    requiredWhen: { 
                        "otherDetails.AppliedInPastYear__c": 'Yes'
                    },
                    visibleWhen: {
                        'otherDetails.AppliedInPastYear__c': 'Yes'
                    }
                },
                { 
                    api: "OtherProgramsAppliedInPastYear__c", 
                    type: "text", 
                    label: "Please specify course name", 
                    requiredWhen: { "otherResources.showOtherProgramAppliedInPast": true},
                    visibleWhen: { "otherResources.showOtherProgramAppliedInPast":true}, 
                    maxlength: '60',
                },
            ]
        };

    }

    _injectPicklists() {

        const optionalPicklists = [
            'Award_Position__c',
            'Level__c',
            'ReferralSource__c',
            'Year__c'
        ];

        const pick = this.picklistCache || {};

        const toOptions = arr =>
            (arr || []).map(x => ({
                label: x.label,
                value: x.value
            }));

        const resolveOptions = (api) => {

            const custom =
                this.resolveCustomDropdown(api);

            if (custom?.options?.length) {
                let options = custom.options.map(o => ({
                    label: o.label,
                    value: o.value
                }));

                if (api === 'Year__c') {
                    options = options.filter(o => Number(o.value) >= 1985);
                }

                return options;

            }

            if (pick.defaultSet &&
                pick.defaultSet[api]) {

                let options = toOptions(
                    pick.defaultSet[api].options
                );

                if (api === 'Year__c') {
                    options = options.filter(o => Number(o.value) >= 1985);
                }

                return options;
            }

            return [];
        };

        const merge = (sectionKey) => {

            const sec = this.metadata[sectionKey];

            if (!sec || !sec.fields) return;

            sec.fields.forEach(f => {
                let options = resolveOptions(f.api);

                if (
                    optionalPicklists.includes(f.api) &&
                    !options.some(o => o.value === '')
                ) {
                    options = [
                        { label: '--None--', value: '' },
                        ...options
                    ];
                }

                f.options = options;

            });
        };

        merge('achievements');
        merge('medicalHistory');
        merge('informationSource');
        merge('otherDetails');
        merge('questionnaire');
    }

    /* ------------------------------------------------------------
       Initialize 3 empty rows
    ------------------------------------------------------------- */
    _initializeRows() {
        this.other.achievements = { isSequential: false };
        for (let i = 1; i <= ACHIEVEMENT_MAX_ROWS; i++) {
            this.other.achievements[i] = { Id: null,  };
        }

        this.other.achievementsVisibleRows = 1;

    }

    async loadQuestionnaireMetadata() {

        const programCode =
            this.application?.Program_Code__c;

        const batchCode =
            this.application?.Batch__r?.Batch_Code__c;

        if (!programCode || !batchCode) {
            return;
        }

        const response = await fetchMetadataBulk({
            requests:
                this.buildQuestionnaireMetadataRequests(
                    programCode,
                    batchCode
                )
        });

        console.log(
            'QUESTIONNAIRE RESPONSE',
            JSON.stringify(response)
        );

        const records =
            response?.Batch_Questionnaire__mdt || [];

        this._buildQuestionnaireMetadata(records);
    }

    buildQuestionnaireMetadataRequests(programCode, batchCode) {
        return [
            {
                metadataName: 'Batch_Questionnaire__mdt',
                fields: [
                    'DeveloperName',
                    'Program__c',
                    'Batch__c',
                    'Section__c',
                    'Sequence__c',
                    'Question_Code__c',
                    'Question_Text__c',
                    'Answer_Type__c',
                    'Picklist_Options__c',
                    'Is_Required__c',
                    'Min_Words__c',
                    'Max_Words__c',
                    'Max_Length__c',
                    'Is_Active__c'
                ],
                filters: [
                    {
                        field: 'Program__c',
                        operator: '=',
                        value: programCode
                    },
                    {
                        field: 'Batch__c',
                        operator: '=',
                        value: batchCode
                    },
                    {
                        field: 'Is_Active__c',
                        operator: '=',
                        value: true
                    }
                ]
            }
        ];
    }

    _buildQuestionnaireMetadata(records) {

        const section = this.metadata.questionnaire;

        section.rows = [];
        section.fields = [];

        const sorted = [...records].sort(
            (a, b) =>
                (a.Sequence__c || 0) -
                (b.Sequence__c || 0)
        );

        sorted.forEach(rec => {

            const api = rec.Question_Code__c;

            const getHelpText = ((min, max) => {
                if(min && max) {
                    return `Min. ${min} and Max. ${max} words`
                }
                
                if(min) {
                    return `Min. ${min} words`
                }

                if(max) {
                    return `Max. ${max} words`
                }

                return ''
            })

            const field = {
                api,
                type: rec.Answer_Type__c,
                label: rec.Question_Text__c,
                required: rec.Is_Required__c,
                minWords: rec.Min_Words__c,
                maxWords: rec.Max_Words__c,
                showCounter: true,
                maxlength: rec.Max_Length__c,
                sequence: rec.Sequence__c,
                helpText:getHelpText(rec.Min_Words__c, rec.Max_Words__c),
            };

            if (
                rec.Answer_Type__c === 'picklist' &&
                rec.Picklist_Options__c
            ) {

                field.options =
                    rec.Picklist_Options__c
                        .split(';')
                        .map(v => v.trim())
                        .filter(Boolean)
                        .map(v => ({
                            label: v,
                            value: v
                        }));
            }

            section.fields.push(field);

            section.rows.push({
                columns: [
                    {
                        width: 12,
                        fields: [api]
                    }
                ]
            });

            if (
                this.other.questionnaire[api] === undefined
            ) {
                this.other.questionnaire[api] = '';
            }
        });

        console.log(
            'QUESTIONNAIRE METADATA',
            JSON.stringify(section)
        );
    }

    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta) return null;

        const cs = meta.columnSystem || 12;

        const section = {
            key: meta.key,
            title: meta.title,
            hideTitle: meta.hideTitle,
            rows: []
        };

                // read the correct section data
        const secData = this.other[sectionKey] || {};

        if (meta.layout === 'fluid') {
            section.rows = this._buildSequentialFluidRows(
                sectionKey,
                meta,
                secData
            );

            return section;
        }

        // SPECIAL: single-row sections (radio, totals)
        if (['medicalHistory', 'achievementsActions', 'informationSource', 'otherDetails', 'questionnaire'].includes(sectionKey)) {

            (meta.rows || []).forEach((metaRow, rIdx) => {
                const rowStyle =
                    `display:grid;grid-template-columns:repeat(${cs},1fr);` +
                    `gap:8px;margin-bottom:12px;`;

                const renderRow = {
                    key: `${sectionKey}-row-${rIdx}`,
                    style: rowStyle,
                    columns: []
                };

                metaRow.columns.forEach((col, cIdx) => {
                    const span = col.width || cs;
                    const renderCol = {
                        key: `${sectionKey}-col-${rIdx}-${cIdx}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: []
                    };

                    (col.fields || []).forEach(api => {

                        const baseMeta =
                            (meta.fields || []).find(f => f.api === api) ||
                            { api, type: 'text' };


                        const visible =
                            this._computeFieldVisible(baseMeta, sectionKey);

                        if (!visible) {
                            return;
                        }

                        const fieldMeta = {
                            ...baseMeta,
                            required: this._computeFieldRequired(baseMeta, sectionKey),
                            disabled: this._computeFieldDisabled(baseMeta, sectionKey),
                            visible: true
                        };

                        delete fieldMeta.visibleWhen;

                        const value =
                            sectionKey === 'questionnaire'
                                ? secData[api]?.value ?? null
                                : secData[api] ?? null;

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${rIdx}`,
                            meta: fieldMeta,
                            value
                        });
                    });

                    renderRow.columns.push(renderCol);
                });

                section.rows.push(renderRow);
            });

            return section;
        }

        // Special NOTE section (no rows, only text block)
        if (meta.type === 'note') {
            return {
                key: meta.key,
                title: null,
                rows: [
                    {
                        key: meta.key + '-note',
                        style: '',
                        columns: [
                            {
                                key: meta.key + '-col',
                                widthStyle: 'grid-column: span 12;',
                                fields: [
                                    {
                                        key: meta.key + '-text',
                                        meta: { type: 'note' },
                                        value: meta.text
                                    }
                                ]
                            }
                        ]
                    }
                ]
            };
        }



        // ----------------------------------------------------
        // MULTI-ROW Achievements (1..3 rows)
        // ----------------------------------------------------
        const seqList = Object.keys(secData)
            .map(k => Number(k))
            .filter(k => !isNaN(k))
            .sort((a, b) => a - b);

        if (seqList.length === 0) seqList.push(1);

        seqList.forEach(seq => {
            const rec = secData[seq] || {};

            (meta.rows || []).forEach((metaRow, rIdx) => {
                const rowStyle =
                    `display:grid;grid-template-columns:repeat(${cs},1fr);` +
                    `gap:8px;margin-bottom:12px;`;

                const renderRow = {
                    key: `${sectionKey}-row-${seq}-${rIdx}`,
                    style: rowStyle,
                    columns: []
                };

                // sequence numbering
                const seqCol = {
                    key: `${sectionKey}-seqcol-${seq}-${rIdx}`,
                    widthStyle: `grid-column: span 1;`,
                    fields: [{
                        key: `${sectionKey}-seq-label-${seq}-${rIdx}`,
                        meta: { type: 'label', label: rIdx === 0 ? seq : '' },
                        value: rIdx === 0 ? seq : null
                    }]
                };
                renderRow.columns.push(seqCol);

                // normal columns
                metaRow.columns.forEach((col, cIdx) => {
                    const span = col.width || cs;

                    const renderCol = {
                        key: `${sectionKey}-col-${seq}-${rIdx}-${cIdx}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: []
                    };

                    (col.fields || []).forEach((api) => {

                        const requiredFieldsMap = {
                            achievements : [
                                'Title_of_the_Award__c',
                                'Institute_Granting_the_Award__c',
                                'Year__c'
                            ]
                        };

                        const baseMeta =
                            (meta.fields || []).find(f => f.api === api && f.sequence === seq) ||
                            (meta.fields || []).find(f => f.api === api) ||
                            { api, type: 'text' };

                        const visible =
                            this._computeFieldVisible(
                                baseMeta,
                                sectionKey,
                                seq
                            );

                        if (!visible) {
                            return;
                        }

                        let isRequired = false;

                        if (requiredFieldsMap[sectionKey]?.includes(api)) {

                            // Row 1 → always required
                            /*if (seq === 1) {
                                isRequired = true;
                            }

                            // Row 2+ → required only if row is active
                            else*/ if (this._isRowActive(sectionKey, seq)) {
                                isRequired = true;
                            }
                        }

                        const fieldMeta = {
                            ...baseMeta,
                            required: isRequired || this._computeFieldRequired(baseMeta,sectionKey,seq),
                            disabled: this._computeFieldDisabled(baseMeta, sectionKey),
                        };

                        const value = rec[api] ?? null;

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${seq}-${rIdx}`,
                            meta: { ...fieldMeta, sequence: seq },
                            value
                        });
                    });

                    renderRow.columns.push(renderCol);
                });

                section.rows.push(renderRow);
            });
        });

        return section;
    }

    _buildFluidRows(meta, sectionData, groupFilter) {
        const cs = meta.columnSystem || 12;
        const rows = [];

        sectionData.Display ||= {};

        let row = { columns: [], used: 0 };

        meta.fields.forEach(f => {

            const fieldGroup = f.group || 'default';

            if (groupFilter && fieldGroup !== groupFilter) {
                return;
            }

            if (f.type === 'note') return;

            const metaForRender = this._resolveFieldMeta(meta.key, { ...f, sectionKey: meta.key });
            if (!this._isFieldVisible(metaForRender)) return;

            const span = metaForRender.span || 3;

            if (row.used + span > cs) {
                rows.push(row);
                row = { columns: [], used: 0 };
            }

            // ✅ INJECT DYNAMIC FILTER
            this._applyDynamicFilter(metaForRender);

            row.columns.push({
                key: `${meta.key}-${f.api}`,
                widthStyle: `grid-column: span ${span};`,
                fields: [{
                    key: `${meta.key}-${f.api}`,
                    meta: metaForRender,
                    value: sectionData?.[f.api] ?? null
                }]
            });

            row.used += span;
        });

        if (row.columns.length) {
            rows.push(row);
        }

        return rows.map((r, i) => ({
            key: `${meta.key}-fluid-row-${i}`,
            style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
            columns: r.columns
        }));
    }

    _buildFluidRowFromFieldList(meta, fieldApis, sectionData, rowIndex) {
        const cs = meta.columnSystem || 12;
        const rows = [];

        sectionData.Display ||= {};

        let row = { columns: [], used: 0 };

        fieldApis.forEach(api => {
            const f = meta.fields.find(x => x.api === api);
            if (!f) return;

            const metaForRender = this._resolveFieldMeta(meta.key, { ...f, sectionKey: meta.key });
            if (!this._isFieldVisible(metaForRender)) return;

            const span = metaForRender.span || 3;

            if (row.used + span > cs) {
                rows.push(row);
                row = { columns: [], used: 0 };
            }

            this._applyDynamicFilter(metaForRender);

            row.columns.push({
                key: `${meta.key}-${api}`,
                widthStyle: `grid-column: span ${span};`,
                fields: [{
                    key: `${meta.key}-${api}`,
                    meta: metaForRender,
                    value: sectionData?.[api] ?? null
                }]
            });

            row.used += span;
        });

        if (row.columns.length) rows.push(row);

        return rows.map((r, i) => ({
            key: `${meta.key}-fluid-${rowIndex}-${i}`,
            style: `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`,
            columns: r.columns
        }));
    }

    _buildSequentialFluidRows(sectionKey, meta, sectionData, groupFilter) {
        const cs = meta.columnSystem || 12;
        const sequences = this._getSequenceList(sectionKey, sectionData);
        const rows = [];
        let fluidRowIdx = 0;

        sequences.forEach((seq, seqIdx) => {
            
            let row = { columns: [], used: 0 };

            if (sectionKey === 'achievements') {
                row.columns.push({
                    key: `${meta.key}-seq-${seq}`,
                    widthStyle: 'grid-column: span 1;',
                    fields: [{
                        key: `${meta.key}-seq-${seq}`,
                        meta: {
                            type: 'label',
                            label: `${seq}`
                        },
                        value: null
                    }]
                });

                row.used += 1;
            }

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

                        if (sectionKey === 'achievements') {
                            row.columns.push({
                                key: `${meta.key}-seq-${seq}-cont-${fluidRowIdx}`,
                                widthStyle: 'grid-column: span 1;',
                                fields: [{
                                    key: `${meta.key}-seq-${seq}-cont-${fluidRowIdx}`,
                                    meta: {
                                        type: 'label',
                                        label: ''
                                    },
                                    value: null
                                }]
                            });

                            row.used += 1;
                        }

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

    _getSequenceList(sectionKey, sectionData = this.other[sectionKey] || {}) {
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

        if (sectionKey === 'achievements') {
            return Array.from(
                { length: this.other.achievementsVisibleRows || 1 },
                (_, i) => i + 1
            );
        }

        return result.length ? result : [1];
    }

    _getValueForField(sectionKey, api, sequence) {
        // other experience (non-sequential numeric keys)
        if (sectionKey === 'achievements') {
            if (!sequence) return null;
            if (sectionKey === 'achievements') {
                return this.other?.[sectionKey]?.[sequence]?.[api] ?? null;
            }
        }

        // normal single-row section
        return (this.other[sectionKey] || {})[api] || null;
    }

    _resolveFieldMeta(sectionKey, fieldMeta) {
        const resolved = { ...fieldMeta };
        const isSequential = this._isSequentialSection(sectionKey);

        if (this.isReadOnly) {
            resolved.readOnly = true;
            if (isSequential) {
                resolved.required = false;
                resolved.visible = this._computeFieldVisible(resolved, sectionKey, resolved.sequence);
                delete resolved.visibleWhen;
                delete resolved.requiredWhen;
            }

            return resolved;
        }

        const requiredFieldsMap = {
            achievements: [
                'Title_of_the_Award__c',
                'Institute_Granting_the_Award__c',
                'Year__c'
            ],
        };

        let baseRequired = false;

        if (requiredFieldsMap[sectionKey]?.includes(resolved.api)) {

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
            resolved.visible = this._computeFieldVisible(resolved, sectionKey, resolved.sequence);
            resolved.required = baseRequired || this._computeFieldRequired(resolved, sectionKey, resolved.sequence);
            delete resolved.visibleWhen;
            delete resolved.requiredWhen;
        }

        return resolved;
    }

    _isFieldVisible(fMeta) {
        if (!fMeta.visibleWhen) return true;

        const conds = Array.isArray(fMeta.visibleWhen)
            ? fMeta.visibleWhen
            : [fMeta.visibleWhen];

        const root = this.contextBlock || this.other;

        return conds.every(cond => {
            const key = Object.keys(cond)[0];
            const expected = cond[key];

            const parts = key.split('.');
            let cur = root; // ⭐ start from root

            for (let p of parts) {
                if (cur == null) return false;
                cur = cur[p];
            }

            if (expected === '__notNull' || expected === '__notEmpty') {
                return cur !== null && cur !== undefined && cur !== '';
            }

            return String(cur) === String(expected);
        });
    }

    _applyDynamicFilter(metaForRender) {
        if (!metaForRender?.dynamicFilter) return;

        if (metaForRender.dynamicFilter === 'city') {
            metaForRender.filter =
                this.getCityFilter(metaForRender.sequence);
            return;
        }

        const getter = this[metaForRender.dynamicFilter];

        if (getter === undefined) return;

        metaForRender.filter =
            typeof getter === 'function'
                ? getter.call(this)
                : getter;
    }

    getCityFilter(sequence) {

        const selectedCityId =
            this.other.achievements?.[sequence]?.City__c;

        const criteria = [
            {
                fieldPath: 'District__r.State__r.Country_Master__r.Name',
                operator: 'eq',
                value: 'India'
            },
            {
                fieldPath: 'Name',
                operator: 'eq',
                value: 'Other'
            }
        ];

        let filterLogic = '1 OR 2';

        if (selectedCityId) {
            criteria.push({
                fieldPath: 'Id',
                operator: 'eq',
                value: selectedCityId
            });

            filterLogic = '1 OR 2 OR 3';
        }

        return {
            criteria,
            filterLogic
        };
    }

    _isRowActive(sectionKey, seq) {
        const rec = this.other[sectionKey]?.[seq];
        if (!rec) return false;

        const activationFieldsMap = {
            achievements: [
                'Title_of_the_Award__c',
                'Institute_Granting_the_Award__c',
                'Year__c'
            ]
        };

        const activationFields = activationFieldsMap[sectionKey] || [];

        return activationFields.some(field =>
            rec[field] !== null &&
            rec[field] !== '' &&
            rec[field] !== undefined
        );
    }


    _buildRenderModelAll() {
        const list = [];

        // 2. Achievements rows (only if Yes)
        list.push(this._buildSectionRenderModel('achievements'));

        if (!this.isReadOnly) {
            list.push(this._buildSectionRenderModel('achievementsActions'));
        }
        
        list.push(this._buildSectionRenderModel('questionnaire'));
        list.push(this._buildSectionRenderModel('medicalHistory'));
        list.push(this._buildSectionRenderModel('informationSource'));
        list.push(this._buildSectionRenderModel('otherDetails'));
        
        this.sectionModel = list;        
    }


    get renderModel() {
        return this.sectionModel;
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

    _updateActionState() {

        const visibleRows =
            this.other.achievementsVisibleRows || 1;

        this.other.achievementsActions = {
            fullCapacity: visibleRows >= ACHIEVEMENT_MAX_ROWS,
            noneToRemove: visibleRows <= 1
        };

    }

    /* ------------------------------------------------------------
       Field Change Handler
    ------------------------------------------------------------- */
    handleSectionFieldChange(e) {
        const { api, value, displayValue, sectionKey, sequence } = e.detail;

        // Handle medical history grid
        if (sectionKey === 'medicalHistory') {
            this.other.medicalHistory[api] = value;

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'informationSource') {
            this.other.informationSource[api] = value;

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'otherDetails') {
            this.other.otherDetails[api] = value;

            this._buildRenderModelAll();
            return;
        }


        // Handle main other experience grid
        if (sectionKey === 'achievements') {
            this.other.achievements[sequence] =
                this.other.achievements[sequence] || {};
            this.other.achievements[sequence][api] = value;

            this.other.achievements[sequence].Display ||= {};
            this.other.achievements[sequence].Display[api] = displayValue;

            this._updateActionState();
            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'questionnaire') {

            this.other.questionnaire[api] = {
                ...(this.other.questionnaire[api] || {}),
                value
            };

            this._buildRenderModelAll();
            return;
        }

        // Nothing else to handle
    }

    handleLookupSet(e){

        const { api, value, displayValue, sectionKey, additionalFields, sequence } = e.detail;

        this.other[sectionKey][sequence] ||= {};

        this.other[sectionKey][sequence][api] = value;

        this.other[sectionKey][sequence].Display ||= {};

        this.other[sectionKey][sequence].Display[api] = displayValue;

        this._buildRenderModelAll();
    }

    handleSectionAction(e) {
        const { action } = e.detail;

        switch (action) {

            case 'addMoreWe':
                this._addAchievementsRow();
                break;

            case 'removeWe':
                this._removeAchievementsRow();
                break;

        }

        this._updateActionState();
        this._buildRenderModelAll();
    }

    _addAchievementsRow() {

        if (this.other.achievementsVisibleRows < ACHIEVEMENT_MAX_ROWS ) {
            this.other.achievementsVisibleRows++;
        }
    }

    _removeAchievementsRow() {

        const visible =
            this.other.achievementsVisibleRows;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.other.achievements[visible];

        if (rec?.Id) {
            this.other.achievementsDeleted ||= [];
            this.other.achievementsDeleted.push(rec.Id);
        }

        this.other.achievements[visible] = { Id:null };

        this.other.achievementsVisibleRows--;

    }

    /* ------------------------------------------------------------
       Month Calculation
    ------------------------------------------------------------- */
    _parseYearMonth(val) {
        if (!val) return null;
        const m = String(val).match(/(\d{4})-(\d{2})/);
        return m ? { y:Number(m[1]), m:Number(m[2]) } : null;
    }

    _normalizeDate(val) {
        if (!val) return null;

        // enforce yyyy-MM-dd only
        const d = new Date(val);
        if (isNaN(d)) return null;

        // Format back to yyyy-MM-dd
        return d.toISOString().substring(0, 10);
    }

    _normalizeMonthYear(val) {

        if (val == null) return null;

        // always string
        val = String(val).trim();
        if (!val) return null;

        let normalized = null;

        // Case 1: YYYY-MM → expand to YYYY-MM-01
        if (/^\d{4}-\d{2}$/.test(val)) {
            normalized = `${val}-01`;
        }
        // Case 2: start with YYYY-MM-DD (any further content ignored)
        else if (/^\d{4}-\d{2}-\d{2}/.test(val)) {
            normalized = val.substring(0, 10); // YYYY-MM-DD
        }

        // If invalid format
        if (!normalized) {
            return null;
        }

        // ⭐ Return final required format YYYY-MM-DD HH:mm:ss
        return `${normalized} 00:00:00`;

    }

    _isSequentialSection(sectionKey) {
        return sectionKey === 'achievements';
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

    _resolveFieldConditionValue(path, sectionKey, sequence) {
        const parts = String(path || '').split('.');
        if (!parts.length) return undefined;

        if (path === 'otherResources.showOtherInformationSource') {
            return this.other.informationSource?.ReferralSource__c === 'Other';
        }

        if (path === 'otherResources.showOtherProgramAppliedInPast') {
            return this._containsValue(
                this.other.otherDetails?.ProgramsAppliedInPastYear__c,
                'Any Other'
            );
        }

        // For sequential sections like achievements[seq]
        if (
            sequence !== null &&
            sequence !== undefined &&
            this._isSequentialSection(sectionKey) &&
            parts[0] === sectionKey
        ) {
            let cur = this.other?.[sectionKey]?.[sequence];
            for (let i = 1; i < parts.length; i++) {
                if (cur == null) return undefined;
                cur = cur[parts[i]];
            }
            return cur;
        }

        // Non-sequential root: other.medicalHistory,  etc.
        let cur = this.other;
        for (const part of parts) {
            if (cur == null) return undefined;
            cur = cur[part];
        }
        return cur;
    }

    _conditionsMatchForField(conditions, sectionKey, sequence) {
        if (!conditions) return true;

        const conds = Array.isArray(conditions) ? conditions : [conditions];
        return conds.every(cond => {
            const key = Object.keys(cond)[0];
            const expected = cond[key];
            const cur = this._resolveFieldConditionValue(key, sectionKey, sequence);

            console.log(
                'COND',
                key,
                'CUR',
                cur,
                'EXPECTED',
                expected,
                'SECTION',
                sectionKey
            );

            if (expected === '__notNull' || expected === '__notEmpty') {
                return cur !== null && cur !== undefined && cur !== '';
            }

            return String(cur) === String(expected);
        });
    }

    _computeFieldVisible(fieldMeta, sectionKey = fieldMeta?.sectionKey, sequence = fieldMeta?.sequence) {
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

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfOtherInformationContainerPgpm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfOtherInformationContainerPgpm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
    }
    
    /* ------------------------------------------------------------
       FETCH
    ------------------------------------------------------------- */
    async fetchForm() {

        const request = { parents: [], children: [] };

        context.parents.forEach(p => {
            if (p.logicalName === 'application') {
                request.parents.push({
                    logicalName: p.logicalName,
                    sobject: p.sobject,
                    fields: p.fieldsToQuery,
                    filters: [
                        { field: 'Id', value: this.application.Id }
                    ]
                });
            } else if(p.recordName) {
                request.parents.push({
                    logicalName: p.logicalName,
                    sobject: p.sobject,
                    fields: p.fieldsToQuery,
                    filters: [
                        { field: 'Name', value: p.recordName },
                        { field: context.parentLookupField, value: this.application.Id }
                    ]
                });
            }
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
                        value: this.application.Id
                    },
                    ...(c.filters || [])
                ]
            });
        });

        try {
            const response = await fetchDynamic({
                requestJson: JSON.stringify(request)
            });

            if (response.questionnaire) {

                Object.values(response.questionnaire)
                    .forEach(rec => {

                        this.other.questionnaire[rec.Question_Code__c] = {
                            Id: rec.Id,
                            value: rec.Answer_Value__c
                        };
                    });
            }

            if (response && response.application) {
                this.application.Application_Status__c = response?.application?.Application_Status__c;
                this.application.Assignment_Status__c = response?.application?.Assignment_Status__c;
                this.application.Batch__r =  this.application?.Batch__r ?? {};
                this.application.Batch__r.Batch_Code__c = response?.application?.Batch__r?.Batch_Code__c;
                this.application.Program_Code__c = response?.application?.Program_Code__c;

                this.other.medicalHistory = {
                    AnyMedicalIssue__c: response.application.AnyMedicalIssue__c,
                    MedicalIssueDetails__c: response.application.MedicalIssueDetails__c,
                    UnderAnyMedication__c: response.application.UnderAnyMedication__c,
                    MedicationDetails__c: response.application.MedicationDetails__c,
                };

                this.other.informationSource = {
                    ReferralSource__c: response.application.ReferralSource__c,
                    OtherReferralSource__c: response.application.OtherReferralSource__c,
                };

                this.other.otherDetails = {
                    InterestedInOtherProgram__c: response.application.InterestedInOtherProgram__c,
                    OtherProgramsInterestedIn__c: response.application.OtherProgramsInterestedIn__c,
                    AppliedInPastYear__c: response.application.AppliedInPastYear__c,
                    ProgramsAppliedInPastYear__c: response.application.ProgramsAppliedInPastYear__c,
                    OtherProgramsAppliedInPastYear__c: response.application.OtherProgramsAppliedInPastYear__c,
                };
                await this.loadQuestionnaireMetadata();
            }

            if (response && response.achievements) {

                // 1️⃣ Convert object to array
                let records = Object.keys(response.achievements)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.achievements[k]);

                // 3️⃣ Re-map into sequential rows
                this.other.achievements = { isSequential: false };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= ACHIEVEMENT_MAX_ROWS ) {
                        this.other.achievements[seq] = rec;
                        seq++;
                    }
                });

                this.other.achievementsVisibleRows =
                    Math.max(1, Math.min(records.length, ACHIEVEMENT_MAX_ROWS ));

                // 4️⃣ Fill remaining rows
                while (seq <= ACHIEVEMENT_MAX_ROWS ) {
                    this.other.achievements[seq] = { Id: null };
                    seq++;
                }
            }

        } catch (err) {
            console.warn('Fetch failed', err);
        }

        this._applyReadOnlyMode();
        this._updateActionState();
        this._buildRenderModelAll();
    }


    /* ------------------------------------------------------------
       VALIDATION
    ------------------------------------------------------------- */
    validateAll() {
        const meta = this.metadata.achievements;
        const errors = {
            achievements: {}
        };

        for (let seq = 1; seq <= this.other.achievementsVisibleRows; seq++) {
            const rec = this.other.achievements[seq] || {};
            const prev = this.other.achievements[seq - 1];

            // Required field validation

            meta.fields.forEach(f => {

                const requiredFields = [
                    'Title_of_the_Award__c',
                    'Institute_Granting_the_Award__c',
                    'Year__c'
                ];

                let isRequired = false;

                if (requiredFields.includes(f.api)) {

                    /*if (seq === 1) {
                        isRequired = true;
                    } else*/ if (this._isRowActive('achievements', seq)) {
                        isRequired = true;
                    }
                }

                const visible =
                    this._computeFieldVisible(
                        f,
                        'achievements',
                        seq
                    );

                if (!visible) {
                    return; // skip validation for hidden fields
                }

                const metadataRequired =
                    this._computeFieldRequired(
                        f,
                        'achievements',
                        seq
                    );

                const finalRequired =
                    isRequired || metadataRequired;

                if (finalRequired && (rec[f.api] === null || rec[f.api] === undefined || rec[f.api] === '')) {
                    errors.achievements[`${f.api}__${seq}`] = `${f?.shortLabel || f.label} is required`;
                    return;
                }              

                if ((f.type === 'number' || f.type === 'currency') && rec[f.api]) {
                    const err = validateNumber(f, rec[f.api]);
                    if (err) {
                        errors.achievements[`${f.api}__${seq}`] = err;
                    }
                }

                if(f.type === 'text' || f.type === 'textarea') {
                    const textValue = String(rec[f.api] || '').trim();

                    const textErr =
                        validateTextConstraints(f, textValue);

                    if (textErr) {
                        errors.achievements[`${f.api}__${seq}`] = textErr;
                    }

                }

            });

        }

        const longLableSections = ['questionnaire', 'medicalHistory'];

        const validateSingleSection = (sectionKey) => {
            const meta = this.metadata[sectionKey];
            const data = this.other[sectionKey] || {};

            errors[sectionKey] ||= {};

            meta.fields.forEach(f => {

                const visible =
                    this._computeFieldVisible(f, sectionKey);

                if (!visible) {
                    return;
                }

                const required =
                    this._computeFieldRequired(f, sectionKey);

                const value = 
                    sectionKey === 'questionnaire'
                        ? data[f.api]?.value
                        : data[f.api];

                console.log('value passed '+JSON.stringify(this.metadata[sectionKey]));

                if (
                    required &&
                    (value === null ||
                    value === undefined ||
                    value === '')
                ) {
                    console.log('longLableSections '+longLableSections+' '+sectionKey+' '+longLableSections.includes(sectionKey));
                    errors[sectionKey][f.api] = longLableSections.includes(sectionKey) ?
                        'This field is required' :
                        `${f?.shortLabel || f.label} is required`;
                }

                const textValue = String(value || '').trim();

                const textErr =
                    validateTextConstraints(f, textValue);

                if (textErr) {
                    errors[sectionKey][f.api] = textErr;
                }

            });
        };

        validateSingleSection('medicalHistory');
        validateSingleSection('informationSource');
        validateSingleSection('otherDetails');
        validateSingleSection('questionnaire');

        const cmp = this.template.querySelector('c-af-section-engine');
        if (cmp && typeof cmp.applyErrors === 'function') {
            cmp.applyErrors(errors);
        }

        const hasErrors =
            Object.values(errors)
                .some(sec => Object.keys(sec).length > 0);

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

        return !hasErrors;
    }

    /* ------------------------------------------------------------
       SAVE (children only)
    ------------------------------------------------------------- */
    @api async saveForm() {
        if(this.isReadOnly) return true;

        this.isLoading = true;
        if (!this.validateAll()) {
            this.isLoading = false;
            return false;
        }

        if (!this._containsValue(this.other?.otherDetails?.ProgramsAppliedInPastYear__c, 'Any Other')) {
            this.other.otherDetails.OtherProgramsAppliedInPastYear__c = null;
        }

        try {
            await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify({
                    application: {
                        sobject: "Application__c",
                        fields: {
                            Id: this.application.Id,
                            AnyMedicalIssue__c: 
                                this.other?.medicalHistory?.AnyMedicalIssue__c  || '',
                            MedicalIssueDetails__c: 
                                this.other?.medicalHistory?.MedicalIssueDetails__c  || '',
                            UnderAnyMedication__c: 
                                this.other?.medicalHistory?.UnderAnyMedication__c  || '',
                            MedicationDetails__c: 
                                this.other?.medicalHistory?.MedicationDetails__c  || '',
                            InterestedInOtherProgram__c: 
                                this.other?.otherDetails?.InterestedInOtherProgram__c  || '',
                            OtherProgramsInterestedIn__c: 
                                this.other?.otherDetails?.OtherProgramsInterestedIn__c  || '',
                            AppliedInPastYear__c: 
                                this.other?.otherDetails?.AppliedInPastYear__c  || '',
                            ProgramsAppliedInPastYear__c: 
                                this.other?.otherDetails?.ProgramsAppliedInPastYear__c  || '',
                            OtherProgramsAppliedInPastYear__c: 
                                this.other?.otherDetails?.OtherProgramsAppliedInPastYear__c  || '',
                            ReferralSource__c: 
                                this.other?.informationSource?.ReferralSource__c  || '',
                            OtherReferralSource__c: 
                                this.other?.informationSource?.OtherReferralSource__c  || '',
                        }
                    }
                })
            });

            const childPayload = {};
            const c = context.children[0];

            let rows = [];
            let deleted = this.other.achievementsDeleted || [];

            for (let seq = 1; seq <= ACHIEVEMENT_MAX_ROWS; seq++) {

                const row = this.other.achievements[seq] || {};
                const hasId = !!row.Id;

                // If record is already scheduled for deletion, skip it
                if (hasId && deleted.includes(row.Id)) {
                    continue;
                }

                // const hasData = Object.keys(row).some(k =>
                //     k !== 'Id' && row[k] !== null && row[k] !== ''
                // );

                // 1) Normalize row values based on metadata
                Object.keys(row).forEach(api => {
                    const fieldMeta = this.metadata.achievements.fields.find(f => f.api === api);

                    if (fieldMeta?.type === 'monthyear') {
                        row[api] = this._normalizeMonthYear(row[api]);
                    }

                    // DATE (full date)
                    if (fieldMeta?.type === 'date') {
                        row[api] = this._normalizeDate(row[api]);
                    }

                    if (fieldMeta?.type === 'number') {
                        const n = Number(row[api]);
                        row[api] = isNaN(n) ? null : n;
                    }

                    // Currency formatting: always 2 decimals
                    if (fieldMeta?.type === 'currency') {
                        let val = row[api];

                        if (val === null || val === undefined || val === '') {
                            row[api] = null;
                        } else {
                            val = Number(val);
                            row[api] = isNaN(val) ? null : Number(val.toFixed(2));
                        }
                    }

                    
                });

                // 2) Build clean row based on fieldsToQuery
                const allowed = new Set(c.fieldsToQuery);
                let cleanRow = {};

                Object.keys(row).forEach(api => {

                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                const hasData = Object.keys(cleanRow)
                    .filter(k => k !== 'Id')
                    .some(k => {
                        const val = cleanRow[k];

                        return (
                            val !== null &&
                            val !== undefined &&
                            val !== ''
                        );
                    });

                if (!hasId && !hasData) continue;     // ignore
                if (!hasId && hasData) {               
                    let row = {
                        sobject: c.sobject,
                        parentLookupField: c.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    };
                    rows.push(row);
                    continue;
                }
                if (hasId && !hasData) {
                    deleted.push(row.Id);
                    continue;
                }
                if (hasId && hasData) {
                    rows.push({
                        sobject: c.sobject,
                        parentLookupField: c.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: row.Id
                    });
                }
            }

            childPayload[c.logicalName] = {
                sobject: c.sobject,
                parentLookupField: c.parentLookupField,
                rows,
                deletedIds: deleted
            };

            const questionnaireRows = [];

            this.metadata.questionnaire.fields.forEach(field => {

                const row =
                    this.other.questionnaire?.[field.api];

                const value = row?.value;
                const recordId = row?.Id || null;

                if (
                    value === null ||
                    value === undefined ||
                    value === ''
                ) {
                    return;
                }

                questionnaireRows.push({

                    sobject: 'Questionnaire_Response__c',

                    parentLookupField: 'Application__c',

                    parentId: this.application.Id,

                    Id: recordId,

                    fields: {

                        Section__c:
                            field.section || 'questionnaire',

                        Sequence__c:
                            field.sequence,

                        Question_Code__c:
                            field.api,

                        Question_Text__c:
                            field.label,

                        Answer_Type__c:
                            field.type,

                        Answer_Value__c:
                            value
                    }
                });
            });

            childPayload.questionnaire = {

                sobject: 'Questionnaire_Response__c',

                parentLookupField: 'Application__c',

                rows: questionnaireRows,

                deletedIds: []
            };

            await saveChildren({
                payloadJson: JSON.stringify(childPayload)
            });

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Other Details'
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Saved successfully',
                variant: 'success',
            }));
            await this.fetchForm();

            return true;
        } catch (e) {
            console.warn('save failed', e);
            return false;
        } finally {
            this.isLoading = false;
        }
        
    }
}