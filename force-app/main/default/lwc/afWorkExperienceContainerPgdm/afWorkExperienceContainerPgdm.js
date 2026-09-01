import { LightningElement, track, api } from 'lwc';
import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveChildren from '@salesforce/apex/ApFormDataController.saveChildren';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { buildErrorSummary } from "c/applicationFormService";
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import getRecordTypesByName from '@salesforce/apex/AcademicFormController.getRecordTypesByName';

import { validateNumber, validateTextConstraints } from "c/applicationFormService";

import { context as context } from './context';

export default class AfWorkExperienceContainerPgdm extends LightningElement {

    static MULTI_ROW_LIMITS = {
        workExperience: 2,
        achievements: 3,
        versatility: 5
    };

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

    recordTypeIds = {};

    async _loadRecordTypes() {
        const res = await getRecordTypesByName({
            objectApiName: 'Application__c',
            recordTypeNames: ['PGDM']
        });

        this.recordTypeIds = res.nameToId || {};
    }

    @track work = {
        haveWorkExperience : {},
        workExperience: { isSequential: false },
        totalExperienceSummary : {},
        graduationDetails: {},
        workExperienceVisibleRows: 1,
        workExperienceActions: {},
        workExperienceDeleted: [],

        achievements: { isSequential: false },
        achievementsVisibleRows: 1,
        achievementsActions: {},
        achievementsDeleted: [],

        versatility: { isSequential: false },
        versatilityVisibleRows: 1,
        versatilityActions: {},
        versatilityDeleted: [],

        responsibilitiesShouldered: {},
        informationSource: {},
    };

    _getRequiredFields(sectionKey) {
        return (
            AfWorkExperienceContainerPgdm
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
                'Gross_Annual_CTC__c',
                'Responsibilities__c',
                'Employment_Type__c',
                'Industry__c',
                'Function__c',
            ]
        },

        achievements: {
            requiredFields: [
                'Title_of_the_Award__c',
                'Institute_Granting_the_Award__c',
                'Year__c'
            ]
        },

        versatility: {
            requiredFields: [
                'Title_of_the_Award__c',
                'Institute_Granting_the_Award__c',
                'Year__c'
            ]
        },
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
            const data = await getAllPicklistsForObjects({ objectApiNames: ['Work_Experience__c', 'Academic_Achievements__c', 'Versatility__c', 'Application__c'] })
            
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
            await this._loadRecordTypes();
            this._injectPicklists();
            this._updateActionState();
            this._buildRenderModelAll();

