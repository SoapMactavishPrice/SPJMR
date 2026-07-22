import { LightningElement, track, api } from 'lwc';
import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveChildren from '@salesforce/apex/ApFormDataController.saveChildren';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { buildErrorSummary } from "c/applicationFormService";
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';

import { validateNumber, validateTextConstraints } from "c/applicationFormService";

import { context as context } from './context';

export default class AfWorkExperienceContainerPgpm extends LightningElement {

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

    @track work = {
        haveWorkExperience : {},
        workExperience: { isSequential: false },
        totalExperienceSummary : {},
        graduationDetails: {},
        haveCareerBreak : {},
        careerBreak: { isSequential: false },
        totalCareerBreakSummary: {},
        haveSabbatical : {},
        sabbatical: { isSequential: false },
        totalSabbaticalSummary: {},
        workExperienceVisibleRows: 1,
        careerBreakVisibleRows: 1,
        sabbaticalVisibleRows: 1,
        workExperienceActions: {},
        workExperienceDeleted: [],
        careerBreakActions: {},
        careerBreakDeleted: [],
        sabbaticalActions: {},
        sabbaticalDeleted: [],
    };

    _getRequiredFields(sectionKey) {
        return (
            AfWorkExperienceContainerPgpm
                .ROW_RULES?.[sectionKey]
                ?.requiredFields || []
        );
    }

    _isRequiredField(sectionKey, api) {
        return this
            ._getRequiredFields(sectionKey)
            .includes(api);
    }

    static ROW_RULES = {
        workExperience: {
            requiredFields: [
                'Name_of_Organisation__c',
                'Designation__c',
                'Start_Date__c',
                'End_Date__c',
                'City__c',
                'Gross_Annual_CTC__c',
                'Responsibilities__c',
                'Employment_Type__c',
                'Industry__c',
                'Function__c',
                'Currency__c',
            ]
        },

        careerBreak: {
            requiredFields: [
                'StartDate__c',
                'EndDate__c'
            ]
        },

        sabbatical: {
            requiredFields: [
                'StartDate__c',
                'EndDate__c'
            ]
        }
    };

    _isFieldRequired(sectionKey, api, sequence, fieldMeta) {

        // Field belongs to another sequence
        if (
            fieldMeta?.sequence != null &&
            Number(fieldMeta.sequence) !== Number(sequence)
        ) {
            return false;
        }

        let required = false;

        if (this._isRequiredField(sectionKey, api)) {

            if (sequence === 1) {
                required = true;
            }
            else if (
                this._isRowActive(sectionKey, sequence)
            ) {
                required = true;
            }
        }

        return required ||
            this._computeFieldRequired(
                fieldMeta,
                sectionKey,
                sequence
            );
    }

    metadata = {};
    @track sectionModel = [];

    async connectedCallback() {
        this._buildMetadataSkeleton();

        try {
            const data = await getAllPicklistsForObjects({ objectApiNames: ['Work_Experience__c', 'Application__c'] })
            
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

        this.metadata.haveWorkExperience = {
            key: 'haveWorkExperience',
            title: 'Work Experience',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['HasWorkExperience__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'HasWorkExperience__c',
                    type: 'radio',
                    label: 'Do you have work experience?',
                    required: true,
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ]
                }
            ]
        };

        this.metadata.workExperienceNote = {
            key: 'workExperienceNote',
            type: 'note',
            text: `
            1) Sabbatical / study leave / leave without pay / medical leave / similar leaves will not be counted towards work experience.<br>
            2) Relevant work experience after graduation will be considered. Internship/training/ project work which were a part of the curriculum will not be considered as work experience.<br>
            3) Please list your work experience in chronological order, starting with your most recent organization and working backward<br>
            `
        };

