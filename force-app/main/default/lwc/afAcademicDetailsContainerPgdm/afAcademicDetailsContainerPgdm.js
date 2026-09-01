import { LightningElement, track, api } from 'lwc';
import getAllPicklistsForObjects from '@salesforce/apex/AcademicFormController.getAllPicklistsForObjects';
import updateStage from '@salesforce/apex/ApplicationFormController.updateStage';
import getRecordTypesByName from '@salesforce/apex/AcademicFormController.getRecordTypesByName';
import { validateNumber } from "c/applicationFormService";


import { ShowToastEvent } from "lightning/platformShowToastEvent";
import fetchMetadataBulk from '@salesforce/apex/ApplicationFormController.fetchMetadataBulk';

const PROFESSIONAL_QUALIFICATION_MAX_ROWS = 3;

export default class AfAcademicDetailsContainerPgdm  extends LightningElement {

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
        havePostGrad : {},
        postGraduation: {},
        postGraduationDetails: {},
        haveProfessionalQualification: {},

        professionalQualification: { isSequential: false },
        professionalQualificationVisibleRows: 1,
        professionalQualificationActions: {},
        professionalQualificationDeleted: [],

        importantCertification: {},
        semester: {},
        year: {},
    };

    _getDependentOptions(dependentApi, controllingValue) {
        const dependency = this.dependentCache?.[dependentApi];

        if (!dependency || !controllingValue) {
            return [];
        }

        const controllingIndex =
            dependency.controllingValueIndexByValue?.[controllingValue];

        if (controllingIndex === undefined || controllingIndex === null) {
            return [];
        }

        return (dependency.options || [])
            .filter(option =>
                (option.validForIndexes || []).includes(controllingIndex)
            )
            .map(option => ({
                label: option.label,
                value: option.value
            }));
    }

    // renderModel sections split for academic (10th/12th/diploma) and graduation
    @track academicSections = []; // array of section renderModels

    // metadata (source) - stored internally
    metadata = {};
    picklistCache = {};
    dependentCache = {};
    customDropdownCache = {};
    academicBreakPicklistFilter = {};

    resolveCustomDropdown(api, recordTypeId) {

        const rtConfig =
            this.customDropdownCache?.customDropdownRecordTypeSet?.[recordTypeId]?.[api];

        if (rtConfig) {
            return rtConfig;
        }

        const configs =
            this.customDropdownCache?.customDropdowns?.[api] || [];

        return configs.find(
            x => x.context === 'Program.PGDM'
        );
    }

    async connectedCallback() {
        this._buildMetadataSkeleton();

        try {
            const data = await getAllPicklistsForObjects({
                objectApiNames:['Academic_Detail__c','BasicAcademicDetail__c','Professional_Qualification__c']
            }); 

            // Support multiple returned bundles (one per object)
            // Merge defaultSet/recordTypeSet so resolveOptions can see all fields
            const merged = {
                defaultSet: {},
                recordTypeSet: {},
                customDropdowns: {},
                customDropdownRecordTypeSet: {}
            };

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

                    // merge default custom dropdowns
                    if (b.customDropdowns) {
                        Object.entries(b.customDropdowns).forEach(([api, configs]) => {
                            merged.customDropdowns[api] = configs;
                        });
                    }

                    console.log('picklists '+JSON.stringify(b.customDropdownRecordTypeSet));

                    // merge record type custom dropdowns
                    if (b.customDropdownRecordTypeSet) {
                        Object.entries(b.customDropdownRecordTypeSet).forEach(([rtId, fields]) => {

                            if (!merged.customDropdownRecordTypeSet[rtId]) {
                                merged.customDropdownRecordTypeSet[rtId] = {};
                            }

                            Object.entries(fields).forEach(([api, config]) => {
                                merged.customDropdownRecordTypeSet[rtId][api] = config;
                            });
                        });
                    }
                });
            }

            this.customDropdownCache = merged;

            if (Object.keys(merged.defaultSet).length > 0 || Object.keys(merged.recordTypeSet).length > 0) {
                this.picklistCache = merged;   // ⭐ merged structure for both Academic_Detail__c and BasicAcademicDetail__c
                this.dependentCache = {};

                (data || []).forEach(eachOpb => {
                    const defaultRecordTypeSet =
                        Object.values(eachOpb?.recordTypeSet || {})[0];

                    Object.entries(defaultRecordTypeSet || {}).forEach(
                        ([picklistField, fieldSet]) => {

                            if (
                                fieldSet?.controllingValueIndexByValue &&
                                Object.keys(fieldSet.controllingValueIndexByValue).length
                            ) {
                                this.dependentCache[picklistField] = {
                                    options: fieldSet.options || [],
                                    controllingValueIndexByValue:
                                        fieldSet.controllingValueIndexByValue
                                };
                            }
                        }
                    );
                });

                console.log(
                    'DEPENDENT CACHE',
                    JSON.stringify(this.dependentCache)
                );

                console.log(
                    'DEPENDENT CACHE',
                    JSON.stringify(this.dependentCache)
                );
            }

            await this._loadRecordTypes();   // ✅ NOW VALID
            await this._loadAcademicBreakPicklistFilter();
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

    // Build metadata skeleton and default columnSystem per section
    _buildMetadataSkeleton() {
        this.metadata = {};

        // per-section columnSystem recommended values
        const cs = {
            tenth:12, after10:12, twelfth:12, diploma:17, graduation:12, graduationDetails:15, havePostGrad:15, postGraduation:12, postGraduationDetails:15
        };

        this.metadata.instructions = {
            key: 'instructions',
            title: 'Instructions',
            note: {
                api: 'SECTION_NOTE',
                type: 'note',
                text: `
                    <ul style="list-style-type: disc; list-style-position: outside; display:inline-block; text-align:left; margin-top:8px; padding-left:30px;">
                        <li>For 10th and 12th grade examinations, the aggregate of all subjects scores (marks) mentioned on the mark sheet should be considered while calculating the final percentage. This is irrespective of whether the university/board takes it into consideration or not while calculating the final percentage.</li>

                        <li>Your Examination Roll Number is the unique number assigned to you for your 10th/12th board examination. This may also be referred to as the examination reference number. You can find it on your mark sheet or admit card issued by the respective board.</li>

                        <li>For all grade exams (10th, 12th, Graduation) if the institute provides grades/CGPA instead of marks, a conversion of the same to equivalent percentage is mandatory. If no conversion factor is available/provided, then a percentage needs to be calculated by multiplying the obtained CGPA with the conversion factor of 10. The conversion certificate needs to be furnished during the verification process, if shortlisted. If no conversion factor exists, then a certificate from the institution/university certifying the practice, needs to be provided during the verification process, if shortlisted.</li>

                        <li>The data provided by you (Marks/CGPA etc.) in the form will be verified during the verification process, if shortlisted.</li>

                        <li>To refer to the eligibility document of PGDM programme (Indian applicant) <a href="#">click here</a></li>

                        <li>To refer to the eligibility document of PGDM programme (International applicant only) <a href="#">click here</a></li>

                        <li>To refer to the eligibility document of PGDM (BM) programme <a href="#">click here</a></li>
                    </ul>
                `
            },
            rows: [],
            fields: [
                { api: 'SECTION_NOTE', type: 'note' }
            ]
        };

        this.metadata.academicNote = {
            key: "academicNote",
            note: {
                api: "ACADEMIC_NOTE",
                type: "note",
                text: `
<b>Note:</b><br/><br/>

1. Conversion factor is the factor used to convert CGPA to percentage. If the institute provides grades/CGPA instead of marks, a conversion of the same to equivalent percentage is mandatory. If no conversion factor is available / provided, then obtained CGPA needs to be multiplied by conversion factor of 10 to obtain the percentage. The conversion certificate needs to be furnished during the verification process. If no conversion factor exists, then a certificate from the institution/university certifying the practice needs to be provided during the verification process.<br/><br/>

2. An aggregate of all subjects scores (marks) mentioned on the mark sheet will be considered for arriving at the final percentage. This is irrespective of whether the university/board takes it into consideration or not while calculating the final percentage<br/><br/>

`
            },
            rows: [],
            fields: [
                { api: 'ACADEMIC_NOTE', type: 'note' }
            ]
        },

        // Tenth
        this.metadata.tenth = {
            key: 'tenth',
            title: '10th Academic Details',
            columnSystem: cs.tenth,
            layout: 'fluid',
            // rows: [
            //     { columns: [ {width:3, fields:['Board_University__c'] }, { width:3, fields:['School_Institute__c'] }, { width:3, fields:['MonthAndYearOfPassing__c'] }, { width:2, fields:['Marking_Scheme__c'] }, ] },
            //     { columns: [ { width:2, fields:['Maximum_Marks__c'] }, { width:2, fields:['Obtained_Marks__c'] }, { width:2, fields:['Conversion_Factor__c'] }, { width:2, fields:['Percentage__c'] }, { width:2, fields:[] } ] }
            // ],
            fields: [
                { api:'Board_University__c', type:'picklist', label:'Board', required:true, span: 3 },
                {
                    api:'Other_Board_University__c', 
                    type:'text', 
                    label:'Enter Board Name', 
                    shortLabel:'Board Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "tenth.Board_University__c": "Other" }, 
                },
                { api:'School_Institute__c', type:'text', label:'Institute Name', required:true, maxlength: '255', span: 3, },
                { api:'Examination_ID__c', type:'text', label:'Examination Id', required:true, maxlength: '255', span: 3, },
                // { api:'MonthAndYearOfCommencement__c', type:'monthyear', min:"2005-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true},
                { api:'MonthAndYearOfPassing__c', type:'monthyear', min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Passing', required:true, span: 3,},
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme', required:true, span: 2, },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"9999", span: 2 },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPercentage', required:true, step: "0.01", max:"9999", span: 2 },
                { api:'ConversionFormula__c', type:'text', label:'Conversion Factor', maxlength:'50', visibleWhen: { 'tenth.Marking_Scheme__c': 'CGPA' }, span: 2 },
                { api:'Percentage__c', type:'number', label:'Percentage', readOnly:true, calculate:'computePercentage', minPercentage:33, step: "0.01", max:"100", span: 2, helpText:"% symbol not required" },
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
        this.metadata.twelfth.fields[1].visibleWhen = { 'twelfth.Board_University__c': 'Other' };
        this.metadata.twelfth.fields[4].min = "1985-01-01";
        this.metadata.twelfth.fields[4].max= new Date().toISOString().split('T')[0];
        // this.metadata.twelfth.fields[3].min = "2007-01-01";
        // this.metadata.twelfth.fields[3].max= new Date().toISOString().split('T')[0];
        this.metadata.twelfth.fields[8].visibleWhen = { 'twelfth.Marking_Scheme__c': 'CGPA' };
        this.metadata.twelfth.title = '12th Academic Details';
        this.metadata.twelfth.columnSystem = cs.twelfth;

        // Diploma
        this.metadata.diploma = {
            key: 'diploma',
            title: 'Diploma Details',
            columnSystem: cs.diploma,
            layout: 'fluid',
            note: {
                api:'DIPLOMA_NOTE',
                type:'note',
                text: `
<b>Note: </b>Overall percentage / CGPA should be the same as mentioned in your mark sheet
                `
            },
            // rows: [
            //     { columns: [ { width:3, fields:['Board_University__c'] }, { width:3, fields:['School_Institute__c'] }, { width:3, fields:['Diploma_Name__c'] }, { width:4, fields:['MonthAndYearOfCommencement__c'] }, { width:4, fields:['MonthAndYearOfPassing__c'] } ] },
            //     { columns: [ { width:3, fields:['Marking_Scheme__c'] }, { width:3, fields:['Maximum_Marks__c'] }, { width:3, fields:['Obtained_Marks__c'] }, { width:3, fields:['Conversion_Factor__c'] }, { width:3, fields:['Percentage__c'] },  ] }
            // ],
            fields: [
                { api:'Board_University__c', type:'text', label:'University', required:true, maxlength: '255', span: 3 },
                { api:'School_Institute__c', type:'text', label:'Institute Name', required:true, maxlength: '255', span: 3 },
                { api:'Diploma_Name__c', type:'text', label:'Diploma Name', required:true, maxlength: '255', span: 3 },
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true, span: 4},
                { api:'MonthAndYearOfPassing__c', type:'monthyear', min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Passing', required:true, span: 4 },
                { api:'Marking_Scheme__c', type:'picklist', label:'Marking Scheme', required:true, span: 3 },
                { api:'Maximum_Marks__c', type:'number', label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"9999", span: 3 },
                { api:'Obtained_Marks__c', type:'number', label:'Obtained Marks/CGPA', onChange:'recalcPercentage', required:true, step: "0.01", max:"9999", span: 3 },
                { api:'ConversionFormula__c', type:'text', label:'Conversion Factor', visibleWhen: { 'diploma.Marking_Scheme__c': 'CGPA' }, maxlength:'50', span: 3  },
                { api:'Percentage__c', type:'number', label:'Percentage', readOnly:true, calculate:'computePercentage', minPercentage:33, step: "0.01", max:"100", span: 3, helpText:"% symbol not required" },
            ]
        };

        this.metadata.haveAcademicBreak = {
            key: 'haveAcademicBreak',
            title: 'Academic Break',
            columnSystem: 12,
            rows: [
                {
                    columns: [
                        { width: 4, fields: ['HasAcademicBreak__c'] },
                        { width: 3, fields: ['AcademicBreakAfter__c'] },
                        { width: 5, fields: ['AcademicBreakReason__c'] }
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
                    helpText:"The question is pertaining to a break in between 10th grade and graduation. You can choose \"No\" if you have completed your graduation without a break in between.",
                    required: true
                },
                {
                    api: 'AcademicBreakAfter__c', 
                    type: 'multipicklist',
                    label: 'Academic Break Taken After',
                    visibleWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' },
                    requiredWhen: { 'haveAcademicBreak.HasAcademicBreak__c': 'Yes' }
                },
                {
                    api: 'AcademicBreakReason__c', 
                    maxlength: '2000',
                    type: 'textarea',
                    label: 'Reason for Academic Break',
                    maxWords: 50,
                    showCounter: true,
                    helpText:"Max. 50 words",
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
                    label: "Institute",
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
                    label:'Enter Institute Name',
                    shortLabel:'Institute Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "otherResources.showOtherUgCollege": true } 
                },
                { 
                    api:'InstituteCity__c', 
                    type:'text', 
                    label:'Institute City',
                    shortLabel:'Institute City',
                    required:true,
                    span: 3, 
                },
                { api:'Mode_of_Study__c', type:'picklist', label:'Mode of Study', required:true, span: 3 },
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
                { api:'Specialization_Name__c', type:'picklist', label:'Specialisation', span: 4, maxlength: '255', required:true },
                { api:'Degree_Type__c', type:'picklist', label:'Degree Type', required:true, span: 2 },
                { 
                    api:'Pattern_of_Examination__c',
                    type:'picklist',
                    label:'Pattern Of Examination',
                    required:true,
                    span: 2
                }
            ]
        };

        // Graduation details (marks)
        this.metadata.graduationDetails = {
            key:'graduationDetails',
            title:'Graduation Marks',
            columnSystem: cs.graduationDetails,
            layout: 'fluid',
            note: {
                api: 'GRADUATION_DETAILS_NOTE',
                type: 'note',
                text: `
                    To calculate graduate percentage refer to point no. 3 in the Instructions<br>
                    For ex CGPA-0.50*10
                `
            },
            fields: [
                { api:'DegreeStatus__c', type:'picklist', span:3, label:'Degree Status', required:true },
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', span:4, min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true },
                { api:'MonthAndYearOfPassing__c', type:'monthyear', span:4, min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year Of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', span:2, label:'Marking Scheme', required:true },
                { api:'Maximum_Marks__c', type:'number', span:3, label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"99999" },
                { api:'Obtained_Marks__c', type:'number', span:3, label:'Obtained Marks/CGPA', onChange:'recalcGraduationPercentage', required:true, step: "0.01", max:"99999" },
                { api:'ConversionFormula__c', type:'text', span:2, label:'Conversion Factor', maxlength:"50", visibleWhen: { 'graduationDetails.Marking_Scheme__c': 'CGPA' } },
                { api:'Percentage__c', type:'number', span:3, label:'Graduation Percentage', readOnly:true, calculate:'computeGraduationPercentage', step: "0.01", max:"100", helpText:"% symbol not required" },
            ]
        };

        this.metadata.semester = {
            key: 'semester',
            title: 'Semester Wise Details',
            columnSystem: 30,
            rows: [
                {
                    columns: Array.from({ length: 10 }, () => ({
                        width: 3,
                        fields: ['Maximum_Marks_SGPA__c']
                    }))
                },
                {
                    columns: Array.from({ length: 10 }, () => ({
                        width: 3,
                        fields: ['Obtained_Marks_SGPA__c']
                    }))
                }
            ],
            fields: [
                ...Array.from({ length: 10 }, (_, i) => ({
                    api: 'Maximum_Marks_SGPA__c',
                    type: 'number',
                    sequence: i + 1,
                    label: `Sem ${i + 1} Maximum Score`,
                    step: '0.01',
                    max: '9999'
                })),
                ...Array.from({ length: 10 }, (_, i) => ({
                    api: 'Obtained_Marks_SGPA__c',
                    type: 'number',
                    sequence: i + 1,
                    label: `Sem ${i + 1} Obtained Score`,
                    step: '0.01',
                    max: '9999'
                }))
            ]
        };

        this.metadata.year = {
            key: 'year',
            title: 'Year Wise Details',
            columnSystem: 30,
            rows: [
                {
                    columns: Array.from({ length: 5 }, () => ({
                        width: 6,
                        fields: ['Maximum_Marks_SGPA__c']
                    }))
                },
                {
                    columns: Array.from({ length: 5 }, () => ({
                        width: 6,
                        fields: ['Obtained_Marks_SGPA__c']
                    }))
                }
            ],
            fields: [
                ...Array.from({ length: 5 }, (_, i) => ({
                    api: 'Maximum_Marks_SGPA__c',
                    type: 'number',
                    sequence: i + 1,
                    label: `Year ${i + 1} Maximum Score`,
                    step: '0.01',
                    max: '9999'
                })),
                ...Array.from({ length: 5 }, (_, i) => ({
                    api: 'Obtained_Marks_SGPA__c',
                    type: 'number',
                    sequence: i + 1,
                    label: `Year ${i + 1} Obtained Score`,
                    step: '0.01',
                    max: '9999'
                }))
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
                    label: "Institute",
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
                    label:'Enter Institute Name',
                    shortLabel:'Institute Name',
                    required:true, 
                    span: 3, 
                    visibleWhen: { "otherResources.showOtherPgCollege": true } 
                },
                { 
                    api:'InstituteCity__c', 
                    type:'text', 
                    label:'Institute City',
                    shortLabel:'Institute City',
                    required:true,
                    span: 3, 
                },
                { api:'Mode_of_Study__c', type:'picklist', label:'Mode of Study', required:true, span: 3 },
                { api:'Degree__c', type:'picklist', label:'Degree', required:true, span: 4 },
                { 
                    api:'OtherDegree__c', 
                    type:'text', 
                    label:'Enter Degree',
                    shortLabel:'Degree',
                    required:true,
                    span: 4, 
                    visibleWhen: { "postGraduation.Degree__c": "Other" } 
                },
                { api:'Specialization_Name__c', type:'text', label:'Specialisation', span: 4, maxlength: '255', required:true },
                { api:'Degree_Type__c', type:'picklist', label:'Degree Type', required:true, span: 2 },
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
                { api:'MonthAndYearOfCommencement__c', type:'monthyear', span:4, min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year of Commencement', required:true},
                { api:'MonthAndYearOfPassing__c', type:'monthyear', span:4, min:"1985-01-01", max:new Date().toISOString().split('T')[0], label:'Month & Year Of Passing', required:true },
                { api:'Marking_Scheme__c', type:'picklist', span:2, label:'Marking Scheme', required:true },
                { api:'Maximum_Marks__c', type:'number', span:3, label:'Maximum Marks/CGPA', required:true, step: "0.01", max:"99999" },
                { api:'Obtained_Marks__c', type:'number', span:3, label:'Obtained Marks/CGPA', onChange:'recalcPostGraduationPercentage', required:true, step: "0.01", max:"99999" },
                { api:'ConversionFormula__c', type:'text', span:2, label:'Conversion Factor', visibleWhen: { 'postGraduationDetails.Marking_Scheme__c': 'CGPA' }, maxlength:"50" },
                { api:'Percentage__c', type:'number', span:3, label:'Post Graduation Percentage', readOnly:true, calculate:'computePostGraduationPercentage', step: "0.01", max:"100", helpText:"% symbol not required" },
            ]
        };

        this.metadata.haveProfessionalQualification = {
            key: 'haveProfessionalQualification',
            title: 'Do you have any Professional Qualification?',
            columnSystem: 16,
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
                    { width: 2, fields: ['Name_of_Qualification_Picklist__c'] },
                    { width: 2, fields: ['Name_of_Qualification__c'] },
                    { width: 2, fields: ['ProfessionalQualification__c'] },
                    { width: 2, fields: ['Name_of_Institute_Picklist__c'] },
                    { width: 2, fields: ['Name_of_Institute__c'] },
                    { width: 2, fields: ['Qualification_Status__c'] },
                    { width: 1, fields: ['Rank_Achieved__c'] },
                    { width: 1, fields: ['Level_Achieved__c'] },
                    { width: 2, fields: ['Year_of_Passing_pq__c'] }, 
                    { width: 2, fields: ['Year_of_Commencement_pq__c'] }
                ]
            });
        }

        // this.metadata.professionalQualification = {
        //     key: 'professionalQualification',
        //     title: 'Professional Qualifications (eg. CA / ICWA/CFA)',
        //     columnSystem: 12,
        //     rows: pqRows,
        //     fields: [
        //         ...Array.from({ length: 3 }, (_, i) => ({ required:i===0?true:false, api:'Name_of_Qualification__c', sequence:i+1, type:'text', label:'Qualification' })),
        //         ...Array.from({ length: 3 }, (_, i) => ({ required:i===0?true:false, api:'Name_of_Institute__c', sequence:i+1, type:'text', label:'Institute', maxlength: '255' })),
        //         ...Array.from({ length: 3 }, (_, i) => ({ api:'Rank_Achieved__c', sequence:i+1, type:'text', label:'Rank', maxlength: '255' })),
        //         ...Array.from({ length: 3 }, (_, i) => ({ api:'Level_Achieved__c', sequence:i+1, type:'text', label:'Level', maxlength: '255' })),
        //         ...Array.from({ length: 3 }, (_, i) => ({ api:'Total_Max_Marks__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:'Total Max Marks' })),
        //         ...Array.from({ length: 3 }, (_, i) => ({ api:'Marks_Obtained__c', step: "0.01", max:"9999", sequence:i+1, type:'number', label:'Marks Obtained' })),
        //         ...Array.from({ length: 3 }, (_, i) => ({ api:'Percentage__c', sequence:i+1, type:'number', label:'Percentage', readOnly: true, calculate: 'computePQPercentage', step: "0.01" }))
        //     ]
        // };

        const pqActiveWhen = {
            'haveProfessionalQualification.HasProfessionalQualification__c': 'Yes'
        };

        this.metadata.professionalQualification = {
            key: 'professionalQualification',
            title: 'Professional Qualifications (eg. CA / ICWA/CFA)',
            columnSystem: 12,
            layout: 'fluid',
            rows: pqRows,
            fields: [
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Name_of_Qualification_Picklist__c',
                    sequence: i + 1,
                    type: 'picklist',
                    label: 'Qualification',
                    required: i === 0,
                    span: 2,
                    requiredWhen: i === 0 ? pqActiveWhen : undefined
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Name_of_Qualification__c',
                    sequence: i + 1,
                    type: 'text',
                    label: 'Other Qualification',
                    maxlength: '255',
                    required: i === 0,
                    span: 2,
                    requiredWhen: {
                        'professionalQualification.Name_of_Qualification_Picklist__c': 'Other'
                    },
                    visibleWhen: {'professionalQualification.Name_of_Qualification_Picklist__c' : 'Other'}
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'ProfessionalQualification__c',
                    sequence: i + 1,
                    type: 'picklist',
                    label: 'Professional Qualification',
                    required: i === 0,
                    span: 2,
                    requiredWhen: i === 0 ? pqActiveWhen : undefined,
                    visibleWhen: {
                        'professionalQualification.showProfessionalQualification': true
                    }
                })),                
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Name_of_Institute_Picklist__c',
                    sequence: i + 1,
                    type: 'picklist',
                    label: 'Institute',
                    required: i === 0,
                    span: 2,
                    requiredWhen: i === 0 ? pqActiveWhen : undefined,
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Name_of_Institute__c',
                    sequence: i + 1,
                    type: 'text',
                    label: 'Other Institute',
                    maxlength: '255',
                    required: i === 0,
                    span: 2,
                    requiredWhen: {
                        'professionalQualification.Name_of_Institute_Picklist__c': 'Other'
                    },
                    visibleWhen: {'professionalQualification.Name_of_Institute_Picklist__c' : 'Other'}
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Qualification_Status__c',
                    sequence: i + 1,
                    type: 'picklist',
                    label: 'Qualification Status',
                    required: i === 0,
                    span: 2,
                    requiredWhen: i === 0 ? pqActiveWhen : undefined
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Rank_Achieved__c',
                    sequence: i + 1,
                    type: 'text',
                    label: 'Rank',
                    maxlength: '255',
                    span: 1,
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Level_Achieved__c',
                    sequence: i + 1,
                    type: 'text',
                    label: 'Level',
                    maxlength: '255',
                    span: 1,
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Year_of_Commencement_pq__c',
                    sequence: i + 1,
                    type: 'picklist',
                    label: 'Year of Commencement',
                    span: 2,
                })),
                ...Array.from({ length: 3 }, (_, i) => ({
                    api: 'Year_of_Passing_pq__c',
                    sequence: i + 1,
                    type: 'picklist',
                    label: 'Year of Passing',
                    span: 2,
                })),
            ]
        };

        this.metadata.professionalQualificationActions = {
            key: 'professionalQualificationActions',
            title: 'Professional Qualification Actions',
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
                    action: 'addMoreProfessionalQualification',
                    disableWhen: {
                        'professionalQualificationActions.fullCapacity': true
                    },
                    variant: 'brand'
                },
                {
                    api: 'Remove',
                    type: 'button',
                    label: '➖ Remove',
                    action: 'removeProfessionalQualification',
                    disableWhen: {
                        'professionalQualificationActions.noneToRemove': true
                    },
                    variant: 'brand'
                }
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
                { api:'CertificationDetails__c', type:'textarea', label:'If yes, please specify (Max. 50 words)', maxlength:"32768", maxWords: 50, showCounter: true }
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
            recordTypeNames:['PG','UG','Tenth','Twelfth']
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

            const custom = this.resolveCustomDropdown(api, rt);

            // if (custom?.controllingFieldApi) {
            //     return {
            //         controllingFieldApi: custom.controllingFieldApi,
            //         optionsByControllingValue:
            //             custom.optionsByControllingValue || {}
            //     };
            // }

            if (custom?.options?.length) {
                return custom.options.map(o => ({
                    label: o.label,
                    value: o.value
                }));
            }

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

        setOptions('tenth','Board_University__c',resolveOptions('Board_University__c',this.recordTypeIds.Tenth));
        setOptions('twelfth','Board_University__c',resolveOptions('Board_University__c',this.recordTypeIds.Twelfth));

        // DIPLOMA
        setOptions('diploma','Diploma_Name__c',resolveOptions('Diploma_Name__c'));
        setOptions('diploma','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));

        // UG
        setOptions('graduation','Mode_of_Study__c',resolveOptions('Mode_of_Study__c'));
        setOptions('graduation','Degree__c',resolveOptions('Degree__c',this.recordTypeIds.UG));
        setOptions('graduation','Degree_Type__c',resolveOptions('Degree_Type__c',this.recordTypeIds.UG));
        setOptions('graduation','Pattern_of_Examination__c',resolveOptions('Pattern_of_Examination__c',this.recordTypeIds.UG));
        setOptions('graduationDetails','DegreeStatus__c',resolveOptions('DegreeStatus__c'));


        // PG
        setOptions('postGraduation','Mode_of_Study__c',resolveOptions('Mode_of_Study__c'));
        setOptions('postGraduation','Degree__c',resolveOptions('Degree__c',this.recordTypeIds.PG));
        setOptions('postGraduation','Degree_Type__c',resolveOptions('Degree_Type__c',this.recordTypeIds.PG));
        setOptions('postGraduationDetails','DegreeStatus__c',resolveOptions('DegreeStatus__c'));

        setOptions('havePostGrad','AnyPostGraduation__c',resolveOptions('AnyPostGraduation__c'));
        setOptions('graduationDetails','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));
        setOptions('postGraduationDetails','Marking_Scheme__c',resolveOptions('Marking_Scheme__c'));

        // Academic break
        let academicBreakOptions =
            resolveOptions('AcademicBreakAfter__c');

        const academicBreakFilter =
            this.academicBreakPicklistFilter[
                'BasicAcademicDetail__c.AcademicBreakAfter__c'
            ];

        if (Array.isArray(academicBreakFilter)) {
            academicBreakOptions = academicBreakOptions.filter(option =>
                academicBreakFilter.includes(option.value)
            );
        }

        setOptions('haveAcademicBreak','AcademicBreakAfter__c',academicBreakOptions);

        const setMultiRowOptions = (sectionKey, api, options) => {
            const fields = this.metadata?.[sectionKey]?.fields || [];
            fields
                .filter(f => f.api?.toLowerCase() === api.toLowerCase())
                .forEach(f => {
                    f.options = options;
                });
        };

        setMultiRowOptions('professionalQualification', 'Name_of_Qualification_Picklist__c', [{ label: '--None--', value: '' }, ...resolveOptions('Name_of_Qualification_Picklist__c')]);
        setMultiRowOptions('professionalQualification', 'Name_of_Institute_Picklist__c', [{ label: '--None--', value: '' }, ...resolveOptions('Name_of_Institute_Picklist__c')]);
        setMultiRowOptions('professionalQualification', 'Qualification_Status__c', [{ label: '--None--', value: '' }, ...resolveOptions('Qualification_Status__c')]);
        
        setMultiRowOptions(
            'professionalQualification',
            'Year_of_Passing_pq__c',
            [
                { label: '--None--', value: '' },
                ...resolveOptions('Year_of_Passing_pq__c')
                    .filter(opt => Number(opt.value) >= 1985 && Number(opt.value) <= new Date().getFullYear())
            ]
            
        );

        setMultiRowOptions(
            'professionalQualification',
            'Year_of_Commencement_pq__c',
            [
                { label: '--None--', value: '' },
                ...resolveOptions('Year_of_Commencement_pq__c')
                    .filter(opt => Number(opt.value) >= 1985 && Number(opt.value) <= new Date().getFullYear())
            ]
            
        );

    }

    resolveCustomDropdownConfig(api, recordTypeId) {
        return this.resolveCustomDropdown(api, recordTypeId);
    }

    _getCustomDependentOptions(api, controllingValue, recordTypeId) {
        const config =
            this.resolveCustomDropdownConfig(api, recordTypeId);

        if (!config?.controllingFieldApi) {
            return null;
        }

        return [
            { label: '--None--', value: '' },
            ...(config.optionsByControllingValue?.[controllingValue] || [])
        ];
    }

    async _loadAcademicBreakPicklistFilter() {
        this.academicBreakPicklistFilter = {};

        try {
            const metadataResponse = await fetchMetadataBulk({
                requests: [
                    {
                        metadataName: 'ApplicationProgramBasedConfig__mdt',
                        fields: [
                            'Intent__c',
                            'ProgramCode__c',
                            'Type__c',
                            'ConfigValue__c'
                        ],
                        filters: [
                            {
                                field: 'Intent__c',
                                operator: '=',
                                value: 'AcademicBreakAfterPicklistFilter'
                            },
                            {
                                field: 'ProgramCode__c',
                                operator: '=',
                                value: 'PGDM'
                            }
                        ]
                    }
                ]
            });

            const configRecords =
                metadataResponse?.ApplicationProgramBasedConfig__mdt || [];

            const config = configRecords[0];

            if (
                !config ||
                String(config.Type__c || '').toLowerCase() !== 'map'
            ) {
                return;
            }

            const configMap = JSON.parse(config.ConfigValue__c || '{}');

            Object.entries(configMap).forEach(([fieldKey, allowedValues]) => {
                if (!Array.isArray(allowedValues)) {
                    return;
                }

                this.academicBreakPicklistFilter[fieldKey] = allowedValues;
            });

        } catch (error) {
            console.warn(
                'Academic break picklist metadata load failed',
                error
            );
        }
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

        const buildSlicedGridSection = (baseKey, countYears) => {
            const base = this.metadata[baseKey];
            if (!base) return null;

            const clone = JSON.parse(JSON.stringify(base));

            const pursuing =
                this.education?.graduationDetails?.DegreeStatus__c === 'Pursuing';

            // YEAR
            if (baseKey === 'year') {
                const yearCount = Math.min(countYears || 0, 5);
                const exemptTail = 1;

                clone.rows = [
                    {
                        ...clone.rows[0],
                        columns: clone.rows[0].columns.slice(0, yearCount)
                    },
                    {
                        ...clone.rows[1],
                        columns: clone.rows[1].columns.slice(0, yearCount)
                    }
                ];

                clone.fields = clone.fields
                    .filter(f =>
                        !f.sequence ||
                        Number(f.sequence) <= yearCount
                    )
                    .map(f => ({
                        ...f,
                        required: f.sequence
                            ? (
                                pursuing
                                    ? Number(f.sequence) <= yearCount - exemptTail
                                    : true
                            )
                            : f.required
                    }));
            }

            // SEMESTER
            if (baseKey === 'semester') {
                const semCount = Math.min((countYears || 0) * 2, 10);
                const exemptTail = 2;

                clone.rows = [
                    {
                        ...clone.rows[0],
                        columns: clone.rows[0].columns.slice(0, semCount)
                    },
                    {
                        ...clone.rows[1],
                        columns: clone.rows[1].columns.slice(0, semCount)
                    }
                ];

                clone.fields = clone.fields
                    .filter(f =>
                        !f.sequence ||
                        Number(f.sequence) <= semCount
                    )
                    .map(f => ({
                        ...f,
                        required: f.sequence
                            ? (
                                pursuing
                                    ? Number(f.sequence) <= semCount - exemptTail
                                    : true
                            )
                            : f.required
                    }));
            }

            return clone;
        };

        const pattern =
            this.education.graduation?.Pattern_of_Examination__c || '';

        const degreeType =
            this.education.graduation?.Degree_Type__c || '';

        const yearsMatch =
            String(degreeType).match(/([3-5])\s*year/i);

        const yearsFromDegreeType =
            yearsMatch ? Number(yearsMatch[1]) : null;

        const isYearWise =
            pattern.toLowerCase().includes('year');

        const isSemWise =
            pattern.toLowerCase().includes('sem');

        let dynamicGridMeta = null;

        if (yearsFromDegreeType) {
            if (isYearWise) {
                dynamicGridMeta =
                    buildSlicedGridSection('year', yearsFromDegreeType);
            } else if (isSemWise) {
                dynamicGridMeta =
                    buildSlicedGridSection('semester', yearsFromDegreeType);
            }
        }

        let restoreKey = null;
        let originalMeta = null;

        if (dynamicGridMeta) {
            restoreKey = dynamicGridMeta.key;
            originalMeta = this.metadata[restoreKey];
            this.metadata[restoreKey] = dynamicGridMeta;
        }

        // Always include 10th and After10
        let list = [
            {
                ...this._buildSectionRenderModel('instructions'),
                block: 'academic'
            },
            {
                ...this._buildSectionRenderModel('academicNote'),
                block: 'academic'
            },
            {
                ...this._buildSectionRenderModel('tenth'),
                block: 'academic'
            },
            {
                ...this._buildSectionRenderModel('after10'),
                block: 'academic'
            },
        ];

        // Show 12th?
        if (after10.AfterTen__c === '12th' || after10.AfterTen__c === 'both') {
            list.push(
                {
                    ...this._buildSectionRenderModel('twelfth'),
                    block: 'academic'
                }
            );
        }

        // Show Diploma?
        if (after10.AfterTen__c === 'diploma' || after10.AfterTen__c === 'both') {
            list.push(
                {
                    ...this._buildSectionRenderModel('diploma'),
                    block: 'academic'
                }
            );
        }

        let academicBreakSection = {
            ...this._buildSectionRenderModel('haveAcademicBreak'),
            block: 'academic'
        };

        let sections = [
            ...list,
            academicBreakSection,
            {
                ...this._buildSectionRenderModel('graduation'),
                block: 'graduation'
            },
            {
                ...this._buildSectionRenderModel('graduationDetails'),
                block: 'graduation'
            },
        ].filter(Boolean);

        if (pattern.toLowerCase().includes('sem')) {
            sections.push({
                ...this._buildSectionRenderModel('semester'),
                block: 'graduation'
            });
        }

        if (pattern.toLowerCase().includes('year')) {
            sections.push({
                ...this._buildSectionRenderModel('year'),
                block: 'graduation'
            });
        }

        sections.push({
            ...this._buildSectionRenderModel('havePostGrad'),
            block: 'graduation'
        });

        // Check if we should show Post Graduation sections
        const anyPostGraduation = (this.education.havePostGrad && this.education.havePostGrad.AnyPostGraduation__c) || '';
        const showPostGraduation = anyPostGraduation === 'Yes';

        // Build Post Graduation sections if needed
        let postGraduationSections = [];
        if (showPostGraduation) {
            postGraduationSections = [
                {
                    ...this._buildSectionRenderModel('postGraduation'),
                    block: 'postGraduation'
                },
                {
                    ...this._buildSectionRenderModel('postGraduationDetails'),
                    block: 'postGraduation'
                }
            ].filter(Boolean);

        }

        // Store the post graduation sections for rendering
        sections = [
            ...sections,
            ...postGraduationSections
        ];

        // Show Professional Qualification toggle always

        let pqList = [];
        pqList.push(
            {
                ...this._buildSectionRenderModel('haveProfessionalQualification'),
                block: 'professionalQualification'
            }
        );

        // If Yes → show 3-row grid
        const hasPQ = (this.education.haveProfessionalQualification && this.education.haveProfessionalQualification.HasProfessionalQualification__c) || '';
        if (hasPQ === 'Yes') {

            pqList.push({
                ...this._buildSectionRenderModel('professionalQualification'),
                block: 'professionalQualification'
            });

            if (!this.isReadOnly) {
                pqList.push({
                    ...this._buildSectionRenderModel(
                        'professionalQualificationActions'
                    ),
                    block: 'professionalQualification'
                });
            }
        }

        sections = [
            ...sections,
            ...pqList,
            {
                ...this._buildSectionRenderModel('importantCertification'),
                block: 'academicDetailsFooterSections'
            },
        ];

        this.academicSections = sections.filter(Boolean);

        if (restoreKey) {
            this.metadata[restoreKey] = originalMeta;
        }
    }

    _buildSectionRenderModel(sectionKey, options = {}) {
        const meta = this.metadata[sectionKey];
        const groupFilter = options.group || null;
        if (!meta) return null;

        const sectionData = this.education[sectionKey] || {};

        const section = {
            key: meta.key || sectionKey,
            title: meta.title || sectionKey,
            hideTitle: meta.hideTitle,
            rows: []
        };

        if (meta.note && !meta.noteInline) {
            section.title = meta.title || '';
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

        const useSequentialRenderer =
            this._isSequentialSection(sectionKey, sectionData) &&
            !['semester', 'year'].includes(sectionKey);

        if (useSequentialRenderer) {
            section.rows.push(
                ...(meta?.layout === 'fluid'
                    ? this._buildSequentialFluidRows(sectionKey, meta, sectionData, groupFilter)
                    : this._buildSequentialGridRows(sectionKey, meta, sectionData, groupFilter))
            );
            return section;
        }

        if (meta?.layout === 'fluid') {
            section.rows.push(...this._buildFluidRows(meta, sectionData, groupFilter));
            return section;
        }

        const cs = meta.columnSystem || 12;
        // const section = {
        //     key: meta.key || sectionKey,
        //     title: meta.title || sectionKey,
        //     rows: []
        // };

        /* NOTE ROW (static) */
        // if (meta.note && !meta.noteInline) {
        //     section.title = meta.title || '';
        //     section.rows.push({
        //         key: `${sectionKey}-note-row`,
        //         style: `margin-bottom: 10px;`,
        //         columns: [{
        //             key: `${sectionKey}-note-col`,
        //             widthStyle: 'grid-column: span 12;',
        //             fields: [{
        //                 key: `${sectionKey}-NOTE`,
        //                 meta: { ...meta.note, sectionKey },
        //                 value: meta.note.text
        //             }]
        //         }]
        //     });
        // }


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

                        let val = null;

                        // For normal fields → from data model
                        if (fieldMeta.type !== "note") {
                            val = rec[api] || null;
                        }
                        // For note fields → take text from metadata
                        else {
                            val = fieldMeta.text || "";
                        }

                        renderCol.fields.push({
                            key: `${sectionKey}-${api}-${seq}`,
                            meta: { ...fieldMeta, sequence: seq },
                            value: val
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

            // ⭐ DYNAMIC GRADUATION DATE LOGIC
            if (
                ['graduationDetails', 'postGraduationDetails'].includes(meta.key) &&
                f.api === 'MonthAndYearOfPassing__c'
            ) {
                const isPursuing =
                    this.education?.[meta.key]?.DegreeStatus__c === 'Pursuing';

                const addYears = (date, years) => {
                    if (!date) return null;

                    const d = new Date(date);

                    d.setUTCFullYear(d.getUTCFullYear() + years);
                    d.setUTCMonth(0, 1);
                    d.setUTCHours(0, 0, 0, 0);

                    return d.toISOString().split('T')[0];
                };

                if (!isPursuing) {
                    // Completed
                    metaForRender.min = "1985-01-01";

                    metaForRender.max =
                        new Date().toISOString().split('T')[0];

                    metaForRender.label =
                        'Graduated Month and Year';
                } else {
                    // Pursuing
                    metaForRender.min =
                        new Date().toISOString().split('T')[0];

                    metaForRender.max =
                        new Date(
                            new Date().setFullYear(
                                new Date().getFullYear() + 1
                            )
                        ).toISOString().split('T')[0];

                    metaForRender.label =
                        'Expected graduation Month and Year';
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

    _isSequentialSection(sectionKey, sectionData = this.education[sectionKey] || {}) {
        if (!sectionKey) return false;

        if (sectionData?.isSequential === true || sectionData?.isSequential === false) {
            return true;
        }

        return (this.metadata[sectionKey]?.fields || []).some(f => f.sequence !== undefined && f.sequence !== null);
    }

    _getSequenceList(sectionKey, sectionData = this.education[sectionKey] || {}) {
        const sequenceSet = new Set();

        // Semester / Year are dynamically controlled by
        // Degree Type + Pattern of Examination.
        if (sectionKey === 'semester' || sectionKey === 'year') {
            const maxSeq = this._getAcademicPeriodCount(sectionKey);

            for (let seq = 1; seq <= maxSeq; seq++) {
                sequenceSet.add(seq);
            }

            // Also preserve any existing rows within the valid range.
            Object.keys(sectionData || {}).forEach(key => {
                if (/^\d+$/.test(String(key))) {
                    const seq = Number(key);

                    if (seq >= 1 && seq <= maxSeq) {
                        sequenceSet.add(seq);
                    }
                }
            });

            return Array.from(sequenceSet)
                .sort((a, b) => a - b);
        }

        if (sectionKey === 'professionalQualification') {
            return Array.from(
                {
                    length:
                        this.education.professionalQualificationVisibleRows || 1
                },
                (_, i) => i + 1
            );
        }

        // Existing behaviour for other sequential sections.
        (this.metadata[sectionKey]?.fields || []).forEach(f => {
            if (
                f.sequence !== undefined &&
                f.sequence !== null &&
                f.sequence !== ''
            ) {
                sequenceSet.add(Number(f.sequence));
            }
        });

        Object.keys(sectionData || {}).forEach(key => {
            if (/^\d+$/.test(String(key))) {
                sequenceSet.add(Number(key));
            }
        });

        return Array.from(sequenceSet)
            .filter(Number.isFinite)
            .sort((a, b) => a - b);
    }

    _buildSequentialGridRows(sectionKey, meta, sectionData, groupFilter) {
        const cs = meta.columnSystem || 12;
        const rowStyle = `display:grid;grid-template-columns:repeat(${cs},1fr);gap:8px;margin-bottom:12px;`;
        const rows = [];
        const sequences = this._getSequenceList(sectionKey, sectionData);
        const templateRows = (meta.rows || []).length ? meta.rows : [{ columns: [] }];
        const useSingleTemplate = templateRows.length === 1;

        sequences.forEach((seq, seqIdx) => {
            const templateRow = useSingleTemplate ? templateRows[0] : (templateRows[seqIdx] || templateRows[0]);
            const renderRow = {
                key: `${sectionKey}-row-${seq}`,
                style: rowStyle,
                columns: []
            };

            (templateRow.columns || []).forEach((col, cIdx) => {
                const span = col.width && Number(col.width) >= 1 ? Number(col.width) : cs;
                const renderCol = {
                    key: `${sectionKey}-col-${seq}-${cIdx}`,
                    header: col.header || null,
                    widthStyle: `grid-column: span ${span};`,
                    fields: []
                };

                (col.fields || []).forEach(fieldApi => {
                    let fieldMeta = (meta.fields || []).find(
                        f => f.api === fieldApi && Number(f.sequence) === Number(seq)
                    );

                    if (!fieldMeta) {
                        fieldMeta = (meta.fields || []).find(f => f.api === fieldApi);
                    }

                    if (!fieldMeta) {
                        fieldMeta = { api: fieldApi, sequence: seq, label: fieldApi, type: 'text' };
                    }

                    const fieldGroup = fieldMeta?.group || 'default';
                    if (groupFilter && fieldGroup !== groupFilter) {
                        return;
                    }

                    const metaForRender = this._resolveFieldMeta(
                        sectionKey,
                        { ...fieldMeta, sequence: seq, sectionKey }
                    );

                    if (metaForRender.visible === false) return;

                    this._applyDynamicFilter(metaForRender);

                    renderCol.fields.push({
                        key: `${sectionKey}-${fieldApi}-${seq}`,
                        meta: metaForRender,
                        value: this._getValueForField(sectionKey, fieldApi, seq)
                    });
                });

                renderRow.columns.push(renderCol);
            });

            rows.push(renderRow);
        });

        return rows;
    }

    _buildSequentialFluidRows(sectionKey, meta, sectionData, groupFilter) {
        const cs = meta.columnSystem || 12;
        const sequences = this._getSequenceList(sectionKey, sectionData);
        const rows = [];
        let fluidRowIdx = 0;

        sequences.forEach((seq, seqIdx) => {
            
            let row = { columns: [], used: 0 };

            if (sectionKey === 'professionalQualification') {
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
                .filter(f => f.type !== 'note' && Number(f.sequence) === Number(seq))
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

                        if (sectionKey === 'professionalQualification') {
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

    _updateProfessionalQualificationActionState() {
        const visibleRows =
            this.education.professionalQualificationVisibleRows || 1;

        this.education.professionalQualificationActions = {
            fullCapacity:
                visibleRows >= PROFESSIONAL_QUALIFICATION_MAX_ROWS,

            noneToRemove:
                visibleRows <= 1
        };
    }

    _resolveFieldConditionValue(path, sectionKey, sequence) {
        const root = this.contextBlock || this.education;
        const parts = String(path || '').split('.');
        if (!parts.length) return undefined;

        if (
            sequence !== null &&
            sequence !== undefined &&
            this._isSequentialSection(sectionKey) &&
            parts[0] === sectionKey
        ) {
            let cur = this.education?.[sectionKey]?.[sequence];
            for (let i = 1; i < parts.length; i++) {
                if (cur == null) return undefined;
                cur = cur[parts[i]];
            }
            return cur;
        }

        let cur = root;
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
        if (!fieldMeta?.requiredWhen) {
            return baseRequired;
        }

        return this._conditionsMatchForField(fieldMeta.requiredWhen, sectionKey, sequence);
    }

    _getValueForField(sectionKey, api, sequence) {

        if (
            sectionKey === 'semester' ||
            sectionKey === 'year' ||
            sectionKey === 'professionalQualification'
        ) {
            if (!sequence) return null;

            return (
                (this.education[sectionKey] || {})[sequence] || {}
            )[api] || null;
        }

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

    _handleMarkingSchemeTransition(sectionKey, oldValue, newValue) {
        if (oldValue === newValue) return;

        const resetApis = ['Maximum_Marks__c', 'Obtained_Marks__c', 'Percentage__c', 'ConversionFormula__c'];

        if (['tenth', 'twelfth', 'diploma', 'graduationDetails', 'postGraduationDetails'].includes(sectionKey)) {
            this._clearFields(sectionKey, resetApis);
        }

    }

    _resolveFieldMeta(sectionKey, fieldMeta) {
        const resolved = { ...fieldMeta };
        const isSequential = this._isSequentialSection(sectionKey);

        const customDropdown = this.resolveCustomDropdown(
            resolved.api,
            null
        );

        if (customDropdown?.controllingFieldApi) {
            const sequence = Number(resolved.sequence);

            const controllingValue =
                this._getValueForField(
                    sectionKey,
                    customDropdown.controllingFieldApi,
                    sequence
                );

            resolved.options = [
                { label: '--None--', value: '' },
                ...(customDropdown
                    .optionsByControllingValue
                    ?. [controllingValue] || [])
            ];
        }

        if (
            sectionKey === 'professionalQualification' &&
            resolved.api === 'ProfessionalQualification__c'
        ) {
            const sequence = Number(resolved.sequence);

            const controllingValue =
                this._getValueForField(
                    sectionKey,
                    'Name_of_Qualification_Picklist__c',
                    sequence
                );

            resolved.options = [
                { label: '--None--', value: '' },
                ...this._getDependentOptions(
                    'ProfessionalQualification__c',
                    controllingValue
                )
            ];
        }

        if (
            sectionKey === 'graduation' &&
            resolved.api === 'Specialization_Name__c'
        ) {
            const degreeValue =
                this._getValueForField(
                    sectionKey,
                    'Degree__c',
                    resolved.sequence
                );

            if (degreeValue === 'Other') {
                resolved.type = 'text';
            } else {
                resolved.type = 'picklist';
            }
        }

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

        if (sectionKey === 'graduationDetails') {
            if (['Maximum_Marks__c', 'Obtained_Marks__c'].includes(resolved.api)) {
                resolved.readOnly = false;
                resolved.required = true;
            }

            if (resolved.api === 'Percentage__c') {
                if (this.isUgCgpaMode()) {
                    resolved.readOnly = false;
                    resolved.required = true;
                    delete resolved.calculate;
                } else {
                    resolved.readOnly = true;
                    resolved.required = false;
                }
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

        if (['tenth', 'twelfth', 'diploma'].includes(sectionKey)
            && resolved.api === 'Percentage__c') {

            const isCgpa =
                (this.education?.[sectionKey]?.Marking_Scheme__c || '') === 'CGPA';

            if (isCgpa) {   
                resolved.readOnly = false;
                resolved.required = true;
                delete resolved.calculate;
            } else {
                resolved.readOnly = true;
                resolved.required = false;
            }
        }

        //if (isSequential) {
            resolved.visible = this._computeFieldVisible(resolved, sectionKey, resolved.sequence);
            resolved.required = this._computeFieldRequired(resolved, sectionKey, resolved.sequence);
            delete resolved.visibleWhen;
            delete resolved.requiredWhen;
        //}

        return resolved;
    }

    _shouldRunCalculation(sectionKey, fieldMeta) {
        if (!fieldMeta?.calculate) return false;

        if (
            ['tenth', 'twelfth', 'diploma'].includes(sectionKey) &&
            fieldMeta.calculate === 'computePercentage'
        ) {
            return (this.education?.[sectionKey]?.Marking_Scheme__c || '') !== 'CGPA';
        }

        if (sectionKey === 'graduationDetails' &&
            fieldMeta.calculate === 'computeGraduationPercentage') {
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
        professionalQualification: {},
        academicBreak: {}
    };

    // handle field change events from children
    handleSectionFieldChange(e) {

        const oldGradDegreeType = this.education.graduation.Degree_Type__c;
        const oldPostGradDegreeType = this.education.postGraduation.Degree_Type__c;

        const oldGradExamPattern =
            this.education?.graduation?.Pattern_of_Examination__c || '';

        const oldPostGradExamPattern =
            this.education?.postGraduation?.Pattern_of_Examination__c || '';

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

        if (sectionKey === 'tenth' || sectionKey === 'twelfth') {            
            if (api === 'Board_University__c' && value !== 'Other') {
                this.education[sectionKey].Other_Board_University__c = null;
            }
        }

        if (sectionKey === 'postGraduationDetails' && api === 'DegreeStatus__c') {
            if(oldPostDegreeStatus != value){
                this.education.postGraduationDetails.MonthAndYearOfPassing__c = null;
            }
        }

        if (sectionKey === 'graduationDetails' && api === 'DegreeStatus__c') {
            if(oldDegreeStatus != value){
                this.education.graduationDetails.MonthAndYearOfPassing__c = null;
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

        if (sectionKey === 'semester' || sectionKey === 'year') {
            this.education[sectionKey] ||= {};
            this.education[sectionKey].isSequential = true;

            if (!sequence) return;

            this.education[sectionKey][sequence] ||= {};
            this.education[sectionKey][sequence][api] = value;

        } else if (sectionKey === 'professionalQualification') {
            this.education[sectionKey] = this.education[sectionKey] || {};
            this.education[sectionKey][api] = value;
        } else {
            this.education[sectionKey] ||= {};
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
                    AcademicBreakAfter__c: this.backup.academicBreak?.AcademicBreakAfter__c ?? this.education.haveAcademicBreak?.AcademicBreakAfter__c ?? null,
                    AcademicBreakReason__c: this.backup.academicBreak?.AcademicBreakReason__c ?? this.education.haveAcademicBreak?.AcademicBreakReason__c ?? null
                };

                const pq =
                    this.education.professionalQualification || {};

                const existingRows = Object.keys(pq)
                    .filter(k => k !== 'isSequential')
                    .filter(k => {
                        const row = pq[k];
                        return row?.Id ||
                            Object.keys(row || {}).some(
                                f =>
                                    f !== 'Id' &&
                                    row[f] !== null &&
                                    row[f] !== undefined &&
                                    row[f] !== ''
                            );
                    }).length;

                this.education.professionalQualificationVisibleRows =
                    Math.max(
                        1,
                        Math.min(existingRows || 1, PROFESSIONAL_QUALIFICATION_MAX_ROWS)
                    );
            } else {
                this.backup.academicBreak = { ...this.education.haveAcademicBreak };
                this.education.haveAcademicBreak = {
                    Id: this.backup.academicBreak?.Id || null,
                    HasAcademicBreak__c: 'No',
                    AcademicBreakAfter__c: null,
                    AcademicBreakReason__c: null
                };
                this.education.professionalQualificationVisibleRows = 1;
            }

            this._buildRenderModelAll();
            return;
        }

        if (
            sectionKey === 'graduationDetails' &&
            api === 'DegreeStatus__c'
        ) {
            const isPursuing = value === 'Pursuing';

            this.education.basicAcademic ||= {};

            this.education.basicAcademic.GraduationCompleted__c =
                isPursuing ? 'No' : 'Yes';

            if (oldDegreeStatus !== value) {
                this.education.graduationDetails.MonthAndYearOfPassing__c = null;
            }

            this._buildRenderModelAll();
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
            }

            // If user selects NO → clear UI but preserve IDs in backup
            else {
                // BACKUP the real PG values INCLUDING ID
                this.backup.postGraduation = { ...this.education.postGraduation };
                this.backup.postGraduationDetails = { ...this.education.postGraduationDetails };

                // CLEAR UI — DO NOT SEND ID WHEN PG = NO
                this.education.postGraduation = {};
                this.education.postGraduationDetails = {};
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

            if (api === 'Name_of_Qualification_Picklist__c') {
                pq[seq].ProfessionalQualification__c =
                    value === 'Other' ? 'Other' : null;

                pq[seq].showProfessionalQualification =
                    value !== 'Other';
            }

            const otherFieldMap = {
                Name_of_Qualification_Picklist__c: 'Name_of_Qualification__c',
                Name_of_Institute_Picklist__c: 'Name_of_Institute__c'
            };

            if (value !== 'Other' && otherFieldMap[api]) {
                pq[seq][otherFieldMap[api]] = null;
            }

            // Recalculate PQ percentage for this row
            this._runSectionCalculations('professionalQualification');

            this.education.professionalQualification = pq;
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

            if (api === "Degree_Type__c") {
                const pattern =
                    (this.education[sectionKey].Pattern_of_Examination__c || '').toLowerCase();

                const periodCount =
                    pattern.includes('semester')
                        ? this._getAcademicPeriodCount('semester')
                        : pattern.includes('year')
                            ? this._getAcademicPeriodCount('year')
                            : 0;

                if (sectionKey === 'graduation') {
                    if (pattern.includes('semester')) {
                        this.truncateSequentialSection(
                            this.education.semester,
                            periodCount,
                            'semester'
                        );
                    }

                    if (pattern.includes('year')) {
                        this.truncateSequentialSection(
                            this.education.year,
                            periodCount,
                            'year'
                        );
                    }
                }
            }

            if (api === 'Pattern_of_Examination__c') {
                const yearKey =
                    sectionKey === 'graduation'
                        ? 'year'
                        : 'postYear';

                const semKey =
                    sectionKey === 'graduation'
                        ? 'semester'
                        : 'postSemester';

                const oldPattern =
                    sectionKey === 'graduation'
                        ? oldGradExamPattern
                        : oldPostGradExamPattern;

                const newPattern = value || '';

                const oldIsYear =
                    oldPattern.toLowerCase().includes('year');

                const oldIsSem =
                    oldPattern.toLowerCase().includes('sem');

                const newIsYear =
                    newPattern.toLowerCase().includes('year');

                const newIsSem =
                    newPattern.toLowerCase().includes('sem');

                // Update first
                this.education[sectionKey].Pattern_of_Examination__c = value;

                // SEM → YEAR
                if (oldIsSem && newIsYear) {
                    this.deleteEntireMode(semKey);
                    this.deleteEntireMode(yearKey);

                    this.education[semKey] = {};
                    this.education[yearKey] = {};
                }

                // YEAR → SEM
                if (oldIsYear && newIsSem) {
                    this.deleteEntireMode(semKey);
                    this.deleteEntireMode(yearKey);

                    this.education[yearKey] = {};
                    this.education[semKey] = {};
                }

                this._buildRenderModelAll();
                return;
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

            if (api === 'Degree__c') {
                if (value !== 'Other') {
                    this.education[sectionKey].OtherDegree__c = null;
                }
            }
        }


        // run hooks if any
        if (fieldMeta && fieldMeta.onChange && typeof this[fieldMeta.onChange] === 'function') {
            this[fieldMeta.onChange](sectionKey, api, value);
        }

        // recompute calculations for that section and rebuild renderModel
        this._runSectionCalculations(sectionKey);
        this._buildRenderModelAll();
    }

    handleSectionAction(e) {
        const { action } = e.detail;

        switch (action) {

            case 'addMoreProfessionalQualification':
                this._addProfessionalQualificationRow();
                break;

            case 'removeProfessionalQualification':
                this._removeProfessionalQualificationRow();
                break;
        }

        this._updateProfessionalQualificationActionState();
        this._buildRenderModelAll();
    }

    _addProfessionalQualificationRow() {

        const visible =
            this.education.professionalQualificationVisibleRows || 1;

        if (visible >= PROFESSIONAL_QUALIFICATION_MAX_ROWS) {
            return;
        }

        this.education.professionalQualificationVisibleRows =
            visible + 1;

        this.education.professionalQualification[visible + 1] ||= {
            Id: null,
            showProfessionalQualification: true
        };
    }

    _removeProfessionalQualificationRow() {

        const visible =
            this.education.professionalQualificationVisibleRows || 1;

        if (visible <= 1) {
            return;
        }

        const rec =
            this.education.professionalQualification[visible];

        if (rec?.Id) {
            this.education.professionalQualificationDeleted ||= [];

            this.education.professionalQualificationDeleted.push(
                rec.Id
            );
        }

        // Clear the removed row so it is not included in the save payload
        this.education.professionalQualification[visible] = {
            Id: null,
            showProfessionalQualification: true
        };

        this.education.professionalQualificationVisibleRows =
            visible - 1;
    }

    _clearInactiveAcademicPattern(sectionKey, activePattern) {
        const section = this.education[sectionKey];

        if (!section || typeof section !== 'object') {
            return;
        }

        const deletedList = [];

        Object.keys(section)
            .filter(key => /^\d+$/.test(String(key)))
            .forEach(key => {
                const row = section[key];

                if (row?.Id) {
                    deletedList.push(row.Id);
                }

                delete section[key];
            });

        if (deletedList.length) {
            const deletedKey = `${sectionKey}Deleted`;

            this.education[deletedKey] ||= [];

            this.education[deletedKey].push(...deletedList);
        }
    }

    deleteEntireMode(modeKey) {
        const section = this.education[modeKey];

        if (!section) return;

        const deletedList = [];

        Object.keys(section)
            .filter(k => !isNaN(Number(k)))
            .forEach(k => {
                const row = section[k];

                if (row && row.Id) {
                    deletedList.push(row.Id);
                }

                delete section[k];
            });

        const delKey = modeKey + 'Deleted';

        if (!this.education[delKey]) {
            this.education[delKey] = [];
        }

        this.education[delKey].push(...deletedList);

        this.education[modeKey] = {};
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
        postGraduation: ['State__c','University__c','College__c']
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
        const targetKeys = new Set(sectionKeys);

        this.academicSections = (this.academicSections || []).map(section => {
            if (!targetKeys.has(section.key)) {
                return section;
            }

            const rebuilt = this._buildSectionRenderModel(section.key);
            return rebuilt
                ? { ...rebuilt, block: section.block }
                : section;
        }).filter(Boolean);
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


    _runSectionCalculations(sectionKey) {
        const sec = this.metadata[sectionKey];
        if (!sec || !sec.fields) return;

        const secData = this.education[sectionKey] || {};

        // Row-based (sequential or fixed 1..N)
        const isRowBased =
            secData.isSequential ||
            ['professionalQualification','semester','year']
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

        // Single-row section
        sec.fields.forEach(f => {
            if (this._shouldRunCalculation(sectionKey, f)) {
                const val = this[f.calculate](sectionKey, f.api, f);
                secData[f.api] = val;
            }
        });
    }

    _getAcademicPeriodCount(sectionKey) {
        const degreeType =
            this.education.graduation?.Degree_Type__c || '';

        const pattern =
            this.education.graduation?.Pattern_of_Examination__c || '';

        const match = String(degreeType).match(/([3-5])\s*year/i);

        if (!match) return 0;

        const years = Number(match[1]);

        if (sectionKey === 'year') {
            return years;
        }

        if (sectionKey === 'semester') {
            return years * 2;
        }

        return 0;
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
            return secData.Percentage__c ?? null;
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
        const academicCmp = this.template.querySelector('c-af-section-engine');

        academicCmp && academicCmp.applyErrors({});

        const after10Val = this.education.after10.AfterTen__c; // fix undefined variable bug

        // Build error maps per section: { [api]: 'message' }
        const errorMaps = {
            tenth: {},
            after10: {},
            twelfth: {},
            diploma: {},
            graduation: {},
            graduationDetails: {},
            semester: {},
            year: {},
            havePostGrad: {},
            postGraduation: {},
            postGraduationDetails: {},
            haveAcademicBreak: {},
            professionalQualification: {},
            importantCertification: {},
        };

        // Helper to set missing errors
        const addMissing = (sectionKey, fieldMeta, sectionTitle) => {
            fieldMeta = this._resolveFieldMeta(sectionKey, fieldMeta);

            console.log(
                sectionKey,
                fieldMeta.api,
                'visible',
                fieldMeta.visible,
                'required',
                fieldMeta.required
            );

            if (fieldMeta.visible === false) {
                return;
            }

            const secData = this.education[sectionKey] || {};

            const metaSec = this.metadata[sectionKey] || {};

            // SINGLE ROW VALIDATION
            const value = secData[fieldMeta.api];

            if (fieldMeta.required && (value === '' || value === null || value === undefined)) {
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

            if (metaSec?.layout === 'fluid') {

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

            if (sectionKey === 'semester' || sectionKey === 'year') {
                maxSeq = this._getAcademicPeriodCount(sectionKey);
            } else {
                maxSeq = metaFields.reduce(
                    (max, f) => Math.max(max, Number(f.sequence) || 0),
                    0
                );
            }
            
            const fieldVal = secData[fieldMeta.api];

            if (fieldMeta.type === 'number') {
                const err = validateNumber(fieldMeta, fieldVal);
                if (err) {
                    errorMaps[sectionKey][fieldMeta.api] = err;
                }
            }


            // MULTI-ROW / SEQUENTIAL VALIDATION
            if (secData.isSequential || maxSeq > 0) {

                const errors = {};
    

                for (let seq = 1; seq <= maxSeq; seq++) {

                    const isPursuing =
                        this.education.graduationDetails?.DegreeStatus__c === 'Pursuing';

                    const exemptTail =
                        sectionKey === 'semester' ? 2 :
                        sectionKey === 'year' ? 1 :
                        0;

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
                    const isRequired =
                        !isPursuing ||
                        seq <= maxSeq - exemptTail;

                    if (
                        (!val || val === '' || val === null || val === undefined) &&
                        isRequired
                    ) {
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

            // // SINGLE ROW VALIDATION
            // const val = secData[fieldMeta.api];

            // if (fieldMeta.required && (val === '' || val === null || val === undefined)) {
            //     errorMaps[sectionKey][fieldMeta.api] =
            //         `${fieldMeta.shortLabel || fieldMeta.label || fieldMeta.api} is required`;
            // }

            // // Special rule: percentage minimum
            // if (fieldMeta.api === 'Percentage__c' && fieldMeta.minPercentage) {
            //     const v = parseFloat(secData[fieldMeta.api]);
            //     if (!isNaN(v) && v < fieldMeta.minPercentage) {
            //         errorMaps[sectionKey][fieldMeta.api] =
            //             `Cannot be less than ${fieldMeta.minPercentage}%`;
            //     }
            // }
        };

        const addResolvedMissing = (sectionKey, fieldMeta) => {
            const resolvedMeta = this._resolveFieldMeta(sectionKey, fieldMeta);
            if (resolvedMeta.visible === false) return;

            const secData = this.education[sectionKey] || {};
            const isSequential = this._isSequentialSection(sectionKey, secData);
            const seq = resolvedMeta.sequence;
            const rowData = isSequential && seq !== undefined && seq !== null
                ? (secData[seq] || {})
                : secData;
            const val = rowData?.[resolvedMeta.api];

            if (resolvedMeta.required && (val === null || val === '' || val === undefined)) {
                if (isSequential && seq !== undefined && seq !== null) {
                    errorMaps[sectionKey][seq] ||= {};
                    errorMaps[sectionKey][seq][resolvedMeta.api] =
                        `${resolvedMeta.shortLabel || resolvedMeta.label || resolvedMeta.api} is required`;
                } else {
                    errorMaps[sectionKey][resolvedMeta.api] =
                        `${resolvedMeta.shortLabel || resolvedMeta.label || resolvedMeta.api} is required`;
                }
            }

            if (resolvedMeta.type === 'number') {
                const err = validateNumber(resolvedMeta, val);
                if (err) {
                    if (isSequential && seq !== undefined && seq !== null) {
                        errorMaps[sectionKey][seq] ||= {};
                        errorMaps[sectionKey][seq][resolvedMeta.api] = err;
                    } else {
                        errorMaps[sectionKey][resolvedMeta.api] = err;
                    }
                }
            }

            if (resolvedMeta.api === 'Percentage__c' && resolvedMeta.minPercentage) {
                const percentValue = parseFloat(val);
                if (!isNaN(percentValue) && percentValue < resolvedMeta.minPercentage) {
                    if (isSequential && seq !== undefined && seq !== null) {
                        errorMaps[sectionKey][seq] ||= {};
                        errorMaps[sectionKey][seq][resolvedMeta.api] =
                            `Cannot be less than ${resolvedMeta.minPercentage}%`;
                    } else {
                        errorMaps[sectionKey][resolvedMeta.api] =
                            `Cannot be less than ${resolvedMeta.minPercentage}%`;
                    }
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

        //50 word limit
        if(this.education.haveAcademicBreak.AcademicBreakReason__c){
            const { isValid, count } = validateWordLimit(this.education.haveAcademicBreak.AcademicBreakReason__c, 50);
            if(!isValid){
                errorMaps.haveAcademicBreak = errorMaps.haveAcademicBreak || {};
                errorMaps.haveAcademicBreak.AcademicBreakReason__c = `Should not exceed 50 words. You have ${count} words`;
            }
        }

        const sec = this.metadata.haveAcademicBreak;

        if (sec?.fields) {
            sec.fields.forEach(f =>
                addResolvedMissing('haveAcademicBreak', f)
            );
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
        
        const isPursuing =
            this.education.graduationDetails?.DegreeStatus__c === 'Pursuing';

        if (!isPursuing) {
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
        const hasPQ =
            this.education.haveProfessionalQualification
                ?.HasProfessionalQualification__c || '';

        // Professional Qualification
        if (hasPQ === 'Yes') {
            const pqMeta = this.metadata.professionalQualification;

            if (pqMeta?.fields) {
                pqMeta.fields.forEach(f => {
                    const seq = Number(f.sequence);

                    // Only validate currently visible rows
                    if (
                        !seq ||
                        seq > (
                            this.education.professionalQualificationVisibleRows || 1
                        )
                    ) {
                        return;
                    }

                    addResolvedMissing(
                        'professionalQualification',
                        f
                    );
                });

                const visibleRows =
                    this.education.professionalQualificationVisibleRows || 1;

                const pqRows =
                    this.education.professionalQualification || {};

                for (let seq = 1; seq <= visibleRows; seq++) {
                    const row = pqRows[seq] || {};

                    const commencedYear =
                        Number(row['Year_of_Commencement_pq__c']);

                    const passingYear =
                        Number(row['Year_of_Passing_pq__c']);

                    if (
                        Number.isFinite(commencedYear) &&
                        Number.isFinite(passingYear) &&
                        commencedYear > passingYear
                    ) {
                        if (!errorMaps.professionalQualification[seq]) {
                            errorMaps.professionalQualification[seq] = {};
                        }

                        errorMaps.professionalQualification[seq]['Year_of_Passing_pq__c'] =
                            'Passing year cannot be before commencement year';
                    }
                }
            }
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

            //graduation
            academicCmp.applyErrors(errorMaps.havePostGrad, 'havePostGrad');
            academicCmp.applyErrors(errorMaps.graduation, 'graduation');
            academicCmp.applyErrors(errorMaps.graduationDetails, 'graduationDetails');

            // academic period details
            academicCmp.applyErrors(errorMaps.semester, 'semester');
            academicCmp.applyErrors(errorMaps.year, 'year');

            //post graduation
            if (showPostGraduation) {
                academicCmp.applyErrors(errorMaps.postGraduation, 'postGraduation');
                academicCmp.applyErrors(errorMaps.postGraduationDetails, 'postGraduationDetails');
            }

            //academic break
            academicCmp.applyErrors(errorMaps.haveAcademicBreak, 'haveAcademicBreak');

            academicCmp.applyErrors(errorMaps.professionalQualification, 'professionalQualification');

            //footer
            academicCmp.applyErrors(errorMaps.importantCertification, 'importantCertification');

        }

        console.log(
            'errorMaps',
            JSON.stringify(errorMaps)
        );
        // Aggregate message for summary
        const flatErrors = []
            .concat(Object.values(errorMaps.tenth))
            .concat(Object.values(errorMaps.after10))
            .concat(Object.values(errorMaps.twelfth))
            .concat(Object.values(errorMaps.diploma))
            .concat(Object.values(errorMaps.havePostGrad))
            .concat(Object.values(errorMaps.haveAcademicBreak))
            .concat(Object.values(errorMaps.graduation))
            .concat(Object.values(errorMaps.graduationDetails))
            .concat(Object.values(errorMaps.postGraduation))
            .concat(Object.values(errorMaps.postGraduationDetails))
            .concat(Object.values(errorMaps.professionalQualification || {}).flatMap(row => Object.values(row || {})))
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
        return AfAcademicDetailsContainerPgdm.LOCKED_APPLICATION_STATUSES.includes(this.application?.Application_Status__c) &&
            !AfAcademicDetailsContainerPgdm.UNLOCK_ASSIGNMENT_STATUSES.includes(this.application?.Assignment_Status__c);
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
        
        // const dob = this.personalDetails?.Date_of_Birth_As_Per_10th_Marksheet__c;
        // if (!dob) return;

        // const dobDate = new Date(dob);

        // const addYears = (years, resetToJan1) => {
        //     const d = new Date(dobDate);
        //     d.setUTCFullYear(d.getUTCFullYear() + years);
        //     if (resetToJan1) {
        //         d.setUTCMonth(0, 1); // Jan 1
        //         d.setUTCHours(0, 0, 0, 0);
        //     }
        //     return d.toISOString().split('T')[0];
        // };

        // const rules = {
        //     tenth: { passing: 15 },
        //     twelfth: { passing: 17 },
        //     diploma: { start: 15, passing: 18 },
        //     graduationDetails: { start: 17, passing: 20 },
        //     postGraduationDetails: { start: 20, passing: 22 }
        // };

        // Object.entries(rules).forEach(([section, config]) => {

        //     if (!this.metadata[section]) return;

        //     this.metadata[section].fields.forEach(f => {

        //         if (f.api === 'MonthAndYearOfCommencement__c' && config.start !== undefined) {
        //             f.min = addYears(config.start,true);
        //         }

        //         if (f.api === 'MonthAndYearOfPassing__c' && config.passing !== undefined) {
        //             f.min = addYears(config.passing,true);
        //         }

        //     });

        // });

        this.education = response;
        this.application = response?.application;

        ['semester', 'year'].forEach(sectionKey => {
            const section = this.education[sectionKey];

            if (!section || typeof section !== 'object') {
                this.education[sectionKey] = {};
                return;
            }

            const normalized = {
                isSequential: true
            };

            Object.keys(section)
                .filter(k => k !== 'isSequential')
                .forEach(k => {
                    normalized[k] = {
                        ...section[k]
                    };
                });

            this.education[sectionKey] = normalized;
        });

        // ===== NORMALIZE PROFESSIONAL QUALIFICATION =====
        {
            const pq = this.education.professionalQualification;
            if (pq && typeof pq === 'object' && pq.isSequential === false) {
                const norm = { isSequential: false };
                let seq = 1;

                Object.keys(pq)
                    .filter(k => k !== 'isSequential')
                    .forEach(k => {
                        norm[seq] = {
                            Id: k,
                            ...pq[k],
                            showProfessionalQualification:
                                pq[k]?.Name_of_Qualification_Picklist__c !== 'Other'
                        };
                        seq++;
                    });

                let existingRowCount = 0;

                Object.keys(norm)
                    .filter(k => k !== 'isSequential')
                    .forEach(k => {
                        const row = norm[k];

                        if (
                            row?.Id ||
                            Object.keys(row || {}).some(
                                field =>
                                    field !== 'Id' &&
                                    row[field] !== null &&
                                    row[field] !== undefined &&
                                    row[field] !== ''
                            )
                        ) {
                            existingRowCount++;
                        }
                    });

                this.education.professionalQualificationVisibleRows =
                    Math.max(
                        1,
                        Math.min(
                            existingRowCount || 1,
                            PROFESSIONAL_QUALIFICATION_MAX_ROWS
                        )
                    );

                this._updateProfessionalQualificationActionState();

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

            const ugPattern =
                (this.education.graduation?.Pattern_of_Examination__c || '').toLowerCase();

            if (ugPattern.includes('year')) {
                this.education.semester = { isSequential: true };
            }

            if (ugPattern.includes('sem')) {
                this.education.year = { isSequential: true };
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
                    this._findFieldMetaForParent(
                        'graduationDetails',
                        'MonthAndYearOfPassing__c'
                    )
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

            if (sectionKey === 'tenth' && this.recordTypeIds?.Tenth) {
                cleanFields.RecordTypeId = this.recordTypeIds.Tenth;
            }

            if (sectionKey === 'twelfth' && this.recordTypeIds?.Twelfth) {
                cleanFields.RecordTypeId = this.recordTypeIds.Twelfth;
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
            if (api === childMeta?.childKeyField) return;
            if (!allowedFields.has(api)) return;

            const v = row[api];

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