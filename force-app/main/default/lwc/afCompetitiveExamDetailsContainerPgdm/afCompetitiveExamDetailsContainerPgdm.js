import { LightningElement, api, track } from 'lwc';
import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';

import deleteDocumentsByCode from '@salesforce/apex/ApFormDataController.deleteDocumentsByCode';

import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import { buildErrorSummary, validateMinMaxDate, validateNumber, isFieldVisible } from "c/applicationFormService";

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
    cat: {
        score: {
            field: 'CAT_Overall_Score__c',
            min: 80,
            max: 198,
            eligibility: false
        },
        percentile: {
            field: 'CAT_Overall_Percentile__c',
            min: 0,
            max: 100,
            eligibility: true
        },
        year: {
            field: 'CAT_Year_of_Exam__c',
            min: 2023,
            max: 2025,
            eligibility: true
        }
    },

    gmat: {
        score: {
            field: 'GMAT_Total_Score__c',
            min: 550,
            max: 800,
            eligibility: false
        },
        percentile: {
            field: 'GMAT_Total_Percentile__c',
            min: 0,
            max: 100,
            eligibility: true
        },
        date: {
            field: 'Test_Date__c',
            min: new Date('2021-09-30'),
            max: new Date('2026-09-30'),
            eligibility: true
        },
        scoreIssueDate: {
            field: 'GMAT_Score_Issue_Date__c',
            min: new Date('2021-09-30'),
            max: new Date('2026-09-30'),
            eligibility: true
        }
    },

    gmatFocus: {
        score: {
            field: 'GMAT_Focus_Edition_Total_Score__c',
            min: 525,
            max: 805,
            eligibility: false
        },
        percentile: {
            field: 'GMAT_Focus_Edition_Total_Percentile__c',
            min: 0,
            max: 100,
            eligibility: true
        },
        date: {
            field: 'GMAT_Focus_Edition_Test_Date__c',
            min: new Date('2021-09-30'),
            max: new Date('2026-09-30'),
            eligibility: true
        },
        scoreIssueDate: {
            field: 'GMAT_Focus_Edition_Score_Issue_Date__c',
            min: new Date('2021-09-30'),
            max: new Date('2026-09-30'),
            eligibility: true
        }
    }
};

const ELIGIBILITY_ERROR =
    'You do not meet the eligibility criteria, contact 9820866719 / 9820618910';

const EXAM_KEY_MAP = {
    'CAT': 'cat',
    'GMAT': 'gmat',
    'GMAT Focus': 'gmatFocus'
};

const DOCUMENT_CONFIG = {
    cat: [
        {
            label: 'CAT Score Card',
            code: 'DOC_CAT_SCORE_CARD'
        }
    ],
    gmat: [
        {
            label: 'GMAT Score Card',
            code: 'DOC_GMAT_SCORE_CARD'
        }
    ],
    gmatFocus: [
        {
            label: 'GMAT Focus Score Card',
            code: 'DOC_GMAT_FOCUS_SCORE_CARD'
        }
    ]
};