        this.metadata.workExperience = {
            key: 'workExperience',
            title: 'Work Experience Details',
            columnSystem: 10,
            layout: 'fluid',
            fields: [
                { api:'Name_of_Organisation__c', span: 2, type:'picklist', label:'Name of Organization' },
                { 
                    api: "OtherOrganizationName__c", 
                    type: "text", 
                    label: "Enter Organisation Name", 
                    span: 2,
                    requiredWhen: { "otherResources.showOtherOrganizationName": true},
                    visibleWhen: { "otherResources.showOtherOrganizationName":true}, 
                    maxlength: '60',
                },
                { api:'Industry__c', span: 2, type:'picklist', label:'Industry' },
                { 
                    api: "OtherIndustry__c", 
                    type: "text", 
                    label: "Enter Other Industry", 
                    span: 2,
                    requiredWhen: { "otherResources.showOtherIndustry": true},
                    visibleWhen: { "otherResources.showOtherIndustry":true}, 
                    maxlength: '60',
                },
                { api:'Function__c', span: 2, type:'picklist', label:'Function' },
                { 
                    api: "OtherFunction__c", 
                    type: "text", 
                    label: "Enter Other Function", 
                    span: 2,
                    requiredWhen: { "otherResources.showOtherFunction": true},
                    visibleWhen: { "otherResources.showOtherFunction":true}, 
                    maxlength: '60',
                },
                { api:'Employment_Type__c', span: 2, type:'picklist', label:'Employment Type' },
                { 
                    api: "City__c",
                    type: "lookup", 
                    label: "City",
                    span: 2,
                    objectApi: "IndCity__c",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    dynamicFilter: "city",
                    allowOther: true,
                },
                { 
                    api: "OtherCity__c", 
                    type: "text", 
                    label: "Other City", 
                    span: 2,
                    requiredWhen: { "otherResources.showOtherCityField": true},
                    visibleWhen: { "otherResources.showOtherCityField":true}, 
                    maxlength: '100',
                },
                { api:'Designation__c', span: 2, type:'text', label:'Designation', maxlength: '255' },
                { api:'Gross_Annual_CTC__c', span: 2, type:'currency', label:'Gross Annual Salary in Rupees', step:0.01, max: '999999999' },
                { api:'Currency__c', span: 2, type:'picklist', label:'Currency' },
                { 
                    api: "OtherCurrency__c", 
                    type: "text", 
                    label: "Enter Other Currency", 
                    span: 2,
                    requiredWhen: { "otherResources.showOtherCurrency": true},
                    visibleWhen: { "otherResources.showOtherCurrency":true}, 
                    maxlength: '60',
                },
                {
                    api: 'IsCurrentJob__c',
                    span: 2,
                    type: 'radio',
                    label: 'Is this your current job?',
                    sequence: 1,
                    required: true,
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ]
                },
                { 
                    api:'Start_Date__c',
                    span: 2,
                    type:'date', 
                    label:'Start Date', 
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 35);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { 
                    api:'End_Date__c', 
                    span: 2,
                    type:'date', 
                    label:'End Date',
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 35);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] ,
                    readOnlyWhen: { 'workExperience.IsCurrentJob__c': 'Yes' }

                },
                { api:'Experience_In_Months__c', span: 2, type:'number', label:'Experience (Months)', readOnly:true,  },
                { api:'Responsibilities__c', span: 3, type:'textarea', label:'Describe your role briefly', shortLabel: "Role description", maxlength: '2500', maxWords: 100, showCounter: true, helpText:"Max. 100 words", visibleWhen: { 'workExperience.rowOne': true} }
            ]
        };

        this.metadata.workExperienceActions = {
            key: 'workExperienceActions',
            title: 'Work Experience Actions',
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
                    disableWhen: { 'workExperienceActions.fullCapacity': true },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeWe',
                    disableWhen: { 'workExperienceActions.noneToRemove': true },
                    variant: 'brand'
                }
            ]
        };

        this.metadata.totalExperienceSummary = {
            key: 'totalExperienceSummary',
            title: 'Total Industry Experience',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['TotalIndustryExperience__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['PriorWorkResponsibilities__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api:'TotalIndustryExperience__c',
                    type:'number',
                    label:'Total industry experience (months)',
                    readOnly:true
                },
                {
                    api:'PriorWorkResponsibilities__c',
                    type:'textarea',
                    label:'Roles and Responsibilities in Other Organisations (excluding most recent organisation)',
                    required: true,
                    shortLabel:'Roles and Responsibilities',
                    maxlength:'30000',
                    maxWords: 1000,
                    showCounter: true,
                    helpText:"Max. 1000 words",
                }
            ]
        };

        this.metadata.haveCareerBreak = {
            key: 'haveCareerBreak',
            title: 'Career Break',
            columnSystem: 48,
            rows: [
                {
                    columns: [
                        { width: 12, fields: ['HasCareerBreak__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 1, fields: ['ApplyingUnderRestartInitiative__c'] }, { width: 36, fields: ['RestartInitiativeAcknowledgement__c'] },
                    ]
                },
            ],
            fields: [
                {
                    api: 'HasCareerBreak__c',
                    type: 'radio',
                    label: 'Do you have career break?',
                    required: true,
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ]
                },
                {
                    api: "RestartInitiativeAcknowledgement__c",
                    type: 'richtext',
                    value: `
                        I would like to apply under the Restart Initiative - for women with a career break. <br>
                        (Please tick this option if you are eligible and interested).
                    `,
                    visibleWhen: {
                        'haveCareerBreak.HasCareerBreak__c': 'Yes'
                    }
                },
                {
                    api: "ApplyingUnderRestartInitiative__c",
                    type: "checkbox",
                    shortLabel: "Applying Under Restart Initiative",
                    //label: "Yes",
                    visibleWhen: {
                        'haveCareerBreak.HasCareerBreak__c': 'Yes'
                    }
                }
            ]
        };

        this.metadata.careerBreakNote = {
            key: 'careerBreakNote',
            type: 'note',
            text: `
            * Please list your career breaks in reverse chronological order 
            (starting with your most recent break first).<br>
            * Each break must be earlier than the previous one entered above.
            `
        };

        this.metadata.careerBreak = {
            key: 'careerBreak',
            title: 'Career Break Details',
            columnSystem: cs,
            layout: 'fluid',

            rows: [
                // ---------- ROW 1 ----------
                {
                    columns: [
                        { width: 3, fields: ['StartDate__c'] },
                        { width: 3, fields: ['EndDate__c'] },
                        { width: 3, fields: ['CareerBreakInMonths__c'] },
                    ]
                },
            ],

            fields: [
                { 
                    api:'StartDate__c', 
                    type:'monthyear', 
                    label:'Start Date', 
                    span: 3,
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 35);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { 
                    api:'EndDate__c', 
                    type:'monthyear', 
                    label:'End Date', 
                    span: 3,
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 35);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { api:'CareerBreakInMonths__c', type:'number', label:'Duration (In months)', readOnly:true, span: 3, }
            ]
        };

        this.metadata.careerBreakActions = {
            key: 'careerBreakActions',
            title: 'Career Break Actions',
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
                    action: 'addMoreCb',
                    disableWhen: { 'careerBreakActions.fullCapacity': true },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeCb',
                    disableWhen: { 'careerBreakActions.noneToRemove': true },
                    variant: 'brand'
                }
            ]
        };

        this.metadata.totalCareerBreakSummary = {
            key: 'totalCareerBreakSummary',
            title: 'Total Career Break',
            hideTitle: true,
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 6, fields: ['CareerBreakReason__c'] },
                        { width: 3, fields: ['TotalCareerBreak__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'CareerBreakReason__c',
                    type: 'textarea',
                    label: 'Reason for Career Break',
                    maxWords: 100,
                    showCounter: true,
                    maxlength:"32768",
                    helpText:"Max. 100 words",
                    visibleWhen: { 'haveCareerBreak.HasCareerBreak__c': 'Yes' },
                    requiredWhen: { 'haveCareerBreak.HasCareerBreak__c': 'Yes' }
                },
                {
                    api:'TotalCareerBreak__c',
                    type:'number',
                    label:'Total career break (months)',
                    readOnly:true
                }
            ]
        };

        this.metadata.haveSabbatical = {
            key: 'haveSabbatical',
            title: 'Sabbatical',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width:6, fields: ['TakingSabbatical__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 3, fields: ['HasSabbatical__c'] }
                    ]
                },
            ],
            fields: [
                { api:'TakingSabbatical__c', type:'picklist', label:'Will You Be Taking A Sabbatical From Your Current Organization To Study?' },
                {
                    api: 'HasSabbatical__c',
                    type: 'radio',
                    label: 'Were (Are) you on a sabbatical?',
                    required: true,
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ]
                },
            ]
        };

        this.metadata.sabbaticalNote = {
            key: 'sabbaticalNote',
            type: 'note',
            text: `
            * Please list your sabbatical in reverse chronological order 
            (starting with your most recent break first).<br>
            * Each break must be earlier than the previous one entered above.
            `
        };

        this.metadata.sabbatical = {
            key: 'sabbatical',
            title: 'Sabbatical Details',
            columnSystem: cs,
            layout: 'fluid',

            rows: [
                // ---------- ROW 1 ----------
                {
                    columns: [
                        { width: 3, fields: ['StartDate__c'] },
                        { width: 3, fields: ['EndDate__c'] },
                        { width: 3, fields: ['CareerBreakInMonths__c'] },
                    ]
                },
            ],

            fields: [
                { 
                    api:'StartDate__c', 
                    type:'monthyear', 
                    label:'Start Date',
                    span: 3,
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 35);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { 
                    api:'EndDate__c', 
                    type:'monthyear', 
                    label:'End Date', 
                    span: 3,
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 35);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0] 
                },
                { api:'CareerBreakInMonths__c', type:'number', label:'Duration (In months)', readOnly:true, span: 3, }
            ]
        };

        this.metadata.sabbaticalActions = {
            key: 'sabbaticalActions',
            title: 'Sabbatical Actions',
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
                    action: 'addMoreSab',
                    disableWhen: { 'sabbaticalActions.fullCapacity': true },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeSab',
                    disableWhen: { 'sabbaticalActions.noneToRemove': true },
                    variant: 'brand'
                }
            ]
        };

        this.metadata.totalSabbaticalSummary = {
            key: 'totalSabbaticalSummary',
            title: 'Total Sabbatical Break',
            hideTitle: true,
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 6, fields: ['SabbaticalReason__c'] },
                        { width: 3, fields: ['TotalSabbatical__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'SabbaticalReason__c',
                    type: 'textarea',
                    label: 'Reason of sabbatical',
                    maxWords: 100,
                    showCounter: true,
                    maxlength:"32768",
                    helpText:"Max. 100 words",
                    visibleWhen: { 'haveSabbatical.HasSabbatical__c': 'Yes' },
                    requiredWhen: { 'haveSabbatical.HasSabbatical__c': 'Yes' }
                },
                {
                    api:'TotalSabbatical__c',
                    type:'number',
                    label:'Total sabbatical (months)',
                    readOnly:true
                }
            ]
        };
    }

    _injectPicklists() {

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
                return custom.options.map(o => ({
                    label: o.label,
                    value: o.value
                }));
            }

            if (pick.defaultSet &&
                pick.defaultSet[api]) {

                return toOptions(
                    pick.defaultSet[api].options
                );
            }

            return [];
        };

        const merge = (sectionKey) => {

            const sec = this.metadata[sectionKey];

            if (!sec || !sec.fields) return;

            sec.fields.forEach(f => {
                f.options = resolveOptions(f.api);
            });
        };

        merge('workExperience');
        merge('haveSabbatical');
    }


    /* ------------------------------------------------------------
       Initialize 5 empty rows
    ------------------------------------------------------------- */
    _initializeRows() {
        this.work.workExperience = { isSequential: false };
        for (let i = 1; i <= 5; i++) {
            this.work.workExperience[i] = { Id: null,  };
        }

        this.work.workExperienceVisibleRows = 1;

        this.work.careerBreak = { isSequential: false };
        for (let i = 1; i <= 3; i++) {
            this.work.careerBreak[i] = { Id: null,  };
        }

        this.work.careerBreakVisibleRows = 1;

        this.work.sabbatical = { isSequential: false };
        for (let i = 1; i <= 3; i++) {
            this.work.sabbatical[i] = { Id: null,  };
        }

        this.work.sabbaticalVisibleRows = 1;
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
        const secData = this.work[sectionKey] || {};

        if (meta.layout === 'fluid') {
            section.rows = this._buildSequentialFluidRows(
                sectionKey,
                meta,
                secData
            );

            return section;
        }

        // SPECIAL: single-row sections (radio, totals)
        if (['haveWorkExperience', 'totalExperienceSummary', 'haveCareerBreak', 'totalCareerBreakSummary', 'haveSabbatical', 'totalSabbaticalSummary', 'workExperienceActions', 'careerBreakActions', 'sabbaticalActions'].includes(sectionKey)) {

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

                        if (
                            sectionKey === 'totalExperienceSummary' &&
                            baseMeta.api === 'PriorWorkResponsibilities__c' &&
                            this.work.workExperienceVisibleRows <= 1
                        ) {
                            return;
                        }

                        const fieldMeta = {
                            ...baseMeta,
                            required: this._computeFieldRequired(
                                baseMeta,
                                sectionKey
                            ),
                            disabled: this._computeFieldDisabled(baseMeta, sectionKey)
                        };

                        const visible =
                            this._computeFieldVisible(fieldMeta, sectionKey);

                        if (!visible) {
                            return;
                        }

                        const value = secData[api] ?? null;

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
        // MULTI-ROW WORK EXPERIENCE (1..5 rows)
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

                        const fieldMeta = {
                            ...baseMeta,
                            required: this._isFieldRequired(
                                sectionKey,
                                api,
                                seq,
                                baseMeta
                            )
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

            if (sectionKey === 'workExperience' || sectionKey === 'careerBreak' || sectionKey === 'sabbatical') {
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

                        // Work Experience style
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

                        if (sectionKey === 'workExperience' || sectionKey === 'careerBreak' || sectionKey === 'sabbatical') {
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

    _getSequenceList(sectionKey, sectionData = this.work[sectionKey] || {}) {
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

        if (sectionKey === 'workExperience') {
            return Array.from(
                { length: this.work.workExperienceVisibleRows || 1 },
                (_, i) => i + 1
            );
        }

        if (sectionKey === 'careerBreak') {
            return Array.from(
                { length: this.work.careerBreakVisibleRows || 1 },
                (_, i) => i + 1
            );
        }

        if (sectionKey === 'sabbatical') {
            return Array.from(
                { length: this.work.sabbaticalVisibleRows || 1 },
                (_, i) => i + 1
            );
        }

        return result.length ? result : [1];
    }

    _getValueForField(sectionKey, api, sequence) {
        // work experience (non-sequential numeric keys)
        if (sectionKey === 'workExperience' || sectionKey === 'careerBreak' || sectionKey === 'sabbatical') {
            if (!sequence) return null;
            if (sectionKey === 'workExperience' || sectionKey === 'careerBreak' || sectionKey === 'sabbatical') {
                return this.work?.[sectionKey]?.[sequence]?.[api] ?? null;
            }
        }

        // normal single-row section
        return (this.work[sectionKey] || {})[api] || null;
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

        resolved.required = this._isFieldRequired(
            sectionKey,
            resolved.api,
            resolved.sequence,
            resolved
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

        const root = this.contextBlock || this.work;

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
            this.work.workExperience?.[sequence]?.City__c;

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

        const rec = this.work[sectionKey]?.[seq];
        if (!rec) {
            return false;
        }

        return this
            ._getRequiredFields(sectionKey)
            .some(field => {

                const value = rec[field];

                return value !== null &&
                    value !== undefined &&
                    value !== '';
            });
    }


    _buildRenderModelAll() {
        const list = [];

        list.push(this._buildSectionRenderModel('workExperienceNote'));

        // 1. Do you have work experience?
        list.push(this._buildSectionRenderModel('haveWorkExperience'));

        const hasWork = this.work.haveWorkExperience?.HasWorkExperience__c === 'Yes';
        const hasCareerBreak = this.work.haveCareerBreak?.HasCareerBreak__c === 'Yes';
        const hasSabbatical = this.work.haveSabbatical?.HasSabbatical__c === 'Yes';

        // 2. Work experience rows (only if Yes)
        if (hasWork) {
            list.push(this._buildSectionRenderModel('workExperience'));

            if (!this.isReadOnly) {
                list.push(this._buildSectionRenderModel('workExperienceActions'));
            }

            // 3. Total experience summary
            list.push(this._buildSectionRenderModel('totalExperienceSummary'));

            list.push(this._buildSectionRenderModel('haveSabbatical'));

            // 4. sabbatical (only if Yes)
            if(hasSabbatical){

                list.push(this._buildSectionRenderModel('sabbaticalNote'));

                list.push(this._buildSectionRenderModel('sabbatical'));

                if (!this.isReadOnly) {
                    list.push(
                        this._buildSectionRenderModel(
                            'sabbaticalActions'
                        )
                    );
                }

                // Total sabbatical summary
                list.push(this._buildSectionRenderModel('totalSabbaticalSummary'));
            }

            list.push(this._buildSectionRenderModel('haveCareerBreak'));

            // 5. career break (only if Yes)
            if(hasCareerBreak){

                list.push(this._buildSectionRenderModel('careerBreakNote'));

                list.push(this._buildSectionRenderModel('careerBreak'));

                if (!this.isReadOnly) {
                    list.push(
                        this._buildSectionRenderModel(
                            'careerBreakActions'
                        )
                    );
                }

                // Total career break summary
                list.push(this._buildSectionRenderModel('totalCareerBreakSummary'));
            }
            
        }
        
        this.sectionModel = list;        
    }

    _recomputeTotalIndustryExperience() {
        let total = 0;

        for (let seq = 1; seq <= 5; seq++) {
            const rec = this.work.workExperience[seq];
            if (!rec) continue;

            const m = Number(rec.Experience_In_Months__c || 0);
            if (!isNaN(m)) total += m;
        }

        // Store inside summary section
        if (!this.work.totalExperienceSummary) {
            this.work.totalExperienceSummary = {};
        }

        this.work.totalExperienceSummary.TotalIndustryExperience__c = total;
    }

    _reComputeTotalCareerBreak() {
        let total = 0;

        for (let seq = 1; seq <= 3; seq++) {
            const rec = this.work.careerBreak[seq];
            if (!rec) continue;
            
            const m = Number(rec.CareerBreakInMonths__c || 0);
            if (!isNaN(m)) total += m;
        }

        // Store inside summary section
        if (!this.work.totalCareerBreakSummary) {
            this.work.totalCareerBreakSummary = {};
        }

        this.work.totalCareerBreakSummary.TotalCareerBreak__c = total;
    }

    _reComputeTotalSabbatical() {
        let total = 0;

        for (let seq = 1; seq <= 3; seq++) {
            const rec = this.work.sabbatical[seq];
            if (!rec) continue;
            
            const m = Number(rec.CareerBreakInMonths__c || 0);
            if (!isNaN(m)) total += m;
        }

        // Store inside summary section
        if (!this.work.totalSabbaticalSummary) {
            this.work.totalSabbaticalSummary = {};
        }

        this.work.totalSabbaticalSummary.TotalSabbatical__c = total;
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
            this.work.workExperienceVisibleRows || 1;

        this.work.workExperienceActions = {
            fullCapacity: visibleRows >= 5,
            noneToRemove: visibleRows <= 1
        };

        const visibleRowsCb =
            this.work.careerBreakVisibleRows || 1;

        this.work.careerBreakActions = {
            fullCapacity: visibleRowsCb >= 3,
            noneToRemove: visibleRowsCb <= 1
        };

        this._reComputeTotalCareerBreak();

        const visibleRowsSab =
            this.work.sabbaticalVisibleRows || 1;

        this.work.sabbaticalActions = {
            fullCapacity: visibleRowsSab >= 3,
            noneToRemove: visibleRowsSab <= 1
        };

        this._reComputeTotalSabbatical();

        this._recomputeTotalIndustryExperience();

    }

    /* ------------------------------------------------------------
       Field Change Handler
    ------------------------------------------------------------- */
    handleSectionFieldChange(e) {
        const { api, value, displayValue, sectionKey, sequence } = e.detail;

        // Handle "Do you have work experience?" section
        if (sectionKey === 'haveWorkExperience') {
            this.work.haveWorkExperience[api] = value;

            // When No is selected → clear everything
            if (value === 'No') {

                //clear expweience
                // 1️⃣ Collect ids to delete
                const deleteList = [];
                for (let i = 1; i <= 5; i++) {
                    const rec = this.work.workExperience[i];
                    if (rec && rec.Id) {
                        deleteList.push(rec.Id);
                    }
                }
                
                // 2️⃣ Save this list in container state
                this.work.workExperienceDeleted = deleteList;

                // 3️⃣ Clear all rows
                this.work.workExperience = { isSequential: false };
                for (let i = 1; i <= 5; i++) {
                    this.work.workExperience[i] = { Id: null };
                }

                this.work.workExperienceVisibleRows = 1;

                // 4️⃣ Reset total experience
                this.work.totalExperienceSummary = {
                    TotalIndustryExperience__c: 0
                };

                //clear career break
                this.work.haveCareerBreak = { ...this.work.haveCareerBreak, HasCareerBreak__c: 'No', ApplyingUnderRestartInitiative__c: false };

                //clear expweience
                // 1️⃣ Collect ids to delete
                const cbDeleteList = [];
                for (let i = 1; i <= 3; i++) {
                    const rec = this.work.careerBreak[i];
                    if (rec && rec.Id) {
                        cbDeleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.careerBreakDeleted = cbDeleteList;

                // 3️⃣ Clear all rows
                this.work.careerBreak = { isSequential: false };
                for (let i = 1; i <= 3; i++) {
                    this.work.careerBreak[i] = { Id: null };
                }

                this.work.careerBreakVisibleRows = 1;

                // 4️⃣ Reset total experience
                this.work.totalCareerBreakSummary = {
                    ...this.work.totalCareerBreakSummary,
                    CareerBreakReason__c: '',
                    TotalCareerBreak__c: 0
                };

                //clear sabbatical
                this.work.haveSabbatical = { ...this.work.haveSabbatical, HasSabbatical__c: 'No' };

                //clear experience
                // 1️⃣ Collect ids to delete
                const sabDeleteList = [];
                for (let i = 1; i <= 3; i++) {
                    const rec = this.work.sabbatical[i];
                    if (rec && rec.Id) {
                        sabDeleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.sabbaticalDeleted = sabDeleteList;

                // 3️⃣ Clear all rows
                this.work.sabbatical = { isSequential: false };
                for (let i = 1; i <= 3; i++) {
                    this.work.sabbatical[i] = { Id: null };
                }

                this.work.sabbaticalVisibleRows = 1;

                // 4️⃣ Reset total experience
                this.work.totalSabbaticalSummary = {
                    ...this.work.totalSabbaticalSummary,
                    SabbaticalReason__c: '',
                    TotalSabbatical__c: 0
                };

                this._updateActionState();
            
            }

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'totalExperienceSummary') {
            this.work.totalExperienceSummary[api] = value;
            this._buildRenderModelAll();
            return;
        }

        // Handle career break grid
        if (sectionKey === 'haveCareerBreak') {
            this.work.haveCareerBreak[api] = value;

            // When No is selected → clear everything
            if (api === 'HasCareerBreak__c' && value === 'No') {

                this.work.haveCareerBreak.ApplyingUnderRestartInitiative__c = false;

                //clear expweience
                // 1️⃣ Collect ids to delete
                const deleteList = [];
                for (let i = 1; i <= 3; i++) {
                    const rec = this.work.careerBreak[i];
                    if (rec && rec.Id) {
                        deleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.careerBreakDeleted = deleteList;

                // 3️⃣ Clear all rows
                this.work.careerBreak = { isSequential: false };
                for (let i = 1; i <= 3; i++) {
                    this.work.careerBreak[i] = { Id: null };
                }

                this.work.careerBreakVisibleRows = 1;

                // 4️⃣ Reset total experience
                this.work.totalCareerBreakSummary = {
                    ...this.work.totalCareerBreakSummary,
                    CareerBreakReason__c: '',
                    TotalCareerBreak__c: 0
                };
            }


            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'totalCareerBreakSummary') {
            this.work.totalCareerBreakSummary[api] = value;
            this._buildRenderModelAll();
            return;
        }

        // Handle sabbatical grid
        if (sectionKey === 'haveSabbatical') {
            this.work.haveSabbatical[api] = value;

            // When No is selected → clear everything
            if (api === 'HasSabbatical__c' && value === 'No') {

                //clear expweience
                // 1️⃣ Collect ids to delete
                const deleteList = [];
                for (let i = 1; i <= 3; i++) {
                    const rec = this.work.sabbatical[i];
                    if (rec && rec.Id) {
                        deleteList.push(rec.Id);
                    }
                }

                // 2️⃣ Save this list in container state
                this.work.sabbaticalDeleted = deleteList;

                // 3️⃣ Clear all rows
                this.work.sabbatical = { isSequential: false };
                for (let i = 1; i <= 3; i++) {
                    this.work.sabbatical[i] = { Id: null };
                }

                this.work.sabbaticalVisibleRows = 1;

                // 4️⃣ Reset total experience
                this.work.totalSabbaticalSummary = {
                    ...this.work.totalSabbaticalSummary,
                    SabbaticalReason__c: '',
                    TotalSabbatical__c: 0
                };
            }


            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'totalSabbaticalSummary') {
            this.work.totalSabbaticalSummary[api] = value;
            this._buildRenderModelAll();
            return;
        }


        // Handle main work experience grid
        if (sectionKey === 'workExperience') {
            this.work.workExperience[sequence] =
                this.work.workExperience[sequence] || {};
            this.work.workExperience[sequence][api] = value;

            this.work.workExperience[sequence].Display ||= {};
            this.work.workExperience[sequence].Display[api] = displayValue;

            // Clear stale Other City
            if (
                api === 'City__c' &&
                displayValue !== 'Other'
            ) {
                this.work.workExperience[sequence].OtherCity__c = null;
            }

            if (
                api === 'Name_of_Organisation__c' &&
                displayValue !== 'Other'
            ) {
                this.work.workExperience[sequence].OtherOrganizationName__c = null;
            }

            if (
                api === 'Industry__c' &&
                displayValue !== 'Other'
            ) {
                this.work.workExperience[sequence].OtherIndustry__c = null;
            }

            if (
                api === 'Function__c' &&
                displayValue !== 'Other'
            ) {
                this.work.workExperience[sequence].OtherFunction__c = null;
            }

            if (
                api === 'Currency__c' &&
                displayValue !== 'Other'
            ) {
                this.work.workExperience[sequence].OtherCurrency__c = null;
            }

            if (
                api === 'IsCurrentJob__c' &&
                sequence === 1
            ) {
                if (value === 'Yes') {
                    this.work.workExperience[sequence].End_Date__c =
                        this.application.Application_End_Date__c ||
                        new Date().toISOString().split('T')[0];
                }

                this._recomputeExperienceMonths(sequence);
                this._recomputeTotalIndustryExperience();
            }

            if (api === 'Start_Date__c' || api === 'End_Date__c') {
                this._recomputeExperienceMonths(sequence);
                this._recomputeTotalIndustryExperience();
            }

            this._updateActionState();
            this._buildRenderModelAll();
            return;
        }

        // Handle main career break grid
        if (sectionKey === 'careerBreak') {
            this.work.careerBreak[sequence] =
                this.work.careerBreak[sequence] || {};
            this.work.careerBreak[sequence][api] = value;

            if (api === 'StartDate__c' || api === 'EndDate__c') {
                this._recomputeCareerBreakMonths(sequence);
                this._reComputeTotalCareerBreak();
            }

            this._buildRenderModelAll();
            return;
        }

        // Handle main sabbatical grid
        if (sectionKey === 'sabbatical') {
            this.work.sabbatical[sequence] =
                this.work.sabbatical[sequence] || {};
            this.work.sabbatical[sequence][api] = value;

            if (api === 'StartDate__c' || api === 'EndDate__c') {
                this._recomputeSabbaticalMonths(sequence);
                this._reComputeTotalSabbatical();
            }

            this._buildRenderModelAll();
            return;
        }

        // Nothing else to handle
    }

    handleLookupSet(e){

        const { api, value, displayValue, sectionKey, additionalFields, sequence } = e.detail;

        this.work[sectionKey][sequence] ||= {};

        this.work[sectionKey][sequence][api] = value;

        this.work[sectionKey][sequence].Display ||= {};

        this.work[sectionKey][sequence].Display[api] = displayValue;

        if (
            sectionKey === 'workExperience' &&
            api === 'City__c' &&
            displayValue !== 'Other'
        ) {
            this.work[sectionKey][sequence].OtherCity__c = null;
        }

        if (
            sectionKey === 'workExperience' &&
            api === 'IsCurrentJob__c' &&
            sequence === 1 &&
            value === 'Yes'
        ) {
            this.work.workExperience[sequence].End_Date__c =
                this.application.Application_End_Date__c ||
                new Date().toISOString().split('T')[0];
        }

        this._buildRenderModelAll();
    }

    handleSectionAction(e) {
        const { action } = e.detail;

        switch (action) {

            case 'addMoreWe':
                this._addWorkExperienceRow();
                break;

            case 'removeWe':
                this._removeWorkExperienceRow();
                break;

            case 'addMoreCb':
                this._addCareerBreakRow();
                break;

            case 'removeCb':
                this._removeCareerBreakRow();
                break;

            case 'addMoreSab':
                this._addSabbaticalRow();
                break;

            case 'removeSab':
                this._removeSabbaticalRow();
                break;
        }

        this._updateActionState();
        this._buildRenderModelAll();
    }

    _addWorkExperienceRow() {

        if (this.work.workExperienceVisibleRows < 5) {
            this.work.workExperienceVisibleRows++;
        }
    }

    _removeWorkExperienceRow() {

        const visible =
            this.work.workExperienceVisibleRows;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.work.workExperience[visible];

        if (rec?.Id) {
            this.work.workExperienceDeleted ||= [];
            this.work.workExperienceDeleted.push(rec.Id);
        }

        this.work.workExperience[visible] = { Id:null };

        this.work.workExperienceVisibleRows--;

        if (this.work.workExperienceVisibleRows === 1) {
            this.work.totalExperienceSummary.PriorWorkResponsibilities__c = '';
        }
    }

    _addCareerBreakRow() {

        if (this.work.careerBreakVisibleRows < 3) {
            this.work.careerBreakVisibleRows++;
        }
    }

    _removeCareerBreakRow() {

        const visible =
            this.work.careerBreakVisibleRows;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.work.careerBreak[visible];

        if (rec?.Id) {
            this.work.careerBreakDeleted ||= [];
            this.work.careerBreakDeleted.push(rec.Id);
        }

        this.work.careerBreak[visible] = { Id:null };

        this.work.careerBreakVisibleRows--;
    }

    _addSabbaticalRow() {

        if (this.work.sabbaticalVisibleRows < 3) {
            this.work.sabbaticalVisibleRows++;
        }
    }

    _removeSabbaticalRow() {

        const visible =
            this.work.sabbaticalVisibleRows;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.work.sabbatical[visible];

        if (rec?.Id) {
            this.work.sabbaticalDeleted ||= [];
            this.work.sabbaticalDeleted.push(rec.Id);
        }

        this.work.sabbatical[visible] = { Id:null };

        this.work.sabbaticalVisibleRows--;
    }

    /* ------------------------------------------------------------
       Month Calculation
    ------------------------------------------------------------- */
    _parseYearMonth(val) {
        if (!val) return null;
        const m = String(val).match(/(\d{4})-(\d{2})/);
        return m ? { y:Number(m[1]), m:Number(m[2]) } : null;
    }

    _recomputeExperienceMonths(seq) {
        const rec = this.work.workExperience[seq] || {};

        if (!rec.Start_Date__c) {
            rec.Experience_In_Months__c = null;
            return;
        }

        const start = new Date(rec.Start_Date__c);

        // End date source:
        // - If current job = Yes, use Application End Date
        // - Otherwise use the row's End Date
        let end = null;

        if (rec.IsCurrentJob__c === 'Yes') {
            end = this.application?.Application_End_Date__c
                ? new Date(this.application.Application_End_Date__c)
                : new Date();
        } else {
            if (!rec.End_Date__c) {
                rec.Experience_In_Months__c = null;
                return;
            }
            end = new Date(rec.End_Date__c);
        }

        if (isNaN(start) || isNaN(end) || end < start) {
            rec.Experience_In_Months__c = 0;
            return;
        }

        // Full month difference
        let months =
            (end.getFullYear() - start.getFullYear()) * 12 +
            (end.getMonth() - start.getMonth());

        // Move the anchor forward by the full months counted
        const anchor = new Date(start);
        anchor.setMonth(anchor.getMonth() + months);

        // Remaining days after full months
        const remainingDays =
            Math.floor(
                (end.getTime() - anchor.getTime()) / (1000 * 60 * 60 * 24)
            ) + 1;

        // 17-day rule
        if (remainingDays >= 17) {
            months++;
        }

        rec.Experience_In_Months__c = Math.max(0, months);
    }


    _recomputeCareerBreakMonths(seq) {
        const rec = this.work.careerBreak[seq] || {};

        const s = this._parseYearMonth(rec.StartDate__c);
        if (!s) {
            rec.CareerBreakInMonths__c = null;
            return;
        }

        const e = this._parseYearMonth(rec.EndDate__c);
        if (!e) {
            rec.CareerBreakInMonths__c = null;
            return;
        }

        const appEnd = this._parseYearMonth(
            this.application?.Application_End_Date__c
        );

        let effectiveEnd = e;

        // 🔥 Cap at Application_End_Date__c
        if (appEnd) {
            const breakEndVal = e.y * 100 + e.m;
            const appEndVal = appEnd.y * 100 + appEnd.m;

            if (breakEndVal > appEndVal) {
                effectiveEnd = appEnd;
            }
        }

        const startVal = s.y * 100 + s.m;
        const endVal = effectiveEnd.y * 100 + effectiveEnd.m;

        if (startVal > endVal) {
            rec.CareerBreakInMonths__c = 0;
            return;
        }

        const months =
            (effectiveEnd.y - s.y) * 12 +
            (effectiveEnd.m - s.m) +
            1;

        rec.CareerBreakInMonths__c = months >= 0 ? months : 0;
    }

    _recomputeSabbaticalMonths(seq) {
        const rec = this.work.sabbatical[seq] || {};

        const s = this._parseYearMonth(rec.StartDate__c);
        if (!s) {
            rec.CareerBreakInMonths__c = null;
            return;
        }

        const e = this._parseYearMonth(rec.EndDate__c);
        if (!e) {
            rec.CareerBreakInMonths__c = null;
            return;
        }

        const appEnd = this._parseYearMonth(
            this.application?.Application_End_Date__c
        );

        let effectiveEnd = e;

        // 🔥 Cap at Application_End_Date__c
        if (appEnd) {
            const breakEndVal = e.y * 100 + e.m;
            const appEndVal = appEnd.y * 100 + appEnd.m;

            if (breakEndVal > appEndVal) {
                effectiveEnd = appEnd;
            }
        }

        const startVal = s.y * 100 + s.m;
        const endVal = effectiveEnd.y * 100 + effectiveEnd.m;

        if (startVal > endVal) {
            rec.CareerBreakInMonths__c = 0;
            return;
        }

        const months =
            (effectiveEnd.y - s.y) * 12 +
            (effectiveEnd.m - s.m) +
            1;

        rec.CareerBreakInMonths__c = months >= 0 ? months : 0;
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
        return sectionKey === 'workExperience' || sectionKey === 'careerBreak' || sectionKey === 'sabbatical';
    }

    _resolveFieldConditionValue(path, sectionKey, sequence) {
        const parts = String(path || '').split('.');
        if (!parts.length) return undefined;

        if (
            path === 'otherResources.showOtherCityField' &&
            sectionKey === 'workExperience'
        ) {
            const row =
                this.work.workExperience?.[sequence];

            return row?.Display?.City__c === 'Other';
        }

        if (
            path === 'otherResources.showOtherOrganizationName' &&
            sectionKey === 'workExperience'
        ) {
            const row =
                this.work.workExperience?.[sequence];

            return row?.Name_of_Organisation__c === 'Other';
        }

        if (
            path === 'otherResources.showOtherIndustry' &&
            sectionKey === 'workExperience'
        ) {
            const row =
                this.work.workExperience?.[sequence];

            return row?.Industry__c === 'Other';
        }

        if (
            path === 'otherResources.showOtherFunction' &&
            sectionKey === 'workExperience'
        ) {
            const row =
                this.work.workExperience?.[sequence];

            return row?.Function__c === 'Other';
        }

        if (
            path === 'otherResources.showOtherCurrency' &&
            sectionKey === 'workExperience'
        ) {
            const row =
                this.work.workExperience?.[sequence];

            return row?.Currency__c === 'Other';
        }

        if (
            path === 'workExperience.IsCurrentJob__c' &&
            sectionKey === 'workExperience'
        ) {
            if (sequence !== 1) {
                return false;
            }

            const row =
                this.work.workExperience?.[1];

            return row?.IsCurrentJob__c;
        }

        if (
            path === 'workExperience.rowOne' &&
            sectionKey === 'workExperience'
        ) {
            return sequence === 1;
        }

        // For sequential sections like workExperience[seq] / careerBreak[seq]
        if (
            sequence !== null &&
            sequence !== undefined &&
            this._isSequentialSection(sectionKey) &&
            parts[0] === sectionKey
        ) {
            let cur = this.work?.[sectionKey]?.[sequence];
            for (let i = 1; i < parts.length; i++) {
                if (cur == null) return undefined;
                cur = cur[parts[i]];
            }
            return cur;
        }

        // Non-sequential root: work.haveCareerBreak, work.totalCareerBreakSummary, etc.
        let cur = this.work;
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
        return AfWorkExperienceContainerPgpm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfWorkExperienceContainerPgpm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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

            if (response && response.application) {

                this.application.Application_Status__c = response?.application?.Application_Status__c;
                this.application.Assignment_Status__c = response?.application?.Assignment_Status__c;
                this.application.Application_End_Date__c = response?.application?.Batch__r?.Application_End_Date__c;

                this.work.haveWorkExperience = {
                    HasWorkExperience__c: response?.application?.HasWorkExperience__c
                };

                this.work.totalExperienceSummary = {
                    TotalIndustryExperience__c:
                        response?.application?.TotalIndustryExperience__c,
                    PriorWorkResponsibilities__c:
                        response?.application?.PriorWorkResponsibilities__c

                };
                this.work.haveCareerBreak = {
                    HasCareerBreak__c: response?.application?.HasCareerBreak__c,
                    ApplyingUnderRestartInitiative__c: response?.application?.ApplyingUnderRestartInitiative__c
                };

                this.work.totalCareerBreakSummary = {
                    TotalCareerBreak__c: response?.application?.TotalCareerBreak__c,
                    CareerBreakReason__c: response?.application?.CareerBreakReason__c
                };

                this.work.haveSabbatical = {
                    HasSabbatical__c: response?.application?.HasSabbatical__c,
                    TakingSabbatical__c: response?.application?.TakingSabbatical__c
                };

                this.work.totalSabbaticalSummary = {
                    TotalSabbatical__c: response?.application?.TotalSabbatical__c,
                    SabbaticalReason__c: response?.application?.SabbaticalReason__c
                };

            }

            if(response && response.graduationDetails) {
                this.work.graduationDetails = response?.graduationDetails;
            }

            if (response && response.workExperience) {

                // 1️⃣ Convert object to array
                let records = Object.keys(response.workExperience)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.workExperience[k]);

                // 2️⃣ Sort by reverse chronology (latest first)
                records.sort((a, b) =>
                    (b.Start_Date__c || '').localeCompare(a.Start_Date__c || '')
                );

                // 3️⃣ Re-map into sequential rows
                this.work.workExperience = { isSequential: false };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= 5) {
                        this.work.workExperience[seq] = rec;
                        if (
                            rec.IsCurrentJob__c === 'Yes' &&
                            !rec.End_Date__c
                        ) {
                            this.work.workExperience[seq].End_Date__c =
                                this.application.Application_End_Date__c ||
                                new Date().toISOString().split('T')[0];
                        }                        
                        this._recomputeExperienceMonths(seq);
                        seq++;
                    }
                });

                this.work.workExperienceVisibleRows =
                    Math.max(1, Math.min(records.length, 5));

                this._recomputeTotalIndustryExperience();
                // 4️⃣ Fill remaining rows
                while (seq <= 5) {
                    this.work.workExperience[seq] = { Id: null };
                    seq++;
                }

            }

            if (response && response.careerBreak) {
                this.work.careerBreak = { isSequential:false };

                // Convert object → array
                let records = Object.keys(response.careerBreak)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.careerBreak[k]);

                // Sort reverse chronological (latest break first)
                records.sort((a, b) =>
                    (b.StartDate__c || '').localeCompare(a.StartDate__c || '')
                );

                // Rebuild sequential UI structure
                this.work.careerBreak = { isSequential: false };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= 3) {
                        this.work.careerBreak[seq] = rec;
                        this._recomputeCareerBreakMonths(seq);
                        seq++;
                    }
                });

                this.work.careerBreakVisibleRows =
                        Math.max(1, Math.min(records.length, 3));

                this._reComputeTotalCareerBreak();


                // Fill remaining empty rows
                while (seq <= 3) {
                    this.work.careerBreak[seq] = { Id: null };
                    seq++;
                }


            }

            if (response && response.sabbatical) {
                this.work.sabbatical = { isSequential:false };

                // Convert object → array
                let records = Object.keys(response.sabbatical)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.sabbatical[k]);

                // Sort reverse chronological (latest break first)
                records.sort((a, b) =>
                    (b.StartDate__c || '').localeCompare(a.StartDate__c || '')
                );

                // Rebuild sequential UI structure
                this.work.sabbatical = { isSequential: false };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= 3) {
                        this.work.sabbatical[seq] = rec;
                        this._recomputeSabbaticalMonths(seq);
                        seq++;
                    }
                });

                this.work.sabbaticalVisibleRows =
                        Math.max(1, Math.min(records.length, 3));

                this._reComputeTotalSabbatical();


                // Fill remaining empty rows
                while (seq <= 3) {
                    this.work.sabbatical[seq] = { Id: null };
                    seq++;
                }


            }

        } catch (err) {
            console.warn('Fetch failed', err);
        }

        // 🔥 Final recalculation after both work + career break + sabbatical are loaded
        for (let i = 1; i <= 5; i++) {
            this._recomputeExperienceMonths(i);
        }

        this._recomputeTotalIndustryExperience();

        this._applyReadOnlyMode();
        this._updateActionState();
        this._buildRenderModelAll();
    }


    /* ------------------------------------------------------------
       VALIDATION
    ------------------------------------------------------------- */
    validateAll() {
        const meta = this.metadata.workExperience;
        const errors = {
            workExperience: {},
            careerBreak: {},
            sabbatical: {},
            totalExperienceSummary: {},
            haveCareerBreak: {},
            haveSabbatical: {}
        };

        for (let seq = 1; seq <= this.work.workExperienceVisibleRows; seq++) {
            const rec = this.work.workExperience[seq] || {};
            const prev = this.work.workExperience[seq - 1];

            // Required field validation

            meta.fields.forEach(f => {

                const visible =
                    this._computeFieldVisible(
                        f,
                        'workExperience',
                        seq
                    );

                if (!visible) {
                    return; // skip validation for hidden fields
                }

                const finalRequired = this._isFieldRequired(
                    'workExperience',
                    f.api,
                    seq,
                    f
                );
                
                if (finalRequired && !rec[f.api] && this.work.haveWorkExperience.HasWorkExperience__c === 'Yes') {
                    errors.workExperience[`${f.api}__${seq}`] =
                        `${f?.shortLabel || f.label} is required`;
                }

                if ((f.type === 'number' || f.type === 'currency') && rec[f.api]) {

                    const err = validateNumber(f, rec[f.api]);
                    if (err) {
                        errors.workExperience[`${f.api}__${seq}`] = err;
                    }
                }

                 if (f.type === 'text' || f.type === 'textarea') {
                    const textValue = String(rec[f.api] || '').trim();

                    const textErr =
                        validateTextConstraints(f, textValue);

                    if (textErr) {
                        errors.workExperience[`${f.api}__${seq}`] = textErr;
                    }

                }

            });

            const graduationPassingDate = this.work?.graduationDetails?.MonthAndYearOfPassing__c;

            // Work > Graduation validation
            if (
                graduationPassingDate&& 
                rec.Start_Date__c &&
                this._normalizeMonthYear(graduationPassingDate) >
                this._normalizeMonthYear(rec.Start_Date__c) 
                
            ) {
                errors.workExperience[`Start_Date__c__${seq}`] =
                    `Start Date should be greater than Graduation passed out Date ${graduationPassingDate}`;
                continue;
            }

            // Start > End validation
            if (
                rec.Start_Date__c &&
                rec.End_Date__c &&
                new Date(rec.Start_Date__c) >
                new Date(rec.End_Date__c)
            ) {
                errors.workExperience[`Start_Date__c__${seq}`] =
                    'Start Date cannot be greater than End Date';
                continue;
            }

            // Reverse chronology (latest → earliest)
            if (
                seq !== 1 &&
                rec.End_Date__c &&
                prev?.Start_Date__c &&
                new Date(rec.End_Date__c) >=
                new Date(prev.Start_Date__c)
            ) {
                errors.workExperience[`End_Date__c__${seq}`] =
                    'End date must be earlier than the previous work experience start date';
            }

        }

        const careerBreakMeta = this.metadata.careerBreak;

        for (let seq = 1; seq <= this.work.careerBreakVisibleRows; seq++) {
            const rec = this.work.careerBreak[seq] || {};
            const prev = this.work.careerBreak[seq - 1];

            // Required field validation

            careerBreakMeta.fields.forEach(f => {

                const finalRequired = this._isFieldRequired(
                    'careerBreak',
                    f.api,
                    seq,
                    f
                );

                if (
                    finalRequired &&
                    !rec[f.api] &&
                    this.work.haveCareerBreak?.HasCareerBreak__c === 'Yes'
                ) {
                    errors.careerBreak[`${f.api}__${seq}`] =
                        `${f?.shortLabel || f.label} is required`;
                }
            });

            // Start > End validation
            if (
                rec.StartDate__c &&
                rec.EndDate__c &&
                this._normalizeMonthYear(rec.StartDate__c) >
                this._normalizeMonthYear(rec.EndDate__c)
            ) {
                errors.careerBreak[`StartDate__c__${seq}`] =
                    'Start Date cannot be greater than End Date';
                continue;
            }

            // Reverse chronology (latest → earliest)
            if (
                seq !== 1 &&
                rec.EndDate__c &&
                prev?.StartDate__c &&
                this._normalizeMonthYear(rec.EndDate__c) >=
                this._normalizeMonthYear(prev.StartDate__c)
            ) {
                errors.careerBreak[`EndDate__c__${seq}`] =
                    'End date must be earlier than the previous career break start date';
            }
        }

        const cbReasonMeta =
            this.metadata.totalCareerBreakSummary.fields.find(
                f => f.api === 'CareerBreakReason__c'
            );

        if (
            this._computeFieldVisible(
                cbReasonMeta,
                'totalCareerBreakSummary'
            ) &&
            this._computeFieldRequired(
                cbReasonMeta,
                'totalCareerBreakSummary'
            ) &&
            !this.work.totalCareerBreakSummary?.CareerBreakReason__c
        ) {
            errors.totalCareerBreakSummary ||= {};

            errors.totalCareerBreakSummary.CareerBreakReason__c =
                'Reason for Career Break is required';
        }

        const cbReasonValue =
            this.work.totalCareerBreakSummary?.CareerBreakReason__c;

        const cbTextErr =
            validateTextConstraints(
                cbReasonMeta,
                cbReasonValue
            );

        if (cbTextErr) {
            errors.totalCareerBreakSummary ||= {};
            errors.totalCareerBreakSummary.CareerBreakReason__c =
                cbTextErr;
        }

        const sabbaticalMeta = this.metadata.sabbatical;

        for (let seq = 1; seq <= this.work.sabbaticalVisibleRows; seq++) {
            const rec = this.work.sabbatical[seq] || {};
            const prev = this.work.sabbatical[seq - 1];

            // Required field validation

            sabbaticalMeta.fields.forEach(f => {

                const finalRequired = this._isFieldRequired(
                    'sabbatical',
                    f.api,
                    seq,
                    f
                );
                
                if (
                    finalRequired &&
                    !rec[f.api] &&
                    this.work.haveSabbatical?.HasSabbatical__c === 'Yes'
                ) {
                    errors.sabbatical[`${f.api}__${seq}`] =
                        `${f?.shortLabel || f.label} is required`;
                }
            });

            // Start > End validation
            if (
                rec.StartDate__c &&
                rec.EndDate__c &&
                this._normalizeMonthYear(rec.StartDate__c) >
                this._normalizeMonthYear(rec.EndDate__c)
            ) {
                errors.sabbatical[`StartDate__c__${seq}`] =
                    'Start Date cannot be greater than End Date';
                continue;
            }

            // Reverse chronology (latest → earliest)
            if (
                seq !== 1 &&
                rec.EndDate__c &&
                prev?.StartDate__c &&
                this._normalizeMonthYear(rec.EndDate__c) >=
                this._normalizeMonthYear(prev.StartDate__c)
            ) {
                errors.sabbatical[`EndDate__c__${seq}`] =
                    'End date must be earlier than the previous sabbatical start date';
            }
        }

        const sabReasonMeta =
            this.metadata.totalSabbaticalSummary.fields.find(
                f => f.api === 'SabbaticalReason__c'
            );

        if (
            this._computeFieldVisible(
                sabReasonMeta,
                'totalSabbaticalSummary'
            ) &&
            this._computeFieldRequired(
                sabReasonMeta,
                'totalSabbaticalSummary'
            ) &&
            !this.work.totalSabbaticalSummary?.SabbaticalReason__c
        ) {
            errors.totalSabbaticalSummary ||= {};

            errors.totalSabbaticalSummary.SabbaticalReason__c =
                'Reason of sabbatical is required';
        }

        const sabReasonValue =
            this.work.totalSabbaticalSummary?.SabbaticalReason__c;

        const sabTextErr =
            validateTextConstraints(
                sabReasonMeta,
                sabReasonValue
            );

        if (sabTextErr) {
            errors.totalSabbaticalSummary ||= {};
            errors.totalSabbaticalSummary.SabbaticalReason__c =
                sabTextErr;
        }

        // 🔥 Career break cannot be before earliest work start date
        let earliestWorkStart = null;

        for (let i = 5; i >= 1; i--) {
            const w = this.work.workExperience[i];
            if (w?.Start_Date__c) {
                earliestWorkStart = this._normalizeMonthYear(w.Start_Date__c);
                break;
            }
        }

        if (earliestWorkStart) {
            for (let seq = 1; seq <= this.work.careerBreakVisibleRows; seq++) {
                const br = this.work.careerBreak[seq];
                if (!br?.StartDate__c) continue;

                const breakStart = this._normalizeMonthYear(br.StartDate__c);

                if (breakStart < earliestWorkStart) {
                    errors.careerBreak[`StartDate__c__${seq}`] =
                        'Career break cannot be before your first work experience start date';
                }
            }

            for (let seq = 1; seq <= this.work.sabbaticalVisibleRows; seq++) {
                const br = this.work.sabbatical[seq];
                if (!br?.StartDate__c) continue;

                const breakStart = this._normalizeMonthYear(br.StartDate__c);

                if (breakStart < earliestWorkStart) {
                    errors.sabbatical[`StartDate__c__${seq}`] =
                        'Sabbatical cannot be before your first work experience start date';
                }
            }
        }

        const priorWorkMeta =
            this.metadata.totalExperienceSummary.fields.find(
                f => f.api === 'PriorWorkResponsibilities__c'
            );

        const priorWorkValue =
            this.work.totalExperienceSummary
                ?.PriorWorkResponsibilities__c;

        if (
            this.work.workExperienceVisibleRows > 1 &&
            this._computeFieldRequired(
                priorWorkMeta,
                'totalExperienceSummary'
            ) &&
            !String(priorWorkValue || '').trim()
        ) {
            errors.totalExperienceSummary ||= {};

            errors.totalExperienceSummary
                .PriorWorkResponsibilities__c =
                    `${priorWorkMeta.shortLabel || priorWorkMeta.label} is required`;
        }
        else {

            const priorWorkErr =
                validateTextConstraints(
                    priorWorkMeta,
                    priorWorkValue
                );

            if (priorWorkErr) {

                errors.totalExperienceSummary ||= {};

                errors.totalExperienceSummary
                    .PriorWorkResponsibilities__c =
                        priorWorkErr;
            }
        }

        const hasCareerBreakMeta =
            this.metadata.haveCareerBreak.fields.find(
                f => f.api === 'HasCareerBreak__c'
            );

        if (
            this.work.haveWorkExperience?.HasWorkExperience__c === 'Yes' &&
            this._computeFieldRequired(
                hasCareerBreakMeta,
                'haveCareerBreak'
            ) &&
            !this.work.haveCareerBreak?.HasCareerBreak__c
        ) {
            errors.haveCareerBreak.HasCareerBreak__c =
                'Choose an option';
        }

        const hasSabbaticalMeta =
            this.metadata.haveSabbatical.fields.find(
                f => f.api === 'HasSabbatical__c'
            );

        if (
            this.work.haveWorkExperience?.HasWorkExperience__c === 'Yes' &&
            this._computeFieldRequired(
                hasSabbaticalMeta,
                'haveSabbatical'
            ) &&
            !this.work.haveSabbatical?.HasSabbatical__c
        ) {
            errors.haveSabbatical.HasSabbatical__c =
                'Choose an option';
        }

        const cmp = this.template.querySelector('c-af-section-engine');
        if (cmp && typeof cmp.applyErrors === 'function') {
            cmp.applyErrors(errors);
        }

        const hasErrors =
            Object.keys(errors.workExperience).length > 0 ||
            Object.keys(errors.careerBreak).length > 0 ||
            Object.keys(errors.sabbatical).length > 0 ||
            Object.keys(errors.haveCareerBreak).length > 0 ||
            Object.keys(errors.haveSabbatical).length > 0 ||
            Object.keys(errors.totalExperienceSummary || {}).length > 0 ||
            Object.keys(errors.totalCareerBreakSummary || {}).length > 0 ||
            Object.keys(errors.totalSabbaticalSummary || {}).length > 0;

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

        if(this.work?.haveCareerBreak?.HasCareerBreak__c === 'No'){
            this.work.totalCareerBreakSummary.TotalCareerBreak__c = 0;
            this.work.totalCareerBreakSummary.CareerBreakReason__c = '';
        }

        if(this.work?.haveSabbatical?.HasSabbatical__c === 'No'){
            this.work.totalSabbaticalSummary.TotalSabbatical__c = 0;
            this.work.totalSabbaticalSummary.SabbaticalReason__c = '';
        }

        this.isLoading = true;
        if (!this.validateAll()) {
            this.isLoading = false;
            return false;
        }

        const totalIndustryExperience =
            this.work?.totalExperienceSummary?.TotalIndustryExperience__c || 0;

        if (totalIndustryExperience < 36) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Warning',
                    message:
                        'Your total industry experience is less than 36 months. PGPM typically expects candidates with 36 months or more of work experience.',
                    variant: 'warning',
                    mode: 'sticky'
                })
            );
        }

        try {
            await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify({
                    application: {
                        sobject: "Application__c",
                        fields: {
                            Id: this.application.Id,
                            TotalIndustryExperience__c: 
                                this.work?.totalExperienceSummary?.TotalIndustryExperience__c || 0,
                            HasWorkExperience__c: 
                                this.work?.haveWorkExperience?.HasWorkExperience__c || '' ,
                            HasCareerBreak__c: 
                                this.work?.haveCareerBreak?.HasCareerBreak__c || '' ,
                            TotalCareerBreak__c: 
                                this.work?.totalCareerBreakSummary?.TotalCareerBreak__c || 0,
                            CareerBreakReason__c: 
                                this.work?.totalCareerBreakSummary?.CareerBreakReason__c || '',
                            HasSabbatical__c: 
                                this.work?.haveSabbatical?.HasSabbatical__c || '' ,
                            TotalSabbatical__c: 
                                this.work?.totalSabbaticalSummary?.TotalSabbatical__c || 0,
                            SabbaticalReason__c: 
                                this.work?.totalSabbaticalSummary?.SabbaticalReason__c || '',
                            ApplyingUnderRestartInitiative__c:
                                this.work?.haveCareerBreak?.ApplyingUnderRestartInitiative__c ?? false,
                            TakingSabbatical__c:
                                this.work?.haveSabbatical?.TakingSabbatical__c ?? '',
                            PriorWorkResponsibilities__c:
                                this.work?.totalExperienceSummary?.PriorWorkResponsibilities__c || '',
                        }
                    }
                })
            });

            const childPayload = {};
            const c = context.children[0];

            let rows = [];
            let deleted = this.work.workExperienceDeleted || [];

            for (let seq = 1; seq <= 5; seq++) {

                    const row = this.work.workExperience[seq];

                    if (!row) {
                        continue;
                    }

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
                    const fieldMeta = this.metadata.workExperience.fields.find(f => f.api === api);

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

                const hasData = Object.keys(cleanRow).length > 1;

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

            console.log('child PayLoad rows '+JSON.stringify(rows, '', 2));

            childPayload[c.logicalName] = {
                sobject: c.sobject,
                parentLookupField: c.parentLookupField,
                rows,
                deletedIds: deleted
            };

            //career break
            const careerBreakContext = context.children[1];

            let cbRows = [];
            let cbDeleted = this.work.careerBreakDeleted || [];

            for (let seq = 1; seq <= 3; seq++) {
                const row = this.work.careerBreak[seq];
                const hasId = !!row.Id;

                // If record is already scheduled for deletion, skip it
                if (hasId && cbDeleted.includes(row.Id)) {
                    continue;
                }

                // const hasData = Object.keys(row).some(k =>
                //     k !== 'Id' && row[k] !== null && row[k] !== ''
                // );

                // 1) Normalize row values based on metadata
                Object.keys(row).forEach(api => {
                    const fieldMeta = this.metadata.careerBreak.fields.find(f => f.api === api);

                    if (fieldMeta?.type === 'monthyear') {
                        row[api] = this._normalizeMonthYear(row[api]);
                    }

                    if (fieldMeta?.type === 'number') {
                        const n = Number(row[api]);
                        row[api] = isNaN(n) ? null : n;
                    }
                    
                });

                // 2) Build clean row based on fieldsToQuery
                const allowed = new Set(careerBreakContext.fieldsToQuery);
                let cleanRow = {};

                Object.keys(row).forEach(api => {

                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                const hasData = Object.keys(cleanRow)
                    .filter(k => k !== 'Id')
                    .some(k =>
                        cleanRow[k] !== null &&
                        cleanRow[k] !== ''
                    );

                (careerBreakContext.filters || []).forEach(f => {
                    cleanRow[f.field] = f.value;
                });

                if (!hasId && !hasData) continue;     // ignore
                if (!hasId && hasData) {               
                    let row = {
                        sobject: careerBreakContext.sobject,
                        parentLookupField: careerBreakContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    };
                    cbRows.push(row);
                    continue;
                }
                if (hasId && !hasData) {
                    cbDeleted.push(row.Id);
                    continue;
                }
                if (hasId && hasData) {
                    cbRows.push({
                        sobject: careerBreakContext.sobject,
                        parentLookupField: careerBreakContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: row.Id
                    });
                }
            }

            childPayload[careerBreakContext.logicalName] = {
                sobject: careerBreakContext.sobject,
                parentLookupField: careerBreakContext.parentLookupField,
                rows: cbRows,
                deletedIds: cbDeleted
            };

            //sabbatical
            const sabbaticalContext = context.children[2];

            let sabRows = [];
            let sabDeleted = this.work.sabbaticalDeleted || [];

            for (let seq = 1; seq <= 3; seq++) {
                const row = this.work.sabbatical[seq];
                const hasId = !!row.Id;

                // If record is already scheduled for deletion, skip it
                if (hasId && sabDeleted.includes(row.Id)) {
                    continue;
                }

                // const hasData = Object.keys(row).some(k =>
                //     k !== 'Id' && row[k] !== null && row[k] !== ''
                // );

                // 1) Normalize row values based on metadata
                Object.keys(row).forEach(api => {
                    const fieldMeta = this.metadata.sabbatical.fields.find(f => f.api === api);

                    if (fieldMeta?.type === 'monthyear') {
                        row[api] = this._normalizeMonthYear(row[api]);
                    }

                    if (fieldMeta?.type === 'number') {
                        const n = Number(row[api]);
                        row[api] = isNaN(n) ? null : n;
                    }
                    
                });

                // 2) Build clean row based on fieldsToQuery
                const allowed = new Set(sabbaticalContext.fieldsToQuery);
                let cleanRow = {};

                Object.keys(row).forEach(api => {

                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                const hasData = Object.keys(cleanRow)
                    .filter(k => k !== 'Id')
                    .some(k =>
                        cleanRow[k] !== null &&
                        cleanRow[k] !== ''
                    );

                (sabbaticalContext.filters || []).forEach(f => {
                    cleanRow[f.field] = f.value;
                });

                if (!hasId && !hasData) continue;     // ignore
                if (!hasId && hasData) {               
                    let row = {
                        sobject: sabbaticalContext.sobject,
                        parentLookupField: sabbaticalContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    };
                    sabRows.push(row);
                    continue;
                }
                if (hasId && !hasData) {
                    sabDeleted.push(row.Id);
                    continue;
                }
                if (hasId && hasData) {
                    sabRows.push({
                        sobject: sabbaticalContext.sobject,
                        parentLookupField: sabbaticalContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: row.Id
                    });
                }
            }

            childPayload[sabbaticalContext.logicalName] = {
                sobject: sabbaticalContext.sobject,
                parentLookupField: sabbaticalContext.parentLookupField,
                rows: sabRows,
                deletedIds: sabDeleted
            };

            await saveChildren({
                payloadJson: JSON.stringify(childPayload)
            });

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Work Experience' 
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