            await this.fetchForm();
        } catch (err) {
            console.warn('Picklist fetch failed', err);
            await this._loadRecordTypes();
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
            x => x.context === 'Program.PGDM'
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
            title: "Instructions",
            type: 'note',
            text: `
<div style="background:#f3f3f3; padding:16px; border-radius:4px;">

    <div>
        <p><b>Instructions</b></p>
        <ul style="list-style-type: disc; list-style-position: outside; display:inline-block; text-align:left; margin-top:8px; padding-left:30px;">
            <li>Work experience is not mandatory for this programme, graduates with no work experience and those with less than five years of work experience can apply.</li>
            <li>Relevant work experience after graduation will be considered. Internship/training/ project work where a part of the curriculum will not be considered as work experience or any period of apprenticeship such as articleship required as part of certain professional courses, or any unpaid work undertaken in any organization or institution will also not be considered as work-experience.</li>
            <li>Proof of work experience such as offer letter, salary slips and the experience letter will have to be provided.</li>
        </ul>
    </div>

</div>
            `
        };

        this.metadata.workExperience = {
            key: 'workExperience',
            title: 'Work Experience Details',
            columnSystem: 10,
            layout: 'fluid',
            note: {
                api: 'WORK_EXPERIENCE_SECTION_NOTE',
                type: 'note',
                text: `
                    <div style="font-size:14px; line-height:1.5; margin-bottom:10px;">
                        <ul style="list-style-type: circle; padding-left:30px;">
                            <li>If your company is not available in the <b>Name of Organization</b> dropdown, please select <b>Other</b> and enter your company name manually.</li>
                            <li>Please enter your <b>Gross Annual Salary</b> in rupees. For example, if your annual CTC is 7.1 lakhs, enter <b>710000</b>.</li>
                            <li>Total work experience includes work experience with your current employer up to November 2026.</li>
                        </ul> 
                    </div>
                `
            },
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
                { api:'Designation__c', span: 2, type:'text', label:'Designation', maxlength: '255' },
                { api:'Gross_Annual_CTC__c', span: 2, type:'currency', label:'Gross Annual Salary in Rupees', step:0.01, max: '999999999' },
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
                { api:'Responsibilities__c', span: 3, type:'textarea', label:'Describe your role briefly', shortLabel: "Role description", maxlength: '2500', maxWords: 100, showCounter: true, helpText:"Max. 100 words", }
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
                        { width: 3, fields: ['AdditionalWorkExperienceInMonths__c'] },
                        { width: 3, fields: ['TotalIndustryExperience__c'] }
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
                    api: 'AdditionalWorkExperienceInMonths__c',
                    type: 'number',
                    label: 'Months of work experience beyond above (if any)',
                    min: 0,
                    max: 60,
                    step: 1
                }
            ]
        };

        this.metadata.achievementsBlock = {
            key: 'achievementsBlock',
            title: "Achievements",
            type: 'note',
            text: `
<div style="background:#f3f3f3; padding:16px; border-radius:4px;">
    <div>
        <p><b>Achievements</b></p>
        In the event you are shortlisted, it is mandatory to upload a valid certificate or document as proof for any achievement entered in the “Achievements” section. Please note that trophies or photos of medals will not be accepted as valid proof.
    </div>
</div>
            `
        };

        this.metadata.achievements = {
            key: 'achievements',
            title: 'Academic Achievements',
            columnSystem: 10,
            layout: 'fluid',
            note: {
                api: 'ACHIEVEMENTS_SECTION_NOTE',
                type: 'note',
                text: `
                    <div>
                        If any academic achievements, please furnish details here. You can enter a maximum of 3 achievements.
                    </div>
                `
            },
            fields: [
                {
                    api: 'Title_of_the_Award__c',
                    span: 2,
                    type: 'text',
                    label: 'Title of the Award',
                    maxlength: '60'
                },
                {
                    api: 'Institute_Granting_the_Award__c',
                    span: 2,
                    type: 'text',
                    label: 'Institute Granting the Award',
                    maxlength: '200'
                },
                {
                    api: 'Year__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Year'
                },
                {
                    api: 'Award_Position__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Award / Position'
                },
                {
                    api: 'Level__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Level'
                },
                {
                    api: 'Describe_the_Award_Max_25_words__c',
                    span: 3,
                    type: 'textarea',
                    label: 'Describe the Award (Max. 25 words)',
                    maxlength: '2000',
                    maxWords: 25,
                    showCounter: true
                }
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
                        { width: 8, fields: [] },
                        { width: 2, fields: ['AddMore'] },
                        { width: 2, fields: ['Remove'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'AddMore',
                    type: 'button',
                    label: '➕ Add More',
                    action: 'addMoreAchievement',
                    disableWhen: {
                        'achievementsActions.fullCapacity': true
                    },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeAchievement',
                    disableWhen: {
                        'achievementsActions.noneToRemove': true
                    },
                    variant: 'brand'
                }
            ]
        };

        this.metadata.versatility = {
            key: 'versatility',
            title: 'Versatility',
            columnSystem: 10,
            layout: 'fluid',
            note: {
                api: 'VERSATILITY_SECTION_NOTE',
                type: 'note',
                text: `
                    <div>
                        Mention significant interest in diverse areas such as sports, creative writing, painting, dancing, social service, etc. Include a maximum of 5 activities.
                    </div>
                `
            },
            fields: [
                {
                    api: 'Name_of_the_Activity__c',
                    span: 2,
                    type: 'text',
                    label: 'Name of the Activity',
                    maxlength: '60'
                },
                {
                    api: 'Interest__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Interest',
                },
                {
                    api: 'Proficiency__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Proficiency'
                },
                {
                    api: 'Award__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Award'
                },
                {
                    api: 'Level__c',
                    span: 2,
                    type: 'picklist',
                    label: 'Level'
                },
                {
                    api: 'Description__c',
                    span: 3,
                    type: 'textarea',
                    label: 'Description',
                    maxlength: '2000',
                    maxWords: 25,
                    showCounter: true
                }
            ]
        };

        this.metadata.versatilityActions = {
            key: 'versatilityActions',
            title: 'Versatility Actions',
            columnSystem: 12,
            hideTitle: true,
            rows: [
                {
                    columns: [
                        { width: 8, fields: [] },
                        { width: 2, fields: ['AddMore'] },
                        { width: 2, fields: ['Remove'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'AddMore',
                    type: 'button',
                    label: '➕ Add More',
                    action: 'addMoreVersatility',
                    disableWhen: {
                        'versatilityActions.fullCapacity': true
                    },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeVersatility',
                    disableWhen: {
                        'versatilityActions.noneToRemove': true
                    },
                    variant: 'brand'
                }
            ]
        };

        this.metadata.overallVersatilityRating = {
            key: 'overallVersatilityRating',
            title: 'Overall Versatility Rating',
            columnSystem: 12,
            hideTitle: true,
            rows: [
                {
                    columns: [
                        {
                            width: 3,
                            fields: ['OverallVersatilityRating__c']
                        }
                    ]
                }
            ],
            fields: [
                {
                    api: 'OverallVersatilityRating__c',
                    type: 'picklist',
                    label: 'Overall Versatility Rating',
                    required: true
                }
            ]
        };

        this.metadata.responsibilitiesShouldered = {
            key: 'responsibilitiesShouldered',
            title: 'Responsibilities Shouldered',
            columnSystem: 12,
            note: {
                api: 'RESPONSIBILITIES_SECTION_NOTE',
                type: 'note',
                text: `
                    <div>
                        Briefly describe situations where you have had the opportunity to take on responsibility in a personal context.
                    </div>
                `
            },
            rows: [
                {
                    columns: [
                        { width: 6, fields: ['PersonalResponsibilityTitle__c'] },  { width: 6, fields: ['ProfessionalResponsibilityTitle__c'] },

                    ]
                },
                {
                    columns: [
                        { width: 6, fields: ['PersonalResponsibilityLevel__c'] }, { width: 6, fields: ['ProfessionalResponsibilityLevel__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 6, fields: ['PersonalResponsibilityDescription__c'] }, { width: 6, fields: ['ProfessionalResponsibilityDescription__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: "PersonalResponsibilityTitle__c",
                    type: 'richtext',
                    value: `
                    <p><u>Personal</u></p>
                    `,
                },
                {
                    api: "ProfessionalResponsibilityTitle__c",
                    type: 'richtext',
                    value: `
                    <p><u>Professional</u></p>
                    `,
                },
                { api:'PersonalResponsibilityLevel__c', span: 2, type:'picklist', label:'Level' },
                {
                    api:'PersonalResponsibilityDescription__c',
                    type:'textarea',
                    label:'Describe Briefly',
                    maxlength:'2500',
                    maxWords: 50,
                    showCounter: true,
                    helpText:"Max. 50 words",
                },
                { api:'ProfessionalResponsibilityLevel__c', span: 2, type:'picklist', label:'Level' },
                {
                    api:'ProfessionalResponsibilityDescription__c',
                    type:'textarea',
                    label:'Describe Briefly',
                    maxlength:'2500',
                    maxWords: 50,
                    showCounter: true,
                    helpText:"Max. 50 words",
                }
            ]
        };

        this.metadata.informationSource = {
            key: 'informationSource',
            title: 'Information Source',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 12, fields: ['ReferralSourceMulti__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['OtherReferralSource__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['InterestedInOtherProgram__c'] }
                    ]
                },
                {
                    columns: [
                        { width: 12, fields: ['OtherProgramsInterestedIn__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'ReferralSourceMulti__c',
                    span: 4,
                    type: 'multipicklist',
                    label: 'How did you get to know about the Institute?',
                    options: []
                },
                {
                    api: 'OtherReferralSource__c',
                    type: 'text',
                    label: 'Enter Other Information Source',
                    span: 2,
                    requiredWhen: {
                        'otherResources.showOtherInformationSource': true
                    },
                    visibleWhen: {
                        'otherResources.showOtherInformationSource': true
                    },
                    maxlength: '60',
                },
                {
                    api: 'InterestedInOtherProgram__c',
                    type: 'picklist',
                    label: 'Are you interested in knowing about other SPJIMR programmes?',
                    shortLabel: 'Intrest in other programmes',
                    required: true,
                },
                {
                    api: 'OtherProgramsInterestedIn__c',
                    label: 'Which programme?',
                    type: 'multipicklist',
                    requiredWhen: {
                        'informationSource.InterestedInOtherProgram__c': 'Yes'
                    },
                    visibleWhen: {
                        'informationSource.InterestedInOtherProgram__c': 'Yes'
                    }
                }
            ]
        };
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

    _injectPicklists() {

        const pick = this.picklistCache || {};

        const toOptions = arr =>
            (arr || []).map(x => ({
                label: x.label,
                value: x.value
            }));

        const resolveOptions = (api, rt) => {

            const custom =
                this.resolveCustomDropdown(api);

            if (custom?.options?.length) {
                return custom.options.map(o => ({
                    label: o.label,
                    value: o.value
                }));
            }

            if (
                rt &&
                pick.recordTypeSet &&
                pick.recordTypeSet[rt] &&
                pick.recordTypeSet[rt][api]
            ) {
                return toOptions(
                    pick.recordTypeSet[rt][api].options
                );
            }


            if (pick.defaultSet &&
                pick.defaultSet[api]) {

                return toOptions(
                    pick.defaultSet[api].options
                );
            }

            return [];
        };

        const optionalPicklists = {
            achievements: [
                'Award_Position__c',
                'Level__c'
            ],
            versatility: [
                'Interest__c',
                'Proficiency__c',
                'Award__c',
                'Level__c'
            ],
            responsibilitiesShouldered: [
                'PersonalResponsibilityLevel__c',
                'ProfessionalResponsibilityLevel__c'
            ]
        };

        const merge = (sectionKey) => {
            const sec = this.metadata[sectionKey];

            if (!sec || !sec.fields) return;

            const optionalFields = optionalPicklists[sectionKey] || [];

            sec.fields.forEach(f => {

                const recordTypeId =
                f.api === 'OtherProgramsInterestedIn__c'
                    ? this.recordTypeIds.PGDM
                    : undefined;

                let options = resolveOptions(f.api, recordTypeId);

                if (
                    optionalFields.includes(f.api) &&
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

        merge('workExperience');
        merge('achievements');
        merge('versatility');
        merge('overallVersatilityRating');
        merge('responsibilitiesShouldered');
        merge('informationSource');
    }


    /* ------------------------------------------------------------
       Initialize empty rows
    ------------------------------------------------------------- */
    _initializeRows() {

        const limits = AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS;

        this.work.workExperience = { isSequential: false };
        for (let i = 1; i <= limits.workExperience; i++) {
            this.work.workExperience[i] = { Id: null };
        }
        this.work.workExperienceVisibleRows = 1;

        this.work.achievements = { isSequential: false };
        for (let i = 1; i <= limits.achievements; i++) {
            this.work.achievements[i] = { Id: null };
        }
        this.work.achievementsVisibleRows = 1;

        this.work.versatility = { isSequential: false };
        for (let i = 1; i <= limits.versatility; i++) {
            this.work.versatility[i] = { Id: null };
        }
        this.work.versatilityVisibleRows = 1;
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

            section.rows = [];
            // Section-level note before the sequential rows
            if (meta.note) {
                section.rows.push({
                    key: `${sectionKey}-note-row`,
                    style: 'margin-bottom: 10px;',
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

            section.rows.push(
                ...this._buildSequentialFluidRows(
                    sectionKey,
                    meta,
                    secData
                )
            );

            return section;

        }

        // SPECIAL: single-row sections (radio, totals)
        if (['haveWorkExperience', 'totalExperienceSummary', 'workExperienceActions', 'achievementsActions', 'versatilityActions', 'overallVersatilityRating', 'responsibilitiesShouldered', 'informationSource'].includes(sectionKey)) {

            if (meta.note) {
                section.rows.push({
                    key: `${sectionKey}-note-row`,
                    style: 'margin-bottom: 10px;',
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

                        const fieldMeta = this._resolveFieldMeta(
                            sectionKey,
                            {
                                ...baseMeta,
                                sectionKey
                            }
                        );

                        delete fieldMeta.visibleWhen;
                        delete fieldMeta.requiredWhen;

                        if (fieldMeta.visible === false) {
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

            if (sectionKey === 'workExperience' || sectionKey === 'achievements' || sectionKey === 'versatility') {
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

                        if (sectionKey === 'workExperience' || sectionKey === 'achievements' || sectionKey === 'versatility') {
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

        if (sectionKey === 'achievements') {
            return Array.from(
                { length: this.work.achievementsVisibleRows || 1 },
                (_, i) => i + 1
            );
        }

        if (sectionKey === 'versatility') {
            return Array.from(
                { length: this.work.versatilityVisibleRows || 1 },
                (_, i) => i + 1
            );
        }

        return result.length ? result : [1];
    }

    _getValueForField(sectionKey, api, sequence) {
        // work experience (non-sequential numeric keys)
        if (
            sectionKey === 'workExperience' ||
            sectionKey === 'achievements' ||
            sectionKey === 'versatility'
        ) {
            if (!sequence) return null;

            return this.work?.[sectionKey]?.[sequence]?.[api] ?? null;
        }
    }

    _resolveFieldMeta(sectionKey, fieldMeta) {
        const resolved = { ...fieldMeta };
        const isSequential = this._isSequentialSection(sectionKey);

        resolved.visible = this._computeFieldVisible(
            resolved,
            sectionKey,
            resolved.sequence
        );

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

        const getter = this[metaForRender.dynamicFilter];

        if (getter === undefined) return;

        metaForRender.filter =
            typeof getter === 'function'
                ? getter.call(this)
                : getter;
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

        // 2. Work experience rows (only if Yes)
        if (hasWork) {
            list.push(this._buildSectionRenderModel('workExperience'));

            if (!this.isReadOnly) {
                list.push(this._buildSectionRenderModel('workExperienceActions'));
            }

            // 3. Total experience summary
            list.push(this._buildSectionRenderModel('totalExperienceSummary'));
            
        }

        list.push(this._buildSectionRenderModel('achievementsBlock'));

        // Achievements
        list.push(
            this._buildSectionRenderModel('achievements')
        );

        if (!this.isReadOnly) {
            list.push(
                this._buildSectionRenderModel(
                    'achievementsActions'
                )
            );
        }

        // Versatility
        list.push(
            this._buildSectionRenderModel('versatility')
        );

        if (!this.isReadOnly) {
            list.push(
                this._buildSectionRenderModel(
                    'versatilityActions'
                )
            );
        }

        list.push(
            this._buildSectionRenderModel('overallVersatilityRating')
        );

        // Responsibilities
        list.push(this._buildSectionRenderModel('responsibilitiesShouldered'));
        list.push(this._buildSectionRenderModel('informationSource'));
        
        this.sectionModel = list;        
    }

    _recomputeTotalIndustryExperience() {
        let total = 0;

        for (
            let seq = 1;
            seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience;
            seq++
        ) {
            const rec = this.work.workExperience[seq];
            if (!rec) continue;

            const m = Number(rec.Experience_In_Months__c || 0);

            if (!isNaN(m)) {
                total += m;
            }
        }

        const additional =
            Number(
                this.work.totalExperienceSummary
                    ?.AdditionalWorkExperienceInMonths__c || 0
            );

        if (!isNaN(additional)) {
            total += additional;
        }

        if (!this.work.totalExperienceSummary) {
            this.work.totalExperienceSummary = {};
        }

        this.work.totalExperienceSummary.TotalIndustryExperience__c = total;
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
            fullCapacity: visibleRows >= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience,
            noneToRemove: visibleRows <= 1
        };

        this._recomputeTotalIndustryExperience();

        const achievementRows =
            this.work.achievementsVisibleRows || 1;

        this.work.achievementsActions = {
            fullCapacity: achievementRows >= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.achievements,
            noneToRemove: achievementRows <= 1
        };

        const versatilityRows =
            this.work.versatilityVisibleRows || 1;

        this.work.versatilityActions = {
            fullCapacity: versatilityRows >= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.versatility,
            noneToRemove: versatilityRows <= 1
        };

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
                for (let i = 1; i <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience; i++) {
                    const rec = this.work.workExperience[i];
                    if (rec && rec.Id) {
                        deleteList.push(rec.Id);
                    }
                }
                
                // 2️⃣ Save this list in container state
                this.work.workExperienceDeleted = deleteList;

                // 3️⃣ Clear all rows
                this.work.workExperience = { isSequential: false };
                for (let i = 1; i <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience; i++) {
                    this.work.workExperience[i] = { Id: null };
                }

                this.work.workExperienceVisibleRows = 1;

                // 4️⃣ Reset total experience
                this.work.totalExperienceSummary = {
                    TotalIndustryExperience__c: 0,
                    AdditionalWorkExperienceInMonths__c: 0
                };

                this._updateActionState();
            
            }

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'totalExperienceSummary') {
            this.work.totalExperienceSummary[api] = value;

            if (api === 'AdditionalWorkExperienceInMonths__c') {
                this._recomputeTotalIndustryExperience();
            }

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

        if (sectionKey === 'achievements') {

            this.work.achievements[sequence] =
                this.work.achievements[sequence] || {};

            this.work.achievements[sequence][api] =
                value;

            this.work.achievements[sequence].Display ||= {};

            this.work.achievements[sequence].Display[api] =
                displayValue;

            this._updateActionState();
            this._buildRenderModelAll();

            return;
        }

        if (sectionKey === 'versatility') {

            this.work.versatility[sequence] =
                this.work.versatility[sequence] || {};

            this.work.versatility[sequence][api] =
                value;

            this.work.versatility[sequence].Display ||= {};

            this.work.versatility[sequence].Display[api] =
                displayValue;

            this._updateActionState();
            this._buildRenderModelAll();

            return;
        }

        if (sectionKey === 'overallVersatilityRating') {
            this.work.overallVersatilityRating =
                this.work.overallVersatilityRating || {};

            this.work.overallVersatilityRating[api] = value;

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'responsibilitiesShouldered') {

            this.work.responsibilitiesShouldered =
                this.work.responsibilitiesShouldered || {};

            this.work.responsibilitiesShouldered[api] = value;

            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'informationSource') {

            this.work.informationSource =
                this.work.informationSource || {};

            this.work.informationSource[api] = value;

            if (api === 'ReferralSourceMulti__c') {
                const selectedValues = Array.isArray(value)
                    ? value
                    : String(value || '')
                        .split(';')
                        .map(v => v.trim())
                        .filter(Boolean);

                if (!selectedValues.includes('Other')) {
                    this.work.informationSource.OtherReferralSource__c = '';
                }
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

            case 'addMoreAchievement':
                this._addAchievementRow();
                break;

            case 'removeAchievement':
                this._removeAchievementRow();
                break;

            case 'addMoreVersatility':
                this._addVersatilityRow();
                break;

            case 'removeVersatility':
                this._removeVersatilityRow();
                break;
        }

        this._updateActionState();
        this._buildRenderModelAll();
    }

    _addWorkExperienceRow() {

        if (this.work.workExperienceVisibleRows < AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience) {
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

    }

    _addAchievementRow() {
        if (this.work.achievementsVisibleRows < AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.achievements) {
            this.work.achievementsVisibleRows++;
        }
    }

    _removeAchievementRow() {

        const visible =
            this.work.achievementsVisibleRows;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.work.achievements[visible];

        if (rec?.Id) {
            this.work.achievementsDeleted ||= [];
            this.work.achievementsDeleted.push(rec.Id);
        }

        this.work.achievements[visible] = { Id:null };

        this.work.achievementsVisibleRows--;
    }


    _addVersatilityRow() {
        if (this.work.versatilityVisibleRows < AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.versatility) {
            this.work.versatilityVisibleRows++;
        }
    }

    _removeVersatilityRow() {

        const visible =
            this.work.versatilityVisibleRows;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.work.versatility[visible];

        if (rec?.Id) {
            this.work.versatilityDeleted ||= [];
            this.work.versatilityDeleted.push(rec.Id);
        }

        this.work.versatility[visible] = { Id:null };

        this.work.versatilityVisibleRows--;
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
        return (
            sectionKey === 'workExperience' ||
            sectionKey === 'achievements' ||
            sectionKey === 'versatility'
        );
    }

    _resolveFieldConditionValue(path, sectionKey, sequence) {
        const parts = String(path || '').split('.');
        if (!parts.length) return undefined;

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

        if (path === 'otherResources.showOtherInformationSource') {
            console.log('otherResources.showOtherInformationSource '+this.work.informationSource?.ReferralSourceMulti__c);
            console.log('otherResources.showOtherInformationSource '+this._containsValue(
                this.work.informationSource?.ReferralSourceMulti__c,
                'Other'
            ));
            return this._containsValue(
                this.work.informationSource?.ReferralSourceMulti__c,
                'Other'
            );
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

        // For sequential sections like workExperience[seq] / achievements[seq]
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

        // Non-sequential root: work.haveWorkExperience, work.totalExperienceSummary, etc.
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
        return AfWorkExperienceContainerPgdm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfWorkExperienceContainerPgdm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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
                this.application.RecordTypeId = response?.application?.RecordTypeId;

                this.work.haveWorkExperience = {
                    HasWorkExperience__c: response?.application?.HasWorkExperience__c
                };

                this.work.totalExperienceSummary = {
                    TotalIndustryExperience__c:
                        response?.application?.TotalIndustryExperience__c,
                    AdditionalWorkExperienceInMonths__c:
                        response?.application?.AdditionalWorkExperienceInMonths__c
                };

                this.work.overallVersatilityRating = {
                    OverallVersatilityRating__c:
                        response?.application?.OverallVersatilityRating__c
                };

                this.work.responsibilitiesShouldered = {
                    PersonalResponsibilityLevel__c:
                        response?.application?.PersonalResponsibilityLevel__c,
                    ProfessionalResponsibilityLevel__c:
                        response?.application?.ProfessionalResponsibilityLevel__c,
                    PersonalResponsibilityDescription__c:
                        response?.application?.PersonalResponsibilityDescription__c,
                    ProfessionalResponsibilityDescription__c:
                        response?.application?.ProfessionalResponsibilityDescription__c
                };

                this.work.informationSource = {
                    ReferralSourceMulti__c:
                        response?.application?.ReferralSourceMulti__c,
                    OtherReferralSource__c:
                        response?.application?.OtherReferralSource__c,
                    InterestedInOtherProgram__c:
                        response?.application?.InterestedInOtherProgram__c,
                    OtherProgramsInterestedIn__c:
                        response?.application?.OtherProgramsInterestedIn__c
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
                    if (seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience) {
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
                    Math.max(1, Math.min(records.length, AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience));

                this._recomputeTotalIndustryExperience();
                // 4️⃣ Fill remaining rows
                while (seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience) {
                    this.work.workExperience[seq] = { Id: null };
                    seq++;
                }

            }
            

            if (response && response.achievements) {

                const records = Object.keys(response.achievements)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.achievements[k]);

                this.work.achievements = {
                    isSequential: false
                };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.achievements) {
                        this.work.achievements[seq] = rec;
                        seq++;
                    }
                });

                this.work.achievementsVisibleRows =
                    Math.max(
                        1,
                        Math.min(records.length, AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.achievements)
                    );

                while (seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.achievements) {
                    this.work.achievements[seq] = {
                        Id: null
                    };
                    seq++;
                }
            }

            if (response && response.versatility) {

                const records = Object.keys(response.versatility)
                    .filter(k => k !== 'isSequential')
                    .map(k => response.versatility[k]);

                this.work.versatility = {
                    isSequential: false
                };

                let seq = 1;

                records.forEach(rec => {
                    if (seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.versatility) {
                        this.work.versatility[seq] = rec;
                        seq++;
                    }
                });

                this.work.versatilityVisibleRows =
                    Math.max(
                        1,
                        Math.min(records.length, AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.versatility)
                    );

                while (seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.versatility) {
                    this.work.versatility[seq] = {
                        Id: null
                    };
                    seq++;
                }
            }

        } catch (err) {
            console.warn('Fetch failed', err);
        }

        // 🔥 Final recalculation after both work loaded
        for (let i = 1; i <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience; i++) {
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
            totalExperienceSummary: {},
            achievements: {},
            versatility: {},
            overallVersatilityRating: {},
            responsibilitiesShouldered: {},
            informationSource: {},
        };

        console.log('val 1');

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

        console.log('val 2');

        let earliestWorkStart = null;

        for (let i = AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience; i >= 1; i--) {
            const w = this.work.workExperience[i];
            if (w?.Start_Date__c) {
                earliestWorkStart = this._normalizeMonthYear(w.Start_Date__c);
                break;
            }
        }

        const additionalMonths =
            this.work.totalExperienceSummary?.AdditionalWorkExperienceInMonths__c;

        if (
            additionalMonths !== null &&
            additionalMonths !== undefined &&
            additionalMonths !== ''
        ) {
            const value = Number(additionalMonths);

            if (!Number.isInteger(value) || value < 0 || value > 60) {
                errors.totalExperienceSummary.AdditionalWorkExperienceInMonths__c =
                    'Enter a whole number between 0 and 60 months.';
            }
        }

        console.log('val 3');

        console.log('val 4');

        //Achievements 

        const achievementsMeta = this.metadata.achievements;

        for (
            let seq = 1;
            seq <= this.work.achievementsVisibleRows;
            seq++
        ) {
            const rec = this.work.achievements[seq] || {};

            achievementsMeta.fields.forEach(f => {

                const visible = this._computeFieldVisible(
                    f,
                    'achievements',
                    seq
                );

                if (!visible) {
                    return;
                }

                const required =
                    [
                        'Title_of_the_Award__c',
                        'Institute_Granting_the_Award__c',
                        'Year__c'
                    ].includes(f.api) &&
                    this._isRowActive('achievements', seq);

                if (required && !rec[f.api]) {
                    errors.achievements[
                        `${f.api}__${seq}`
                    ] = `${f.shortLabel || f.label} is required`;
                }

                if (
                    (f.type === 'text' ||
                    f.type === 'textarea') &&
                    rec[f.api]
                ) {
                    const err = validateTextConstraints(
                        f,
                        String(rec[f.api]).trim()
                    );

                    if (err) {
                        errors.achievements[
                            `${f.api}__${seq}`
                        ] = err;
                    }
                }
            });
        }

        console.log('val 5');

        //Versatility 

        const versatilityMeta = this.metadata.versatility;

        for (
            let seq = 1;
            seq <= this.work.versatilityVisibleRows;
            seq++
        ) {
            const rec = this.work.versatility[seq] || {};

            versatilityMeta.fields.forEach(f => {

                const visible = this._computeFieldVisible(
                    f,
                    'versatility',
                    seq
                );

                if (!visible) {
                    return;
                }

                const required =
                    [
                        'Title_of_the_Award__c',
                        'Institute_Granting_the_Award__c',
                        'Year__c'
                    ].includes(f.api) &&
                    this._isRowActive('versatility', seq);

                if (required && !rec[f.api]) {
                    errors.versatility[
                        `${f.api}__${seq}`
                    ] = `${f.shortLabel || f.label} is required`;
                }

                if (
                    (f.type === 'text' ||
                    f.type === 'textarea') &&
                    rec[f.api]
                ) {
                    const err = validateTextConstraints(
                        f,
                        String(rec[f.api]).trim()
                    );

                    if (err) {
                        errors.versatility[
                            `${f.api}__${seq}`
                        ] = err;
                    }
                }
            });
        }

        console.log('val 6');

        //responsibilities shouldered
        ['PersonalResponsibilityDescription__c', 'ProfessionalResponsibilityDescription__c' ].forEach((eachField) => {
            const currentMeta =
            this.metadata.responsibilitiesShouldered.fields.find(
                f => f.api === eachField
            );

            const currentValue =
                this.work.responsibilitiesShouldered
                    ?.[eachField];

            const responsibilitiesErr =
                validateTextConstraints(
                    currentMeta,
                    currentValue
                );

            if (responsibilitiesErr) {

                errors.responsibilitiesShouldered ||= {};

                errors.responsibilitiesShouldered[eachField] =  responsibilitiesErr;
            }

        })

        const informationSourceData =
            this.work.informationSource || {};

        this.metadata.informationSource.fields.forEach(f => {

            const visible =
                this._computeFieldVisible(
                    f,
                    'informationSource'
                );

            if (!visible) {
                return;
            }

            const required =
                this._computeFieldRequired(
                    f,
                    'informationSource'
                );

            const value =
                informationSourceData[f.api];

            if (
                required &&
                (value === null ||
                value === undefined ||
                value === '')
            ) {
                errors.informationSource[f.api] =
                    `${f?.shortLabel || f.label} is required`;
            }

            const textErr =
                validateTextConstraints(
                    f,
                    String(value || '').trim()
                );

            if (textErr) {
                errors.informationSource[f.api] = textErr;
            }
        });

        const cmp = this.template.querySelector('c-af-section-engine');
        if (cmp && typeof cmp.applyErrors === 'function') {
            cmp.applyErrors(errors);
        }

        console.log('val 7');

        const hasErrors =
            Object.keys(errors.workExperience).length > 0 ||
            Object.keys(errors.totalExperienceSummary || {}).length > 0 ||
            Object.keys(errors.achievements).length > 0 ||
            Object.keys(errors.versatility).length > 0 ||
            Object.keys(errors.responsibilitiesShouldered).length > 0 ||
            Object.keys(errors.informationSource).length > 0;

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

        console.log('val 8');

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

        const totalIndustryExperience =
            this.work?.totalExperienceSummary?.TotalIndustryExperience__c || 0;

        if (totalIndustryExperience > 60) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Work Experience',
                    message:
                        'Your total work experience, including additional experience, is less than 60 months.',
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
                            AdditionalWorkExperienceInMonths__c:
                                Number(
                                    this.work?.totalExperienceSummary
                                        ?.AdditionalWorkExperienceInMonths__c || 0
                                ),

                            OverallVersatilityRating__c:
                                this.work?.overallVersatilityRating
                                    ?.OverallVersatilityRating__c || '',

                             PersonalResponsibilityLevel__c:
                                this.work?.responsibilitiesShouldered?.PersonalResponsibilityLevel__c || '',

                            PersonalResponsibilityDescription__c:
                                this.work?.responsibilitiesShouldered?.PersonalResponsibilityDescription__c || '',

                            ProfessionalResponsibilityLevel__c:
                                this.work?.responsibilitiesShouldered?.ProfessionalResponsibilityLevel__c || '',

                            ProfessionalResponsibilityDescription__c:
                                this.work?.responsibilitiesShouldered?.ProfessionalResponsibilityDescription__c || '',
                            ReferralSourceMulti__c:
                                this.work?.informationSource?.ReferralSourceMulti__c || '',
                            OtherReferralSource__c:
                                this.work?.informationSource?.OtherReferralSource__c || '',
                            InterestedInOtherProgram__c:
                                this.work?.informationSource?.InterestedInOtherProgram__c || '',
                            OtherProgramsInterestedIn__c:
                                this.work?.informationSource?.OtherProgramsInterestedIn__c || ''
                        }
                    }
                })
            });

            const childPayload = {};

            const c = context.children.find(
                c => c.logicalName === 'workExperience'
            );

            const achievementsContext = context.children.find(
                c => c.logicalName === 'achievements'
            );

            const versatilityContext = context.children.find(
                c => c.logicalName === 'versatility'
            );

            if (
                !c ||
                !achievementsContext ||
                !versatilityContext
            ) {
                console.error('Missing child context configuration');
                this.isLoading = false;
                return false;
            }

            let rows = [];
            let deleted = this.work.workExperienceDeleted || [];

            for (let seq = 1; seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.workExperience; seq++) {

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

            let achievementRows = [];

            let achievementDeleted =
                this.work.achievementsDeleted || [];

            for (let seq = 1; seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.achievements; seq++) {

                const row =
                    this.work.achievements[seq];

                if (!row) {
                    continue;
                }

                const hasId = !!row.Id;

                if (
                    hasId &&
                    achievementDeleted.includes(row.Id)
                ) {
                    continue;
                }

                const allowed =
                    new Set(
                        achievementsContext.fieldsToQuery
                    );

                let cleanRow = {};

                Object.keys(row).forEach(api => {
                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                const hasData =
                    Object.keys(cleanRow)
                        .filter(k => k !== 'Id')
                        .some(k =>
                            cleanRow[k] !== null &&
                            cleanRow[k] !== undefined &&
                            cleanRow[k] !== ''
                        );

                if (!hasId && !hasData) {
                    continue;
                }

                if (!hasId && hasData) {
                    achievementRows.push({
                        sobject: achievementsContext.sobject,
                        parentLookupField:
                            achievementsContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    });
                    continue;
                }

                if (hasId && !hasData) {
                    achievementDeleted.push(row.Id);
                    continue;
                }

                achievementRows.push({
                    sobject: achievementsContext.sobject,
                    parentLookupField:
                        achievementsContext.parentLookupField,
                    parentId: this.application.Id,
                    fields: cleanRow,
                    Id: row.Id
                });
            }

            childPayload[
                achievementsContext.logicalName
            ] = {
                sobject: achievementsContext.sobject,
                parentLookupField:
                    achievementsContext.parentLookupField,
                rows: achievementRows,
                deletedIds: achievementDeleted
            };

            let versatilityRows = [];

            let versatilityDeleted =
                this.work.versatilityDeleted || [];

            for (let seq = 1; seq <= AfWorkExperienceContainerPgdm.MULTI_ROW_LIMITS.versatility; seq++) {

                const row =
                    this.work.versatility[seq];

                if (!row) {
                    continue;
                }

                const hasId = !!row.Id;

                if (
                    hasId &&
                    versatilityDeleted.includes(row.Id)
                ) {
                    continue;
                }

                const allowed =
                    new Set(
                        versatilityContext.fieldsToQuery
                    );

                let cleanRow = {};

                Object.keys(row).forEach(api => {
                    if (allowed.has(api)) {
                        cleanRow[api] = row[api];
                    }
                });

                const hasData =
                    Object.keys(cleanRow)
                        .filter(k => k !== 'Id')
                        .some(k =>
                            cleanRow[k] !== null &&
                            cleanRow[k] !== undefined &&
                            cleanRow[k] !== ''
                        );

                if (!hasId && !hasData) {
                    continue;
                }

                if (!hasId && hasData) {
                    versatilityRows.push({
                        sobject: versatilityContext.sobject,
                        parentLookupField:
                            versatilityContext.parentLookupField,
                        parentId: this.application.Id,
                        fields: cleanRow,
                        Id: null
                    });
                    continue;
                }

                if (hasId && !hasData) {
                    versatilityDeleted.push(row.Id);
                    continue;
                }

                versatilityRows.push({
                    sobject: versatilityContext.sobject,
                    parentLookupField:
                        versatilityContext.parentLookupField,
                    parentId: this.application.Id,
                    fields: cleanRow,
                    Id: row.Id
                });
            }

            childPayload[
                versatilityContext.logicalName
            ] = {
                sobject: versatilityContext.sobject,
                parentLookupField:
                    versatilityContext.parentLookupField,
                rows: versatilityRows,
                deletedIds: versatilityDeleted
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