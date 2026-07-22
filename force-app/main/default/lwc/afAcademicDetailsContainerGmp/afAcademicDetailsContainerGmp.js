import { LightningElement, track, api } from 'lwc';
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import updateStage from '@salesforce/apex/ApFormDataController.updateStage';
import getRecordTypesByName from '@salesforce/apex/AcademicFormController.getRecordTypesByName';
import { validateNumber } from "c/applicationFormService";


import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class AfAcademicDetailsContainerGmp  extends LightningElement {

    isLoading = true; // Start spinner immediately
    isInitialRender = true;   // Guard variable

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

    get contextBlock() {
        return {
            ...this.education,
            otherResources: {
                showUgUniversity: this.showUgUniversity,
                showUgCollege: this.showUgCollege,
                showPgUniversity: this.showPgUniversity,
                showPgCollege: this.showPgCollege,
                showOtherUgUniversity:this.showOtherUgUniversity,
                showOtherUgCollege:this.showOtherUgCollege,
                showOtherPgUniversity:this.showOtherPgUniversity,
                showOtherPgCollege:this.showOtherPgCollege
            }
        };
    }


    @track education = {
        tenth: {},
        twelfth: {},
        diploma: {},
        graduation: {},
        graduationDetails: {},
        haveAcademicBreak: {},
        after10: {},
        semester: {},
        havePostGrad : {},
        postGraduation: {},
        postGraduationDetails: {},
        postSemester: {},
        haveProfessionalQualification: {},
        professionalQualification: {}, // sequential 1..3 rows
        extraCurricular: {},
        importantCertification: {},
        publications: {},
    };

    // renderModel sections split for academic (10th/12th/diploma) and graduation
    @track academicSections = []; // array of section renderModels
    @track graduationSections = []; // array of section renderModels
    @track postGraduationSections = [];
    @track professionalQualification = [];
    @track academicDetailsFooterSections = [];

    // metadata (source) - stored internally
    metadata = {};
    picklistCache = {};
    dependentCache = {};

    async connectedCallback() {
        this._buildMetadataSkeleton();

        try {
            const data = await getAllPicklistsForObjects({
                objectApiNames:['Academic_Detail__c','BasicAcademicDetail__c']
            });

            // Support multiple returned bundles (one per object)
            // Merge defaultSet/recordTypeSet so resolveOptions can see all fields
            const merged = { defaultSet:{}, recordTypeSet:{} };
            if (Array.isArray(data)) {
                data.forEach(b => {
                    if (!b) return;
                    // merge defaultSet
                    if (b.defaultSet) {
                        Object.entries(b.defaultSet).forEach(([api, cfg]) => {
                            merged.defaultSet[api] = cfg;
                        });
                    }
                    // merge recordTypeSet
                    if (b.recordTypeSet) {
                        Object.entries(b.recordTypeSet).forEach(([rtId, fields]) => {
                            merged.recordTypeSet[rtId] = merged.recordTypeSet[rtId] || {};
                            Object.entries(fields || {}).forEach(([api, cfg]) => {
                                merged.recordTypeSet[rtId][api] = cfg;
                            });
                        });
                    }
                });
            }

            if (Object.keys(merged.defaultSet).length > 0 || Object.keys(merged.recordTypeSet).length > 0) {
                this.picklistCache = merged;   // ⭐ merged structure for both Academic_Detail__c and BasicAcademicDetail__c
                this.dependentCache = {};

                Object.entries(merged.defaultSet || {}).forEach(([api, fieldSet]) => {
                    if (fieldSet && fieldSet.dependent && fieldSet.controllingFieldApiName) {
                        this.dependentCache[api] = {
                            controllingField: fieldSet.controllingFieldApiName,
                            options: fieldSet.options
                        };
                    }
                });
            }

            await this._loadRecordTypes();   // ✅ NOW VALID
            this._injectPicklists();
            this._buildRenderModelAll();
            await this.fetchForm();
        } catch (err) {
            console.warn('picklist load failed', err);
            this._injectPicklists();
            this._buildRenderModelAll();
        } finally {
             this.isLoading = false;
        }
    }


    needPostGradSemYearWise = false;

    // Build metadata skeleton and default columnSystem per section
    _buildMetadataSkeleton() {
        this.metadata = {};

        // per-section columnSystem recommended values
        const cs = {
            tenth:12, after10:12, twelfth:12, diploma:17, graduation:12, graduationDetails:15, semester:30, havePostGrad:15, postGraduation:12, postGraduationDetails:15, postSemester:30
        };

        // Tenth
        this.metadata.tenth = {
            key: 'tenth',
            title: '10th Academic Details',
            columnSystem: cs.tenth,
            rows: [
                { columns: [ { width:3, fields:['School_Institute__c'] }, { width:3, fields:['Board_University__c'] }, { width:3, fields:['MonthAndYearOfPassing__c'] }, { width:2, fields:['Marking_Scheme__c'] }, ] },
                { columns: [ { width:2, fields:['Percentage__c'] }, { width:2, fields:['Maximum_Marks__c'] }, { width:2, fields:['Obtained_Marks__c'] }, { width:2, fields:['Conversion_Factor__c'] }, { width:2, fields:[] } ] }
            ],
            fields: [
                { api:'Board_University__c', type:'text', label:'Board/University', required:true, maxlength: '255' },
                { api:'School_Institute__c', type:'text', label:'School/Institute', required:true, maxlength: '255' },
                // { api:'MonthAndYearOfCommencement__c', type:'monthyear', min:"2005-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true},
                { api:'MonthAndYearOfPassing__c', type:'monthyear', min:"2005-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Passing', required:true},
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme', required:true },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"9999" },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPercentage', required:true, step: "0.01", max:"9999" },
                { api:'Conversion_Factor__c', type:'number', label:'Conversion Factor', max:"999", step: "0.01", visibleWhen: { 'tenth.Marking_Scheme__c': 'CGPA' } },
                { api:'Percentage__c', type:'number', label:'Percentage', readOnly:true, calculate:'computePercentage', minPercentage:55, step: "0.01" }
            ]
        };

        // after10 virtual
        this.metadata.after10 = {
            key: 'after10',
            title: 'After 10th Qualification',
            columnSystem: cs.after10,
            rows: [ { columns: [ { width:12, fields:['AfterTen__c'] } ] } ],
            fields: [ { 
                api:'AfterTen__c', 
                type:'radio',  
                label: 'Select the qualification you pursued after 10th',
                shortLabel: 'After 10th Qualification', 
                required:true, 
                options:[ {label:'12th',value:'12th'},{label:'Diploma',value:'diploma'},{label:'Both',value:'both'} ] 
            } ]
        };

        // Twelfth = copy of tenth
        this.metadata.twelfth = JSON.parse(JSON.stringify(this.metadata.tenth));
        this.metadata.twelfth.key = 'twelfth';
        this.metadata.twelfth.fields[2].min = "2007-01-01";
        this.metadata.twelfth.fields[2].max= new Date().toISOString().split('T')[0];
        // this.metadata.twelfth.fields[3].min = "2007-01-01";
        // this.metadata.twelfth.fields[3].max= new Date().toISOString().split('T')[0];
        this.metadata.twelfth.fields[6].visibleWhen = { 'twelfth.Marking_Scheme__c': 'CGPA' };
        this.metadata.twelfth.title = '12th Academic Details';
        this.metadata.twelfth.columnSystem = cs.twelfth;

        // Diploma
        this.metadata.diploma = {
            key: 'diploma',
            title: 'Diploma Details',
            columnSystem: cs.diploma,
            rows: [
                { columns: [ { width:3, fields:['School_Institute__c'] }, { width:3, fields:['Board_University__c'] }, { width:3, fields:['Diploma_Name__c'] }, { width:4, fields:['MonthAndYearOfCommencement__c'] }, { width:4, fields:['MonthAndYearOfPassing__c'] } ] },
                { columns: [ { width:3, fields:['Marking_Scheme__c'] }, { width:3, fields:['Maximum_Marks__c'] }, { width:3, fields:['Obtained_Marks__c'] }, { width:3, fields:['Percentage__c'] }, { width:3, fields:['Conversion_Factor__c'] } ] }
            ],
            fields: [
                { api:'Board_University__c', type:'text', label:'Board/University', required:true, maxlength: '255' },
                { api:'School_Institute__c', type:'text', label:'School/Institute', required:true, maxlength: '255' },
                { api:'Diploma_Name__c', type:'text', label:'Diploma Name', required:true, maxlength: '255' },
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', min:"2007-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true},
                { api:'MonthAndYearOfPassing__c', type:'monthyear', min:"2007-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme', required:true },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"9999" },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPercentage', required:true, step: "0.01", max:"9999" },
                { api:'Conversion_Factor__c', type:'number', label:'Conversion Factor', visibleWhen: { 'diploma.Marking_Scheme__c': 'CGPA' }, step: "0.01", max:"999"  },
                { api:'Percentage__c', type:'number', label:'Percentage', readOnly:true, calculate:'computePercentage', minPercentage:55, step: "0.01" }
            ]
        };

        this.metadata.haveAcademicBreak = {
            key: 'haveAcademicBreak',
            title: 'Academic Break',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 3, fields: ['HasAcademicBreak__c'] },
                        { width: 2, fields: ['AcademicBreakYear__c'] },
                        { width: 7, fields: ['AcademicBreakReason__c'] }
                    ]
                }
            ],
            fields: [
                {
                    api: 'HasAcademicBreak__c',
                    type: 'radio',
                    label: 'Do you have an academic break?',
                    options: [
                        { label: 'Yes', value: 'Yes' },
                        { label: 'No', value: 'No' }
                    ],
                    required: true
                },
                {
                    api: 'AcademicBreakYear__c', 
                    maxlength: '255',
                    type: 'text',
                    label: 'In Which Year?',
                    helpText:"If you have taken academic breaks of more than one year, list the years separated by a semicolon.",
                    visibleWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' }                
                },
                {
                    api: 'AcademicBreakReason__c', 
                    maxlength: '255',
                    type: 'textarea',
                    label: 'Reason',
                    maxWords: 50,
                    visibleWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' },
                    requiredWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' }
                }
            ]
        };


        // Graduation
        this.metadata.graduation = {
            key:'graduation',
            title:'Graduation Details',
            columnSystem: cs.graduation,
            layout: 'fluid',
            fields: [
                { 
                    api: "State__c", 
                    type: "lookup", 
                    label: "State",
                    span: 3,
                    required: true,
                    objectApi: "State__c",
                    dynamicFilter: "ugStateFilter",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    allowOther: true,
                },
                {
                    api:'OtherState__c', 
                    type:'text', 
                    label:'Enter State Name', 
                    shortLabel:'State Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "graduation.Display.State__c": "Other" }, 
                },
                {
                    api: "University__c", 
                    type: "lookup", 
                    label: "University",
                    span: 3,
                    required: true,
                    objectApi: "University__c",
                    dynamicFilter: "ugUniversityFilter",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    matchingInfo : {
                        primaryField: { fieldPath: 'UniversityName__c'},
                    },
                    displayFields: {
                        primaryField: 'UniversityName__c',
                    },
                    allowOther: true,
                    visibleWhen: {"otherResources.showUgUniversity":true}
                },
                { 
                    api:'OtherUniversity__c', 
                    type:'text', 
                    label:'Enter University Name', 
                    shortLabel:'University Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "otherResources.showOtherUgUniversity": true },
                },
                { 
                    api: "College__c", 
                    type: "lookup", 
                    label: "College",
                    span: 3,
                    required: true,
                    objectApi: "College__c",
                    dynamicFilter: "ugCollegeFilter",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    matchingInfo : {
                        primaryField: { fieldPath: 'CollegeName__c'},
                    },
                    displayFields: {
                        primaryField: 'CollegeName__c',
                    },
                    allowOther: true,
                    visibleWhen: {"otherResources.showUgCollege":true}
                },
                { 
                    api:'OtherCollege__c', 
                    type:'text', 
                    label:'Enter College Name',
                    shortLabel:'College Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "otherResources.showOtherUgCollege": true } 
                },
                { api:'Mode_of_Study__c', type:'picklist', label:'Mode of Study', required:true, span:3 },
                { api:'Degree__c', type:'picklist', label:'Degree', required:true, span: 4 },
                { 
                    api:'OtherDegree__c', 
                    type:'text', 
                    label:'Enter Degree',
                    shortLabel:'Degree',
                    required:true,
                    span: 4, 
                    visibleWhen: { "graduation.Degree__c": "Other" } 
                },
                { api:'Specialization_Name__c', type:'text', label:'Specialization', span: 4, maxlength: '255', required:true },
                { api:'Degree_Type__c', type:'picklist', label:'Degree Type', required:true, span: 2 },
                { api:'Pattern_of_Examination__c', type:'picklist', label:'Pattern Of Examination', required:true, span: 2 },
            ]
        };

        // Graduation details (marks)
        this.metadata.graduationDetails = {
            key:'graduationDetails',
            title:'Graduation Marks',
            columnSystem: cs.graduationDetails,
            layout: 'fluid',
            fields: [
                { api:'DegreeStatus__c', type:'picklist', span:3, label:'Degree Status', required:true },
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', span:4, min:"2009-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true },
                { api:'MonthAndYearOfPassing__c', type:'monthyear', span:4, min:"2009-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year Of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', span:2, label:'Marking Scheme', required:true },
                { api:'Maximum_Marks__c', type:'number', span:3, label:'Maximum Marks/CGPA', readOnly:true, calculate:'computeGraduationTotals', required:true, group:'totals', step: "0.01", max:"99999" },
                { api:'Obtained_Marks__c', type:'number', span:3, label:'Obtained Marks/CGPA', onChange:'recalcGraduationPercentage', readOnly:true, calculate:'computeGraduationTotals', required:true, group:'totals', step: "0.01", max:"99999" },
                { api:'Percentage__c', type:'number', span:3, label:'Graduation Percentage', readOnly:true, calculate:'computeGraduationPercentage', group:'totals', step: "0.01", max:"100" },
                { api:'Conversion_Factor__c', type:'number', span:2, label:'Conversion Factor', step: "0.01", max:"999", visibleWhen: { 'graduationDetails.Marking_Scheme__c': 'CGPA' } },
            ]
        };

        // Semester: two rows of 10 sem columns plus spacing -> using columnSystem from metadata
        const semColsMax = [];
        const semColsObt = [];
        for (let i=1;i<=10;i++) {
            semColsMax.push({ width:3, fields:['Maximum_Marks_SGPA__c'] }); // using width 2 to fit 30 columns system
            semColsObt.push({ width:3, fields:['Obtained_Marks_SGPA__c'] });
        }
        // add spacers if needed
        this.metadata.semester = {
            key: 'semester',
            title: 'Semester Wise Details',
            columnSystem: cs.semester,
            rows: [
                { columns: semColsMax },
                { columns: semColsObt }
            ],
            fields: [
                ...Array.from({length:10}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Sem ${i+1} Maximum Score` })),
                ...Array.from({length:10}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Sem ${i+1} Obtained Score` }))
            ]
        };

        // Year-wise: two rows of 5 year columns (Max/Obt) using same 30-column system
        const yearColsMax = [];
        const yearColsObt = [];
        for (let i=1;i<=5;i++) {
            yearColsMax.push({ width:6, fields:['Maximum_Marks_SGPA__c'] }); // 5 * 6 = 30
            yearColsObt.push({ width:6, fields:['Obtained_Marks_SGPA__c'] });
        }
        this.metadata.year = {
            key: 'year',
            title: 'Year Wise Details',
            columnSystem: cs.semester,
            rows: [
                { columns: yearColsMax },
                { columns: yearColsObt }
            ],
            fields: [
                ...Array.from({length:5}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Year ${i+1} Maximum Score` })),
                ...Array.from({length:5}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Year ${i+1} Obtained Score` }))
            ]
        };

        //show post grad?
        this.metadata.havePostGrad = {
            key:'havePostGrad',
            title:'Any Post Graduation?',
            columnSystem: cs.havePostGrad,
            rows: [
                { columns: [ { width:3, fields:['AnyPostGraduation__c'] } ] }
            ],
            fields: [
                { 
                    api:'AnyPostGraduation__c', 
                    type:'picklist', 
                    required:true,  
                    label: 'Pick an option',
                    shortLabel: 'Any Post Graduation?', 
                }
            ]
        };

        // Post Graduation
        this.metadata.postGraduation = {
            key:'postGraduation',
            title:'Post Graduation Details',
            columnSystem: cs.postGraduation,
            layout: 'fluid',
            fields: [
                { 
                    api: "State__c", 
                    type: "lookup", 
                    label: "State",
                    span: 3,
                    required: true,
                    objectApi: "State__c",
                    dynamicFilter: "pgStateFilter",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    allowOther: true,
                },
                { 
                    api:'OtherState__c', 
                    type:'text', 
                    label:'Enter State Name', 
                    shortLabel:'State Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "postGraduation.Display.State__c": "Other" }, 
                },
                { 
                    api: "University__c", 
                    type: "lookup", 
                    label: "University",
                    span: 3,
                    required: true,
                    objectApi: "University__c",
                    dynamicFilter: "pgUniversityFilter",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    matchingInfo : {
                        primaryField: { fieldPath: 'UniversityName__c'},
                    },
                    displayFields: {
                        primaryField: 'UniversityName__c',
                    },
                    allowOther: true,
                    visibleWhen: {"otherResources.showPgUniversity":true}
                },
                { 
                    api:'OtherUniversity__c', 
                    type:'text', 
                    label:'Enter University Name',
                    shortLabel:'University Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "otherResources.showOtherPgUniversity": true },
                },
                { 
                    api: "College__c", 
                    type: "lookup", 
                    label: "College",
                    span: 3,
                    required: true,
                    objectApi: "College__c",
                    dynamicFilter: "pgCollegeFilter",
                    sortInfo: ['Order__c DESC NULLS LAST'],
                    matchingInfo : {
                        primaryField: { fieldPath: 'CollegeName__c'},
                    },
                    displayFields: {
                        primaryField: 'CollegeName__c',
                    },
                    allowOther: true,
                    visibleWhen: {"otherResources.showPgCollege":true}
                },
                {
                    api:'OtherCollege__c', 
                    type:'text', 
                    label:'Enter College Name',
                    shortLabel:'College Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "otherResources.showOtherPgCollege": true } 
                },
                { api:'Mode_of_Study__c', type:'picklist', label:'Mode of Study', required:true, span: 3, },
                { api:'Degree__c', type:'picklist', label:'Degree', required:true, span: 4, },
                { 
                    api:'OtherDegree__c', 
                    type:'text', 
                    label:'Enter Degree',
                    shortLabel:'Degree',
                    required:true,
                    span: 4, 
                    visibleWhen: { "postGraduation.Degree__c": "Other" } 
                },
                { api:'Specialization_Name__c', type:'text', label:'Specialization', span: 4, maxlength: '255', required:true },
                { api:'Degree_Type__c', type:'picklist', label:'Degree Type', required:true, span: 2 },
                { api:'Pattern_of_Examination__c', type:'picklist', label:'Pattern Of Examination', required:true, span: 2 },
            ]
        };

        // Post Graduation details (marks)
        this.metadata.postGraduationDetails = {
            key:'postGraduationDetails',
            title:'Post Graduation Marks',
            columnSystem: cs.postGraduationDetails,
            layout: 'fluid',
            fields: [
                { api:'DegreeStatus__c', type:'picklist', span:3, label:'Degree Status', required:true },
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', span:4, min:"2011-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true},
                { api:'MonthAndYearOfPassing__c', type:'monthyear', span:4, min:"2011-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year Of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', span:2, label:'Marking Scheme', required:true },
                { api:'Maximum_Marks__c', type:'number', span:3, label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"99999" },
                { api:'Obtained_Marks__c', type:'number', span:3, label:'Obtained Marks/CGPA', onChange:'recalcPostGraduationPercentage', required:true, step: "0.01", max:"99999" },
                { api:'Percentage__c', type:'number', span:3, label:'Post Graduation Percentage', readOnly:true, calculate:'computePostGraduationPercentage', step: "0.01", max:"100" },
                { api:'Conversion_Factor__c', type:'number', span:2, label:'Conversion Factor', visibleWhen: { 'postGraduationDetails.Marking_Scheme__c': 'CGPA' }, step: "0.01" , max:"999" },
            ]
        };

        if(this.needPostGradSemYearWise){
            // Post Semester: two rows of 10 sem columns plus spacing -> using columnSystem from metadata
            const postSemColsMax = [];
            const postSemColsObt = [];
            for (let i=1;i<=10;i++) {
                postSemColsMax.push({ width:3, fields:['Maximum_Marks_SGPA__c'] }); // using width 2 to fit 30 columns system
                postSemColsObt.push({ width:3, fields:['Obtained_Marks_SGPA__c'] });
            }
            // add spacers if needed
            this.metadata.postSemester = {
                key: 'postSemester',
                title: 'Post Semester Wise Details',
                columnSystem: cs.postSemester,
                rows: [
                    { columns: postSemColsMax },
                    { columns: postSemColsObt }
                ],
                fields: [
                    ...Array.from({length:10}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Sem ${i+1} Maximum Score` })),
                    ...Array.from({length:10}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Sem ${i+1} Obtained Score` }))
                ]
            };

            // Post Year-wise: two rows of 5 year columns (Max/Obt) using same 30-column system
            const postYearColsMax = [];
            const postYearColsObt = [];
            for (let i=1;i<=5;i++) {
                postYearColsMax.push({ width:6, fields:['Maximum_Marks_SGPA__c'] }); // 5 * 6 = 30
                postYearColsObt.push({ width:6, fields:['Obtained_Marks_SGPA__c'] });
            }
            this.metadata.postYear = {
                key: 'postYear',
                title: 'Post Year Wise Details',
                columnSystem: cs.postSemester,
                rows: [
                    { columns: postYearColsMax },
                    { columns: postYearColsObt }
                ],
                fields: [
                    ...Array.from({length:5}, (_,i) => ({ api:'Maximum_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Year ${i+1} Maximum Score` })),
                    ...Array.from({length:5}, (_,i) => ({ api:'Obtained_Marks_SGPA__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:`Year ${i+1} Obtained Score` }))
                ]
            };

        }

        this.metadata.haveProfessionalQualification = {
            key: 'haveProfessionalQualification',
            title: 'Do you have any Professional Qualification?',
            columnSystem: 12,
            rows: [
                { columns: [ { width:3, fields:['HasProfessionalQualification__c'] } ] }
            ],
            fields: [
                {
                    api:'HasProfessionalQualification__c',
                    type:'radio',
                    label:'',
                    options: [
                        { label:'Yes', value:'Yes' },
                        { label:'No', value:'No' }
                    ]
                }
            ]
        };

        // Build 3 rows of 7 columns per row
        const pqRows = [];

        for (let i = 1; i <= 3; i++) {
            pqRows.push({
                columns: [
                    { width: 2, fields: ['Name_of_Qualification__c'] },
                    { width: 2, fields: ['Name_of_Institute__c'] },
                    { width: 1, fields: ['Rank_Achieved__c'] },
                    { width: 1, fields: ['Level_Achieved__c'] },
                    { width: 2, fields: ['Total_Max_Marks__c'] },
                    { width: 2, fields: ['Marks_Obtained__c'] },
                    { width: 2, fields: ['Percentage__c'] }
                ]
            });
        }

        this.metadata.professionalQualification = {
            key: 'professionalQualification',
            title: 'Professional Qualifications (If Any)',
            columnSystem: 12,
            rows: pqRows,
            fields: [
                ...Array.from({ length: 3 }, (_, i) => ({ required:i===0?true:false, api:'Name_of_Qualification__c', sequence:i+1, type:'text', label:'Qualification' })),
                ...Array.from({ length: 3 }, (_, i) => ({ required:i===0?true:false, api:'Name_of_Institute__c', sequence:i+1, type:'text', label:'Institute', maxlength: '255' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Rank_Achieved__c', sequence:i+1, type:'text', label:'Rank', maxlength: '255' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Level_Achieved__c', sequence:i+1, type:'text', label:'Level', maxlength: '255' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Total_Max_Marks__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:'Total Max Marks' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Marks_Obtained__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:'Marks Obtained' })),
                ...Array.from({ length: 3 }, (_, i) => ({ api:'Percentage__c', sequence:i+1, type:'number', label:'Percentage', readOnly: true, calculate: 'computePQPercentage', step: "0.01" }))
            ]
        };

        this.metadata.extraCurricular = {
            key: 'extraCurricular',
            title: 'Extra-Curricular Activities',
            columnSystem: 12,
            rows: [
                { columns: [
                    { width: 12, fields: ['ExtraCurricularActivities__c'] }
                ]}
            ],
            fields: [
                { api:'ExtraCurricularActivities__c', type:'textarea', label:'Share details of any extra-curricular activities?', maxlength: '131072', maxWords: 500 }
            ]
        };

        this.metadata.importantCertification = {
            key: 'importantCertification',
            title: 'Important Certification/Programme (If Any)',
            columnSystem: 12,
            rows: [
                { columns: [
                    { width: 12, fields:['CertificationDetails__c'] }
                ]}
            ],
            fields: [
                { api:'CertificationDetails__c', type:'textarea', label:'If yes, please specify (Max. 50 words)', maxlength:"32768", maxWords: 50 }
            ]
        };

        this.metadata.publications = {
            key: 'publications',
            title: 'Publications (If Any)',
            columnSystem: 12,
            rows: [
                { columns: [
                    { width: 12, fields:['Publications__c'] }
                ]}
            ],
            fields: [
                { api:'Publications__c', type:'text', label:'Any publications?', helpText:'Share the URL of your Publication' }
            ]
        };

    }

    get ugStateFilter() {
        
        return {
            criteria: [
                {
                    fieldPath: 'Country_Master__r.Name',
                    operator: 'eq',
                    value: 'India'
                },
                {
                    fieldPath: 'Name',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.graduation.State__c
                }
            ],
            filterLogic: "1 OR 2 OR 3"
        };
    }

    get pgStateFilter() {
        
        return {
            criteria: [
                {
                    fieldPath: 'Country_Master__r.Name',
                    operator: 'eq',
                    value: 'India'
                },
                {
                    fieldPath: 'Name',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.postGraduation.State__c
                }
            ],
            filterLogic: "1 OR 2 OR 3"
        };
    }

    get ugCollegeFilter() {
        
        return {
            criteria: [
                {
                    fieldPath: 'University__c',
                    operator: 'eq',
                    value: this.education.graduation.University__c
                },
                {
                    fieldPath: 'CollegeName__c',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.graduation.College__c
                }
            ],
            filterLogic: "1 OR 2 OR 3",
            otherField:'CollegeName__c'
        };
    }

    get pgCollegeFilter() {
        
        return {
            criteria: [
                {
                    fieldPath: 'University__c',
                    operator: 'eq',
                    value: this.education.postGraduation.University__c
                },
                {
                    fieldPath: 'CollegeName__c',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.postGraduation.College__c
                }
            ],
            filterLogic: "1 OR 2 OR 3",
            otherField:'CollegeName__c'
        };
    }

    get ugUniversityFilter() {
        
        return {
            criteria: [
                {
                    fieldPath: 'State__c',
                    operator: 'eq',
                    value: this.education.graduation.State__c
                },
                {
                    fieldPath: 'UniversityName__c',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.graduation.University__c
                }
            ],
            filterLogic: "1 OR 2 OR 3",
            otherField:'UniversityName__c'
        };
    }

    get pgUniversityFilter() {
        
        return {
            criteria: [
                {
                    fieldPath: 'State__c',
                    operator: 'eq',
                    value: this.education.postGraduation.State__c
                },
                {
                    fieldPath: 'UniversityName__c',
                    operator: 'eq',
                    value: 'Other'
                },
                {
                    fieldPath: 'Id',
                    operator: 'eq',
                    value: this.education.postGraduation.University__c
                }
            ],
            filterLogic: "1 OR 2 OR 3",
            otherField:'UniversityName__c'
        };
    }

    get showUgUniversity(){
        const grad = this.education?.graduation || {};
        return !!grad.State__c && grad.Display?.State__c !== 'Other';
    }

    get showOtherUgUniversity() {
        const g = this.education?.graduation || {};

        return g.Display?.State__c === 'Other' ||
            g.Display?.University__c === 'Other';
    }

    get showUgCollege() {
        const grad = this.education?.graduation || {};
        return !!grad.State__c &&
            !!grad.University__c &&
            grad.Display?.University__c !== 'Other';
    }

    get showOtherUgCollege() {
        const g = this.education?.graduation || {};

        return g.Display?.State__c === 'Other' ||
            g.Display?.University__c === 'Other' ||
            g.Display?.College__c === 'Other';
    }

    get showPgUniversity(){
        const postGrad = this.education?.postGraduation || {};
        return !!postGrad.State__c && postGrad.Display?.State__c !== 'Other';
    }

    get showOtherPgUniversity() {
        const pg = this.education?.postGraduation || {};

        return pg.Display?.State__c === 'Other' ||
            pg.Display?.University__c === 'Other';
    }

    get showPgCollege(){
        const postGrad = this.education?.postGraduation || {};
        return !!postGrad.State__c &&
            !!postGrad.University__c &&
            postGrad.Display?.University__c !== 'Other';
    }

    get showOtherPgCollege() {
        const pg = this.education?.postGraduation || {};

        return pg.Display?.State__c === 'Other' ||
            pg.Display?.University__c === 'Other' ||
            pg.Display?.College__c === 'Other';
    }

    recordTypeIds = {};
    recordTypeNames = {};

    async _loadRecordTypes() {
        const res = await getRecordTypesByName({
            objectApiName:'Academic_Detail__c',
            recordTypeNames:['PG','UG']
        });
        this.recordTypeIds = res.nameToId || {};
        this.recordTypeNames = res.idToName || {};
    }

    // inject picklists from picklistCache into metadata fields
    _injectPicklists() {
        const pick = this.picklistCache || {};
        const toOptions = arr => (arr || []).map(x => ({ label:x.label, value:x.value }));
        const setOptions = (sectionKey, api, options) => {
            const f = (this.metadata[sectionKey].fields || [])
                .find(x => x.api.toLowerCase() === api.toLowerCase());
            if (f) {
                f.options = options;
            }
        };
        const resolveOptions = (api, rt) => {
            if (rt && pick.recordTypeSet && pick.recordTypeSet[rt] && pick.recordTypeSet[rt][api]) {
                return toOptions(pick.recordTypeSet[rt][api].options);
            }
            if (pick.defaultSet && pick.defaultSet[api]) {
                return toOptions(pick.defaultSet[api].options);
            }
            return [];
        };

        // MASTER
        setOptions('tenth','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));
        setOptions('twelfth','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));

        // DIPLOMA
        setOptions('diploma','Diploma_Name__c',resolveOptions('Diploma_Name__c'));
        setOptions('diploma','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));

        // UG
        setOptions('graduation','Mode_of_Study__c',resolveOptions('Mode_of_Study__c'));
        setOptions('graduation','Degree__c',resolveOptions('Degree__c',this.recordTypeIds.UG));
        setOptions('graduation','Degree_Type__c',resolveOptions('Degree_Type__c',this.recordTypeIds.UG));
        setOptions('graduation','Pattern_of_Examination__c',resolveOptions('Pattern_of_Examination__c'));
        setOptions('graduationDetails','DegreeStatus__c',resolveOptions('DegreeStatus__c'));

        // PG
        setOptions('postGraduation','Mode_of_Study__c',resolveOptions('Mode_of_Study__c'));
        setOptions('postGraduation','Degree__c',resolveOptions('Degree__c',this.recordTypeIds.PG));
        setOptions('postGraduation','Degree_Type__c',resolveOptions('Degree_Type__c',this.recordTypeIds.PG));
        setOptions('postGraduation','Pattern_of_Examination__c',resolveOptions('Pattern_of_Examination__c'));
        setOptions('postGraduationDetails','DegreeStatus__c',resolveOptions('DegreeStatus__c'));

        setOptions('havePostGrad','AnyPostGraduation__c',resolveOptions('AnyPostGraduation__c'));
        setOptions('graduationDetails','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));
        setOptions('postGraduationDetails','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));

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

    // Build renderModel from metadata + values
    _buildRenderModelAll() {

        const after10 = this.education.after10;

        // Always include 10th and After10
        const list = [
            this._buildSectionRenderModel('tenth'),
            this._buildSectionRenderModel('after10')
        ];

        // Show 12th?
        if (after10.AfterTen__c === '12th' || after10.AfterTen__c === 'both') {
            list.push(this._buildSectionRenderModel('twelfth'));
        }

        // Show Diploma?
        if (after10.AfterTen__c === 'diploma' || after10.AfterTen__c === 'both') {
            list.push(this._buildSectionRenderModel('diploma'));
        }

        this.academicSections = list;

        // Conditionally include Semester vs Year sections based on pattern
        const patternVal = (this.education.graduation && this.education.graduation.Pattern_of_Examination__c) || '';
        const degreeTypeVal = (this.education.graduation && this.education.graduation.Degree_Type__c) || '';
        const isYearWise = patternVal && patternVal.toLowerCase().includes('year');
        const isSemWise = patternVal && patternVal.toLowerCase().includes('sem');

        // Parse degree type: expected labels "3 Years" / "4 Years" / "5 Years"
        const yearsFromDegreeType = (() => {
            const m = (degreeTypeVal || '').toString().match(/([3-5])\s*year/gi);
            if (!m) return null;
            const digit = (degreeTypeVal.match(/([3-5])/)||[])[1];
            return digit ? parseInt(digit, 10) : null;
        })();

        // Helper to build a sliced copy of a grid section (metadata) according to required count,
        // and mark only rendered fields as required so generic validation applies.
        const buildSlicedGridSection = (baseKey, countYears) => {
            const base = this.metadata[baseKey];
            if (!base) return null;
            const clone = JSON.parse(JSON.stringify(base));
            
            const getRequired = (periodNum, totalPeriods, exemptTail) => {
                const pursuing =
                    this.education?.graduationDetails?.DegreeStatus__c === 'Pursuing';

                if (!periodNum || totalPeriods <= 0) return false;

                return pursuing
                    ? periodNum <= totalPeriods - exemptTail
                    : true;
            };

            /* =========================================================
            YEAR MODE
            ========================================================= */
            if (baseKey === 'year') {

                const yearCount = Math.min(countYears || 0, 5);
                const exemptedYears = 1;

                clone.rows = [
                    { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, yearCount) },
                    { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, yearCount) }
                ];

                clone.fields = clone.fields
                    // keep only visible sequences
                    .filter(f => !f.sequence || f.sequence <= yearCount)
                    .map(f => {
                        const yearNum = Number(f.sequence);

                        return {
                            ...f,
                            required: yearNum
                                ? getRequired(yearNum, yearCount, exemptedYears)
                                : f.required,
                            type: f.type
                        };
                    });
            }


            /* =========================================================
            SEMESTER MODE
            ========================================================= */
            else if (baseKey === 'semester') {

                const semCount = Math.min((countYears || 0) * 2, 10);
                const exemptedSems = 2;

                clone.rows = [
                    { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, semCount) },
                    { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, semCount) }
                ];

                clone.fields = clone.fields
                    .filter(f => !f.sequence || f.sequence <= semCount)
                    .map(f => {
                        const semNum = Number(f.sequence);

                        return {
                            ...f,
                            required: semNum
                                ? getRequired(semNum, semCount, exemptedSems)
                                : f.required,
                            type: f.type
                        };
                    });
            }

            return clone;
        };

        // Decide dynamic grid (slice + required) based on pattern + degree type
        let dynamicGridMeta = null;
        if (yearsFromDegreeType) {
            if (isYearWise) {
                dynamicGridMeta = buildSlicedGridSection('year', yearsFromDegreeType);
            } else if (isSemWise) {
                dynamicGridMeta = buildSlicedGridSection('semester', yearsFromDegreeType);
            }
        }

        // Temporarily swap metadata with dynamic clone for render model build
        let restoreKey = null;
        let originalMeta = null;
        if (dynamicGridMeta) {
            restoreKey = dynamicGridMeta.key;
            originalMeta = this.metadata[restoreKey];
            this.metadata[restoreKey] = dynamicGridMeta;
        }

        const abVal = this.education.haveAcademicBreak?.HasAcademicBreak__c || '';
        let academicBreakSection = this._buildSectionRenderModel('haveAcademicBreak');

        this.graduationSections = [
            academicBreakSection,
            this._buildSectionRenderModel('graduation'),
            {
                ...this._buildSectionRenderModel('graduationDetails', { group: 'default' }),
                title: 'Graduation Marks'
            },
            isYearWise ? {...this._buildSectionRenderModel('year'), title:''} : {...(isSemWise ? this._buildSectionRenderModel('semester') : null), title:''},
            {
                ...this._buildSectionRenderModel('graduationDetails', { group: 'totals' }),
                title: 'Graduation Total'
            },
            this._buildSectionRenderModel('havePostGrad'),
        ].filter(Boolean);

        // Check if we should show Post Graduation sections
        const anyPostGraduation = (this.education.havePostGrad && this.education.havePostGrad.AnyPostGraduation__c) || '';
        const showPostGraduation = anyPostGraduation === 'Yes';

        // Build Post Graduation sections if needed
        let postGraduationSections = [];
        if (showPostGraduation) {
            // Determine if Post Graduation should use Year or Semester based on Pattern_of_Examination__c
            const postPatternVal = (this.education.postGraduation && this.education.postGraduation.Pattern_of_Examination__c) || '';
            const postDegreeTypeVal = (this.education.postGraduation && this.education.postGraduation.Degree_Type__c) || '';
            const isPostYearWise = postPatternVal && postPatternVal.toLowerCase().includes('year');
            const isPostSemWise = postPatternVal && postPatternVal.toLowerCase().includes('sem');

            // Parse degree type: expected labels "3 Years" / "4 Years" / "5 Years"
            const postYearsFromDegreeType = (() => {
                const m = (postDegreeTypeVal || '').toString().match(/([3-5])\s*year/gi);
                if (!m) return null;
                const digit = (postDegreeTypeVal.match(/([3-5])/)||[])[1];
                return digit ? parseInt(digit, 10) : null;
            })();

            // Helper to build a sliced copy of a grid section (metadata) according to required count,
            // and mark only rendered fields as required so generic validation applies.
            const buildPostSlicedGridSection = (baseKey, countYears) => {
                const base = this.metadata[baseKey];
                if (!base) return null;
                const clone = JSON.parse(JSON.stringify(base));
                if (baseKey === 'postYear') {
                    const maxYears = Math.min(countYears || 0, 5);
                    clone.rows = [
                        { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, maxYears) },
                        { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, maxYears) }
                    ];
                    clone.fields = clone.fields.filter(f => {
                        const m = f.api.match(/^year(\d+)(Max|Obt)$/);
                        return m ? parseInt(m[1],10) <= maxYears : true;
                    }).map(f => ({ ...f, required: true, type: f.type }));
                } else if (baseKey === 'postSemester') {
                    const semCount = Math.min((countYears || 0) * 2, 10);
                    clone.rows = [
                        { ...clone.rows[0], columns: clone.rows[0].columns.slice(0, semCount) },
                        { ...clone.rows[1], columns: clone.rows[1].columns.slice(0, semCount) }
                    ];
                    clone.fields = clone.fields.filter(f => {
                        const m = f.api.match(/^sem(\d+)(Max|Obt)$/);
                        return m ? parseInt(m[1],10) <= semCount : true;
                    }).map(f => ({ ...f, required: true, type: f.type }));
                }
                return clone;
            };

            // Decide dynamic grid (slice + required) based on pattern + degree type
            let postDynamicGridMeta = null;
            if (postYearsFromDegreeType && this.needPostGradSemYearWise) {
                if (isPostYearWise) {
                    postDynamicGridMeta = buildPostSlicedGridSection('postYear', postYearsFromDegreeType);
                } else if (isPostSemWise) {
                    postDynamicGridMeta = buildPostSlicedGridSection('postSemester', postYearsFromDegreeType);
                }
            }

            // Temporarily swap metadata with dynamic clone for render model build
            let postRestoreKey = null;
            let postOriginalMeta = null;
            if (postDynamicGridMeta) {
                postRestoreKey = postDynamicGridMeta.key;
                postOriginalMeta = this.metadata[postRestoreKey];
                this.metadata[postRestoreKey] = postDynamicGridMeta;
            }

            postGraduationSections = [
                this._buildSectionRenderModel('postGraduation'),
                this._buildSectionRenderModel('postGraduationDetails'),
                isPostYearWise && this.needPostGradSemYearWise ? this._buildSectionRenderModel('postYear') : (isPostSemWise && this.needPostGradSemYearWise ? this._buildSectionRenderModel('postSemester') : null)
            ].filter(Boolean);

            // Restore original metadata after building render model to avoid permanent mutation
            if (postRestoreKey) {
                this.metadata[postRestoreKey] = postOriginalMeta;
            }
        }

        // Store the post graduation sections for rendering
        this.postGraduationSections = postGraduationSections;

        // Show Professional Qualification toggle always

        let pqList = [];
        pqList.push(this._buildSectionRenderModel('haveProfessionalQualification'));

        // If Yes → show 3-row grid
        const hasPQ = (this.education.haveProfessionalQualification && this.education.haveProfessionalQualification.HasProfessionalQualification__c) || '';
        if (hasPQ === 'Yes') {
            pqList.push(this._buildSectionRenderModel('professionalQualification'));
        }

        this.professionalQualification = pqList;

        this.academicDetailsFooterSections = [
            this._buildSectionRenderModel('extraCurricular'),
            this._buildSectionRenderModel('importantCertification'),
            this._buildSectionRenderModel('publications')
        ];

        // Restore original metadata after building render model to avoid permanent mutation
        if (restoreKey) {
            this.metadata[restoreKey] = originalMeta;
        }
    }

    _buildSectionRenderModel(sectionKey, options = {}) {
        const meta = this.metadata[sectionKey];
        const groupFilter = options.group || null;
        if (!meta) return null;

        if (meta?.layout === 'fluid') {
            const sectionData = this.education[sectionKey] || {};
            return {
                key: meta.key,
                title: meta.title,
                rows: this._buildFluidRows(meta, sectionData, groupFilter)
            };
        }

        const cs = meta.columnSystem || 12;
        const section = {
            key: meta.key || sectionKey,
            title: meta.title || sectionKey,
            rows: []
        };

        // ------------------------------------------------------------
        // SPECIAL: PROFESSIONAL QUALIFICATION (3 rows max)
        // ------------------------------------------------------------
        const edSec = this.education[sectionKey];
        if (edSec && typeof edSec === 'object' && edSec.isSequential === false) {

            const section = {
                key: meta.key || sectionKey,
                title: meta.title || sectionKey,
                rows: []
            };

            const rowStyle =
                `display:grid;grid-template-columns:repeat(${cs},1fr);` +
                `gap:8px;margin-bottom:12px;`;

            // Only sequence 1..3
            [1,2,3].forEach(seq => {
                const rec = edSec[seq] || {};

                // Use only FIRST metadata row for PQ
                const metaRow = meta.rows[0];

                const renderRow = {
                    key: `${sectionKey}-row-${seq}`,
                    style: rowStyle,
                    columns: []
                };

                metaRow.columns.forEach((col, cIdx) => {
                    const span = col.width ? Number(col.width) : cs;

                    const renderCol = {
                        key: `${sectionKey}-col-${seq}-${cIdx}`,
                        widthStyle: `grid-column: span ${span};`,
                        fields: []
                    };

                    col.fields.forEach(api => {
                        const fieldMeta =
                            meta.fields.find(f => f.api === api && f.sequence === seq) ||
                            meta.fields.find(f => f.api === api) ||
                            { api, label: api, type: 'text' };

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${seq}`,
                            meta: { ...fieldMeta, sequence: seq },
                            value: rec[api] || null
                        });
                    });

                    renderRow.columns.push(renderCol);
                });

                section.rows.push(renderRow);
            });

            return section;
        }



        
        // compute style for rows: use CSS grid template columns based on column system
        const rowStyle = `display: grid; grid-template-columns: repeat(${cs}, 1fr); gap:8px; margin-bottom:8px;`;
        // for each meta row, create render row
        (meta.rows || []).forEach((r, rIdx) => {

            if (r?.fluid === true) {
                section.rows.push(
                    ...this._buildFluidRowFromFieldList(
                        meta,
                        r.fields || [],
                        this.education[sectionKey] || {},
                        rIdx
                    )
                );
                return;
            }
            const renderRow = { key: `${section.key}-row-${rIdx}`, style: rowStyle, columns: [] };
            (r.columns || []).forEach((col, cIdx) => {
                // compute widthStyle based on span value relative to cs
                const span = col.width && Number(col.width) >= 1 ? Number(col.width) : cs;
                const widthStyle = `grid-column: span ${span};`;
                const renderCol = { key: `${section.key}-col-${rIdx}-${cIdx}`, header: col.header || null, widthStyle, fields: [] };
                // Track global sequence at section level
                section._apiCounts = section._apiCounts || {};

                (col.fields || []).forEach(fieldApi => {

                    // Increment occurrence count for this API
                    section._apiCounts[fieldApi] = (section._apiCounts[fieldApi] || 0) + 1;
                    const seq = section._apiCounts[fieldApi];

                    // Try matching correct meta (API + sequence)
                    let fieldMeta = (meta.fields || []).find(
                        f => f.api === fieldApi && Number(f.sequence) === Number(seq)
                    );

                    // If not found, fallback to FIRST meta with same API (preserves real type)
                    if (!fieldMeta) {
                        fieldMeta = (meta.fields || []).find(f => f.api === fieldApi);
                    }

                    // If still not found, final fallback
                    if (!fieldMeta) {
                        fieldMeta = { api: fieldApi, sequence: seq, label: fieldApi, type: 'text' };
                    }

                    const fieldGroup = fieldMeta?.group || 'default';

                    if (groupFilter && fieldGroup !== groupFilter) {
                        return;
                    }

                    const metaForRender = this._resolveFieldMeta(
                        sectionKey,
                        { ...fieldMeta, sequence: seq }
                    );

                    if (!this._isFieldVisible(metaForRender)) return;

                    const value = this._getValueForField(sectionKey, fieldApi, seq);

                    // ⭐ inject lookup display
                    const display =
                        this.education[sectionKey]?.Display?.[fieldApi];

                    if (display) {
                        metaForRender.displayValue = display;
                    }

                    // ⭐ APPLY DYNAMIC FILTER HERE
                    this._applyDynamicFilter(metaForRender);

                    renderCol.fields.push({
                        key: `${section.key}-${fieldApi}-${seq}`,
                        meta: metaForRender,
                        value
                    });

                });


                renderRow.columns.push(renderCol);
            });
            section.rows.push(renderRow);
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

            // ✅ CLONE METADATA

            // ⭐ DYNAMIC GRADUATION DATE LOGIC (WITH DOB RULE)
            if (meta.key === 'graduationDetails' && f.api === 'MonthAndYearOfPassing__c') {
                const isPursuing =
                    this.education?.graduationDetails?.DegreeStatus__c === 'Pursuing';

                const dob = this.personalDetails?.Date_of_Birth_As_Per_10th_Marksheet__c;

                const addYears = (date, years) => {
                    if (!date) return null;
                    const d = new Date(date);
                    d.setUTCFullYear(d.getUTCFullYear() + years);
                    d.setUTCMonth(0, 1); // Jan 1 of cutoff year
                    d.setUTCHours(0, 0, 0, 0);
                    return d.toISOString().split('T')[0];
                };

                if (!isPursuing) {
                    // ✅ COMPLETED → use DOB-based rules
                    if (dob) {
                        if (f.api === 'MonthAndYearOfPassing__c') {
                            metaForRender.min = addYears(dob, 20);
                        }
                    }

                    metaForRender.max = new Date().toISOString().split('T')[0];
                    metaForRender.label =
                        f.api === 'MonthAndYearOfPassing__c'
                            ? "Graduated Month and Year"
                            : f.label;

                } else {
                    // ✅ PURSUING → future window
                    metaForRender.min = new Date().toISOString().split('T')[0];
                    metaForRender.max = new Date(
                        new Date().setFullYear(new Date().getFullYear() + 1)
                    ).toISOString().split('T')[0];

                    metaForRender.label =
                        f.api === 'MonthAndYearOfPassing__c'
                            ? "Expected graduation Month and Year"
                            : f.label;
                }
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

    _getValueForField(sectionKey, api, sequence) {
        // Professional Qualification (non-sequential numeric keys)
        if (sectionKey === 'professionalQualification') {
            if (!sequence) return null;
            return ((this.education.professionalQualification || {})[sequence] || {})[api] || null;
        }


        // Sections that use numeric row-based sequential storage
        const seqSections = ['semester', 'year', 'postSemester', 'postYear'];

        // If it's a sequential grid section → return value for that row (sequence = numeric row key)
        if (seqSections.includes(sectionKey) && sequence) {
            return ((this.education[sectionKey] || {})[sequence] || {})[api] || null;
        }

        // normal single-row section
        return (this.education[sectionKey] || {})[api] || null;
    }

    isUgCgpaMode() {
        return (this.education?.graduationDetails?.Marking_Scheme__c || '') === 'CGPA';
    }

    isUgMarksMode() {
        return !!this.education?.graduationDetails && !this.isUgCgpaMode();
    }

    isPgCgpaMode() {
        return (this.education?.postGraduationDetails?.Marking_Scheme__c || '') === 'CGPA';
    }

    isPgMarksMode() {
        return !!this.education?.postGraduationDetails && !this.isPgCgpaMode();
    }

    _clearFields(sectionKey, fieldApis = []) {
        this.education[sectionKey] ||= {};
        fieldApis.forEach(api => {
            this.education[sectionKey][api] = null;
        });
    }

    _resetSequentialSection(sectionKey) {
        if (this.education[sectionKey] && Object.keys(this.education[sectionKey]).length) {
            this.deleteEntireMode(sectionKey);
            return;
        }
        this.education[sectionKey] = {};
    }

    _handleMarkingSchemeTransition(sectionKey, oldValue, newValue) {
        if (oldValue === newValue) return;

        const resetApis = ['Maximum_Marks__c', 'Obtained_Marks__c', 'Percentage__c'];

        if (['tenth', 'twelfth', 'diploma', 'graduationDetails', 'postGraduationDetails'].includes(sectionKey)) {
            this._clearFields(sectionKey, resetApis);
        }

        if (sectionKey === 'graduationDetails') {
            this._resetSequentialSection('semester');
            this._resetSequentialSection('year');
        }
    }

    _resolveFieldMeta(sectionKey, fieldMeta) {
        const resolved = { ...fieldMeta };

        if (this.isReadOnly) {
            resolved.readOnly = true;
            return resolved;
        }

        if (sectionKey === 'graduationDetails' &&
            ['Maximum_Marks__c', 'Obtained_Marks__c', 'Percentage__c'].includes(resolved.api)) {
            if (this.isUgCgpaMode()) {
                resolved.readOnly = false;
                resolved.required = true;
                delete resolved.calculate;
            } else {
                resolved.readOnly = true;
                resolved.required = false;
            }
        }

        if (sectionKey === 'postGraduationDetails') {
            if (['Maximum_Marks__c', 'Obtained_Marks__c'].includes(resolved.api)) {
                resolved.readOnly = false;
                resolved.required = true;
            }

            if (resolved.api === 'Percentage__c') {
                if (this.isPgCgpaMode()) {
                    resolved.readOnly = false;
                    resolved.required = true;
                    delete resolved.calculate;
                } else {
                    resolved.readOnly = true;
                    resolved.required = false;
                }
            }
        }

        return resolved;
    }

    _shouldRunCalculation(sectionKey, fieldMeta) {
        if (!fieldMeta?.calculate) return false;

        if (sectionKey === 'graduationDetails') {
            return this.isUgMarksMode();
        }

        if (sectionKey === 'postGraduationDetails' &&
            fieldMeta.calculate === 'computePostGraduationPercentage') {
            return this.isPgMarksMode();
        }

        return true;
    }

    backup = {
        postGraduation: {},
        postGraduationDetails: {},
        postSemester: {},
        postYear: {},
        professionalQualification: {},
        academicBreak: {}
    };

    // handle field change events from children
    handleSectionFieldChange(e) {

        const oldGradDegreeType = this.education.graduation.Degree_Type__c;
        const oldPostGradDegreeType = this.education.postGraduation.Degree_Type__c;
        const oldGradExamPattern = this.education.graduation.Pattern_of_Examination__c;
        const oldPostGradExamPattern = this.education.postGraduation.Pattern_of_Examination__c;
        const oldMarkingScheme = this.education?.[e.detail.sectionKey]?.Marking_Scheme__c;

        const oldDegreeStatus = this.education?.graduationDetails?.DegreeStatus__c;
        const oldPostDegreeStatus = this.education?.postGraduationDetails?.DegreeStatus__c;

        const { api, displayValue, fieldMeta, sectionKey, sequence } = e.detail;

        let {value} = e.detail;

        //for others record picker
        this.education[sectionKey] ||= {};
        this.education[sectionKey].Display ||= {};

        if (value === null || value === undefined || value === '') {
            // ✅ remove stale lookup label
            delete this.education[sectionKey].Display[api];
        } else {
            this.education[sectionKey].Display[api] = displayValue;
        }

        // 🧹 optional: remove empty Display object
        if (this.education[sectionKey].Display &&
            Object.keys(this.education[sectionKey].Display).length === 0) {
            delete this.education[sectionKey].Display;
        }

        if (sectionKey === 'graduationDetails' && api === 'DegreeStatus__c') {
            const isPursuing = value === 'Pursuing';

            // ensure object exists
            this.education.basicAcademic ||= {};

            // update GraduationCompleted__c
            this.education.basicAcademic.GraduationCompleted__c =
                isPursuing ? 'No' : 'Yes';

            if(oldDegreeStatus != value){
                this.education.graduationDetails.MonthAndYearOfPassing__c = null;
            }
        }

        if (sectionKey === 'postGraduationDetails' && api === 'DegreeStatus__c') {
            if(oldPostDegreeStatus != value){
                this.education.postGraduationDetails.MonthAndYearOfPassing__c = null;
            }
        }

        if (api === 'AfterTen__c') {
            // set value in virtual location
            this.education.after10[api] = value;

            if (!(value === '12th' || value === 'both')) {
                this.education.twelfth = {};
            }

            if (!(value === 'diploma' || value === 'both')) {
                this.education.diploma = {};
            }


            // rebuild renderModel to reflect visibility changes
            this._buildRenderModelAll();
            return;
        }
        // find which section contains this api in metadata
        if (!sectionKey) {
            if (api.startsWith('sem')) {
                this.education.semester = this.education.semester || {};
                this.education.semester[api] = value;
                this._buildRenderModelAll();
                return;
            }
            if (api.startsWith('year')) {
                this.education.year = this.education.year || {};
                this.education.year[api] = value;
                this._buildRenderModelAll();
                return;
            }
            return;
        }
        if(sectionKey == 'postSemester' || sectionKey == 'postYear' || sectionKey == 'year' || sectionKey == 'semester') {
            this.education[sectionKey] = this.education[sectionKey] || {};
            this.education[sectionKey].isSequential = true;
            this.education[sectionKey][sequence] = this.education[sectionKey][sequence] || {};
            this.education[sectionKey][sequence][api] = value;
        } else if (!['professionalQualification','semester','year','postSemester','postYear'].includes(sectionKey)) {
            this.education[sectionKey] = this.education[sectionKey] || {};
            this.education[sectionKey][api] = value;
        }

        if (api === 'Marking_Scheme__c') {
            this._handleMarkingSchemeTransition(sectionKey, oldMarkingScheme, value);
        }

        if (sectionKey === 'haveAcademicBreak' && api === 'HasAcademicBreak__c') {
            const newVal = value;

            if (newVal === 'Yes') {
                this.education.haveAcademicBreak = {
                    Id: this.backup.academicBreak?.Id || this.education.haveAcademicBreak?.Id || null,
                    HasAcademicBreak__c: 'Yes',
                    AcademicBreakYear__c: this.backup.academicBreak?.AcademicBreakYear__c ?? this.education.haveAcademicBreak?.AcademicBreakYear__c ?? null,
                    AcademicBreakReason__c: this.backup.academicBreak?.AcademicBreakReason__c ?? this.education.haveAcademicBreak?.AcademicBreakReason__c ?? null
                };
            } else {
                this.backup.academicBreak = { ...this.education.haveAcademicBreak };
                this.education.haveAcademicBreak = {
                    Id: this.backup.academicBreak?.Id || null,
                    HasAcademicBreak__c: 'No',
                    AcademicBreakYear__c: null,
                    AcademicBreakReason__c: null
                };
            }

            this._buildRenderModelAll();
            return;
        }

        //------------------------------------------------------
        // POST GRADUATION - Yes / No toggle
        //------------------------------------------------------
        if (sectionKey === 'havePostGrad' && api === 'AnyPostGraduation__c') {
            const newVal = value;

            // If user selects YES → restore old backup
            if (newVal === 'Yes') {
                this.education.postGraduation           = { ...this.backup.postGraduation };
                this.education.postGraduationDetails    = { ...this.backup.postGraduationDetails };
                this.education.postSemester             = { ...this.backup.postSemester };
                this.education.postYear                 = { ...this.backup.postYear };
            }

            // If user selects NO → clear UI but preserve IDs in backup
            else {
                // BACKUP the real PG values INCLUDING ID
                this.backup.postGraduation = { ...this.education.postGraduation };
                this.backup.postGraduationDetails = { ...this.education.postGraduationDetails };
                this.backup.postSemester = { ...this.education.postSemester };
                this.backup.postYear = { ...this.education.postYear };

                // CLEAR UI — DO NOT SEND ID WHEN PG = NO
                this.education.postGraduation = {};
                this.education.postGraduationDetails = {};
                this.education.postSemester = {};
                this.education.postYear = {};

            }

            this.education.havePostGrad.AnyPostGraduation__c = newVal;
            this._buildRenderModelAll();
            return;
        }

        //------------------------------------------------------
        // PROFESSIONAL QUALIFICATION - Yes / No toggle
        //------------------------------------------------------
        if (sectionKey === 'haveProfessionalQualification' && api === 'HasProfessionalQualification__c') {
            const newVal = value;

            if (newVal === 'Yes') {
                // Restore old PQ values
                this.education.professionalQualification = JSON.parse(
                    JSON.stringify(this.backup.professionalQualification)
                );
            }
            else {
                // Backup PQ before clearing
                this.backup.professionalQualification = JSON.parse(
                    JSON.stringify(this.education.professionalQualification)
                );

                // Clear UI but keep Ids for proper update/delete later
                this.education.professionalQualification = {
                    1: { Id: this.backup.professionalQualification?.[1]?.Id || null },
                    2: { Id: this.backup.professionalQualification?.[2]?.Id || null },
                    3: { Id: this.backup.professionalQualification?.[3]?.Id || null },
                    isSequential: false
                };
            }

            this.education.haveProfessionalQualification.HasProfessionalQualification__c = newVal;
            this._buildRenderModelAll();
            return;
        }



        // PROFESSIONAL QUALIFICATION (non-sequential keyed by record Id)
        if (sectionKey === 'professionalQualification') {
            const pq = this.education.professionalQualification || {};

            pq.isSequential = false;

            // All PQ rows use numeric sequence keys (1..3)
            const seq = Number(sequence);

            if (!seq || seq < 1 || seq > 3) return;

            pq[seq] = pq[seq] || {};
            pq[seq][api] = value;

            // Recalculate PQ percentage for this row
            this._runSectionCalculations('professionalQualification');

            this.education.professionalQualification = pq;
            this._buildRenderModelAll();
            return;
        }

        // =============================================
        // PATTERN OF EXAMINATION CHANGE (UG + PG)
        // =============================================
        if ((sectionKey === 'graduation' || sectionKey === 'postGraduation')
            && api === 'Pattern_of_Examination__c') {
            const yearKey     = sectionKey === 'graduation' ? 'year'        : 'postYear';
            const semKey      = sectionKey === 'graduation' ? 'semester'    : 'postSemester';
            const oldPattern = sectionKey == 'graduation' ? oldGradExamPattern : oldPostGradExamPattern;
            const newPattern = value || '';

            const oldIsYear = oldPattern.toLowerCase().includes('year');
            const oldIsSem  = oldPattern.toLowerCase().includes('sem');

            const newIsYear = newPattern.toLowerCase().includes('year');
            const newIsSem  = newPattern.toLowerCase().includes('sem');

            // ⭐ IMPORTANT: update pattern BEFORE rebuild
            this.education[sectionKey].Pattern_of_Examination__c = value;
            
            // SEM → YEAR
            if (oldIsSem && newIsYear) {
                this.deleteEntireMode(semKey);
                this.deleteEntireMode(yearKey);
                this.education[semKey] = {};
                this.education[yearKey] = {};   // reset target mode
            }


            // YEAR → SEM
            if (oldIsYear && newIsSem) {
                this.deleteEntireMode(semKey);
                this.deleteEntireMode(yearKey);
                this.education[yearKey] = {};
                this.education[semKey] = {};    // reset target mode
            }

            // ⭐ REBUILD UI (now patternVal will be correct)
            this._buildRenderModelAll();
            return;
        }


        // =============================================
        // DEGREE TYPE CHANGE (UG + PG)
        // =============================================
        if ((sectionKey === 'graduation' || sectionKey === 'postGraduation') && api === 'Degree_Type__c') {

            const newYears = this.extractYears(value);
            const oldYears = sectionKey === 'graduation'
                ? this.extractYears(oldGradDegreeType)
                : this.extractYears(oldPostGradDegreeType);

            // update now
            this.education[sectionKey].Degree_Type__c = value;

            // if years increased → do nothing
            if (oldYears && newYears >= oldYears) {
                this._buildRenderModelAll();
                return;
            }

            const pattern = (this.education[sectionKey].Pattern_of_Examination__c || '').toLowerCase();
            const isYear = pattern.includes('year');
            const isSem  = pattern.includes('sem');

            // UG OR PG MODE MAP
            const yearKey     = (sectionKey === 'graduation') ? 'year' : 'postYear';
            const semesterKey = (sectionKey === 'graduation') ? 'semester' : 'postSemester';

            if (isYear) {
                this.truncateSequentialSection(this.education[yearKey], newYears, yearKey);
                this.education[semesterKey] = {}; // clear opposite mode
            }

            if (isSem) {
                this.truncateSequentialSection(this.education[semesterKey], newYears * 2, semesterKey);
                this.education[yearKey] = {};     // clear opposite mode
            }

            this._runSectionCalculations('graduationDetails');
            this._buildRenderModelAll();
            return;
        }

        if (sectionKey === 'graduation' || sectionKey === 'postGraduation') {

            if (api === "State__c") {

                const stateId = value;
                const stateLabel = displayValue;

                if (!stateId || stateLabel === 'Other') {

                    this.education[sectionKey].University__c = null;
                    this.education[sectionKey].College__c = null;

                    if (this.education[sectionKey].Display) {
                        delete this.education[sectionKey].Display.University__c;
                        delete this.education[sectionKey].Display.College__c;
                    }
                }
            }

            if (api === "University__c") {

                const uniId = value;
                const uniLabel = displayValue;

                if (!uniId || uniLabel === 'Other') {

                    this.education[sectionKey].College__c = null;

                    if (this.education[sectionKey].Display) {
                        delete this.education[sectionKey].Display.College__c;
                    }
                }
            }
        }

        if (sectionKey === 'graduation' || sectionKey === 'postGraduation') {

            const display = this.education[sectionKey]?.Display || {};

            // ---------- STATE ----------
            if (api === "State__c") {

                if (display.State__c !== 'Other') {
                    this.education[sectionKey].OtherState__c = null;
                }
            }

            // ---------- UNIVERSITY ----------
            if (api === "University__c") {

                if (display.University__c !== 'Other') {
                    this.education[sectionKey].OtherUniversity__c = null;
                }
            }

            // ---------- COLLEGE ----------
            if (api === "College__c") {

                if (display.College__c !== 'Other') {
                    this.education[sectionKey].OtherCollege__c = null;
                }
            }
        }


        // run hooks if any
        if (fieldMeta && fieldMeta.onChange && typeof this[fieldMeta.onChange] === 'function') {
            this[fieldMeta.onChange](sectionKey, api, value);
        }

        if (sectionKey === 'semester' || sectionKey === 'year') {
            this._runSectionCalculations('graduationDetails');
        }

        // recompute calculations for that section and rebuild renderModel
        this._runSectionCalculations(sectionKey);
        this._buildRenderModelAll();
    }

    handleLookupSet(e){
        const { api, value, displayValue, sectionKey } = e.detail;

        const fieldMeta = this.metadata[sectionKey]?.fields?.find(f => f.api === api);

        const normalized = this._normalizeValue(api, value, fieldMeta);

        this.education[sectionKey][api] = normalized;
        
        //for others record picker
        this.education[sectionKey] ||= {};
        this.education[sectionKey].Display ||= {};
        this.education[sectionKey].Display[api] = displayValue;

        if(['State__c','University__c','College__c'].includes(api)){
            this._handleLookupDrivenRerender(api);
        }
    }

    SECTION_DEPENDENCIES = {
        graduation: ['State__c','University__c','College__c'],
        postGraduation: ['State__c']
    };


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
        const rebuilt = new Set(sectionKeys);

        if (rebuilt.has('graduation')) {
            this.graduationSections = this.graduationSections.map(s =>
                rebuilt.has(s.key) ? this._buildSectionRenderModel(s.key) : s
            );
        }

        if (rebuilt.has('postGraduation')) {
            this.postGraduationSections = this.postGraduationSections.map(s =>
                rebuilt.has(s.key) ? this._buildSectionRenderModel(s.key) : s
            );
        }
    }

    extractYears(degreeTypeValue) {
        const match = (degreeTypeValue || '').match(/([1-5])\s*year/i);
        return match ? parseInt(match[1], 10) : null;
    }

    truncateSequentialSection(section, allowedMax, logicalName) {
        if (!section) return;

        const deletedList = [];

        // numeric keys only → actual rows
        Object.keys(section)
            .filter(key => !isNaN(Number(key)))
            .forEach(key => {
                const seq = Number(key);

                if (seq > allowedMax) {
                    const row = section[key];
                    if (row && row.Id) {
                        deletedList.push(row.Id);
                    }
                    delete section[key];
                }
            });

        const delKey = logicalName + 'Deleted';

        if (!this.education[delKey]) {
            this.education[delKey] = [];
        }

        this.education[delKey].push(...deletedList);
    }

    deleteEntireMode(modeKey) {
        // modeKey = 'semester', 'year', 'postSemester', or 'postYear'

        const section = this.education[modeKey];

        if (!section) return;

        const deletedList = [];

        // Only numeric keys = actual semester/year rows
        Object.keys(section)
            .filter(k => !isNaN(Number(k)))
            .forEach(k => {
                const row = section[k];
                if (row && row.Id) {
                    deletedList.push(row.Id);
                }
                delete section[k];   // remove from UI state
            });

        // Store deleted list in education.{modeKey}Deleted for backend
        const delKey = modeKey + 'Deleted';
        if (!this.education[delKey]) {
            this.education[delKey] = [];
        }
        this.education[delKey].push(...deletedList);

        // Clear object completely
        this.education[modeKey] = {};
    }


    _runSectionCalculations(sectionKey) {
        const sec = this.metadata[sectionKey];
        if (!sec || !sec.fields) return;

        const secData = this.education[sectionKey] || {};

        // Row-based (sequential or fixed 1..N)
        const isRowBased =
            secData.isSequential ||
            ['professionalQualification','semester','year','postSemester','postYear']
                .includes(sectionKey);

        if (isRowBased) {
            // Iterate each row
            Object.keys(secData)
                .filter(k => k !== 'isSequential')
                .forEach(seq => {
                    sec.fields.forEach(f => {
                        if (this._shouldRunCalculation(sectionKey, f) && f.sequence === Number(seq)) {
                            const val = this[f.calculate](
                                sectionKey,
                                f.api,
                                f       // pass meta for sequence
                            );
                            secData[seq][f.api] = val;
                        }
                    });
                });

            return;
        }

        // SPECIAL ORDERING FOR GRADUATION DETAILS
        if (sectionKey === 'graduationDetails' && this.isUgMarksMode()) {

            // 1️⃣ First compute totals
            const totalsFields = sec.fields.filter(f => f.calculate === 'computeGraduationTotals');
            totalsFields.forEach(f => {
                const val = this.computeGraduationTotals(sectionKey, f.api, f);
                secData[f.api] = val;
            });

            // 2️⃣ Then compute percentage
            const percentField = sec.fields.find(f => f.calculate === 'computeGraduationPercentage');
            if (percentField) {
                secData[percentField.api] = this.computeGraduationPercentage();
            }

            return;
        }

        // Single-row section
        sec.fields.forEach(f => {
            if (this._shouldRunCalculation(sectionKey, f)) {
                const val = this[f.calculate](sectionKey, f.api, f);
                secData[f.api] = val;
            }
        });
    }

    computeCgpaPercentage(obtained, max, conversionFactor) {

        const cgpa = Number(obtained);
        const maxCgpa = Number(max);

        if (isNaN(cgpa) || isNaN(maxCgpa) || maxCgpa <= 0) return null;

        const finalConv = Number(conversionFactor) || 10;

        return Number((((cgpa / maxCgpa) * 10 * finalConv)).toFixed(2));
    }


    // generic compute percentage used by tenth/twelfth/diploma
    computePercentage(sectionKey) {
        const secData = this.education[sectionKey] || {};

        const scheme = secData.Marking_Scheme__c || '';

        const max = Number(secData.Maximum_Marks__c);
        const obtained = Number(secData.Obtained_Marks__c);

        // Missing obtained → no percentage
        if (isNaN(obtained)) return null;

        if (scheme === 'CGPA') {
            return this.computeCgpaPercentage(obtained, max, secData.Conversion_Factor__c);
        }

        // Non-CGPA → standard percentage
        if (!isNaN(max) && max > 0) {
            return Number((((obtained / max) * 100)).toFixed(2));
        }

        return null;
    }


    recalcPercentage(sectionKey, api, value) {
        this._runSectionCalculations(sectionKey);
        this._buildRenderModelAll();
    }

    computeGraduationPercentage() {
        if (!this.isUgMarksMode()) return null;

        const sec = this.education.graduationDetails || {};

        const max = Number(sec.Maximum_Marks__c);
        const obtained = Number(sec.Obtained_Marks__c);

        if (isNaN(obtained)) return null;

        if (!isNaN(max) && max > 0) {
            return Number((((obtained / max) * 100)).toFixed(2));
        }

        return null;
    }

    recalcGraduationPercentage(sectionKey, api, value) {
        this._runSectionCalculations('graduationDetails');
        this._buildRenderModelAll();
    }

    computeGraduationTotals(sectionKey, api) {
        if (!this.isUgMarksMode()) {
            return this.education.graduationDetails?.[api] ?? null;
        }

        const pattern =
            (this.education.graduation?.Pattern_of_Examination__c || '')
            .toLowerCase();

        const sourceSection = pattern.includes('year')
            ? this.education.year || {}
            : pattern.includes('sem')
            ? this.education.semester || {}
            : {};

        let totalMax = 0;
        let totalObt = 0;
        let hasCompleteRow = false;

        Object.keys(sourceSection)
            .filter(k => k !== 'isSequential')
            .forEach(k => {

                const row = sourceSection[k] || {};

                const maxRaw = row.Maximum_Marks_SGPA__c;
                const obtRaw = row.Obtained_Marks_SGPA__c;

                // Only proceed if BOTH fields are actually filled
                if (
                    maxRaw !== null && maxRaw !== undefined && maxRaw !== '' &&
                    obtRaw !== null && obtRaw !== undefined && obtRaw !== ''
                ) {
                    const maxVal = Number(maxRaw);
                    const obtVal = Number(obtRaw);

                    if (!isNaN(maxVal) && !isNaN(obtVal)) {
                        totalMax += maxVal;
                        totalObt += obtVal;
                        hasCompleteRow = true;
                    }
                }

            });

        // 🔥 CGPA = average instead of sum
        const normalizedMax = hasCompleteRow ? totalMax : null;
        const normalizedObt = hasCompleteRow ? totalObt : null;

        this.education.graduationDetails.Maximum_Marks__c = normalizedMax;
        this.education.graduationDetails.Obtained_Marks__c = normalizedObt;

        if (api === 'Maximum_Marks__c') return normalizedMax;
        if (api === 'Obtained_Marks__c') return normalizedObt;

        return this.education.graduationDetails[api]; // 🔥 do not wipe other fields
    }


    computePostGraduationPercentage(sectionKey, api) {
        if (!this.isPgMarksMode()) return null;

        const sec = this.education.postGraduationDetails || {};

        const max = Number(sec.Maximum_Marks__c);
        const obtained = Number(sec.Obtained_Marks__c);

        if (isNaN(obtained)) return null;

        if (!isNaN(max) && max > 0) {
            return Number((((obtained / max) * 100)).toFixed(2));
        }

        return null;
    }

    recalcPostGraduationPercentage(sectionKey, api, value) {
        this._runSectionCalculations('postGraduationDetails');
        this._buildRenderModelAll();
    }

    computePQPercentage(sectionKey, api, f) {
        // Use the meta passed in (f) which contains the correct sequence for the row
        const seq = Number(f && f.sequence);
        if (!seq) return null;

        const pq = this.education.professionalQualification || {};
        const row = pq[seq] || {};

        const total = Number(row.Total_Max_Marks__c || 0);
        const obtained = Number(row.Marks_Obtained__c || 0);

        if (!total || !obtained) return null;

        return ((obtained / total) * 100).toFixed(2);
    }

    _runAllCalculations() {
        this._runSectionCalculations('tenth');
        this._runSectionCalculations('twelfth');
        this._runSectionCalculations('diploma');
        // Graduation totals
        this._runSectionCalculations('graduationDetails');

        // Post Graduation totals (if PG exists)
        if (this.education.havePostGrad?.AnyPostGraduation__c === 'Yes') {
            this._runSectionCalculations('postGraduationDetails');
        }

        // Professional Qualifications percentage
        if (this.education.haveProfessionalQualification?.HasProfessionalQualification__c === 'Yes') {
            this._runSectionCalculations('professionalQualification');
        }
    }

    _isFieldVisible(fMeta) {
        if (!fMeta.visibleWhen) return true;

        const conds = Array.isArray(fMeta.visibleWhen)
            ? fMeta.visibleWhen
            : [fMeta.visibleWhen];

        const root = this.contextBlock || this.education;

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

    // validation
    validateAll() {
        // Clear existing client-side errors in child composites
        const academicCmp = this.template.querySelector('c-af-academic-details');
        const graduationCmp = this.template.querySelector('c-af-graduation-details');
        const postGraduationCmp = this.template.querySelector('c-af-post-graduation-details');
        const professionalQualificationCmp = this.template.querySelector('c-af-professional-qualification');
        const academicFooterCmp = this.template.querySelector('c-af-academic-details-footer');
        academicCmp && academicCmp.applyErrors({});
        graduationCmp && graduationCmp.applyErrors({});
        postGraduationCmp && postGraduationCmp.applyErrors({});
        professionalQualificationCmp && professionalQualificationCmp.applyErrors({});
        academicFooterCmp && academicFooterCmp.applyErrors({});

        const after10Val = this.education.after10.AfterTen__c; // fix undefined variable bug

        // Build error maps per section: { [api]: 'message' }
        const errorMaps = {
            tenth: {},
            after10: {},
            twelfth: {},
            diploma: {},
            graduation: {},
            graduationDetails: {},
            havePostGrad: {},
            postGraduation: {},
            postGraduationDetails: {},
            year: {},               // ← ADD
            semester: {},           // ← ADD
            postYear: {},           // ← ADD
            postSemester: {},       // ← ADD
            professionalQualification: {},
            importantCertification: {}
        };

        // Helper to set missing errors
        const addMissing = (sectionKey, fieldMeta, sectionTitle) => {
            fieldMeta = this._resolveFieldMeta(sectionKey, fieldMeta);
            if (!this._isFieldVisible(fieldMeta)) return;

            const secData = this.education[sectionKey] || {};

            const metaSec = this.metadata[sectionKey] || {};

            if (metaSec?.layout === 'fluid') {
                const val = this.education[sectionKey]?.[fieldMeta.api];
                if (fieldMeta.required && (val === null || val === '' || val === undefined)) {
                    errorMaps[sectionKey][fieldMeta.api] =
                        `${fieldMeta.shortLabel || fieldMeta.label || fieldMeta.api} is required`;
                }

                const fieldVal = secData[fieldMeta.api];

                if (fieldMeta.type === 'number') {
                    const err = validateNumber(fieldMeta, fieldVal);
                    if (err) {
                        errorMaps[sectionKey][fieldMeta.api] = err;
                    }
                }

                return;
            }            

            // Determine expected row count
            const metaFields = metaSec.fields || [];

            let maxSeq = 0;

            const fieldVal = secData[fieldMeta.api];

            if (fieldMeta.type === 'number') {
                const err = validateNumber(fieldMeta, fieldVal);
                if (err) {
                    errorMaps[sectionKey][fieldMeta.api] = err;
                }
            }


            // ----------------------------
            // 1. Determine from degree type
            // ----------------------------
            const degreeTypeVal = this.education[sectionKey === 'year' || sectionKey === 'semester' 
                ? 'graduation' 
                : 'postGraduation']?.Degree_Type__c || '';

            const patternVal = this.education[sectionKey === 'year' || sectionKey === 'semester'
                ? 'graduation'
                : 'postGraduation']?.Pattern_of_Examination__c || '';

            // Extract number of years (3,4,5)
            const years = (() => {
                const m = (degreeTypeVal || '').toString().match(/([3-5])\s*year/i);
                if (!m) return null;
                return parseInt(m[1], 10);
            })();

            const isYearWise = patternVal.toLowerCase().includes('year');
            const isSemWise  = patternVal.toLowerCase().includes('sem');

            // ------------------------------------
            // 2. If degreeType + pattern available
            // ------------------------------------
            if (years) {
                if (isYearWise)   maxSeq = years;       // 3,4,5 years
                if (isSemWise)    maxSeq = years * 2;   // 6,8,10 sems
            }

            // ------------------------------------
            // 3. Fallback to metadata (old logic)
            // ------------------------------------
            if (!maxSeq && metaFields.some(f => f.sequence)) {
                maxSeq = metaFields.reduce(
                    (m, f) => Math.max(m, Number(f.sequence || 0)),
                    0
                );
            }

            // ------------------------------------
            // 4. Fallback to existing data
            // ------------------------------------
            if (!maxSeq) {
                maxSeq = Object.keys(secData)
                    .filter(k => !isNaN(Number(k)))
                    .reduce((m, k) => Math.max(m, Number(k)), 0);
            }

            // ------------------------------------
            // 5. Final fallback defaults
            // ------------------------------------
            if (!maxSeq && secData.isSequential) {
                if (sectionKey === 'semester' || sectionKey === 'postSemester') maxSeq = 10;
                else if (sectionKey === 'year' || sectionKey === 'postYear') maxSeq = 5;
                else maxSeq = 1;
            }

            const getRequired = (periodNum, totalPeriods, exemptTail) => {
                const pursuing =
                    this.education?.graduationDetails?.DegreeStatus__c === 'Pursuing';

                if (!periodNum || totalPeriods <= 0) return false;

                return pursuing
                    ? periodNum <= totalPeriods - exemptTail
                    : true;
            };

            // MULTI-ROW / SEQUENTIAL VALIDATION
            if (secData.isSequential || maxSeq > 0) {

                const errors = {};

                // determine exemptTail based on section type
                const exemptTail =
                    (sectionKey === 'semester' || sectionKey === 'postSemester') ? 2 : 1;

                for (let seq = 1; seq <= maxSeq; seq++) {

                    const row = secData[seq] || {};

                    const fm = metaFields.find(f =>
                        f.api === fieldMeta.api &&
                        Number(f.sequence) === Number(seq)
                    );

                    if (!fm) continue;

                    const val = row[fm.api];

                    if (fm.type === 'number') {

                        const err = validateNumber(fm, val);

                        if (err) {
                            if (!errors[seq]) errors[seq] = {};
                            errors[seq][fm.api] = err;
                        }
                    }

                    // ⭐ USE SAME REQUIRED LOGIC
                    const isRequired = getRequired(seq, maxSeq, exemptTail);

                    if ((!val || val === '' || val === null || val === undefined) && isRequired) {
                        if (!errors[seq]) errors[seq] = {};
                        errors[seq][fm.api] =
                            `${fm.shortLabel || fm.label || fm.api} is required`;
                    }

                    // marks comparison validation (unchanged)
                    const obtained = parseFloat(row["Obtained_Marks_SGPA__c"]);
                    const maxMarks  = parseFloat(row["Maximum_Marks_SGPA__c"]);

                    if (!isNaN(obtained) && !isNaN(maxMarks) && obtained > maxMarks) {
                        if (!errors[seq]) errors[seq] = {};
                        errors[seq]["Obtained_Marks_SGPA__c"] =
                            "Obtained Mark should be less than maximum mark";
                    }
                }

                // MERGE instead of overwrite
                Object.keys(errors).forEach(seq => {
                    const rowErrors = errors[seq];

                    // 🚨 Skip rows that have NO real errors
                    if (!rowErrors || Object.keys(rowErrors).length === 0) {
                        return; // ← IMPORTANT: prevents phantom rows
                    }

                    if (!errorMaps[sectionKey][seq]) {
                        errorMaps[sectionKey][seq] = {};
                    }

                    Object.assign(errorMaps[sectionKey][seq], rowErrors);
                });

                // DO NOT return here
            }

            // SINGLE ROW VALIDATION
            const val = secData[fieldMeta.api];

            if (fieldMeta.required && (val === '' || val === null || val === undefined)) {
                errorMaps[sectionKey][fieldMeta.api] =
                    `${fieldMeta.shortLabel || fieldMeta.label || fieldMeta.api} is required`;
            }

            // Special rule: percentage minimum
            if (fieldMeta.api === 'Percentage__c' && fieldMeta.minPercentage) {
                const v = parseFloat(secData[fieldMeta.api]);
                if (!isNaN(v) && v < fieldMeta.minPercentage) {
                    errorMaps[sectionKey][fieldMeta.api] =
                        `Cannot be less than ${fieldMeta.minPercentage}%`;
                }
            }
        };

        const validateWordLimit = (text, limit = 200) => {
            if (!text) {
                return { isValid: true, count: 0 };
            }

            const words = text.trim().split(/\s+/).filter(Boolean);
            const count = words.length;

            return {
                isValid: count <= limit,
                count
            };
        }

        //50 word limit
        if(this.education.importantCertification.CertificationDetails__c){
            const { isValid, count } = validateWordLimit(this.education.importantCertification.CertificationDetails__c, 50);
            if(!isValid){
                errorMaps.importantCertification = errorMaps.importantCertification || {};
                errorMaps.importantCertification.CertificationDetails__c = `Should not exceed 50 words. You have ${count} words`;
            }
        }

        // Base sections
        ['tenth','graduation','graduationDetails'].forEach(key => {
            const sec = this.metadata[key];
            if (!sec || !sec.fields) return;
            sec.fields.forEach(f => addMissing(key, f, sec.title));
        });

        ['after10','havePostGrad'].forEach(key => {
            const sec = this.metadata[key];
            if (!sec || !sec.fields) return;
            sec.fields.forEach(f => addMissing(key, f, sec.title));
        });

        // Academic marks and dates
        ['tenth','twelfth','diploma','graduationDetails','postGraduationDetails'].forEach((key, index, thisArray) => {
            const sec = this.metadata[key];

            if (!sec || !sec.fields) return;

            const secData = this.education[key];
            if (!secData) return;

            errorMaps[key] ||= {};

            const maxMark = secData.hasOwnProperty('Maximum_Marks__c') ? parseFloat(secData['Maximum_Marks__c']) : NaN;
            const obtMark = secData.hasOwnProperty('Obtained_Marks__c') ? parseFloat(secData['Obtained_Marks__c']) : NaN;

            if (!isNaN(maxMark) && !isNaN(obtMark) && maxMark < obtMark) {
                errorMaps[key]["Obtained_Marks__c"] = 'Obtained Mark should be less than maximum mark';
            }

            
            if(secData.MonthAndYearOfCommencement__c && secData.MonthAndYearOfPassing__c) {

                const normalisedCommencementMonthYear = this._normalizeMonthYear(secData.MonthAndYearOfCommencement__c);
                const normalisedEndMonthYear = this._normalizeMonthYear(secData.MonthAndYearOfPassing__c);

                if(normalisedCommencementMonthYear > normalisedEndMonthYear){
                    errorMaps[key]["MonthAndYearOfCommencement__c"] = 'Commencement Date should be earlier than End Date';
                }
                if(normalisedCommencementMonthYear === normalisedEndMonthYear){
                    errorMaps[key]["MonthAndYearOfCommencement__c"] = 'Commencement Date and End Date cannot be of same month and year';
                }
            }

            const getLatest = (sections) => {
                const availableSections = sections.filter(sectionName =>
                    this.education?.[sectionName]?.MonthAndYearOfPassing__c
                );

                if (!availableSections.length) return null;

                let latestSection = availableSections[0];

                availableSections.forEach((sectionName, i) => {
                    if (i === 0) return;

                    const latestPassing = this._normalizeMonthYear(
                        this.education[latestSection].MonthAndYearOfPassing__c
                    );
                    const currentPassing = this._normalizeMonthYear(
                        this.education[sectionName].MonthAndYearOfPassing__c
                    );

                    if (latestPassing < currentPassing) {
                        latestSection = sectionName;
                    }
                });

                return latestSection;
            };

            const ensureChronology = (currentValue, predecessorSection, targetField, targetFieldLabel) => {
                if (!currentValue || !predecessorSection) return;

                const predecessorPassing = this.education?.[predecessorSection]?.MonthAndYearOfPassing__c;
                if (!predecessorPassing) return;

                if (
                    this._normalizeMonthYear(currentValue) <=
                    this._normalizeMonthYear(predecessorPassing)
                ) {
                    errorMaps[key][targetField] = `${targetFieldLabel} must be later than the ${this.metadata[predecessorSection].title} passing date`;
                }
            };

            if (Object.keys(errorMaps[key]).length === 0) {
                if (key === 'twelfth') {
                    ensureChronology(secData.MonthAndYearOfPassing__c, 'tenth', 'MonthAndYearOfPassing__c', 'Passing Date');
                }

                if (key === 'diploma' || key === 'twelfth') {
                    ensureChronology(secData.MonthAndYearOfCommencement__c, 'tenth', 'MonthAndYearOfCommencement__c', 'Commencement Date');
                }

                if (key === 'graduationDetails') {
                    const secToValidate = getLatest(['diploma', 'twelfth']);
                    ensureChronology(secData.MonthAndYearOfCommencement__c, secToValidate, 'MonthAndYearOfCommencement__c', 'Commencement Date');
                }

                if (key === 'postGraduationDetails') {
                    ensureChronology(secData.MonthAndYearOfCommencement__c, 'graduationDetails', 'MonthAndYearOfCommencement__c', 'Commencement Date');
                }
            }
        });
     
        
        const ensurePercentMet = (minValue, unit, section, api) => {
            const currentValue = this.education[section][api];
            if (currentValue != null && currentValue < parseFloat(minValue)) {
                errorMaps[section] = errorMaps[section] || {};
                errorMaps[section][api] = `Minimum required ${unit} is ${minValue}`;
            }
        }

        const pursuing = this.education?.graduationDetails?.DegreeStatus__c === 'Pursuing';

        if (!pursuing) {
            const minimumRequiredPercent =
                this.application?.Batch__r?.MinGradPercentRequired__c || 55;

            ensurePercentMet(
                minimumRequiredPercent,
                'Percent',
                'graduationDetails',
                'Percentage__c'
            );
        }

        // Conditional sections
        if (after10Val === '12th') {
            const sec = this.metadata.twelfth;
            if (sec && sec.fields) {
                sec.fields.forEach(f => addMissing('twelfth', f, '12th'));
            }
        }
        if (after10Val === 'diploma') {
            const sec = this.metadata.diploma;
            if (sec && sec.fields) {
                sec.fields.forEach(f => addMissing('diploma', f, 'Diploma'));
            }
        }

        if (after10Val === 'both') {
            const secTwelfth = this.metadata.twelfth;
            if (secTwelfth && secTwelfth.fields) {
                secTwelfth.fields.forEach(f => addMissing('twelfth', f, '12th'));
            }

            const secDiploma = this.metadata.diploma;
            if (secDiploma && secDiploma.fields) {
                secDiploma.fields.forEach(f => addMissing('diploma', f, 'Diploma'));
            }
        }

        // --- PROFESSIONAL QUALIFICATION (only row 1 is required) ---
        const hasPQ = this.education.haveProfessionalQualification?.HasProfessionalQualification__c;

        if (hasPQ === 'Yes') {
            const pq = this.education.professionalQualification || {};
            const pqErrors = errorMaps.professionalQualification = {};
            const pqMeta = this.metadata.professionalQualification.fields;

            Object.keys(pq)
                .filter(k => k !== 'isSequential')              // skip non-row flag
                .forEach(rowKey => {

                    const row = pq[rowKey];                    // ⭐ correct PQ row
                    const seq = Number(rowKey);                // PQ row sequence
                    pqErrors[seq] = pqErrors[seq] || {};

                    // Validate only fields that belong to this row's sequence
                    pqMeta
                        .filter(f => Number(f.sequence) === seq)
                        .forEach(f => {

                            const val = row[f.api];

                            // Required validation
                            if (f.required && (val === '' || val === null || val === undefined)) {
                                pqErrors[seq][f.api] = `${f.shortLabel || f.label || f.api} is required`;
                            }

                            if (f.type === 'number') {

                                const err = validateNumber(f, val);

                                if (err) {
                                    pqErrors[seq][f.api] = err;
                                }
                            }
                        });

                        if (row.hasOwnProperty("Marks_Obtained__c") && row.hasOwnProperty("Total_Max_Marks__c")) {
                            const obtained = parseFloat(row["Marks_Obtained__c"]);
                            const total    = parseFloat(row["Total_Max_Marks__c"]);

                            // Guard against invalid numbers
                            if (!isNaN(obtained) && !isNaN(total) && obtained > total) {
                                pqErrors[seq]["Marks_Obtained__c"] =
                                    "Marks Obtained cannot be greater than Total Marks";
                            }
                        }

                });

        }

        if (professionalQualificationCmp) {
            professionalQualificationCmp.applyErrors(errorMaps.professionalQualification);
        }

        // Check if we should validate Post Graduation sections
        const anyPostGraduation = (this.education.havePostGrad && this.education.havePostGrad.AnyPostGraduation__c) || '';
        const showPostGraduation = anyPostGraduation === 'Yes';

        if (showPostGraduation) {
            // Add validation for Post Graduation sections
            ['postGraduation','postGraduationDetails'].forEach(key => {
                const sec = this.metadata[key];
                if (!sec || !sec.fields) return;
                sec.fields.forEach(f => addMissing(key, f, sec.title));
            });
        }

        // --- validate sequential grids (year/semester + post variants) ---
        // Determine which UG/PG grids are visible from metadata/education
        const patternVal = (this.education.graduation && this.education.graduation.Pattern_of_Examination__c) || '';
        const isYearWise = patternVal.toLowerCase().includes('year');
        const isSemWise = patternVal.toLowerCase().includes('sem');

        const ugGridToValidate = isYearWise ? 'year' : (isSemWise ? 'semester' : null);
        if (ugGridToValidate) {
            const sec = this.metadata[ugGridToValidate];
            if (sec && sec.fields) {
                sec.fields.forEach(f => addMissing(ugGridToValidate, f, sec.title));
            }
        }

        // Post-grad grids (if PG shown)
        if (showPostGraduation) {
            const pgPattern = (this.education.postGraduation && this.education.postGraduation.Pattern_of_Examination__c) || '';
            const pgYear = pgPattern.toLowerCase().includes('year');
            const pgSem = pgPattern.toLowerCase().includes('sem');
            const pgGridToValidate = pgYear ? 'postYear' : (pgSem ? 'postSemester' : null);
            if (pgGridToValidate) {
                const psec = this.metadata[pgGridToValidate];
                if (psec && psec.fields) {
                    psec.fields.forEach(f => addMissing(pgGridToValidate, f, psec.title));
                }
            }
        }

        // Apply errors down to relevant children
        if (academicCmp) {
            // tenth always present
            academicCmp.applyErrors(errorMaps.tenth,'tenth');
            academicCmp.applyErrors(errorMaps.after10,'after10');
            // twelfth/diploma conditionally
            if (after10Val === '12th') {
                academicCmp.applyErrors(errorMaps.twelfth,'twelfth');
            }
            if (after10Val === 'diploma') {
                academicCmp.applyErrors(errorMaps.diploma,'diploma');
            }
            if (after10Val === 'both') {
                academicCmp.applyErrors(errorMaps.twelfth,'twelfth');
                academicCmp.applyErrors(errorMaps.diploma,'diploma');
            }
        }
        if (graduationCmp) {
            graduationCmp.applyErrors(errorMaps.havePostGrad);
            graduationCmp.applyErrors(errorMaps.graduation);
            graduationCmp.applyErrors(errorMaps.graduationDetails);
            graduationCmp.applyErrors(errorMaps.year);            
            graduationCmp.applyErrors(errorMaps.semester);

            const combinedGridErrors = {
                ...errorMaps.havePostGrad,
                ...errorMaps.graduation,
                ...errorMaps.graduationDetails,
                ...errorMaps.year,
                ...errorMaps.semester
            };

            graduationCmp.applyErrors(combinedGridErrors);


        }
        if (postGraduationCmp && showPostGraduation) {
            postGraduationCmp.applyErrors(errorMaps.postGraduation, 'postGraduation');
            postGraduationCmp.applyErrors(errorMaps.postGraduationDetails, 'postGraduationDetails');
        }

        if(academicFooterCmp) {
            academicFooterCmp.applyErrors(errorMaps.importantCertification);
        }

        // Aggregate message for summary
        const flatErrors = []
            .concat(Object.values(errorMaps.tenth))
            .concat(Object.values(errorMaps.after10))
            .concat(Object.values(errorMaps.twelfth))
            .concat(Object.values(errorMaps.diploma))
            .concat(Object.values(errorMaps.havePostGrad))
            .concat(Object.values(errorMaps.graduation))
            .concat(Object.values(errorMaps.graduationDetails))
            .concat(Object.values(errorMaps.postGraduation))
            .concat(Object.values(errorMaps.postGraduationDetails))
            .concat(Object.values(errorMaps.professionalQualification || {}).flatMap(row => Object.values(row || {})))
            .concat(Object.values(errorMaps.year || {}).flatMap(row => Object.values(row || {})))
            .concat(Object.values(errorMaps.semester || {}).flatMap(row => Object.values(row || {})))
            .concat(Object.values(errorMaps.postYear || {}).flatMap(row => Object.values(row || {})))
            .concat(Object.values(errorMaps.postSemester || {}).flatMap(row => Object.values(row || {})))
            .concat(Object.values(errorMaps.importantCertification));


        if (flatErrors.length) {
            let errorMessage = `Not so quick. Resolve issues in below mentioned sections\n`;
            Object.keys(errorMaps).forEach(section => {
                let errorCount = 0;
                if (errorMaps[section] instanceof Object && Object.keys(errorMaps[section]).length > 0) {
                    let subSectionPresent = false;
                    Object.keys(errorMaps[section]).forEach(seqSections => {
                        if (errorMaps[section][seqSections] instanceof Object) {
                            subSectionPresent = true;
                            const nonEmpty = Object.values(errorMaps[section][seqSections])
                                .filter(eachVal => eachVal instanceof Object ? Object.keys(eachVal).length > 0 : !!eachVal);

                            if (nonEmpty.length > 0) {
                                errorCount += nonEmpty.length;
                            }
                        }
                    });

                    if (!subSectionPresent) errorCount = Object.keys(errorMaps[section]).length;
                }
                if (errorCount > 0) {
                    const label = this.metadata?.[section]?.title || section;
                    errorMessage += `* section ${label.toUpperCase()} has ${errorCount} unresolved issue${errorCount > 1 ? 's' : ''}\n`;
                }
            });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: errorMessage,
                variant: 'error',
                mode: 'sticky'
            }));
            return false;
        }

        return true;
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

    static LOCKED_APPLICATION_STATUSES = ['Paid'];
    static UNLOCK_ASSIGNMENT_STATUSES = ['Change Requested'];

    get isReadOnly() {
        return AfAcademicDetailsContainerGmp.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfAcademicDetailsContainerGmp.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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

    /* ============================================================
       FETCH FORM DATA
       ============================================================ */
    async fetchForm() {
        const request = this.buildFetchPayload(this.application.Id);
        const response = await fetchDynamic({
            requestJson: JSON.stringify(request)
        });

        this.personalDetails = Object.values(response?.personalDetails)[0];
        
        const dob = this.personalDetails?.Date_of_Birth_As_Per_10th_Marksheet__c;
        if (!dob) return;

        const dobDate = new Date(dob);

        const addYears = (years, resetToJan1) => {
            const d = new Date(dobDate);
            d.setUTCFullYear(d.getUTCFullYear() + years);
            if (resetToJan1) {
                d.setUTCMonth(0, 1); // Jan 1
                d.setUTCHours(0, 0, 0, 0);
            }
            return d.toISOString().split('T')[0];
        };

        const rules = {
            tenth: { passing: 15 },
            twelfth: { passing: 17 },
            diploma: { start: 15, passing: 18 },
            graduationDetails: { start: 17, passing: 20 },
            postGraduationDetails: { start: 20, passing: 22 }
        };

        Object.entries(rules).forEach(([section, config]) => {

            if (!this.metadata[section]) return;

            this.metadata[section].fields.forEach(f => {

                if (f.api === 'MonthAndYearOfCommencement__c' && config.start !== undefined) {
                    f.min = addYears(config.start,true);
                }

                if (f.api === 'MonthAndYearOfPassing__c' && config.passing !== undefined) {
                    f.min = addYears(config.passing,true);
                }

            });

        });

        this.education = response;
        this.application = response?.application;

        // ===== NORMALIZE PROFESSIONAL QUALIFICATION =====
        {
            const pq = this.education.professionalQualification;
            if (pq && typeof pq === 'object' && pq.isSequential === false) {
                const norm = { isSequential: false };
                let seq = 1;

                Object.keys(pq)
                    .filter(k => k !== 'isSequential')
                    .forEach(k => {
                        norm[seq] = { Id: k, ...pq[k] };
                        seq++;
                    });

                // always pad to max 3 rows
                while (seq <= 3) {
                    norm[seq] = { Id: null };
                    seq++;
                }

                this.education.professionalQualification = norm;
            }
        }

        // Ensure every metadata section exists in this.education
        Object.keys(this.metadata).forEach(key => {
            if (!this.education[key]) {
                this.education[key] = {};
            }
        });

        // seed backups from server so toggles can restore original values
        this.backup.academicBreak = { ...(this.education.haveAcademicBreak || {}) };
        this.backup.postGraduation = { ...(this.education.postGraduation || {}) };
        this.backup.postGraduationDetails = { ...(this.education.postGraduationDetails || {}) };
        this.backup.postSemester = { ...(this.education.postSemester || {}) };
        this.backup.postYear = { ...(this.education.postYear || {}) };
        this.backup.professionalQualification = JSON.parse(JSON.stringify(this.education.professionalQualification || {}));

        this._runAllCalculations();
        this._applyReadOnlyMode();
        this._buildRenderModelAll();
        return response;
    }

    /* ============================================================
       SAVE FORM (PARENTS → CHILDREN)
       ============================================================ */
    @api async saveForm() {

        if(this.isReadOnly) return true;
        this.isLoading = true;
        if (!this.validateAll()) {
            this.isLoading = false;
            return false;
        }

        // 1. Build parent payload
        const parentPayload = this.buildParentSavePayload(this.education);

        // ===========================================================
        // DELETE POST GRADUATION RECORDS WHEN USER SAVES "NO"
        // ===========================================================
        if (this.education.havePostGrad.AnyPostGraduation__c !== 'Yes') {

            if (this.backup.postGraduation?.Id) {
                parentPayload.postGraduation = {
                    sobject: "Academic_Detail__c",
                    delete: true,
                    fields: { Id: this.backup.postGraduation.Id }
                };
            }
        }

        try {

            // 2. Save parents (updates, inserts, deletes)
            const parentIds = await saveParents({
                applicationId: this.application.Id,
                payloadJson: JSON.stringify(parentPayload)
            });

            // ==========================================================
            //  PATTERN-BASED GRID DISABLING (UG + PG)
            //  Prevents year ↔ semester overwrites during save
            // ==========================================================

            // -------- Undergraduate --------
            const ugPattern = (this.education.graduation?.Pattern_of_Examination__c || '').toLowerCase();

            if (ugPattern.includes('year')) {
                // Disable semester completely
                this.education.semester = { isSequential: true };
            }

            if (ugPattern.includes('sem')) {
                // Disable year completely
                this.education.year = { isSequential: true };
            }

            // -------- Postgraduate --------
            const pgPattern = (this.education.postGraduation?.Pattern_of_Examination__c || '').toLowerCase();

            if (pgPattern.includes('year')) {
                this.education.postSemester = { isSequential: true };
            }

            if (pgPattern.includes('sem')) {
                this.education.postYear = { isSequential: true };
            }

            // 3. Build child payload
            const childPayload = this.buildChildSavePayload(
                this.education,
                parentIds,
                this.application.Id
            );

            // 4. Save children (updates, inserts, deletes)
            await saveChildren({
                payloadJson: JSON.stringify(childPayload)
            });

            await updateStage({ 
                applicationId: this.application.Id, 
                newStage: 'Academic Details' 
            });

            // 5. Clear deleted lists
            context.children.forEach(c => {
                const delKey = c.logicalName + 'Deleted';
                if (this.education[delKey]) this.education[delKey] = [];
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Saved successfully',
                variant: 'success',
            }));

            await this.fetchForm();
            return true;
        } catch (e) {
            console.error("save error", e);
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

    /* ============================================================
       BUILD FETCH PAYLOAD
       ============================================================ */
    buildFetchPayload(applicationId, parentIds = {}) {
        let out = { parents: [
            {
                logicalName : 'application',
                sobject     : context.parents.find(p => p.logicalName === 'application').sobject,
                fields      : context.parents.find(p => p.logicalName === 'application').fieldsToQuery,
                filters     : [{ field: 'Id', value: applicationId }]
            }
        ], children: [] };

        // ----- Parents -----
        context.parents.forEach(p => {
            if(p.logicalName === 'application') return;
            out.parents.push({
                logicalName: p.logicalName,
                sobject: p.sobject,
                fields: p.fieldsToQuery,
                recordName: p.recordName,
                filters: [
                    { field: 'Name', value: p.recordName },
                    { field: context.parentLookupField, value: applicationId }
                ]
            });
        });

        // ----- Children -----
        context.children.forEach(c => {
            const filters = c.parentRecordName
                ? [
                    // child of academic detail → use ONLY parent lookup after server resolution
                    { field: c.parentLookupField, value: null }
                ]
                : [
                    // PQ → direct child of application
                    { field: c.parentLookupField, value: applicationId }
                ];

            out.children.push({
                logicalName: c.logicalName,
                sobject: c.sobject,
                fields: c.fieldsToQuery,
                filters,
                childKeyField: c.childKeyField,
                useSequenceKey: c.useSequenceKey,
                parentRecordName : c.parentRecordName
            });

        });

        return out;
    }

    /**
     * Normalize a single parent block before saving:
     * - Keep only allowed fields
     * - Normalize values (number, date, monthyear)
     * - If parent is disabled (toggle OFF), keep it blank but do not delete
     */
    normalizeParentBeforeSave(sectionKey, block) {
        const p = context.parents.find(x => x.logicalName === sectionKey);
        if (!p) return block;

        const allowed = new Set(p.fieldsToQuery);
        const metaSec = this.metadata[sectionKey] || {};
        const metaFields = metaSec.fields || [];

        const clean = {};

        Object.keys(block || {}).forEach(api => {
            if (!allowed.has(api)) return;
            if (p.sobject === "Application__c" && api === "Application_Status__c") return;
            const val = block[api];

            const fieldMeta = metaFields.find(f => f.api === api);
            clean[api] = this._normalizeValue(api, val, fieldMeta);
        });

        return clean;
    }


    /**
     * Build parent save payload with correct parent CRUD behavior:
     * - INSERT if no Id and user entered data
     * - UPDATE if Id exists (even if data is blank)
     * - Never delete parent records automatically
     */
    buildParentSavePayload(formData) {
        const out = {};
        if (!formData) return out;

        context.parents.forEach(p => {
            const sectionKey = p.logicalName;
            const block = { ...(formData[sectionKey] || {}) };

            if (
                sectionKey === 'basicAcademic' &&
                formData?.graduationDetails?.DegreeStatus__c === 'Pursuing'
            ) {
                const normalizedPassingDate = this._normalizeValue(
                    'MonthAndYearOfPassing__c',
                    formData?.graduationDetails?.MonthAndYearOfPassing__c,
                    this._findFieldMetaForParent('graduationDetails', 'MonthAndYearOfPassing__c')
                );

                block.ExpectedGraduationDate__c = normalizedPassingDate
                    ? String(normalizedPassingDate).substring(0, 10)
                    : null;
            } else if (
                sectionKey === 'basicAcademic' &&
                formData?.graduationDetails?.DegreeStatus__c === 'Completed'
            ) {
                block.ExpectedGraduationDate__c = null;
            }

            // Normalize parent fields first
            const cleanFields = this.normalizeParentBeforeSave(sectionKey, block);

            // Determine if this parent has ANY meaningful data
            const hasData = Object.keys(cleanFields).some(api => {
                const val = cleanFields[api];
                return val !== null && val !== '' && val !== undefined;
            });

            // Parent handling:
            // ✔ If there is ANY data → save the parent (insert or update)
            // ✔ If blank but had an Id → still save (update to blank)
            // ✔ If blank and no Id → skip writing entirely (never insert blank)
            const shouldWrite =
                hasData ||
                (cleanFields.Id && cleanFields.Id !== null && cleanFields.Id !== undefined);

            if (!shouldWrite) {
                // Skip completely blank unsaved parent sections
                return;
            }

            // 🔹 Inject RecordTypeId for PG Academic Detail
            if (sectionKey === 'postGraduation' && this.recordTypeIds?.PG) {
                cleanFields.RecordTypeId = this.recordTypeIds.PG;
            }

            if (sectionKey === 'graduation' && this.recordTypeIds?.UG) {
                cleanFields.RecordTypeId = this.recordTypeIds.UG;
            }

            out[sectionKey] = {
                sobject: p.sobject,
                recordName: p.recordName,
                fields: cleanFields
            };
        });

        return out;
    }

    _findFieldMetaForParent(sectionKey, api) {
        const sec = this.metadata[sectionKey];
        if (!sec || !sec.fields) return null;
        return sec.fields.find(f => f.api === api) || null;
    }

    _normalizeValue(api, val, fieldMeta) {
        if (!fieldMeta) return val;

        // NUMBER
        if (fieldMeta.type === 'number') {
            if (val === null || val === undefined) return null;
            if (typeof val === 'string' && val.trim() === '') return null;
            const n = Number(val);
            return isNaN(n) ? null : n;
        }

        if (fieldMeta?.type === 'monthyear') {
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




        // DATE (full date)
        if (fieldMeta.type === 'date') {
            if (!val) return null;

            // enforce yyyy-MM-dd only
            const d = new Date(val);
            if (isNaN(d)) return null;

            // Format back to yyyy-MM-dd
            return d.toISOString().substring(0, 10);
        }


        // BOOLEAN (controlled by metadata)
        if (fieldMeta.isBoolean) {
            return (val === true || val === 'true');
        }

        // Everything else stays as-is
        return val;
    }

    // Determine if a row contains ANY meaningful data (besides Id)
    _hasData(row, allowedFields, logicalName) {
        const childMeta = context.children.find(c => c.logicalName === logicalName);
        const zeroIsBlank = childMeta?.zeroIsBlank === true;

        let hasRealData = false;

        Object.keys(row).forEach(api => {
            if (api === 'Id') return;
            if (!allowedFields.has(api)) return;

            const v = row[api];

            // Apply SAME rules as your logic
            const isEmpty =
                v === null ||
                v === undefined ||
                (typeof v === 'string' && v.trim() === '') ||
                (zeroIsBlank && (v === 0 || v === '0')) ||
                (typeof v === 'number' && isNaN(v));

            if (!isEmpty) {
                hasRealData = true;
            }
        });

        return hasRealData;
    }



    /**
     * Normalize a child row BEFORE CRUD logic:
     * - Keep only allowed fields (based on context.children.fieldsToQuery)
     * - Trim all strings
     * - Convert "" or whitespace-only → null
     * - Normalize monthyear and date fields
     * - Convert number-like values to numbers
     * - Ensure output is safe for Apex (no invalid date, no wrong types)
     *
     * Returns a brand-new, sanitized row.
     */
    normalizeChildBeforeSave(sectionKey, rawRow) {
        if (!rawRow) return {};

        const childMeta = context.children.find(c => c.logicalName === sectionKey);
        if (!childMeta) return rawRow;

        // Allowed = fieldsToQuery + Id + sequence key field
        const allowed = new Set(
            childMeta.fieldsToQuery.concat([childMeta.childKeyField, 'Id'])
        );

        const metaSec = this.metadata[sectionKey] || {};
        const metaFields = metaSec.fields || [];

        const clean = {};

        Object.keys(rawRow).forEach(api => {
            if (!allowed.has(api)) return;

            let val = rawRow[api];

            // 1) Convert undefined → null
            if (val === undefined) val = null;

            // 2) Trim strings
            if (typeof val === 'string') {
                val = val.trim();
            }

            // 3) Convert "" → null
            if (val === '') val = null;

            // 4) Find field metadata for normalization
            const fieldMeta = metaFields.find(f => f.api === api);

            // 5) Use global value normalizer (handles monthyear, date, number)
            val = this._normalizeValue(api, val, fieldMeta);

            clean[api] = val;
        });

        return clean;
    }


    /* ============================================================
       BUILD CHILD SAVE PAYLOAD
       ============================================================ */
    buildChildSavePayload(formData, parentIds, applicationId) {
        
        const out = {};
        if (!formData) return out;

        context.children.forEach(c => {
            const block = formData[c.logicalName];
            if (!block) return;

            const rows = [];
            const deleted = [];

            Object.keys(block)
                .filter(k => k !== 'isSequential')
                .forEach(k => {
                    const rawRow = block[k];
                    const row = this.normalizeChildBeforeSave(c.logicalName, rawRow);

                    if (!row) return;

                    const allowed = new Set(c.fieldsToQuery.concat([c.childKeyField, 'Id']));

                    const hasId = !!row.Id;
                    const hasData = this._hasData(row, allowed, c.logicalName);

                    // 🔥 RULE 1: NEW ROW, NO DATA → ignore
                    if (!hasId && !hasData) {
                        return;
                    }

                    // 🔥 RULE 2: NEW ROW + DATA → INSERT
                    if (!hasId && hasData) {
                        const newRow = {};

                        // Only allowed fields
                        Object.keys(row).forEach(api => {
                            if (allowed.has(api)) newRow[api] = row[api];
                        });

                        // Normalize number / monthyear formats
                        const metaSec = this.metadata[c.logicalName] || {};
                        const metaFields = metaSec.fields || [];

                        Object.keys(newRow).forEach(api => {
                            const fieldMeta = metaFields.find(f => f.api === api);
                            newRow[api] = this._normalizeValue(api, newRow[api], fieldMeta);
                        });

                        // Sequence key if required
                        if (c.useSequenceKey && c.childKeyField) {
                            newRow[c.childKeyField] = k;
                        }

                        const parentId = c.parentRecordName
                            ? (parentIds[c.parentRecordName]
                                || (formData[c.parentRecordName] && formData[c.parentRecordName].Id)
                                || applicationId)
                            : applicationId;


                        rows.push({
                            sobject: c.sobject,
                            parentLookupField: c.parentLookupField,
                            childKeyField: c.childKeyField,
                            useSequenceKey: c.useSequenceKey,
                            parentId,
                            fields: newRow,
                            Id: null // INSERT
                        });

                        return;
                    }

                    // 🔥 RULE 3: HAS ID + NO DATA → DELETE
                    if (hasId && !hasData) {
                        deleted.push(row.Id);
                        return;
                    }

                    // 🔥 RULE 4: HAS ID + DATA → UPDATE
                    if (hasId && hasData) {
                        const updateFields = {};

                        Object.keys(row).forEach(api => {
                            if (allowed.has(api)) updateFields[api] = row[api];
                        });

                        const metaSec = this.metadata[c.logicalName] || {};
                        const metaFields = metaSec.fields || [];

                        Object.keys(updateFields).forEach(api => {
                            const fieldMeta = metaFields.find(f => f.api === api);
                            updateFields[api] = this._normalizeValue(api, updateFields[api], fieldMeta);
                        });

                        if (c.useSequenceKey && c.childKeyField) {
                            updateFields[c.childKeyField] = k;
                        }

                        const parentId = c.parentRecordName
                            ? parentIds[c.parentRecordName]
                            : applicationId;

                        rows.push({
                            sobject: c.sobject,
                            parentLookupField: c.parentLookupField,
                            childKeyField: c.childKeyField,
                            useSequenceKey: c.useSequenceKey,
                            parentId,
                            fields: updateFields,
                            Id: row.Id // UPDATE
                        });
                    }
                });

            const deletedArr = (formData[c.logicalName + 'Deleted'] || []).concat(deleted);

            out[c.logicalName] = {
                sobject: c.sobject,
                parentLookupField: c.parentLookupField,
                childKeyField: c.childKeyField,
                useSequenceKey: c.useSequenceKey,
                rows,
                deletedIds: deletedArr
            };
        });

        return out;
    }


    /* ============================================================
       MARK ROW AS DELETED (helper)
       ============================================================ */
    deleteChildRow(logicalName, rowId) {
        if (!this.education[logicalName + 'Deleted']) {
            this.education[logicalName + 'Deleted'] = [];
        }
        this.education[logicalName + 'Deleted'].push(rowId);

        delete this.education[logicalName][rowId];
    }
}

import fetchDynamic from '@salesforce/apex/ApFormDataController.fetchDynamic';
import saveParents from '@salesforce/apex/ApFormDataController.saveParents';
import saveChildren from '@salesforce/apex/ApFormDataController.saveChildren';

import { context } from './context';