import { LightningElement, api, track } from 'lwc';
import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';

import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import { buildErrorSummary, validateMinMaxDate, validateNumber } from "c/applicationFormService";

import { context } from './context';

const TODAY = new Date();

const getMinDate = (yearsBack) => {
    const d = new Date();
    d.setFullYear(d.getFullYear() - yearsBack);
    d.setMonth(0, 1); // Jan 1 of cutoff year
    d.setHours(0, 0, 0, 0);
    return d;
};

const EXAM_RULES = {
    gmat: {
        score: { field: 'GMAT_Total_Score__c', min: 550, max: 800 },
        date: { field: 'Test_Date__c', min: getMinDate(3), max: TODAY }
    },
    gre: {
        score: { field: 'GRE_Total_Score__c', min: 300, max: 340 },
        date: { field: 'GreMonthAndYear__c', min: getMinDate(3), max: TODAY }
    },
    cat: {
        score: { field: 'CAT_Overall_Percentile__c', min: 80, max: 100 },
        year: { field: 'CAT_Year_of_Exam__c', min: new Date().getFullYear() - 2, max: new Date().getFullYear() }
    },
    xat: {
        score: { field: 'XAT_Total_Percentile__c', min: 80, max: 100 },
        year: { field: 'XAT_Year_of_Exam__c', min: new Date().getFullYear() - 2, max: new Date().getFullYear() }
    },
    nmat: {
        score: { field: 'Total_NMAT_Score_Obtained__c', min: 230, max: 360 },
        date: { field: 'NmatMonthAndYearOfExam__c', min: getMinDate(2), max: TODAY }
    },
    gmatFocus: {
        score: { field: 'GMAT_Focus_Edition_Total_Score__c', min: 525, max: 805 },
        date: { field: 'GMAT_Focus_Edition_Test_Date__c', min: getMinDate(3), max: TODAY }
    },
    ielts: {
        score: { field: 'IELTS_Overall_Band_Score__c', min: 0, max: 9 },
        year: { field: 'IELTS_Year_of_Exam__c', min: new Date().getFullYear() - 2, max: new Date().getFullYear() }
    },
    toefl: {
        score: { field: 'TOEFL_Total_Score__c', min: 0, max: 120 },
        year: { field: 'TOEFL_Year_of_Exam__c', min: new Date().getFullYear() - 2, max: new Date().getFullYear() }
    }
};

const ELIGIBILITY_ERROR =
    'You do not meet the eligibility criteria, contact 9820866719 / 9820618910';

export default class AfCompetitiveExamDetailsContainerGmp extends LightningElement {

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

    @track education = {};     
    @track examSections = [];  
    @track eligibilityError = null;

    get contextBlock() {
        return {
            ...this.education,
            application: this.application
        };
    }

    picklistCache = {};
    dependentCache = {};

    async connectedCallback() {

        // construct safely
        this.recordToLogical = {};

        if (context.parents && Array.isArray(context.parents)) {
            context.parents.forEach(p => {
                if (p?.recordName) {
                    this.recordToLogical[p.recordName.toUpperCase()] = p.logicalName;
                }
            });
        }

        try {
            const data = await getAllPicklistsForObjects({ objectApiNames: ['Competitive_Exam_Details__c'] })
            // Process the new structured response
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
            // Since we now use getAllPicklistsForObjects which includes dependent picklist data,
            // we don't need to call getDependentPicklistMap separately
            this._buildMetadataSkeleton();
            this._applyExamRulesToMetadata();
            this._injectPicklists();
            await this.fetchForm(this.application?.Id)
        } catch (err) {
            console.error(err);
            this._buildMetadataSkeleton();
            this._applyExamRulesToMetadata();
            await this.fetchForm(this.application?.Id)
        }
        finally {
            this.isLoading = false;
        }
    }

    // inject picklists from picklistCache into metadata fields
    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr => (arr || []).map(x => ({ label: x.label || x.Label || x, value: x.value || x.Value || x }));
        const setOptions = (sectionKey, api, options) => {
            const f = (this.metadata[sectionKey].fields || []).find(x => x.api.toLowerCase() === api.toLowerCase());
            if (f) f.options = options;
        };

        const fourYearsBeforeNow = Number(new Date().getFullYear()) - 2

        if(pick?.CAT_Year_of_Exam__c){
            setOptions('cat','CAT_Year_of_Exam__c', toOptions(
                pick.CAT_Year_of_Exam__c.filter(y =>
                    Number(y.value) >= fourYearsBeforeNow
                )
            ));
        }

        if(pick?.IELTS_Year_of_Exam__c){
            setOptions('ielts','IELTS_Year_of_Exam__c', toOptions(
                pick.IELTS_Year_of_Exam__c.filter(y =>
                    Number(y.value) >= fourYearsBeforeNow
                )
            ));
        }

        if(pick?.XAT_Year_of_Exam__c){
            setOptions('xat','XAT_Year_of_Exam__c', toOptions(
                pick.XAT_Year_of_Exam__c.filter(y =>
                    Number(y.value) >= fourYearsBeforeNow
                )
            ));
        }