export default class AfCompetitiveExamDetailsContainerPgdm extends LightningElement {

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
            application: this.application,
            applicationId: this.application?.Id
        };
    }

    picklistCache = {};
    dependentCache = {};

    async connectedCallback() {

        // construct safely
        this.recordToLogical = {};
        this.education.documentUpload = {};

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

    _buildDynamicDocumentMetadata() {

        const fields = [];
        const rows = [];
        const rowColumns = [];

        const selectedExams =
            this.education?.application?.CompetitiveExams__c || [];

        const exams = Array.isArray(selectedExams)
            ? selectedExams
            : selectedExams.split(';').filter(Boolean);

        exams.forEach(exam => {

            const examKey = EXAM_KEY_MAP[exam];
            const docs = DOCUMENT_CONFIG[examKey] || [];

            docs.forEach(doc => {

                const fieldMeta = {
                    api: doc.code,
                    type: 'file',
                    label: doc.label,
                    docCode: doc.code,
                    maxFiles: 1,
                    accept: ['.png', '.jpg', '.jpeg', '.pdf'],
                    required: true,
                    readOnly: this.isReadOnly,
                    visibleWhen: {
                        [`${examKey}.Result_Status__c`]: 'Declared'
                    }
                };

                fields.push(fieldMeta);

                rowColumns.push({
                    width: 6,
                    fields: [doc.code]
                });
            });
        });

        // 4 fields per row (12-column layout)
        for (let i = 0; i < rowColumns.length; i += 2) {
            rows.push({
                columns: rowColumns.slice(i, i + 2)
            });
        }

        this.metadata.documentUpload = {
            key: 'documentUpload',
            title: 'Document Upload',
            columnSystem: 12,
            rows,
            fields
        };

        console.log(
            'documentUpload metadata',
            JSON.stringify(this.metadata.documentUpload)
        );
    }

    // inject picklists from picklistCache into metadata fields
    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr => (arr || []).map(x => ({ label: x.label || x.Label || x, value: x.value || x.Value || x }));
        const setOptions = (sectionKey, api, options) => {
            const f = (this.metadata[sectionKey].fields || []).find(x => x.api.toLowerCase() === api.toLowerCase());
            if (f) f.options = options;
        };

        const { min, max } = EXAM_RULES.cat.year;

        setOptions('cat', 'CAT_Year_of_Exam__c', toOptions(
            pick?.CAT_Year_of_Exam__c.filter(y => {
                const year = Number(y.value);
                return year >= min && year <= max;
            })
        ));

        setOptions('cat','Result_Status__c', toOptions(pick?.Result_Status__c));
        setOptions('gmat','Result_Status__c', toOptions(pick?.Result_Status__c));
        setOptions('gmatFocus','Result_Status__c', toOptions(pick?.Result_Status__c));       

    }


    recordToLogical = {};

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfCompetitiveExamDetailsContainerPgdm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfCompetitiveExamDetailsContainerPgdm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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
            this.originalCompetitiveExams = [
                ...(Array.isArray(selectedExams)
                    ? selectedExams
                    : selectedExams.split(';').filter(Boolean))
            ];

            let examKeys = [
                ...selectedExams.map(ex => this.recordToLogical[ex?.toUpperCase?.()]),
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

            examKeys = [
                ...selectedExams.map(ex => this.recordToLogical[ex?.toUpperCase?.()]),
            ].filter(Boolean);


            /* ============================================================
            5) BUILD RENDER MODEL
            ============================================================ */
            this._buildDynamicDocumentMetadata();
            this._applyReadOnlyMode();
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

        const examKeys = [
            ...selectedExams.map(ex => this.recordToLogical[ex?.toUpperCase?.()]),
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

        const EXAM_ORDER = {
            cat: 1,
            gmat: 2,
            gmatFocus: 3
        };

        // 1) competitive exams → convert to logicalName
        const selectedExams = parse(this.application.CompetitiveExams__c)
            .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
            .filter(Boolean).sort((a, b) => EXAM_ORDER[a] - EXAM_ORDER[b]);

        const sections = [];

        if (this.metadata.topInstruct) {
            sections.push(this._buildSectionRenderModel("topInstruct"));
        }
        
        // Application section
        sections.push(this._buildSectionRenderModel("application"));

        // Competitive exams first
        selectedExams.forEach(k => {
            if (this.metadata[k]) {
                sections.push(this._buildSectionRenderModel(k));
            }
        });      

        if (this.metadata.documentUpload?.fields?.length) {
            sections.push(
                this._buildSectionRenderModel('documentUpload')
            );
        }

        console.log('sections '+JSON.stringify(sections));
        //if(this.CHANGE_HAPPENING) return;
        this.examSections = sections;

        console.log('application', this.application?.CompetitiveExams__c);
        console.log('education application', this.education?.application?.CompetitiveExams__c);
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
<div style="background:#f3f3f3; padding:16px; border-radius:4px;">

    <div>
        <p>The form can be submitted without the scores, provided you have entered your exam registration number carefully. You may not have your CAT/GMAT scores by the time you submit the form, hence that is not expected. The submitted application form will be made available again for applicants to update their entrance exam scores after the CAT results are declared.</p>

        <p>In case you have already taken the GMAT exam please enter the details as per below:</p>

        <ul style="list-style-type: disc; list-style-position: outside; display:inline-block; text-align:left; margin-top:8px; padding-left:30px;">
            <li>Enter complete scores exactly as per your scorecard.</li>
            <li>Ensure to upload the scorecard in addition to entering your scores.</li>
            <li>If a downloadable scorecard is not available, please upload a screenshot of your scores.</li>
            <li>If a screenshot is uploaded, ensure that the screenshot has details of your appointment ID, GMAT ID and Name along with your score. You may club multiple screenshots and upload as a single PDF document.</li>
            <li>It is mandatory to submit your GMAT scores through GMAC for the exams taken. Please use the code provided below to send your scores:
                <br>- PGDM Programme code - 6DQ-MJ-98 or search by name "S.P. Jain Institute of management and research - Post graduate Diploma in Management"
                <br>- PGDM (BM) Programme code - 6DQ-MJ-68 or search by name "S. P. Jain Institute of Management and Research – PGDM (Business Management)"
            </li>
            <li>For both GMAT and the Focus Edition scores are accepted, provided the exam is taken at a test centre. GMAT Online scores are not accepted.</li>
            <li>The GMAT scores will be considered only if the exam is taken between Jan 01, 2023 till Dec 10, 2025 for GMAT and Nov 2023 till Dec 10, 2025 for GMAT Focus Edition</li>
        </ul>
    </div>

</div>
            `
            },
            rows: [],
            fields: [
                { api: 'SECTION_NOTE', type: 'note' }
            ]
        };

        this.metadata.application = {
            key: "application",
            title: "Entrance Examination Details",
            columnSystem: 12,
            rows: [
                { columns: [{ width: 12, fields: ["CompetitiveExams__c"] }] },
            ],

            fields: [
                {
                    api: "CompetitiveExams__c",
                    type: "multipicklist",
                    label: "Select Exam(s)",
                    required: true,
                    options: [
                        { label: "CAT", value: "CAT" },
                        { label: "GMAT", value: "GMAT" },
                        { label: "GMAT Focus", value: "GMAT Focus" },
                    ],
                },

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
                    {width:3,fields:['CAT_Year_of_Exam__c']},
                    {width:3,fields:['CAT_Registration_Number__c']},
                    {width:3,fields:['Result_Status__c'] },
                    {width:3,fields:['CAT_Overall_Score__c']},                   
                ]},
                { columns:[
                    {width:3,fields:['CAT_Overall_Percentile__c']},
                    {width:3,fields:['CatVerbalReadingComprehensionScore__c']},
                    {width:3,fields:['CatVerbalReadingComprehensionPercentile__c']},
                    {width:3,fields:['Data_interpretation_and_logical_re_score__c']},
                ]},
                { columns:[
                    {width:3,fields:['Data_interpretation_and_logical_re_perce__c']},
                    {width:3,fields:['CAT_Quantitative_Aptitude__c']},
                    {width:3,fields:['CAT_Quantitative_Aptitude_Percentile__c']},
                ]},
                { columns:[
                    {width:3,fields:['Is_your_primary_email_ID_same_as_CAT_exa__c']},
                    {width:3,fields:['CAT_E_Mail__c']},
                ]}
            ],

            fields:[
                { api:'CAT_NOTE', type:'note' },
                { api:'CAT_Year_of_Exam__c', type:'picklist', label:'Year of Exam', required:true, max: new Date().getFullYear(), min: 2022 },
                { api:'CAT_Registration_Number__c', type:'text', label:'Registration Number', required:true, maxlength: '255' },
                {
                    api:'Result_Status__c',
                    type:'picklist',
                    label:'Result Status',
                    required:true
                },
                { api:'CAT_Overall_Score__c', step: "0.01", max:"999", type:'number', label:'Overall score', requiredWhen: {'cat.Result_Status__c': 'Declared'}  },
                { api:'CAT_Overall_Percentile__c', step: "0.01", max:"999", type:'number', label:'Overall Percentile', requiredWhen: {'cat.Result_Status__c': 'Declared'} },
                { api:'CatVerbalReadingComprehensionScore__c', step: "0.01", max:"999", type:'number', label:'Verbal ability and reading comprehension score', requiredWhen: {'cat.Result_Status__c': 'Declared'} },
                { api:'CatVerbalReadingComprehensionPercentile__c', step: "0.01", max:"999", type:'number', label:'Verbal ability and reading comprehension percentile', requiredWhen: {'cat.Result_Status__c': 'Declared'} },
                { api:'Data_interpretation_and_logical_re_score__c', step: "0.01", max:"999", type:'number', label:'Data interpretation and logical reasoning score', requiredWhen: {'cat.Result_Status__c': 'Declared'} },
                { api:'Data_interpretation_and_logical_re_perce__c', step: "0.01", max:"999", type:'number', label:'Data interpretation and logical reasoning percentile', requiredWhen: {'cat.Result_Status__c': 'Declared'} },
                { api:'CAT_Quantitative_Aptitude__c', step: "0.01", max:"999", type:'number', label:'Quantitative ability score', requiredWhen: {'cat.Result_Status__c': 'Declared'}, },
                { api:'CAT_Quantitative_Aptitude_Percentile__c', step: "0.01", max:"999", type:'number', label:'Quantitative ability percentile', requiredWhen: {'cat.Result_Status__c': 'Declared'}, },
                { api:'Is_your_primary_email_ID_same_as_CAT_exa__c', type:'radio', label:'Is your primary email same as CAT exam email?',
                    options:[
                        {label:'Yes',value:'Yes'},
                        {label:'No',value:'No'}
                    ]
                },
                { api:'CAT_E_Mail__c', type:'email', label:'CAT Email', maxlength: '80', visibleWhen: { 'cat.Is_your_primary_email_ID_same_as_CAT_exa__c': 'No' } },
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
                    { width:3, fields:['GMAT_Appointment_No__c']},
                    { width:3, fields:['Test_Date__c'] },
                    { width:3, fields:['Result_Status__c'] },

                ]},
                { columns: [
                    { width:3, fields:['GMAT_Score_Issue_Date__c']},
                    { width:3, fields:['GMAT_Total_Score__c'] },
                    { width:3, fields:['GMAT_Total_Percentile__c'] },
                    { width:3, fields:['Quantitative_Score__c'] },
                ]},
                { columns: [
                    { width:3, fields:['Quantitative_Percentile__c'] }, // change type
                    { width:3, fields:['Verbal_Score__c'] }, 
                    { width:3, fields:['Verbal_Percentile__c'] }, // change type
                ]},
            ],
            fields: [
                { api:'GMAT_NOTE', type:'note' },
                { api:'GMAT_ID__c', type:'text', label:'GMAT ID', required:true, maxlength: '255' },
                { api:'GMAT_Appointment_No__c', type:'text', label:'Appointment Number', required:true, maxlength: '255' },
                { api:'Test_Date__c', type:'date', label:'Test Date', required:true, max:new Date().toISOString().split('T')[0], min:"2020-01-01" },
                {
                    api:'Result_Status__c',
                    type:'picklist',
                    label:'Result Status',
                    required:true
                },
                { api:'GMAT_Score_Issue_Date__c', type:'date', label:'GMAT Score Issue Date ', requiredWhen: {'gmat.Result_Status__c': 'Declared'}, max:new Date().toISOString().split('T')[0], min:"2020-01-01" },
                { api:'GMAT_Total_Score__c', type:'number', step: "0.01", max:"999", label:'Overall Score', requiredWhen: {'gmat.Result_Status__c': 'Declared'} },
                { api:'GMAT_Total_Percentile__c', type:'number', step: "0.01", max:"999", label:'Overall Percentile', requiredWhen: {'gmat.Result_Status__c': 'Declared'}  },
                { api:'Quantitative_Score__c', type:'number', step: "0.01", max:"999", label:'Quantitative Score', requiredWhen: {'gmat.Result_Status__c': 'Declared'} },
                { api:'Quantitative_Percentile__c', type:'number', step: "0.01", max:"999", label:'Quantitative Percentile', requiredWhen: {'gmat.Result_Status__c': 'Declared'} },
                { api:'Verbal_Score__c', type:'number', step: "0.01", max:"999", label:'Verbal Score', requiredWhen: {'gmat.Result_Status__c': 'Declared'} },
                { api:'Verbal_Percentile__c', type:'number', step: "0.01", max:"999", label:'Verbal Percentile',requiredWhen: {'gmat.Result_Status__c': 'Declared'} },
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
                    {width:3,fields:['GMAT_FOCUS_ID_Appointment_Number__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Test_Date__c']},
                    {width:3,fields:['Result_Status__c'] },
                ]},
                { columns:[
                    {width:3,fields:['GMAT_Focus_Edition_Score_Issue_Date__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Total_Score__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Total_Percentile__c']},// change field
                    {width:3,fields:['GMAT_Focus_Edition_Quantitative_Reasonin__c']},
                ]},
                { columns:[
                    {width:3,fields:['GMAT_FE_Quantitative_Reasoning_Perce__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Verbal_Reasoning__c']},
                    {width:3,fields:['GMAT_FE_Verbal_Reasoning_Perce__c']},
                    {width:3,fields:['GMAT_Focus_Edition_Data_Insights__c']},
                ]},
                { columns:[
                    {width:3,fields:['GMAT_FE_Data_Insights_Percentile__c']},
                ]}
            ],

            fields:[
                { api:'GMAT_FOCUS_NOTE', type:'note' },
                { api:'GMAT_FOCUS_ID__c', type:'text', label:'GMAT Focus ID', required:true, maxlength: '255' },
                { api:'GMAT_FOCUS_ID_Appointment_Number__c', type:'text', label:'Appointment Number', required:true, maxlength: '255' },
                { api:'GMAT_Focus_Edition_Test_Date__c', type:'date', label:'Test Date', required:true, max:new Date().toISOString().split('T')[0], min:"2020-01-01" },
                {
                    api:'Result_Status__c',
                    type:'picklist',
                    label:'Result Status',
                    required:true
                },
                { api:'GMAT_Focus_Edition_Score_Issue_Date__c', type:'date', label:'GMAT Score Issue Date', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, max:new Date().toISOString().split('T')[0], min:"2020-01-01" },
                { api:'GMAT_Focus_Edition_Total_Score__c', step: "0.01", max:"999", type:'number', label:'Overall Score', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_Focus_Edition_Total_Percentile__c', step: "0.01", max:"999", type:'number', label:'Overall Percentile', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_Focus_Edition_Quantitative_Reasonin__c', step: "0.01", max:"999", type:'number', label:'Quantitative Score', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_FE_Quantitative_Reasoning_Perce__c', step: "0.01", max:"999", type:'number', label:'Quantitative Percentile', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_Focus_Edition_Verbal_Reasoning__c', step: "0.01", max:"999", type:'number', label:'Verbal Score', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_FE_Verbal_Reasoning_Perce__c', step: "0.01", max:"999", type:'number', label:'Verbal Percentile', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_Focus_Edition_Data_Insights__c', step: "0.01", max:"999", type:'number', label:'Data Score', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
                { api:'GMAT_FE_Data_Insights_Percentile__c', step: "0.01", max:"999", type:'number', label:'Data Percentile', requiredWhen: {'gmatFocus.Result_Status__c': 'Declared'}, },
            ]
        };

        this.metadata.documentUpload = {
            key: "documentUpload",
            title: "Document Upload",
            columnSystem: 12,

            rows: [
            ],

            fields: [
            ]
        }

    }

    _applyExamRulesToMetadata() {


        const applyEligibilityMessages = (field, rule, defaultMaxMessage) => {
                field.messageWhenRangeUnderflow = rule?.eligibility
                    ? ELIGIBILITY_ERROR
                    : `${field.label} should be at least ${field.min}`;

                field.messageWhenRangeOverflow =
                    defaultMaxMessage ||
                    `${field.label} should not exceed ${field.max}`;
        };

        const formatLocalDate = (d) => {
            const year = d.getFullYear();
            const month = String(d.getMonth() + 1).padStart(2, '0');
            const day = String(d.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        };

        Object.keys(EXAM_RULES).forEach(sectionKey => {
            const rules = EXAM_RULES[sectionKey];
            const meta = this.metadata[sectionKey];
            if (!meta) return;

            meta.fields.forEach(f => {

                // SCORE
                if (rules.score && f.api === rules.score.field) {
                    f.min = rules.score.eligibility
                        ? rules.score.min
                        : 0;

                    if(rules.score.eligibility){
                        f.max = rules.score.max;
                    }

                    applyEligibilityMessages(
                        f,
                        rules.score,
                        `${meta.title} should not exceed ${f.max}`
                    );

                    f.skipOnChangeValidation = true;
                    f.eligibility = !!rules.score?.eligibility;
                }

                // DATE / MONTHYEAR
                if (rules.date && f.api === rules.date.field) {

                    let min = new Date(rules.date.min);
                    let max = new Date(rules.date.max);

                    // ✅ Only for monthyear fields
                    if (f.type === 'monthyear') {
                        min.setDate(1);
                        max.setDate(1);
                    }

                    f.min = formatLocalDate(min);
                    f.max = formatLocalDate(max);

                    if (rules.date.eligibility) {
                        f.eligibility = true;
                    }
                }

                // YEAR (picklist → still JS validated)
                if (rules.year && f.api === rules.year.field) {
                    f.min = rules.year.min;
                    f.max = rules.year.max;

                    if (rules.year.eligibility) {
                        f.eligibility = true;
                    }
                }

                if (rules.percentile && f.api === rules.percentile.field) {

                    f.min = rules.percentile.eligibility
                        ? rules.percentile.min
                        : 0;

                    f.max = rules.percentile.eligibility
                        ? rules.percentile.max
                        : 100;

                    applyEligibilityMessages(
                        f,
                        rules.percentile,
                        `${f.label} should not exceed ${f.max}`
                    );

                    f.skipOnChangeValidation = true;
                    f.eligibility = !!rules.percentile?.eligibility;
                }

                if (
                    rules.scoreIssueDate &&
                    f.api === rules.scoreIssueDate.field
                ) {

                    let min = new Date(rules.scoreIssueDate.min);
                    let max = new Date(rules.scoreIssueDate.max);

                    f.min = formatLocalDate(min);
                    f.max = formatLocalDate(max);

                    if (rules.scoreIssueDate.eligibility) {
                        f.eligibility = true;
                    }
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

                if (err.includes('decimal')) {
                    return err;
                }

                if (f.eligibility) {
                    return ELIGIBILITY_ERROR;
                }

                return err;
            }
        }

        // DATE + MONTHYEAR
        if (f.type === 'date' || f.type === 'monthyear') {
            const d = new Date(value);
            if (
                isNaN(d.getTime()) ||
                d.getFullYear() < 2000
            ) {
                return 'Enter a valid date';
            }
            const err = validateMinMaxDate(f, value);

            if (err) {
                return f.eligibility
                    ? ELIGIBILITY_ERROR
                    : err;
            }

            return null;
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

                    const resolvedMeta = {
                        ...fMeta,
                        sectionKey
                    };

                    resolvedMeta.required =
                        this._computeFieldRequired(
                            resolvedMeta,
                            sectionKey
                        );

                    // single 'value' variable only — no shadowing
                    let value = null;

                    /* APPLICATION SECTION: read from this.application */
                    if (sectionKey === "application") {
                        if (api === "CompetitiveExams__c") {
                            const raw = this.application.CompetitiveExams__c || '';
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

                    if (!isFieldVisible(fMeta, this.education)) {
                        return;
                    }

                    column.fields.push({
                        key: `${sectionKey}-${api}`,
                        meta: resolvedMeta,
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

    CHANGE_HAPPENING = false;

    /* ====================================================
       CHANGE HANDLER
    ==================================================== */
    async handleSectionFieldChange(e) {
        this.CHANGE_HAPPENING = true;
        const { api, value, sectionKey } = e.detail;
        if (!sectionKey) return;

        /* ========================================================
        APPLICATION SECTION (Exams)
        ======================================================== */
        if (sectionKey === "application") {

            if (api === "CompetitiveExams__c") {

                const previousExamKeys = Object.keys(this.education).filter(
                    k => k === 'cat' || k === 'gmat' || k === 'gmatFocus'
                );

                // store as "CAT;GMAT;GMAT Focus"
                this.application[api] = Array.isArray(value) ? value.join(";") : value;

                // always synced normalized array
                const arr = Array.isArray(value)
                    ? value
                    : (value ? value.split(";").map(x => x.trim()) : []);

                // ensure competitive exams are untouched
                const activeExamKeys = arr
                    .map(ex => this.recordToLogical[ex?.toUpperCase?.()])
                    .filter(Boolean);

                const removedExamKeys = previousExamKeys.filter(
                    key => !activeExamKeys.includes(key)
                );

                const addedExamKeys = activeExamKeys.filter(
                    key => !previousExamKeys.includes(key)
                );

                this.cleanupDocuments(removedExamKeys);
                this.removeCleanupDocuments(addedExamKeys);

                addedExamKeys.forEach(key => {
                    this.syncDocumentCleanupForSection(key);
                });

                // ADD missing exam blocks
                activeExamKeys.forEach(key => {
                    if (!this.education[key]) {
                        this.education[key] = {};
                    }
                });

                // REMOVE unselected exam exam blocks only
                Object.keys(this.education).forEach(k => {
                    if (k === "application") return;
                    if (k === "cat" || k === "gmat" || k === "gmatFocus") {
                        if (!activeExamKeys.includes(k)) {
                            delete this.education[k];
                        }
                    }
                });
                // sync mirror
                this.education.application = { ...this.application };

                // rerender UI
                this._buildDynamicDocumentMetadata();
                this._buildRenderModelAll();
                this.examSections = [...this.examSections];
                return;
            }

            // OTHER application fields (like radio Yes/No)
            this.application[api] = value;
            this.education.application = { ...this.application };

            this._buildDynamicDocumentMetadata();
            this._buildRenderModelAll();
            this.examSections = [...this.examSections];
            return;
        }
        
        /* ========================================================
        EXAM SECTIONS
        ======================================================== */
        this.education[sectionKey] = this.education[sectionKey] || {};
        this.education[sectionKey][api] = value;

        if (
            api === 'Result_Status__c'
        ) {

            this.syncDocumentCleanupForSection(sectionKey);
        }

        this._buildDynamicDocumentMetadata();
        
        this._buildRenderModelAll();
        this.examSections = [...this.examSections];
    }

    pendingDocumentCleanup = new Set();

    cleanupDocumentsForHiddenUploads(sectionKey) {

        const section = this.education?.[sectionKey];

        if (!section) {
            return [];
        }

        const documentCodes = [];

        if (sectionKey === 'gmat') {

            if (section.Result_Status__c !== 'Declared') {
                documentCodes.push('DOC_GMAT_SCORE_CARD');
            }

            return documentCodes;
        }

        return (DOCUMENT_CONFIG[sectionKey] || [])
            .filter(() => section.Result_Status__c !== 'Declared')
            .map(doc => doc.code);
    }

    removeCleanupDocuments(examKeys) {

        const documentCodes = examKeys.flatMap(
            examKey => (DOCUMENT_CONFIG[examKey] || []).map(doc => doc.code)
        );

        documentCodes.forEach(code => {
            this.pendingDocumentCleanup.delete(code);
        });
    }

    cleanupDocuments(examKeys) {

        const documentCodes = examKeys.flatMap(
            examKey => (DOCUMENT_CONFIG[examKey] || []).map(doc => doc.code)
        );

        documentCodes.forEach(code => {
            this.pendingDocumentCleanup.add(code);
        });
    }

    syncDocumentCleanupForSection(sectionKey) {

        if (!DOCUMENT_CONFIG[sectionKey]) {
            return;
        }

        const hiddenCodes =
            this.cleanupDocumentsForHiddenUploads(sectionKey);

        const allCodes =
            (DOCUMENT_CONFIG[sectionKey] || []).map(d => d.code);

        hiddenCodes.forEach(code =>
            this.pendingDocumentCleanup.add(code)
        );

        allCodes
            .filter(code => !hiddenCodes.includes(code))
            .forEach(code =>
                this.pendingDocumentCleanup.delete(code)
            );
    }

    handleDocsFetched(event) {
        const { documentId, files, api, sectionKey } = event.detail;

        // Ensure section exists
        if (!this.education[sectionKey]) {
            this.education[sectionKey] = {};
        }

        // Assign the ContentDocumentId into the correct field
        this.education[sectionKey][api] = files?.length > 0 ? documentId : undefined;

        this.education[sectionKey].fileInfo ||= {}
        this.education[sectionKey].fileInfo[api] = {fileLength: files?.length, files: files};

    }

    _computeFieldRequired(fieldMeta, sectionKey = fieldMeta?.sectionKey, sequence = fieldMeta?.sequence) {
        const baseRequired = !!fieldMeta?.required;
        if (!fieldMeta?.requiredWhen) {
            return baseRequired;
        }

        return baseRequired ||
            this._conditionsMatchForField(
                fieldMeta.requiredWhen,
                sectionKey,
                sequence
            );
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

    _resolveFieldConditionValue(path) {

        const [section, field] = path.split('.');

        return this.education?.[section]?.[field];
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

                const isRequired =
                    this._computeFieldRequired(
                        f,
                        secKey
                    );

                if (isFieldVisible(f, this.education) && isRequired) {                    
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

        const docMeta = this.metadata.documentUpload;

        if (docMeta?.fields?.length) {

            sectionErrors.documentUpload = {};

            docMeta.fields.forEach(f => {

                if (!isFieldVisible(f, this.education)) {
                    return;
                }

                const fileLength =
                    this.education?.documentUpload?.fileInfo?.[f.api]?.fileLength ?? 0;

                if (f.required && fileLength === 0) {
                    sectionErrors.documentUpload[f.api] =
                        `${f?.shortLabel || f.label} is required`;

                    failed = true;
                }

                const maxAllowed = Number(f.maxFiles || 0);

                if (maxAllowed > 0 && fileLength > maxAllowed) {
                    sectionErrors.documentUpload[f.api] =
                        `${f?.shortLabel || f.label} cannot exceed ${maxAllowed} files`;

                    failed = true;
                }
            });
        }

        // APPLY ERRORS
        const wrapper = this.template.querySelector('c-af-section-engine');
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

        // All selected exam section keys
        const selectedKeys = [...selectedCompetitive];


        /* ============================================================
        1) Walk all parent exam sections
        ============================================================ */
        context.parents.forEach(p => {

            const sectionKey = p.logicalName;   // e.g. "gmat", "cat"

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
                const usePrimaryEmail =
                    clean.Is_your_primary_email_ID_same_as_CAT_exa__c === 'Yes';

                if (usePrimaryEmail) {
                    clean.CAT_E_Mail__c =
                        formData?.personalDetails?.Primary_E_mail__c ?? null;
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

        this.isLoading = true;

        if (!this.validateAll()) {
            this.template.querySelector('c-af-section-engine').reportValidity();
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

            const documentCodes = [
                ...this.pendingDocumentCleanup
            ];

            if (documentCodes.length) {

                await deleteDocumentsByCode({
                    applicationId: this.application.Id,
                    documentCodes
                });

                this.pendingDocumentCleanup.clear();
            }

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