        if(pick?.TOEFL_Year_of_Exam__c){
            setOptions('toefl','TOEFL_Year_of_Exam__c', toOptions(
                pick.TOEFL_Year_of_Exam__c.filter(y =>
                    Number(y.value) >= fourYearsBeforeNow
                )
            ));  
        }
        
    }


    recordToLogical = {};

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfCompetitiveExamDetailsContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfCompetitiveExamDetailsContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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


    /* ====================================================
       FETCH FORM (Application + selected exam parents)
    ==================================================== */
    async fetchForm(appId) {
        if (!appId) return;

        try {
            /* ============================================================
            1) FIRST REQUEST → ONLY APPLICATION
            ============================================================ */
            const applicationRequest = {
                parents: [{
                    logicalName : 'application',
                    sobject     : context.parents.find(p => p.logicalName === 'application').sobject,
                    fields      : context.parents.find(p => p.logicalName === 'application').fieldsToQuery,
                    filters     : [{ field: 'Id', value: appId }]
                }],
                children: []
            };

            const appResponse = await fetchDynamic({
                requestJson: JSON.stringify(applicationRequest)
            });

            // Store root application
            this.application = appResponse.application || {};
            this.education = { application: this.application };


            /* ============================================================
            2) FIGURE OUT WHICH EXAMS THE USER SELECTED
            ============================================================ */
            const parse = v => (v || '').split(';').map(s => s.trim()).filter(Boolean);

            let selectedExams = parse(this.application.CompetitiveExams__c);
            let selectedLang  = parse(this.application.LanguageProficiencyExams__c);
            let hasLang       = (this.application.HasLanguageProficiency__c || '').toLowerCase() === 'yes';

            let examKeys = [
                ...selectedExams.map(ex => this.recordToLogical[ex?.toUpperCase?.()]),
                ...(hasLang ? selectedLang.map(ex => this.recordToLogical[ex?.toUpperCase?.()]) : [])
            ].filter(Boolean);

            if (examKeys.length === 0) {
                // No exams selected → just render application
                this._buildRenderModelAll();
                this.examSections = [...this.examSections];
                return;
            }

            /* ============================================================
            3) SECOND REQUEST → ONLY FETCH REQUIRED PARENT EXAMS
            ============================================================ */
            const parentsRequest = {
                parents: [],
                children: []
            };

            examKeys.forEach(key => {
                const meta = context.parents.find(p => p.logicalName === key);
                if (!meta) return;

                parentsRequest.parents.push({
                    logicalName : meta.logicalName,
                    sobject     : meta.sobject,
                    fields      : meta.fieldsToQuery,
                    filters     : [
                        { field: 'Exam_Name__c', value: meta.recordName },
                        { field: context.parentLookupField, value: appId }
                    ]
                });
            });

            const personalDetailsContext = context.parents.find(p => p.logicalName === 'personalDetails');
            parentsRequest.parents.push({
                logicalName : personalDetailsContext.logicalName,
                sobject     : personalDetailsContext.sobject,
                fields      : personalDetailsContext.fieldsToQuery,
                filters     : [
                    { field: context.parentLookupField, value: appId }
                ]
            });

            const parentResponse = await fetchDynamic({
                requestJson: JSON.stringify(parentsRequest)
            });

            /* ============================================================
            4) STORE ONLY REQUIRED PARENT BLOCKS
            ============================================================ */
            examKeys.forEach(k => {
                this.education[k] = parentResponse[k] ? parentResponse[k] : {};
            });
            this.education.personalDetails = parentResponse.personalDetails ? parentResponse.personalDetails : {};

            // Recompute examKeys after parent data is ready
            selectedExams = parse(this.application.CompetitiveExams__c);
            selectedLang  = parse(this.application.LanguageProficiencyExams__c);
            hasLang       = (this.application.HasLanguageProficiency__c || '').toLowerCase() === 'yes';

            examKeys = [
                ...selectedExams.map(ex => this.recordToLogical[ex?.toUpperCase?.()]),
                ...(hasLang ? selectedLang.map(ex => this.recordToLogical[ex?.toUpperCase?.()]) : [])
            ].filter(Boolean);

            this._applyReadOnlyMode();


            /* ============================================================
            5) BUILD RENDER MODEL
            ============================================================ */
            this._buildRenderModelAll();
            this.examSections = [...this.examSections];
        } catch (e) {
            console.error('fetchForm error', e);
        }
    }


    /* ====================================================
       BUILD FETCH REQUEST
    ==================================================== */
    _buildFetchRequest(appId) {
        const request = { parents: [], children: [] }; // children will stay empty

        // 1. Application parent
        const rootMeta = context.parents.find(p => p.logicalName === 'application');

        request.parents.push({
            logicalName: rootMeta.logicalName,
            sobject: rootMeta.sobject,
            fields: rootMeta.fieldsToQuery,
            filters: [{ field: 'Id', value: appId }]
        });

        // 2. Determine selected exams
        const parse = v => (v || '').split(';').map(s => s.trim()).filter(Boolean);
        const selectedExams = parse(this.application.CompetitiveExams__c);
        const selectedLang = parse(this.application.LanguageProficiencyExams__c);
        const hasLang = (this.application.HasLanguageProficiency__c || '').toLowerCase() === 'yes';

        const examKeys = [
            ...selectedExams.map(ex => this.recordToLogical[ex?.toUpperCase?.()]),
            ...(hasLang ? selectedLang.map(ex => this.recordToLogical[ex?.toUpperCase?.()]) : [])
        ].filter(Boolean);

        // 3. Add each exam as PARENT block (NOT CHILD)
        examKeys.forEach(key => {
            const p = context.parents.find(x => x.logicalName === key);
            if (!p) return;

            request.parents.push({
                logicalName: p.logicalName,
                sobject: p.sobject,
                fields: p.fieldsToQuery,
                filters: [
                    { field: 'Exam_Name__c', value: p.recordName },
                    { field: context.parentLookupField, value: appId }
                ]
            });
        });

        return request;
    }


    /* ====================================================
       BUILD RENDER MODEL
    ==================================================== */
    _buildRenderModelAll() {
        const parse = v => (v || '').split(';').map(s => s.trim()).filter(Boolean);

        // 1) competitive exams → convert to logicalName
        const selectedExams = parse(this.application.CompetitiveExams__c)
            .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
            .filter(Boolean);

        // 2) language exams
        const hasLang = (this.application.HasLanguageProficiency__c || '').toLowerCase() === 'yes';

        const selectedLang = hasLang
            ? parse(this.application.LanguageProficiencyExams__c)
                .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
                .filter(Boolean)
            : [];

        const sections = [];

        if (this.metadata.topInstruct) {
            sections.push(this._buildSectionRenderModel("topInstruct"));
        }

        // Competitive exams first
        selectedExams.forEach(k => {
            if (this.metadata[k]) {
                sections.push(this._buildSectionRenderModel(k));
            }
        });

        // Application section
        sections.push(this._buildSectionRenderModel("application"));

        // Language exams
        selectedLang.forEach(k => {
            if (this.metadata[k]) {
                sections.push(this._buildSectionRenderModel(k));
            }
        });

        this.examSections = sections;
    }


    /* ====================================================
       METADATA (ALL EXAMS + NOTES)
    ==================================================== */
    _buildMetadataSkeleton() {
        this.metadata = {};

        this.metadata.topInstruct = {
        key: "topInstruct",
        title: "Instructions",
        columnSystem: 12,
        note: {
            api: "SECTION_NOTE",
            type: "note",
            text: `
<b>Important Instructions</b><br/>

• <a href="https://www.spjimr.org/course/global-management-programme-gmp/admission/" target="_blank">Click here</a> to know the Important Dates of the Cohort.<br/><br/>
            `
        },
        rows: [],
        fields: [
            { api: 'SECTION_NOTE', type: 'note' }
        ]
    };


        /* ====================================================
           GMAT
        ==================================================== */
        this.metadata.gmat = {
            key: "gmat",
            title: "GMAT",
            columnSystem: 12,
            rows: [
                { columns: [
                    { width:3, fields:['GMAT_ID__c'] },
                    { width:3, fields:['Test_Date__c'] },
                    { width:3, fields:['Verbal_Score__c'] },
                    { width:3, fields:['Quantitative_Score__c'] }
                ]},
                { columns: [
                    { width:3, fields:['Analytical_Writing_Score__c'] },
                    { width:3, fields:['Integrated_Reasoning_Score__c'] },
                    { width:3, fields:['GMAT_Total_Score__c'] }
                ]}
            ],
            fields: [
                { api:'GMAT_NOTE', type:'note' },
                { api:'GMAT_ID__c', type:'text', label:'GMAT ID', required:true, maxlength: '255' },
                { api:'Test_Date__c', type:'date', label:'Test Date', required:true, max:new Date().toISOString().split('T')[0], min:"2020-01-01" },
                { api:'Verbal_Score__c', type:'number', step: "0.01", max:"999", label:'Verbal', required:true },
                { api:'Quantitative_Score__c', type:'number', step: "0.01", max:"999", label:'Quantitative', required:true },
                { api:'Analytical_Writing_Score__c', type:'number', step: "0.01", max:"999", label:'Analytical Writing', required:true },
                { api:'Integrated_Reasoning_Score__c', type:'number', step: "0.01", max:"999", label:'Integrated Reasoning', required:true },
                { api:'GMAT_Total_Score__c', type:'number', step: "0.01", max:"999", label:'GMAT Total Score' }
            ]
        };

        /* ====================================================
           GRE
        ==================================================== */
        this.metadata.gre = {
            key: "gre",
            title: "GRE",
            columnSystem: 12,
            rows: [
                { columns: [
                    { width:3, fields:['GRE_ID__c'] },
                    { width:3, fields:['GreMonthAndYear__c'] },
                    { width:3, fields:['GRE_Analytical_Reasoning__c'] },
                    { width:3, fields:['GRE_Analytical_Writing__c'] }
                ]},
                { columns: [
                    { width:4, fields:['GRE_Quantitative_Reasoning__c'] },
                    { width:4, fields:['GRE_Total_Score__c'] }
                ]}
            ],
            fields: [
                { api:'GRE_NOTE', type:'note' },
                { api:'GRE_ID__c', type:'text', label:'GRE ID', required:true, maxlength: '255' },
                { api:'GreMonthAndYear__c', type:'monthyear', min:"2022-01-01", max:new Date().toISOString().split('T')[0], label:'Month/Year',  required:true },
                { api:'GRE_Analytical_Reasoning__c', step: "0.01", max:"999", type:'number', label:'Analytical Reasoning', required:true },
                { api:'GRE_Analytical_Writing__c',step: "0.01", max:"999", type:'number', label:'Analytical Writing', required:true },
                { api:'GRE_Quantitative_Reasoning__c', step: "0.01", max:"999", type:'number', label:'Quantitative Reasoning', required:true },
                { api:'GRE_Total_Score__c', type:'number', step: "0.01", max:"999", label:'GRE Total Score', required:true }
            ]
        };

        /* ====================================================
           CAT
        ==================================================== */
        this.metadata.cat = {
            key:'cat',
            title:'CAT',
            columnSystem:12,
            rows:[
                { columns:[
                    {width:3,fields:['CAT_Registration_Number__c']},
                    {width:3,fields:['CAT_Year_of_Exam__c']},
                    {width:3,fields:['CAT_Quantitative_Aptitude__c']},
                    {width:3,fields:['Data_interpretation_and_logical_re_score__c']},
                ]},
                { columns:[
                    {width:3,fields:['CatVerbalReadingComprehensionScore__c']},
                    {width:3,fields:['CAT_Overall_Percentile__c']},
                    {width:3,fields:['Is_your_primary_email_ID_same_as_CAT_exa__c']},
                    {width:3,fields:['CAT_E_Mail__c']},
                ]}
            ],

            fields:[
                { api:'CAT_NOTE', type:'note' },
                { api:'CAT_Registration_Number__c', type:'text', label:'Registration Number', required:true, maxlength: '255' },
                { api:'CAT_Year_of_Exam__c', type:'picklist', label:'Year of Exam', required:true, max: new Date().getFullYear(), min: 2022 },
                { api:'Is_your_primary_email_ID_same_as_CAT_exa__c', type:'radio', label:'Is your primary email same as CAT exam email?',
                    options:[
                        {label:'Yes',value:'Yes'},
                        {label:'No',value:'No'}
                    ]
                },
                { api:'CAT_E_Mail__c', type:'email', label:'CAT Email', maxlength: '80', visibleWhen: { 'cat.Is_your_primary_email_ID_same_as_CAT_exa__c': 'No' } },
                { api:'CAT_Quantitative_Aptitude__c', step: "0.01", max:"999", type:'number', label:'QuantitativeAptitude', required:true },
                { api:'Data_interpretation_and_logical_re_score__c', step: "0.01", max:"999", type:'number', label:'Data Integration / Logical Reasoning', required:true },
                { api:'CatVerbalReadingComprehensionScore__c', step: "0.01", max:"999", type:'number', label:'Verbal & Reading Comprehension', required:true },
                { api:'CAT_Overall_Percentile__c', step: "0.01", max:"999", type:'number', label:'CAT Total Percentile', required:true }
            ]
        };

        /* ====================================================
           XAT
        ==================================================== */
        this.metadata.xat = {
            key:'xat',
            title:'XAT',
            columnSystem:12,
            rows:[
                { columns:[
                    {width:3,fields:['XAT_ID__c']},
                    {width:3,fields:['XAT_Year_of_Exam__c']},
                    {width:3,fields:['XAT_Quantitative_Analytical_Ability__c']},
                    {width:3,fields:['XAT_Verbal_Logical_Ability__c']}
                ]},
                { columns:[
                    {width:3,fields:['XAT_Decision_Making__c']},
                    {width:3,fields:['XAT_Total_Percentile__c']},
                ]}
            ],

            fields:[
                { api:'XAT_NOTE', type:'note' },
                { api:'XAT_ID__c', type:'text', label:'XAT ID', required:true, maxlength: '255' },
                { api:'XAT_Year_of_Exam__c', type:'picklist', label:'Year', required:true, max: new Date().getFullYear(), min: 2022 },
                { api:'XAT_Quantitative_Analytical_Ability__c', step: "0.01", max:"999", type:'number', label:'Quantitative & Analytical Ability', required:true },
                { api:'XAT_Verbal_Logical_Ability__c', step: "0.01", max:"999", type:'number', label:'Verbal / Logical Ability', required:true },
                { api:'XAT_Decision_Making__c', step: "0.01", max:"999", type:'number', label:'Decision Making', required:true },
                { api:'XAT_Total_Percentile__c', step: "0.01", max:"999", type:'number', label:'XAT Total Percentile', required:true }
            ]
        };

        /* ====================================================
           NMAT
        ==================================================== */
        this.metadata.nmat = {
            key:'nmat',
            title:'NMAT',
            columnSystem:12,
            rows:[
                { columns:[
                    {width:3,fields:['NMAT_ID__c']},
                    {width:3,fields:['NmatMonthAndYearOfExam__c']},
                    {width:3,fields:['NMAT_Quantitative_Skills_Score_Obtained__c']},
                    {width:3,fields:['NMAT_Logical_Reasoning_Score_Obtained__c']}
                ]},
                { columns:[
                    {width:3,fields:['NMAT_Language_Skills_Score_Obtained__c']},
                    {width:3,fields:['Total_NMAT_Score_Obtained__c']},
                ]}
            ],

            fields:[
                { api:'NMAT_NOTE', type:'note' },
                { api:'NMAT_ID__c', type:'text', label:'NMAT ID', required:true, maxlength: '255' },
                { 
                    api:'NmatMonthAndYearOfExam__c', 
                    type:'monthyear', 
                    label:'Month & Year of Exam', 
                    min: (() => {
                        const d = new Date();
                        d.setFullYear(d.getFullYear() - 4);
                        return d.toISOString().split('T')[0];
                        }
                    )(),
                    max:new Date().toISOString().split('T')[0], 
                    required:true 
                },
                { api:'NMAT_Quantitative_Skills_Score_Obtained__c', step: "0.01", max:"999", type:'number', label:'Quantitative Skills Score Obtained', required:true },
                { api:'NMAT_Logical_Reasoning_Score_Obtained__c', step: "0.01", max:"999", type:'number', label:'Logical Reasoning Score Obtained', required:true },
                { api:'NMAT_Language_Skills_Score_Obtained__c', step: "0.01", max:"999", type:'number', label:'Language Skills Score Obtained', required:true },
                { api:'Total_NMAT_Score_Obtained__c', step: "0.01", max:"999", type:'number', label:'Total Nmat Score Obtained', required:true }
            ]
        };

        /* ====================================================
           GMAT FOCUS
        ==================================================== */
        this.metadata.gmatFocus = {
            key:'gmatFocus',
            title:'GMAT Focus',
            columnSystem:12,
            rows:[
                { columns:[
                    {width:3,fields:['GMAT_FOCUS_ID__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Test_Date__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Verbal_Reasoning__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Quantitative_Reasonin__c']}
                ]},
                { columns:[
                    {width:3,fields:['GMAT_Focus_Edition_Data_Insights__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Total_Score__c']},
                ]}
            ],

            fields:[
                { api:'GMAT_FOCUS_NOTE', type:'note' },
                { api:'GMAT_FOCUS_ID__c', type:'text', label:'GMAT Focus ID', required:true, maxlength: '255' },
                { api:'GMAT_Focus_Edition_Test_Date__c', type:'date', label:'Test Date', required:true, max:new Date().toISOString().split('T')[0], min:"2020-01-01" },
                { api:'GMAT_Focus_Edition_Verbal_Reasoning__c', step: "0.01", max:"999", type:'number', label:'Verbal Reasoning', required:true },
                { api:'GMAT_Focus_Edition_Quantitative_Reasonin__c', step: "0.01", max:"999", type:'number', label:'Quantitative Reasoning', required:true },
                { api:'GMAT_Focus_Edition_Data_Insights__c', step: "0.01", max:"999", type:'number', label:'Data Insights' },
                { api:'GMAT_Focus_Edition_Total_Score__c', step: "0.01", max:"999", type:'number', label:'GMAT Score', required:true }
            ]
        };


        this.metadata.application = {
            key: "application",
            title: "English Proficiency",
            note: {
                api:'CAT_NOTE',
                type:'note',
                text: `
<b>English Proficiency Requirements</b><br/>

• For detailed information on English Proficiency Requirements, <a href="https://www.spjimr.org/wp-content/uploads/2026/03/gmp-eligibilty-criteria.pdf" target="_blank" rel="noopener noreferrer">click here</a>.<br/><br/>
                `
            },
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 4, fields: ['HasLanguageProficiency__c'] },
                        { width: 8, fields: ['LanguageProficiencyExams__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'HasLanguageProficiency__c',
                    type: 'radio',
                    label: 'Do you hold an English proficiency certificate?',
                    shortLabel: 'English proficiency response',
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ],
                    required:true
                },
                {
                    api: 'LanguageProficiencyExams__c',
                    type: 'multipicklist',
                    label: 'Select exam(s)',
                    visibleWhen: { 'application.HasLanguageProficiency__c': 'Yes' },
                    options: [
                        { label: 'TOEFL', value: 'TOEFL' },
                        { label: 'IELTS', value: 'IELTS' }
                    ],
                }
            ]
        };


        /* ====================================================
           TOEFL
        ==================================================== */
        this.metadata.toefl = {
            key:'toefl',
            title:'TOEFL',
            columnSystem:12,
            rows:[
                { columns:[
                    {width:3,fields:['TOEFL_ID__c']},
                    {width:3,fields:['TOEFL_Year_of_Exam__c']},
                    {width:3,fields:['TOEFL_Reading__c']},
                    {width:3,fields:['TOEFL_Listening__c']}
                ]},
                { columns:[
                    {width:3,fields:['TOEFL_Speaking__c']},
                    {width:3,fields:['TOEFL_Writing__c']},
                    {width:3,fields:['TOEFL_Total_Score__c']},
                    {width:3,fields:[]}
                ]}
            ],

            fields:[
                { api:'TOEFL_NOTE', type:'note' },
                { api:'TOEFL_ID__c', type:'text', label:'TOEFL ID', required:true, maxlength: '255' },
                { api:'TOEFL_Year_of_Exam__c', type:'picklist', label:'Year', required:true, max: new Date().getFullYear(), min: 2023 },
                { api:'TOEFL_Reading__c', step: "0.01", max:"999", type:'number', label:'Reading', required:true },
                { api:'TOEFL_Listening__c', step: "0.01", max:"999", type:'number', label:'Listening', required:true },
                { api:'TOEFL_Speaking__c', step: "0.01", max:"999", type:'number', label:'Speaking', required:true },
                { api:'TOEFL_Writing__c', step: "0.01", max:"999", type:'number', label:'Writing', required:true },
                { api:'TOEFL_Total_Score__c', step: "0.01", max:"999", type:'number', label:'Total Score', required:true }
            ]
        };

        /* ====================================================
           IELTS
        ==================================================== */
        this.metadata.ielts = {
            key:'ielts',
            title:'IELTS',

            columnSystem:12,
            rows:[
                { columns:[
                    {width:3,fields:['IELTS_ID__c']},
                    {width:3,fields:['IELTS_Year_of_Exam__c']},
                    {width:2,fields:['IELTS_Reading__c']},
                    {width:2,fields:['IELTS_Listening__c']},
                    {width:2,fields:['IELTS_Speaking__c']}
                ]},
                { columns:[
                    {width:3,fields:['IELTS_Writing__c']},
                    {width:3,fields:['IELTS_Overall_Band_Score__c']},
                    {width:3,fields:['IELTS_CEFR_Level__c']},
                    {width:3,fields:[]}
                ]}
            ],

            fields:[
                { api:'IELTS_NOTE', type:'note' },
                { api:'IELTS_ID__c', type:'text', label:'IELTS ID', required:true, maxlength: '255' },
                { api:'IELTS_Year_of_Exam__c', type:'picklist', label:'Year', required:true, max: new Date().getFullYear(), min:2023 },
                { api:'IELTS_Reading__c', step: "0.01", max:"999", type:'number', label:'Reading', required:true },
                { api:'IELTS_Listening__c', step: "0.01", max:"999", type:'number', label:'Listening', required:true },
                { api:'IELTS_Speaking__c', step: "0.01", max:"999", type:'number', label:'Speaking', required:true },
                { api:'IELTS_Writing__c', step: "0.01", max:"999", type:'number', label:'Writing', required:true },
                { api:'IELTS_Overall_Band_Score__c', step: "0.01", max:"999", type:'number', label:'Overall Band Score', required:true },
                { api:'IELTS_CEFR_Level__c', step: "0.01", max:"999", type:'text', label:'CEFR Level', maxlength: '255' }
            ]
        };
    }

    _applyExamRulesToMetadata() {
        Object.keys(EXAM_RULES).forEach(sectionKey => {
            const rules = EXAM_RULES[sectionKey];
            const meta = this.metadata[sectionKey];
            if (!meta) return;

            meta.fields.forEach(f => {

                // SCORE
                if (rules.score && f.api === rules.score.field) {
                    f.min = rules.score.min;
                    f.max = rules.score.max;

                    f.messageWhenRangeUnderflow = ELIGIBILITY_ERROR;
                    f.messageWhenRangeOverflow = `${meta.title} should not exceed ${f.max}`;

                    f.skipOnChangeValidation = true;
                }

                const formatLocalDate = (d) => {
                    const year = d.getFullYear();
                    const month = String(d.getMonth() + 1).padStart(2, '0');
                    const day = String(d.getDate()).padStart(2, '0');
                    return `${year}-${month}-${day}`;
                };

                // DATE / MONTHYEAR
                if (rules.date && f.api === rules.date.field) {

                    let min = new Date(rules.date.min);
                    let max = new Date();

                    // ✅ Only for monthyear fields
                    if (f.type === 'monthyear') {
                        min.setDate(1);
                        max.setDate(1);
                    }

                    f.min = formatLocalDate(min);
                    f.max = formatLocalDate(max);
                }

                // YEAR (picklist → still JS validated)
                if (rules.year && f.api === rules.year.field) {
                    f.min = rules.year.min;
                    f.max = rules.year.max;

                    f.errorMessage = ELIGIBILITY_ERROR; // used in JS
                }
            });
        });
    }

    validateFieldByType(f, value) {
        if (value === null || value === undefined || value === '') return null;

        // NUMBER
        if (f.type === 'number') {
            const err = validateNumber(f, value);
            if (err) {

                //decimal message is allowed
                if(err.includes('decimal')){
                    return err;
                }

                // ✅ Only override when explicitly configured
                if (f.messageWhenRangeUnderflow || f.messageWhenRangeOverflow) {
                    return f.messageWhenRangeUnderflow || f.messageWhenRangeOverflow;
                }

                // default behavior (normal fields)
                return err;
            }
        }

        // DATE + MONTHYEAR
        if (f.type === 'date' || f.type === 'monthyear') {
            return validateMinMaxDate(f, value);
        }

        // YEAR (picklist)
        if (f.type === 'picklist' && (f.min || f.max)) {
            const year = Number(value);
            if (!year) return null;

            if (f.min && year < f.min) {
                return f.errorMessage || `${f.label} must be at least ${f.min}`;
            }
            if (f.max && year > f.max) {
                return f.errorMessage || `${f.label} must be at most ${f.max}`;
            }
        }

        return null;
    }

    /* ====================================================
    SECTION RENDER MODEL (with NOTE + proper APPLICATION handling)
    ==================================================== */
    _buildSectionRenderModel(sectionKey) {
        const meta = this.metadata[sectionKey];
        if (!meta) return null;

        const section = { key: meta.key, title: meta.title, rows: [] };

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

        /* NORMAL FIELD ROWS */
        meta.rows.forEach((r, rIdx) => {
            const row = {
                key: `${sectionKey}-row-${rIdx}`,
                style: `display:grid;grid-template-columns:repeat(${meta.columnSystem},1fr);gap:8px;margin-bottom:8px;`,
                columns: []
            };

            r.columns.forEach((col, cIdx) => {
                const column = {
                    key: `${sectionKey}-col-${rIdx}-${cIdx}`,
                    widthStyle: `grid-column: span ${col.width || 12};`,
                    fields: []
                };

                col.fields.forEach(api => {
                    const fMeta = meta.fields.find(f => f.api === api);
                    if (!fMeta) return;

                    // single 'value' variable only — no shadowing
                    let value = null;

                    /* APPLICATION SECTION: read from this.application */
                    if (sectionKey === "application") {
                        if (api === "LanguageProficiencyExams__c") {
                            const raw = this.application.LanguageProficiencyExams__c || '';
                            value = raw ? raw.split(';').map(v => v.trim()) : [];
                        } else {
                            value = this.application[api] ?? null;
                        }
                    }
                    /* OTHER EXAM SECTIONS: read from this.education[sectionKey] */
                    else {
                        const sectionData = this.education[sectionKey] || {};
                        value = sectionData[api] ?? null;
                    }

                    column.fields.push({
                        key: `${sectionKey}-${api}`,
                        meta: { ...fMeta, sectionKey },
                        value
                    });
                });

                if (column.fields.length > 0) {
                    row.columns.push(column);
                }
            });

            section.rows.push(row);
        });

        return section;
    }


    /* ====================================================
       CHANGE HANDLER
    ==================================================== */
    handleSectionFieldChange(e) {
        const { api, value, sectionKey } = e.detail;
        if (!sectionKey) return;

        /* ========================================================
        APPLICATION SECTION (Language Proficiency)
        ======================================================== */
        if (sectionKey === "application") {

            if (api === "LanguageProficiencyExams__c") {
                // store as "TOEFL;IELTS"
                this.application[api] = Array.isArray(value) ? value.join(";") : value;

                // always synced normalized array
                const arr = Array.isArray(value)
                    ? value
                    : (value ? value.split(";").map(x => x.trim()) : []);

                // ensure competitive exams are untouched
                const activeLangKeys = arr
                    .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
                    .filter(Boolean);

                // ADD missing language blocks
                activeLangKeys.forEach(key => {
                    if (!this.education[key]) {
                        this.education[key] = {};
                    }
                });

                // REMOVE unselected language exam blocks only
                Object.keys(this.education).forEach(k => {
                    if (k === "application") return;
                    if (k === "toefl" || k === "ielts") {
                        if (!activeLangKeys.includes(k)) {
                            delete this.education[k];
                        }
                    }
                });
                // sync mirror
                this.education.application = { ...this.application };

                // rerender UI
                this._buildRenderModelAll();
                this.examSections = [...this.examSections];
                return;
            }

            // OTHER application fields (like radio Yes/No)
            this.application[api] = value;
            this.education.application = { ...this.application };

            this._buildRenderModelAll();
            this.examSections = [...this.examSections];
            return;
        }

        /* ========================================================
        EXAM SECTIONS
        ======================================================== */
        this.education[sectionKey] = this.education[sectionKey] || {};
        this.education[sectionKey][api] = value;

        this._buildRenderModelAll();
        this.examSections = [...this.examSections];
    }



    /* ====================================================
       VALIDATION (required + eligibility)
    ==================================================== */
    validateAll() {
        this.eligibilityError = null;

        const sectionErrors = {};
        Object.keys(this.metadata).forEach(k => sectionErrors[k] = {});

        let failed = false;

        // Required fields
        this.examSections.forEach(sec => {
            const secKey = sec.key;
            const meta = this.metadata[secKey];

            const secData =
                secKey === "application"
                    ? this.application
                    : (this.education[secKey] || this.education[secKey]) ?? {};


            meta.fields.forEach(f => {
                const v = secData[f.api];
                if (f.required) {                    
                    if (v === null || v === '' || v === undefined) {
                        sectionErrors[secKey][f.api] = `${f?.shortLabel || f.label} is required`;
                        failed = true;
                    }
                }

                const err = this.validateFieldByType(f, v);

                if (err) {
                    sectionErrors[secKey][f.api] = err;
                    if (f.type === 'number' || f.type === 'date' || f.type === 'monthyear') {
                        sectionErrors[secKey][f.api] = '';
                    }
                    if (f.type === 'number' && err.includes('decimal')) {
                        sectionErrors[secKey][f.api] = err;
                    }
                    failed = true;
                }              

            });
        });

        // APPLY ERRORS
        const wrapper = this.template.querySelector('c-af-competitive-exam-details');
        if (wrapper) {
            Object.keys(sectionErrors).forEach(sectionKey => {
                const errorsForSection = sectionErrors[sectionKey] || {};
                wrapper.applyErrors(errorsForSection, sectionKey);
            });
        }
        
        const hasErrors = Object.values(sectionErrors)
            .some(sec => sec && Object.keys(sec).length > 0);

        if (hasErrors) {
            const errorMessage = buildErrorSummary(sectionErrors, this.metadata);
            if (errorMessage) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                }));
            }
        }

        if (failed) return false;

        const hasReq = Object.values(sectionErrors).some(sec => Object.keys(sec).length > 0);
        return !hasReq;
    }

    buildParentSavePayload(formData) {
        const out = {};

        out.application = {
            sobject: "Application__c",
            fields: {
                Id: this.application.Id,
                CompetitiveExams__c: this.application.CompetitiveExams__c,
                LanguageProficiencyExams__c: this.application.LanguageProficiencyExams__c,
                HasLanguageProficiency__c: this.application.HasLanguageProficiency__c
            }
        };

        if (!formData) return out;

        /* ============================================================
        0) Helper parsing for selected exam lists
        ============================================================ */
        const parse = v => (v || '').split(';').map(s => s.trim()).filter(Boolean);

        // Competitive exams selected
        const selectedCompetitive = parse(this.application.CompetitiveExams__c)
            .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
            .filter(Boolean);

        // Language exams selected
        const hasLang = (this.application.HasLanguageProficiency__c || '').toLowerCase() === "yes";
        const selectedLanguages = hasLang
            ? parse(this.application.LanguageProficiencyExams__c)
                .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
                .filter(Boolean)
            : [];

        // All selected exam section keys
        const selectedKeys = [...selectedCompetitive, ...selectedLanguages];


        /* ============================================================
        1) Walk all parent exam sections
        ============================================================ */
        context.parents.forEach(p => {

            const sectionKey = p.logicalName;   // e.g. "gmat", "gre", "cat"

            if (sectionKey === 'application' || sectionKey === 'personalDetails') {
                return;   // <-- skip, already handled
            }

            const block = formData[sectionKey] || {};

            // -----------------------------------------------------------------
            // CASE A: USER UNSELECTED THIS EXAM → DELETE IF RECORD EXISTS
            // -----------------------------------------------------------------
            if (!selectedKeys.includes(sectionKey)) {

                if (block.Id) {
                    // instruct Apex to delete this record
                    out[sectionKey] = {
                        delete: true,
                        id: block.Id
                    };
                }

                return; // Stop processing this exam parent entirely
            }


            /* ============================================================
            CASE B: EXAM IS SELECTED → BUILD SAVE/UPDATE PAYLOAD
            ============================================================ */
            const metaFields =
                (this.metadataCompetitive?.[sectionKey]?.fields) ||
                (this.metadata[sectionKey]?.fields) || [];

            const clean = {};


            // ------------------------------------------------------------
            // Copy + normalize only the allowed fields for this SObject
            // ------------------------------------------------------------
            p.fieldsToQuery.forEach(api => {
                const rawVal = block[api];
                const fieldMeta = metaFields.find(f => f.api === api);

                clean[api] = this._normalizeValue(api, rawVal, fieldMeta);
            });

            if (sectionKey === 'cat') {
                const usePrimaryEmail = clean.Is_your_primary_email_ID_same_as_CAT_exa__c === 'Yes';
                if (usePrimaryEmail) {
                    clean.CAT_E_Mail__c = formData?.personalDetails?.Primary_E_mail__c ?? null;
                }
            }

            // Always set Exam_Name__c
            clean.Exam_Name__c = p.recordName;


            /* ============================================================
            CASE B.1: If Selected but (empty & no Id) → skip (no insert)
            ============================================================ */
            const hasData = Object.keys(clean).some(api => {
                if (api === 'Id') return false;
                const v = clean[api];
                return v !== null && v !== undefined && v !== '';
            });

            if (!hasData && !clean.Id) {
                // User selected exam but did not enter anything → no record needed
                return;
            }


            /* ============================================================
            CASE B.2: SAVE / UPDATE selected exam
            ============================================================ */
            out[sectionKey] = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: clean
            };
        });

        return out;
    }


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


    /* ====================================================
       SAVE FORM
    ==================================================== */
    @api async saveForm() {
        if(this.isReadOnly) return true;

        if(this.application.HasLanguageProficiency__c === 'No') {
            this.application.LanguageProficiencyExams__c = '';
        }

        this.isLoading = true;
        if (!this.validateAll()) {
            this.template.querySelector('c-af-competitive-exam-details').reportValidity();
            this.isLoading = false;
            return false;
        }

        const payload = this.buildParentSavePayload(this.education);

        try {
            await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify(payload)
            });

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Entrance Exam' 
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Saved successfully',
                variant: 'success',
            }));

            // Optional: refresh
            await this.fetchForm(this.application.Id);

            return true;
        } catch (error) {
            console.error("save error", error);
            this.dispatchEvent(new ShowToastEvent({
                title: "Save failed",
                message: "Please try again",
                variant: "error"
            }));
            return false;
        } finally {
            this.isLoading = false;
        }

    }

}